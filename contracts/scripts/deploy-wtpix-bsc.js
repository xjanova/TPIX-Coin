/**
 * Deploy wTPIX (BEP-20) + WTPIXBridgeMinter บน BSC — ฝั่ง BSC ของสะพาน TPIX ↔ wTPIX
 *
 * Usage:
 *   cd contracts
 *   export DEPLOYER_KEY=0x...          # กระเป๋าเจ้าของ (ต้องมี BNB/tBNB จ่ายแก๊ส) — เป็นเจ้าของ wTPIX + minter ถาวร
 *   export RELAYER_ADDRESS=0x...       # ที่อยู่ของ keystore relayer บนเซิร์ฟเวอร์ (ใช้ใบเดียวกับสะพาน USDT ได้)
 *   export GUARDIAN_ADDRESS=0x...      # ไม่ใส่ก็ได้ — สั่ง pause ได้อย่างเดียว
 *
 *   ซ้อม (testnet):  npx hardhat run scripts/deploy-wtpix-bsc.js --network bscTestnet
 *   ของจริง:         CONFIRM_MAINNET=yes npx hardhat run scripts/deploy-wtpix-bsc.js --network bsc
 *   ซ้อมในเครื่อง:    npx hardhat run scripts/deploy-wtpix-bsc.js
 *
 * Env (optional) หน่วย TPIX เต็ม:
 *   BRIDGE_MAX_PER_TX   ปริยาย 100000 — ⚠️ ต้องไม่น้อยกว่า maxLock ของ TPIXBridgeVault
 *   BRIDGE_DAILY_CAP    ปริยาย 500000
 *   WTPIX_BSC_ADDRESS   ใช้ wTPIX ตัวที่มีอยู่แล้ว (deployer ต้องเป็นเจ้าของ) แทนการ deploy ใหม่
 *
 * หลัง deploy relayer จะ mint ได้ "ผ่าน minter เท่านั้น" — ไม่มีที่อยู่อื่นที่ mint wTPIX ได้
 * (ไม่ deploy TokenSale บน BSC อีกแล้ว: ตัวนั้น mint wTPIX โดยไม่ล็อก TPIX จริง = wTPIX ไม่มีเงินหนุน)
 *
 * Developed by Xman Studio
 */

const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

