/**
 * Deploy TPIXBridgeVault — คลังล็อก TPIX ของสะพาน TPIX Chain (4289) ↔ wTPIX (BSC)
 *
 * Usage:
 *   cd contracts
 *   export DEPLOYER_KEY=0x...                 # กระเป๋าเจ้าของ (เป็นเจ้าของคลังถาวร — ตั้งเพดาน/relayer/unpause)
 *   export TPIX_SITE_URL=https://tpix.online
 *   export CONTRACT_REGISTRY_TOKEN=<ค่าเดียวกับใน .env ของเว็บ>
 *   export RELAYER_ADDRESS=0x...              # ที่อยู่ของ keystore relayer บนเซิร์ฟเวอร์ (BRIDGE_RELAYER_ADDRESS)
 *   export GUARDIAN_ADDRESS=0x...             # ไม่ใส่ก็ได้ — สั่ง pause ได้อย่างเดียว
 *   npx hardhat run scripts/deploy-bridge-vault.js --network tpix
 *
 *   ซ้อมก่อน: npx hardhat run scripts/deploy-bridge-vault.js   (เครือข่ายจำลองในเครื่อง ไม่แตะอะไรจริง)
 *
 * Env (optional) หน่วย TPIX เต็ม:
 *   BRIDGE_MIN_LOCK      ปริยาย 10
 *   BRIDGE_MAX_LOCK      ปริยาย 100000 — ⚠️ ต้องไม่เกิน maxPerTx ของ WTPIXBridgeMinter ฝั่ง BSC
 *                        ไม่งั้นล็อกได้แต่ mint ไม่ได้ เหรียญค้างจนกว่าจะขยายเพดานฝั่ง BSC
 *   BRIDGE_MAX_PER_TX    ปริยาย 100000 (ปล่อยต่อครั้ง)
 *   BRIDGE_DAILY_CAP     ปริยาย 500000 (ปล่อยต่อวัน UTC)
 *
 * ⚠️ เชน TPIX รับได้แค่ถึง london — สัญญานี้ pragma 0.8.24 คอมไพล์ด้วย evmVersion london (hardhat.config.js)
 *
 * Developed by Xman Studio
 */

const hre = require("hardhat");
const fs = require("fs");
const path = require("path");
const { registerWithSite, printEnvFallback } = require("./lib/register-with-site");

const REGISTRY_PATH = path.join(__dirname, "..", "deployed-contracts.json");

/** จำนวน TPIX เต็มจาก env → wei — ปฏิเสธค่าแปลก ๆ แทนที่จะเดา */
function tpixFromEnv(name, fallback) {
    const raw = (process.env[name] || "").trim() || fallback;
    if (!/^\d+(\.\d{1,18})?$/.test(raw)) throw new Error(`${name} ต้องเป็นจำนวน TPIX เช่น 100000 — ได้ "${raw}"`);
    return hre.ethers.parseEther(raw);
}

function addressFromEnv(name) {
    const raw = (process.env[name] || "").trim();
    if (!raw) return null;
    if (!/^0x[0-9a-fA-F]{40}$/.test(raw)) throw new Error(`${name} ไม่ใช่ที่อยู่: ${raw}`);
    return hre.ethers.getAddress(raw.toLowerCase());
}

