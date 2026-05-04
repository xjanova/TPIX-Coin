/**
 * Update genesis.json with the 11 BIP-44-derived allocations from
 * wallet-output/wallets.json (per whitepaper §6 Tokenomics).
 *
 * Reads wallets.json (produced by generate-master-wallet.js) — no secrets read.
 *
 * Usage (called by regenesis.ps1):
 *   cd contracts
 *   node scripts/update-genesis.js
 *
 * Updates:
 *   infrastructure/genesis.json
 *   infrastructure/data/validator-N/genesis.json (each, if exists)
 *
 * Backups created with .pre-regenesis.<timestamp> suffix.
 */

const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.join(__dirname, "..", "..");
const WALLETS_FILE = path.join(REPO_ROOT, "wallet-output", "wallets.json");

if (!fs.existsSync(WALLETS_FILE)) {
    console.error("❌ wallet-output/wallets.json not found.");
    console.error("   Run scripts/generate-master-wallet.js first.");
    process.exit(1);
}

const wallets = JSON.parse(fs.readFileSync(WALLETS_FILE, "utf8"));

// Validate total = 7B
const totalTpix = wallets.reduce((s, w) => s + BigInt(w.balance_tpix || "0"), 0n);
if (totalTpix !== 7_000_000_000n) {
    console.error(`❌ wallets.json totals ${totalTpix} TPIX, not 7,000,000,000.`);
    process.exit(1);
}

// Build alloc map (skip 0-balance entries — main alias wallet)
const alloc = {};
for (const w of wallets) {
    const bal = BigInt(w.balance_tpix || "0");
    if (bal === 0n) continue;
    alloc[w.address] = { balance: w.balance_wei_hex };
}

console.log("Genesis allocation (from wallets.json):");
for (const [addr, val] of Object.entries(alloc)) {
    const role = wallets.find(w => w.address === addr)?.role || "?";
    console.log(`  ${role.padEnd(28)} ${addr}  ${val.balance}`);
}
console.log();

// Discover all genesis.json copies
const genesisPaths = [
    path.join(REPO_ROOT, "infrastructure", "genesis.json"),
];

const validatorDataDir = path.join(REPO_ROOT, "infrastructure", "data");
if (fs.existsSync(validatorDataDir)) {
    for (const sub of fs.readdirSync(validatorDataDir)) {
        const candidate = path.join(validatorDataDir, sub, "genesis.json");
        if (fs.existsSync(candidate)) genesisPaths.push(candidate);
    }
}

let updated = 0;
const ts = Date.now();

for (const p of genesisPaths) {
    try {
        const content = fs.readFileSync(p, "utf8");
        const data = JSON.parse(content);
        const backupPath = p + ".pre-regenesis." + ts;
        fs.writeFileSync(backupPath, content);

        // Polygon Edge stores alloc under genesis.alloc; Besu under top-level alloc
        let modified = false;
        if (data.genesis && data.genesis.alloc !== undefined) {
            data.genesis.alloc = alloc;
            modified = true;
        } else if (data.alloc !== undefined) {
            data.alloc = alloc;
            modified = true;
        }

        if (!modified) {
            console.log(`⊘ ${p} — no alloc field, skipping`);
            fs.unlinkSync(backupPath);
            continue;
        }

        fs.writeFileSync(p, JSON.stringify(data, null, 4) + "\n");
        console.log(`✓ ${p}`);
        console.log(`    backup → ${path.basename(backupPath)}`);
        updated++;
    } catch (err) {
        console.error(`✗ ${p} — ${err.message}`);
    }
}

console.log();
console.log(`Updated ${updated} genesis.json file(s).`);
console.log();
console.log("Next:");
console.log("  1. Commit + push:  git add infrastructure/ && git commit && git push");
console.log("  2. On RPC server:  cd ~/TPIX-Coin && git pull && sudo bash infrastructure/scripts/restart-chain.sh");