const WTPIX_FQN = "src/bridge/WTPIX_BEP20.sol:WTPIX";
const BSC_CHAINS = { 56: "BSC mainnet", 97: "BSC testnet" };

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
    const isDryRun = hre.network.name === "hardhat" || hre.network.name === "localhost";
    if (!isDryRun && !BSC_CHAINS[chainId]) throw new Error(`สคริปต์นี้สำหรับ BSC เท่านั้น — ตอนนี้ต่ออยู่กับ chainId ${chainId}`);
    if (chainId === 56 && process.env.CONFIRM_MAINNET !== "yes") {
        throw new Error("กำลังจะ deploy บน BSC mainnet — ซ้อมบน bscTestnet ก่อน แล้วตั้ง CONFIRM_MAINNET=yes เมื่อพร้อม");
    }

    const maxPerTx = tpixFromEnv("BRIDGE_MAX_PER_TX", "100000");
    const dailyCap = tpixFromEnv("BRIDGE_DAILY_CAP", "500000");
    if (maxPerTx === 0n || dailyCap === 0n || maxPerTx > dailyCap) throw new Error("ต้องมากกว่าศูนย์ และ BRIDGE_MAX_PER_TX ≤ BRIDGE_DAILY_CAP");

    const relayer = addressFromEnv("RELAYER_ADDRESS");
    const guardian = addressFromEnv("GUARDIAN_ADDRESS");
    const existingWtpix = addressFromEnv("WTPIX_BSC_ADDRESS");

    const balance = await hre.ethers.provider.getBalance(deployer.address);
    console.log("Network   :", hre.network.name, `(chainId ${chainId}${BSC_CHAINS[chainId] ? " · " + BSC_CHAINS[chainId] : ""})`);
    console.log("Deployer  :", deployer.address, `(${fmt(balance)} BNB) ← เจ้าของ wTPIX + minter ถาวร`);
    console.log("Mint cap  :", fmt(maxPerTx), "wTPIX ต่อครั้ง ·", fmt(dailyCap), "wTPIX ต่อวัน (UTC)");
    console.log("Relayer   :", relayer || "(ยังไม่ตั้ง)");
    console.log("Guardian  :", guardian || "(ยังไม่ตั้ง)\n");
    if (!isDryRun && balance === 0n) throw new Error("กระเป๋า deployer ไม่มี BNB จ่ายแก๊ส");

    // ── 1) wTPIX ───────────────────────────────────────────────────────────────
    let wtpix;
    if (existingWtpix) {
        wtpix = await hre.ethers.getContractAt(WTPIX_FQN, existingWtpix, deployer);
        const owner = await wtpix.owner();
        if (owner.toLowerCase() !== deployer.address.toLowerCase()) {
            throw new Error(`wTPIX ${existingWtpix} เป็นของ ${owner} ไม่ใช่ deployer — setMinter ให้ไม่ได้`);
        }
        console.log("[1/4] wTPIX (reused):", existingWtpix);
    } else {
        console.log("[1/4] Deploying wTPIX (BEP-20)...");
        const WTPIX = await hre.ethers.getContractFactory(WTPIX_FQN, deployer);
        wtpix = await WTPIX.deploy();
        await wtpix.waitForDeployment();
        console.log("   wTPIX:", await wtpix.getAddress());
    }
    const wtpixAddress = await wtpix.getAddress();

    // ── 2) Minter ─────────────────────────────────────────────────────────────
    console.log("\n[2/4] Deploying WTPIXBridgeMinter...");
    const Minter = await hre.ethers.getContractFactory("WTPIXBridgeMinter", deployer);
    const minter = await Minter.deploy(wtpixAddress, maxPerTx, dailyCap);
    await minter.waitForDeployment();
    const minterAddress = await minter.getAddress();
    if ((await hre.ethers.provider.getCode(minterAddress)) === "0x") throw new Error("minter ไม่มีโค้ดบนเชน");
    console.log("   WTPIXBridgeMinter:", minterAddress);

    // ── 3) ผูกสิทธิ์ ─────────────────────────────────────────────────────────────
    console.log("\n[3/4] Roles");
    await (await wtpix.setMinter(minterAddress, true)).wait();
    console.log("   wTPIX.setMinter(minter, true) ✓  ← ทางเดียวที่ mint wTPIX ได้");
    if (relayer) {
        await (await minter.setRelayer(relayer, true)).wait();
        console.log(`   minter.setRelayer(${relayer}, true) ✓`);
    }
    if (guardian) {
        await (await minter.setGuardian(guardian, true)).wait();
        console.log(`   minter.setGuardian(${guardian}, true) ✓`);
    }

    // ── 4) บันทึก ──────────────────────────────────────────────────────────────
    console.log("\n[4/4] Record");
    const record = {
        network: hre.network.name,
        chainId,
        deployedAt: new Date().toISOString(),
        owner: deployer.address,
        wtpix: { address: wtpixAddress, sourceFile: "contracts/src/bridge/WTPIX_BEP20.sol", contract: "WTPIX" },
        minter: {
            address: minterAddress,
            sourceFile: "contracts/src/bridge/WTPIXBridgeMinter.sol",
            maxPerTx: fmt(maxPerTx),
            dailyCap: fmt(dailyCap),
        },
        compiler: { version: "0.8.24", optimizer: { enabled: true, runs: 200 }, evmVersion: "london" },
    };
    if (isDryRun) {
        console.log(`   [dry-run] เครือข่าย ${hre.network.name} — ไม่เขียนไฟล์บันทึก`);
    } else {
        const out = path.join(__dirname, "..", "deployments", `wtpix-bsc-${chainId}.json`);
        fs.mkdirSync(path.dirname(out), { recursive: true });
        fs.writeFileSync(out, JSON.stringify(record, null, 2) + "\n");
        console.log("   บันทึกที่", out);
    }

    console.log("\n" + "─".repeat(72));
    console.log("ใส่ใน .env ของเว็บ แล้วรัน php artisan config:cache");
    console.log("─".repeat(72));
    console.log(`WTPIX_BSC_ADDRESS=${wtpixAddress}`);
    console.log(`WTPIX_BSC_MINTER_ADDRESS=${minterAddress}`);
    if (chainId === 97) {
        console.log("# ⚠️ ที่อยู่ข้างบนเป็นของ BSC testnet (chainId 97) — ห้ามใช้กับเว็บจริงตอนเปิดใช้งาน");
    }

    const todo = [];
    if (!relayer) todo.push(`WTPIXBridgeMinter(${minterAddress}).setRelayer(<ที่อยู่ relayer ของเซิร์ฟเวอร์>, true)`);
    if (!guardian) todo.push(`WTPIXBridgeMinter(${minterAddress}).setGuardian(<ที่อยู่ guardian>, true)   ← ไม่บังคับ`);
    todo.push("เติม BNB ให้ relayer ไว้จ่ายแก๊ส mint (ครั้งละไม่กี่เซ็นต์)");
    todo.push("verify ซอร์สบน BscScan: Verify & Publish → Solidity (Standard JSON) จาก artifacts/build-info");
    todo.push("ย้ายเจ้าของไป multisig (Safe) ก่อนเปิดพูลใหญ่: transferOwnership → acceptOwnership");

    console.log("\nขั้นตอนที่ยังเหลือ:");
    todo.forEach((line, i) => console.log(`  ${i + 1}. ${line}`));
}

if (require.main === module) {
    main().catch((error) => {
        console.error("\n❌ deploy wTPIX บน BSC ล้มเหลว:", error.message || error);
        process.exitCode = 1;
    });
}
