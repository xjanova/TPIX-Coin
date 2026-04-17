#!/usr/bin/env node
/**
 * Submits source code of all contracts in deployed-contracts.json to the TPIX Blockscout
 * explorer for public verification. Updates the registry with verification status.
 *
 * Usage:
 *   node scripts/verify-sources.js                   # verify every un-verified entry
 *   node scripts/verify-sources.js TPIXTokenFactoryV2  # verify a single contract by name
 *   node scripts/verify-sources.js --recheck         # re-check verification status, don't re-submit
 *
 * Requirements:
 *   - Contracts must be compiled (`npx hardhat compile`) before running
 *   - `constructor_arguments.json` may live next to this script to supply ABI-encoded args per contract
 *
 * Blockscout API reference:
 *   https://docs.blockscout.com/for-users/api/rpc-endpoints/contract
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

const REGISTRY_PATH = path.join(__dirname, '..', 'deployed-contracts.json');
const EXPLORER_API = process.env.EXPLORER_API || 'https://explorer.tpix.online/api';

// --- simple argument parsing ---
const args = process.argv.slice(2);
const onlyName = args.find(a => !a.startsWith('--'));
const recheckOnly = args.includes('--recheck');

function loadRegistry() {
    const raw = fs.readFileSync(REGISTRY_PATH, 'utf8');
    return JSON.parse(raw);
}

function saveRegistry(reg) {
    reg.updated = new Date().toISOString().slice(0, 10);
    fs.writeFileSync(REGISTRY_PATH, JSON.stringify(reg, null, 2) + '\n');
}

function httpGet(url) {
    return new Promise((resolve, reject) => {
        https.get(url, (res) => {
            let data = '';
            res.on('data', (c) => (data += c));
            res.on('end', () => {
                try {
                    resolve(JSON.parse(data));
                } catch (e) {
                    reject(new Error(`Invalid JSON from ${url}: ${data.slice(0, 200)}`));
                }
            });
        }).on('error', reject);
    });
}

function httpPost(url, form) {
    return new Promise((resolve, reject) => {
        const body = new URLSearchParams(form).toString();
        const u = new URL(url);
        const req = https.request({
            hostname: u.hostname,
            port: u.port || 443,
            path: u.pathname + u.search,
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Content-Length': Buffer.byteLength(body),
            },
        }, (res) => {
            let data = '';
            res.on('data', (c) => (data += c));
            res.on('end', () => {
                try {
                    resolve(JSON.parse(data));
                } catch (e) {
                    reject(new Error(`Invalid JSON from ${url}: ${data.slice(0, 200)}`));
                }
            });
        });
        req.on('error', reject);
        req.write(body);
        req.end();
    });
}

async function checkVerified(address) {
    const url = `${EXPLORER_API}?module=contract&action=getsourcecode&address=${address}`;
    try {
        const res = await httpGet(url);
        const item = res?.result?.[0];
        return !!(item && item.SourceCode && item.SourceCode.length > 0);
    } catch (e) {
        console.warn(`   ⚠ Verification check failed for ${address}: ${e.message}`);
        return false;
    }
}

function loadFlattenedSource(contractName, sourceFile) {
    // Expect flattened file at contracts/flat/<ContractName>.sol (produced by `npx hardhat flatten`)
    const flatPath = path.join(__dirname, '..', 'flat', `${contractName}.sol`);
    if (fs.existsSync(flatPath)) return fs.readFileSync(flatPath, 'utf8');

    // Fallback: try reading raw source
    const rawPath = path.join(__dirname, '..', sourceFile);
    if (fs.existsSync(rawPath)) {
        console.warn(`   ⚠ No flattened source found at ${flatPath} — using raw source. Imports won't resolve.`);
        console.warn(`     Run:  npx hardhat flatten ${sourceFile} > contracts/flat/${contractName}.sol`);
        return fs.readFileSync(rawPath, 'utf8');
    }

    throw new Error(`Source file not found: ${flatPath} or ${rawPath}`);
}

async function verifyContract(contract) {
    console.log(`\n→ ${contract.name} @ ${contract.address}`);

    const alreadyVerified = await checkVerified(contract.address);
    if (alreadyVerified) {
        console.log('   ✅ Already verified on explorer');
        return { ok: true, reason: 'already-verified' };
    }

    if (recheckOnly) {
        console.log('   ⏭  --recheck mode: skipping submission');
        return { ok: false, reason: 'not-verified' };
    }

    const source = loadFlattenedSource(contract.name, contract.sourceFile);

    // Blockscout verification — Etherscan-compatible endpoint
    const form = {
        module: 'contract',
        action: 'verifysourcecode',
        contractaddress: contract.address,
        sourceCode: source,
        contractname: contract.name,
        compilerversion: `v${contract.compilerVersion}+commit.a1b79de6`, // may need tuning to exact commit
        optimizationUsed: contract.optimizer?.enabled ? '1' : '0',
        runs: String(contract.optimizer?.runs ?? 200),
        constructorArguements: contract.constructorArgs || '', // sic — Etherscan API has this typo
        evmversion: '',
        licenseType: '3', // MIT
    };

    console.log('   ⏳ Submitting source to explorer...');
    const res = await httpPost(EXPLORER_API, form);

    if (res.status === '1') {
        console.log(`   ✅ Submitted — verification GUID: ${res.result}`);
        return { ok: true, guid: res.result };
    } else {
        console.log(`   ❌ Failed: ${res.result || res.message}`);
        return { ok: false, reason: res.result || res.message };
    }
}

async function main() {
    const reg = loadRegistry();
    const targets = onlyName
        ? reg.contracts.filter(c => c.name === onlyName)
        : reg.contracts;

    if (targets.length === 0) {
        console.error(onlyName ? `No contract named "${onlyName}"` : 'No contracts in registry');
        process.exit(1);
    }

    console.log('╔═══════════════════════════════════════════════════════════════╗');
    console.log('║  TPIX Contract Source Verification                             ║');
    console.log('╚═══════════════════════════════════════════════════════════════╝');
    console.log(`Explorer API: ${EXPLORER_API}`);
    console.log(`Targets: ${targets.length} contract(s)`);

    let okCount = 0;
    for (const c of targets) {
        try {
            const result = await verifyContract(c);
            if (result.ok) {
                c.verified = true;
                okCount++;
            }
        } catch (e) {
            console.error(`   💥 Error: ${e.message}`);
        }
    }

    saveRegistry(reg);

    console.log('\n╔═══════════════════════════════════════════════════════════════╗');
    console.log(`║  Result: ${okCount}/${targets.length} verified`.padEnd(64) + '║');
    console.log('╚═══════════════════════════════════════════════════════════════╝');

    process.exit(okCount === targets.length ? 0 : 1);
}

main().catch((e) => {
    console.error('💥 Fatal:', e);
    process.exit(1);
});
