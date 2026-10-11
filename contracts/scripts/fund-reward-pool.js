/**
 * เติม reward pool ของ NodeRegistryV2 จากกระเป๋า allocation "masternode-rewards"
 * (m/44'/60'/0'/0/1 · 0xf54c0deE404ec728a03b467cba7bBA171CC77dad · genesis 1,400,000,000 TPIX)
 *
 * เจ้าของรันเองผ่าน fund-reward-pool.ps1 เสมอ — ตัวนั้นถามรหัสผ่าน keystore / คำ 12 คำ
 * แบบซ่อนแล้วส่งผ่าน env ให้ process นี้ตัวเดียว (ไม่ลงไฟล์ ไม่ขึ้นจอ ไม่เข้า history)
 *
 * ทำไมไม่ใช้ send-tpix.ps1: นั่นโอนแบบ 21,000 gas ตายตัว แต่ receive() ของ registry
 * ใช้ราว 30,000 → tx ล้มเพราะแก๊สหมด สคริปต์นี้เรียก fundRewardPool() + ประเมินแก๊สจากเชน
 *
 * เงินที่เติมเข้าพูลแล้ว "ไม่มีใครถอนคืนได้" (สัญญาไม่มีฟังก์ชันถอนของ owner) —
 * เติมเป็นงวด ๆ ตามที่ต้องใช้จริง สคริปต์บอกให้ว่าเงินในพูลพอจ่ายกี่วันที่อัตราตอนนี้
 *
 * Env:
 *   FUND_AMOUNT        จำนวน TPIX หน่วยเต็ม (บังคับ)
 *   REGISTRY_ADDRESS   ที่อยู่ NodeRegistryV2 (ไม่ใส่ = อ่านจาก deployed-contracts.json แล้วเทียบกับเว็บ)
 *   FUND_ROLE          role ใน wallets.json (ค่าปริยาย masternode-rewards)
 *   KEYSTORE_PASSWORD  รหัสผ่าน keystore · หรือ MASTER_MNEMONIC (คำ 12 คำ)
 *   DRY_RUN=1          ตรวจทุกอย่าง + ประเมินแก๊ส แต่ไม่ส่ง และไม่ต้องใช้กุญแจ
 *   TPIX_RPC_URL       ค่าปริยาย https://rpc1.tpix.online
 *   TPIX_SITE_URL      ค่าปริยาย https://tpix.online (ใช้เทียบที่อยู่กับเว็บ)
 *   WALLET_DIR         ค่าปริยาย ../../wallet-output
 *
 * Developed by Xman Studio
 */
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const { inspectRegistry, runwayDays, fundPool } = require("./lib/reward-pool");

const WALLET_DIR = process.env.WALLET_DIR || path.join(__dirname, "..", "..", "wallet-output");
const RPC_URL = process.env.TPIX_RPC_URL || "https://rpc1.tpix.online";
const SITE_URL = (process.env.TPIX_SITE_URL || "https://tpix.online").replace(/\/+$/, "");
const CHAIN_ID = 4289;
const EXPECTED_ROLE = "masternode-rewards";
const DEPLOYED_PATH = path.join(__dirname, "..", "deployed-contracts.json");

// ไม่ใช้ process.exit() ตรง ๆ — บน Windows ถ้ายังมี fetch ค้างอยู่ Node จะล้มด้วย
// "Assertion failed: UV_HANDLE_CLOSING" แล้วคืน exit code มั่ว → โยน error แล้วให้ main จบเอง
class Abort extends Error {}
function fail(message) {
    throw new Abort(message);
}

const fmt = (wei) => Number(ethers.formatEther(wei)).toLocaleString("en-US", { maximumFractionDigits: 2 });

