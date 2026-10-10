#!/usr/bin/env node
/**
 * Verify สัญญาใน deployed-contracts.json บน Blockscout ของเชน TPIX ด้วย standard JSON input
 *
 * ทำไมไม่ใช้ verify-sources.js เดิม: ตัวนั้นส่ง source แบบ flatten + evmversion ว่าง
 * แต่เชนนี้ต้อง compile แบบ london และ hardhat เลือก solc ตัวใหม่สุดที่เข้ากับ pragma
 * (registry เขียนว่า 0.8.20 แต่ build จริงเป็น 0.8.24) → bytecode ไม่ตรงทุกตัว
 * ตัวนี้ส่ง build-info ที่ hardhat ใช้ compile จริง จึงได้ compiler/optimizer/evmVersion ตรงเป๊ะ
 *
 * Usage:
 *   node scripts/verify-blockscout.js                 # ทุกตัวที่ยังไม่ verified
 *   node scripts/verify-blockscout.js TPIXDEXFactory  # เฉพาะชื่อที่ระบุ
 *
 * Env: EXPLORER_URL (ค่าปริยาย https://explorer.tpix.online) · TPIX_RPC_URL (ค่าปริยาย rpc1)
 *
 * Developed by Xman Studio
 */

const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const ROOT = path.join(__dirname, "..");
const REGISTRY_PATH = path.join(ROOT, "deployed-contracts.json");
const EXPLORER = (process.env.EXPLORER_URL || "https://explorer.tpix.online").replace(/\/+$/, "");
const RPC_URL = process.env.TPIX_RPC_URL || "https://rpc1.tpix.online";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * หา artifact ของสัญญาที่ deploy จริง — ไฟล์ .sol หนึ่งไฟล์อาจมีหลาย contract/interface
 * จึงเลือกตัวที่ความยาว runtime bytecode เท่ากับโค้ดบนเชน (immutable ไม่ทำให้ความยาวเปลี่ยน)
 */
function findArtifact(entry, onChainCode) {
    const rel = entry.sourceFile.replace(/^contracts\//, "");
    const dir = path.join(ROOT, "artifacts", rel);
    if (!fs.existsSync(dir)) throw new Error(`ไม่พบ artifacts/${rel} — รัน npx hardhat compile ก่อน`);

    const candidates = fs.readdirSync(dir)
        .filter((f) => f.endsWith(".json") && !f.endsWith(".dbg.json"))
        .map((f) => ({ file: f, artifact: JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")) }))
        .filter(({ artifact }) => artifact.deployedBytecode && artifact.deployedBytecode.length === onChainCode.length);

    if (candidates.length !== 1) {
        throw new Error(`หา artifact ที่ตรงกับโค้ดบนเชนใน ${rel} ได้ ${candidates.length} ตัว (ต้องได้ 1)`);
    }
    const { file, artifact } = candidates[0];
    const dbg = JSON.parse(fs.readFileSync(path.join(dir, file.replace(/\.json$/, ".dbg.json")), "utf8"));
    const buildInfo = JSON.parse(fs.readFileSync(path.join(dir, dbg.buildInfo), "utf8"));
    return { artifact, buildInfo };
}

async function isVerified(address) {
    const res = await fetch(`${EXPLORER}/api/v2/smart-contracts/${address}`, { headers: { Accept: "application/json" } });
    if (!res.ok) return false;
    const body = await res.json().catch(() => ({}));
    return body.is_verified === true;
}

async function submit(address, buildInfo, artifact) {
    const form = new FormData();
    form.append("compiler_version", `v${buildInfo.solcLongVersion}`);
    form.append("contract_name", `${artifact.sourceName}:${artifact.contractName}`);
    form.append("autodetect_constructor_args", "true");
    form.append("license_type", "mit");
    form.append(
        "files[0]",
        new Blob([JSON.stringify(buildInfo.input)], { type: "application/json" }),
        "standard-input.json",
    );

    const res = await fetch(`${EXPLORER}/api/v2/smart-contracts/${address}/verification/via/standard-input`, {
        method: "POST",
        body: form,
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`explorer ตอบ HTTP ${res.status}: ${text.slice(0, 200)}`);
}

async function main() {
    const only = process.argv.slice(2).filter((a) => !a.startsWith("--"));
    const registry = JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
    const provider = new ethers.JsonRpcProvider(RPC_URL, registry.chain.chainId, { staticNetwork: true });

    const targets = (registry.contracts || []).filter((c) => (only.length ? only.includes(c.name) : c.verified !== true));
    if (targets.length === 0) {
        console.log("ไม่มีสัญญาที่ต้อง verify");
        return;
    }

    let failed = 0;
    for (const entry of targets) {
        process.stdout.write(`${entry.name.padEnd(26)} ${entry.address} … `);
        try {
            if (await isVerified(entry.address)) {
                entry.verified = true;
                console.log("verified อยู่แล้ว");
                continue;
            }

            const code = await provider.getCode(entry.address);
            if (code === "0x") throw new Error("ไม่มีโค้ดบนเชน");

            const { artifact, buildInfo } = findArtifact(entry, code);
            await submit(entry.address, buildInfo, artifact);

            // Blockscout compile เทียบในคิวของมันเอง — รอผลสูงสุด ~90 วินาที
            let ok = false;
            for (let i = 0; i < 30 && !ok; i++) {
                await sleep(3000);
                ok = await isVerified(entry.address);
            }
            if (!ok) throw new Error("ส่งแล้วแต่ยังไม่ขึ้น verified ใน 90 วินาที — รันซ้ำเพื่อเช็คอีกรอบ");

            entry.verified = true;
            entry.compilerVersion = buildInfo.solcVersion;
            entry.evmVersion = buildInfo.input.settings.evmVersion;
            console.log(`✅ verified (solc ${buildInfo.solcVersion}, ${buildInfo.input.settings.evmVersion})`);
        } catch (error) {
            failed++;
            console.log(`❌ ${error.message}`);
        }
    }

    registry.updated = new Date().toISOString().slice(0, 10);
    fs.writeFileSync(REGISTRY_PATH, JSON.stringify(registry, null, 2) + "\n");
    console.log(`\nบันทึกสถานะลง deployed-contracts.json แล้ว${failed ? ` · ล้ม ${failed} ตัว` : ""}`);
    if (failed) process.exitCode = 1;
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