const fmt = (wei) => hre.ethers.formatEther(wei);

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    if (!deployer) throw new Error("ไม่มี signer — ตั้ง DEPLOYER_KEY ก่อน");

    const chainId = Number((await hre.ethers.provider.getNetwork()).chainId);
    if (chainId !== 4289) throw new Error(`คลังต้องอยู่บนเชน TPIX (4289) — ตอนนี้ต่ออยู่กับ ${chainId}`);
    const isDryRun = hre.network.name === "hardhat" || hre.network.name === "localhost";

    const minLock = tpixFromEnv("BRIDGE_MIN_LOCK", "10");
    const maxLock = tpixFromEnv("BRIDGE_MAX_LOCK", "100000");
    const maxPerTx = tpixFromEnv("BRIDGE_MAX_PER_TX", "100000");
    const dailyCap = tpixFromEnv("BRIDGE_DAILY_CAP", "500000");
    if (minLock === 0n || maxLock < minLock) throw new Error("BRIDGE_MIN_LOCK ต้อง > 0 และ ≤ BRIDGE_MAX_LOCK");
    if (maxPerTx === 0n || dailyCap === 0n || maxPerTx > dailyCap) throw new Error("ต้องมากกว่าศูนย์ และ BRIDGE_MAX_PER_TX ≤ BRIDGE_DAILY_CAP");

    const relayer = addressFromEnv("RELAYER_ADDRESS");
    const guardian = addressFromEnv("GUARDIAN_ADDRESS");

    console.log("Network   :", hre.network.name, `(chainId ${chainId})`);
    console.log("Deployer  :", deployer.address, "← จะเป็นเจ้าของคลังถาวร");
    console.log("Lock      :", fmt(minLock), "–", fmt(maxLock), "TPIX ต่อครั้ง");
    console.log("Release   :", fmt(maxPerTx), "TPIX ต่อครั้ง ·", fmt(dailyCap), "TPIX ต่อวัน (UTC)");
    console.log("Relayer   :", relayer || "(ยังไม่ตั้ง)");
    console.log("Guardian  :", guardian || "(ยังไม่ตั้ง)\n");

    // ── Deploy ────────────────────────────────────────────────────────────────
    console.log("[1/3] Deploying TPIXBridgeVault...");
    const Vault = await hre.ethers.getContractFactory("TPIXBridgeVault", deployer);
    // เชน TPIX แก๊สเป็นศูนย์และไม่มี EIP-1559
    const overrides = isDryRun ? {} : { type: 0, gasPrice: 0 };
    const vault = await Vault.deploy(minLock, maxLock, maxPerTx, dailyCap, overrides);
    await vault.waitForDeployment();
    const vaultAddress = await vault.getAddress();
    if ((await hre.ethers.provider.getCode(vaultAddress)) === "0x") {
        throw new Error("eth_getCode คืน 0x — สัญญาไม่ได้ขึ้นเชนจริง");
    }
    console.log("   TPIXBridgeVault:", vaultAddress);

    // ── บทบาท ──────────────────────────────────────────────────────────────────
    console.log("\n[2/3] Roles");
    if (relayer) {
        await (await vault.setRelayer(relayer, true, overrides)).wait();
        console.log(`   setRelayer(${relayer}, true) ✓`);
    }
    if (guardian) {
        await (await vault.setGuardian(guardian, true, overrides)).wait();
        console.log(`   setGuardian(${guardian}, true) ✓`);
    }
    if (!relayer && !guardian) console.log("   ข้าม — ไม่ได้ตั้ง RELAYER_ADDRESS / GUARDIAN_ADDRESS");

    // ── Registry + เว็บ ────────────────────────────────────────────────────────
    console.log("\n[3/3] Registry");
    if (isDryRun) {
        console.log(`   [dry-run] เครือข่าย ${hre.network.name} — ไม่เขียน deployed-contracts.json ไม่ลงทะเบียนกับเว็บ`);
    } else {
        const registry = JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
        if (Number(registry?.chain?.chainId) !== chainId) throw new Error("deployed-contracts.json เป็นของเชนอื่น — ไม่เขียนทับ");
        registry.contracts = (registry.contracts || []).filter((c) => c.name !== "TPIXBridgeVault");
        registry.contracts.push({
            compilerVersion: "0.8.24",
            optimizer: { enabled: true, runs: 200 },
            evmVersion: "london",
            verified: false,
            deployedAt: new Date().toISOString().slice(0, 10),
            name: "TPIXBridgeVault",
            category: "bridge",
            address: vaultAddress,
            sourceFile: "contracts/src/bridge/TPIXBridgeVault.sol",
            description: `คลังล็อก TPIX ของสะพาน ↔ wTPIX (BSC) — ล็อก ${fmt(minLock)}–${fmt(maxLock)} · ปล่อย ${fmt(maxPerTx)}/ครั้ง ${fmt(dailyCap)}/วัน · ไม่มีทางถอนนอกจาก release()`,
        });
        registry.updated = new Date().toISOString().slice(0, 10);
        fs.writeFileSync(REGISTRY_PATH, JSON.stringify(registry, null, 2) + "\n");
        console.log("   Registry updated:", REGISTRY_PATH);

        const payload = { bridge_vault: vaultAddress };
        if (!(await registerWithSite(payload))) printEnvFallback(payload);
    }

    console.log("\n=== TPIXBridgeVault ===");
    console.log("Vault    :", vaultAddress);
    console.log("Owner    :", await vault.owner());

    const todo = [];
    if (!relayer) todo.push(`TPIXBridgeVault(${vaultAddress}).setRelayer(<BRIDGE_RELAYER_ADDRESS>, true)`);
    if (!guardian) todo.push(`TPIXBridgeVault(${vaultAddress}).setGuardian(<ที่อยู่ guardian>, true)   ← ไม่บังคับ`);
    todo.push("deploy ฝั่ง BSC: npx hardhat run scripts/deploy-wtpix-bsc.js --network bscTestnet (ซ้อม) แล้วค่อย --network bsc");
    todo.push(`ตั้ง BRIDGE_MAX_PER_TX ฝั่ง BSC ≥ maxLock ของคลัง (${fmt(maxLock)} TPIX)`);
    todo.push("เติม TPIX เล็กน้อยให้ relayer (แก๊สเป็น 0 แต่บัญชีต้องมีตัวตนบนเชน)");

    console.log("\nขั้นตอนที่ยังเหลือ:");
    todo.forEach((line, i) => console.log(`  ${i + 1}. ${line}`));
}

if (require.main === module) {
    main().catch((error) => {
        console.error("\n❌ deploy TPIXBridgeVault ล้มเหลว:", error.message || error);
        process.exitCode = 1;
    });
}

module.exports = { tpixFromEnv };