/** ที่อยู่ registry: env → deployed-contracts.json → เว็บ แล้วต้องตรงกับเว็บถ้าเว็บรู้จัก */
async function resolveRegistry() {
    let local = (process.env.REGISTRY_ADDRESS || "").trim();
    if (!local && fs.existsSync(DEPLOYED_PATH)) {
        const reg = JSON.parse(fs.readFileSync(DEPLOYED_PATH, "utf8"));
        const e = (reg.contracts || []).find((c) => c.name === "NodeRegistryV2");
        if (e) local = e.address;
    }

    let site = "";
    try {
        const res = await fetch(`${SITE_URL}/api/v1/masternode/config`, {
            headers: { "User-Agent": "TPIX-fund-reward-pool/1.0", Accept: "application/json" },
            signal: AbortSignal.timeout(15000),
        });
        if (res.ok) site = ((await res.json())?.data?.registry_address || "").trim();
    } catch { /* เว็บล่มไม่ควรขวางการเติมเงิน ถ้าเรารู้ที่อยู่อยู่แล้ว */ }

    if (local && site && local.toLowerCase() !== site.toLowerCase()) {
        fail(`ที่อยู่ไม่ตรงกัน: ในเครื่อง ${local} แต่เว็บใช้ ${site} — ตรวจให้แน่ใจก่อน (ตั้ง REGISTRY_ADDRESS ให้ตรงกับเว็บ)`);
    }
    const addr = local || site;
    if (!addr) fail("ไม่รู้ที่อยู่ NodeRegistryV2 — ตั้ง REGISTRY_ADDRESS หรือ deploy ก่อน");
    try { return ethers.getAddress(addr); } catch { fail(`ที่อยู่ไม่ถูกต้อง (หรือ checksum ผิด): ${addr}`); }
}

async function loadSigner(entry, keystoreJson) {
    const password = process.env.KEYSTORE_PASSWORD;
    const mnemonic = process.env.MASTER_MNEMONIC;
    delete process.env.KEYSTORE_PASSWORD;
    delete process.env.MASTER_MNEMONIC;

    if (password) {
        console.log("กำลังถอดรหัส keystore (ประมาณ 10-30 วินาที) ...");
        try { return await ethers.Wallet.fromEncryptedJson(keystoreJson, password); }
        catch { fail("รหัสผ่าน keystore ไม่ถูกต้อง — ยังไม่มีอะไรถูกส่งขึ้นเชน"); }
    }
    if (mnemonic) {
        const phrase = mnemonic.trim().toLowerCase().split(/\s+/).join(" ");
        try { return ethers.HDNodeWallet.fromPhrase(phrase, undefined, entry.path); }
        catch { fail("คำ 12 คำไม่ถูกต้อง — ยังไม่มีอะไรถูกส่งขึ้นเชน"); }
    }
    fail("ไม่ได้ใส่ทั้งรหัสผ่าน keystore และคำ 12 คำ");
}

function printStatus(title, s) {
    console.log(`\n${title}`);
    console.log(`  สัญญา          ${s.address}  (owner ${s.owner})`);
    console.log(`  เงินในพูล       ${fmt(s.fundedBalanceWei)} TPIX`);
    console.log(`  เติมสะสม        ${fmt(s.totalFundedWei)} TPIX · จ่ายไปแล้ว ${fmt(s.distributedWei)} TPIX`);
    for (const t of s.tiers) {
        console.log(`  ${t.name.padEnd(9)} โหนด ${String(t.activeNodes).padStart(4)} · APR สูงสุด ${t.aprCapBps / 100}% · จ่าย ~${fmt(t.perYearWei)} TPIX/ปี`);
    }
    const days = runwayDays(s.fundedBalanceWei, s.annualOutflowWei);
    console.log(`  อัตราจ่ายรวมตอนนี้ ~${fmt(s.annualOutflowWei)} TPIX/ปี → ` +
        (days === null ? "ยังไม่มีโหนด (ยังไม่มีรายจ่าย)" : `พูลพอจ่ายอีก ~${days.toLocaleString()} วัน`));
}

async function main() {
    const amountRaw = (process.env.FUND_AMOUNT || "").trim();
    if (!/^\d+(\.\d{1,18})?$/.test(amountRaw)) fail(`จำนวนไม่ถูกต้อง: ${amountRaw || "(ว่าง)"}`);
    const amountWei = ethers.parseEther(amountRaw);
    if (amountWei === 0n) fail("จำนวนต้องมากกว่า 0");
    if (amountWei > ethers.parseEther("1400000000")) fail("มากกว่า allocation ทั้งก้อน (1.4B) — พิมพ์ผิดหรือเปล่า");

    const dryRun = process.env.DRY_RUN === "1";
    const role = (process.env.FUND_ROLE || EXPECTED_ROLE).trim();

    const provider = new ethers.JsonRpcProvider(RPC_URL, CHAIN_ID, { staticNetwork: true });
    const registry = await resolveRegistry();
    const before = await inspectRegistry(provider, registry, CHAIN_ID);
    printStatus("ก่อนเติม", before);

    const wallets = JSON.parse(fs.readFileSync(path.join(WALLET_DIR, "wallets.json"), "utf8"));
    const entry = wallets.find((w) => w.role === role);
    if (!entry) fail(`ไม่พบ role "${role}" ใน wallets.json`);
    if (role !== EXPECTED_ROLE) {
        console.log(`\n⚠️  กำลังใช้กระเป๋า ${role} ไม่ใช่ ${EXPECTED_ROLE} (กระเป๋ารางวัลมาสเตอร์โหนดตาม tokenomics)`);
    }

    const balance = await provider.getBalance(entry.address);
    console.log(`\nจาก    ${role} ${entry.address} (มี ${fmt(balance)} TPIX)`);
    console.log(`ไปที่   NodeRegistryV2.fundRewardPool() ${registry}`);
    console.log(`จำนวน  ${fmt(amountWei)} TPIX  → พูลหลังเติม ~${fmt(before.fundedBalanceWei + amountWei)} TPIX`);
    if (balance < amountWei) fail(`ยอดไม่พอ: กระเป๋ามี ${fmt(balance)} TPIX`);

    if (dryRun) {
        // ประเมินแก๊สจากที่อยู่ต้นทางจริงโดยไม่ต้องใช้กุญแจ
        const est = await provider.estimateGas({
            from: entry.address, to: registry, value: amountWei,
            data: new ethers.Interface(["function fundRewardPool() payable"]).encodeFunctionData("fundRewardPool"),
        });
        console.log(`\n[DRY_RUN] ประเมินแก๊สได้ ${est} — ไม่ได้ส่งอะไรขึ้นเชน`);
        return;
    }

    const keystores = JSON.parse(fs.readFileSync(path.join(WALLET_DIR, "master-wallet.keystores.json"), "utf8"));
    if (!keystores[role]) fail(`ไม่พบ keystore ของ "${role}"`);
    const signer = (await loadSigner(entry, keystores[role])).connect(provider);
    // กุญแจที่ถอดได้ต้องเป็นของกระเป๋าที่ตั้งใจจริง — กันคำ 12 คำของชุดอื่น/role ผิด
    if (signer.address.toLowerCase() !== entry.address.toLowerCase()) {
        fail(`กุญแจที่ได้คือ ${signer.address} ไม่ใช่กระเป๋า ${role} (${entry.address})`);
    }

    const r = await fundPool(signer, registry, amountWei);
    console.log(`\nส่งแล้ว tx ${r.txHash} · บล็อก ${r.blockNumber} · แก๊ส ${r.gasUsed}/${r.gasLimit}`);

    printStatus("หลังเติม", await inspectRegistry(provider, registry, CHAIN_ID));
}

main().catch((e) => {
    console.error(`\n❌ ${e instanceof Abort ? e.message : (e.shortMessage || e.message || String(e))}`);
    process.exitCode = 1;
});
