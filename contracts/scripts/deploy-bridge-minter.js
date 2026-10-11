/**
 * Deploy TPIXBridgeMinter — ด่านจำกัดอัตราการ mint ของสะพาน USDT → TPIX Chain (4289)
 *
 * หลัง deploy ตัวนี้ต้องเป็น "ที่อยู่เดียว" ที่ USDT_TPIX.bridges[...] = true
 * relayer บนเซิร์ฟเวอร์ mint ผ่านตัวนี้เท่านั้น → คีย์ relayer หลุด เสียหายได้ไม่เกิน dailyCap ต่อวัน
 *
 * Usage:
 *   cd contracts
 *   export DEPLOYER_KEY=0x...                 # เจ้าของ (ควรเป็นเจ้าของ USDT_TPIX ด้วย ถ้าจะให้สคริปต์ทำขั้นต่อให้)
 *   export TPIX_SITE_URL=https://tpix.online
 *   export CONTRACT_REGISTRY_TOKEN=<ค่าเดียวกับใน .env ของเว็บ>
 *   npx hardhat run scripts/deploy-bridge-minter.js --network tpix
 *
 *   (หรือใช้ .\scripts\deploy-bridge-minter.ps1 ซึ่งถามคีย์แบบซ่อนให้)
 *
 * Env (optional):
 *   USDT_TPIX_ADDRESS    ที่อยู่ USDT_TPIX (ปริยาย = ใน deployed-contracts.json)
 *   BRIDGE_MAX_PER_TX    เพดานต่อครั้ง หน่วย USDT เต็ม (ปริยาย 1000)
 *   BRIDGE_DAILY_CAP     เพดานต่อวัน UTC หน่วย USDT เต็ม (ปริยาย 5000)
 *   REDEPLOY=1           deploy ตัวใหม่แม้ registry มีตัวที่ใช้งานได้อยู่แล้ว
 *
 *   APPLY_OWNER_STEPS=1  ทำขั้นตอนของเจ้าของให้เลย (ต้องให้ deployer เป็นเจ้าของ USDT_TPIX):
 *     RELAYER_ADDRESS    ที่อยู่ของ keystore relayer บนเซิร์ฟเวอร์ (BRIDGE_RELAYER_KEYSTORE)
 *     GUARDIAN_ADDRESS   ที่อยู่ของ keystore guardian บนเซิร์ฟเวอร์ (BRIDGE_GUARDIAN_KEYSTORE) — ไม่ใส่ก็ได้
 *     → USDT_TPIX.setBridge(minter, true) · minter.setRelayer(relayer, true) · minter.setGuardian(guardian, true)
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
const USDT_DECIMALS = 6;

function loadRegistry() {
    return JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
}

function findContract(registry, name) {
    const entry = (registry.contracts || []).find((c) => c.name === name);
    return entry ? entry.address : null;
}

function upsertContract(registry, entry) {
    registry.contracts = registry.contracts || [];
    const idx = registry.contracts.findIndex((c) => c.name === entry.name);
    if (idx >= 0) registry.contracts[idx] = { ...registry.contracts[idx], ...entry };
    else registry.contracts.push(entry);
}

/** registry ต้องเป็นของเชนที่กำลังต่ออยู่ (ชื่อสัญญาซ้ำข้ามเชนได้ — ดู deploy-dex.js) */
async function assertRegistryChain(registry) {
    const live = Number((await hre.ethers.provider.getNetwork()).chainId);
    const expected = Number(registry?.chain?.chainId);
    if (!expected) throw new Error("deployed-contracts.json ไม่มี chain.chainId — ห้าม deploy ต่อ");
    if (expected !== live) throw new Error(`chainId ไม่ตรงกัน: registry = ${expected} แต่กำลังต่อกับเชน ${live}`);
}

/** อ่านจำนวน USDT เต็มจาก env เป็นหน่วย 6 ทศนิยม — ปฏิเสธค่าแปลก ๆ แทนที่จะเดา */
function capFromEnv(name, fallback) {
    const raw = (process.env[name] || "").trim() || fallback;
    if (!/^\d+(\.\d{1,6})?$/.test(raw)) throw new Error(`${name} ต้องเป็นจำนวน USDT เช่น 1000 — ได้ "${raw}"`);
    return hre.ethers.parseUnits(raw, USDT_DECIMALS);
}

function addressFromEnv(name) {
    const raw = (process.env[name] || "").trim();
    if (!raw) return null;
    if (!/^0x[0-9a-fA-F]{40}$/.test(raw)) throw new Error(`${name} ไม่ใช่ที่อยู่: ${raw}`);
    return hre.ethers.getAddress(raw.toLowerCase());
}

const fmt = (units) => hre.ethers.formatUnits(units, USDT_DECIMALS);

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    if (!deployer) throw new Error("ไม่มี signer — ตั้ง DEPLOYER_KEY ก่อน");

    const registry = loadRegistry();
    await assertRegistryChain(registry);
    const isDryRun = hre.network.name === "hardhat" || hre.network.name === "localhost";

    // ── USDT_TPIX ────────────────────────────────────────────────────────────
    let usdtAddress = addressFromEnv("USDT_TPIX_ADDRESS") || findContract(registry, "USDT_TPIX");
    if (!usdtAddress) throw new Error("ไม่พบที่อยู่ USDT_TPIX — ตั้ง USDT_TPIX_ADDRESS");
    if ((await hre.ethers.provider.getCode(usdtAddress)) === "0x") {
        if (!isDryRun) throw new Error(`USDT_TPIX ${usdtAddress} ไม่มีโค้ดบนเชนนี้`);
        // ซ้อมบนเครือข่ายจำลอง — ไม่มีเหรียญจริงให้ผูก จึง deploy ตัวชั่วคราวขึ้นมาแทน
        const Usdt = await hre.ethers.getContractFactory("USDT_TPIX", deployer);
        const local = await Usdt.deploy();
        await local.waitForDeployment();
        usdtAddress = await local.getAddress();
        console.log(`[dry-run] ใช้ USDT_TPIX จำลองที่ ${usdtAddress}`);
    }
    const usdt = await hre.ethers.getContractAt("USDT_TPIX", usdtAddress, deployer);
    const decimals = Number(await usdt.decimals());
    if (decimals !== USDT_DECIMALS) throw new Error(`USDT_TPIX decimals = ${decimals} ไม่ใช่ 6 — ผิดตัว?`);
    const usdtOwner = await usdt.owner();

    const maxPerTx = capFromEnv("BRIDGE_MAX_PER_TX", "1000");
    const dailyCap = capFromEnv("BRIDGE_DAILY_CAP", "5000");
    if (maxPerTx === 0n || dailyCap === 0n || maxPerTx > dailyCap) {
        throw new Error("เพดานไม่ถูกต้อง: ต้องมากกว่าศูนย์ และ BRIDGE_MAX_PER_TX ≤ BRIDGE_DAILY_CAP");
    }

    console.log("Deployer   :", deployer.address);
    console.log("USDT_TPIX  :", usdtAddress, `(owner ${usdtOwner}, supply ${fmt(await usdt.totalSupply())})`);
    console.log("maxPerTx   :", fmt(maxPerTx), "USDT");
    console.log("dailyCap   :", fmt(dailyCap), "USDT / วัน (UTC)\n");

    // ── Deploy (หรือใช้ตัวเดิม) ──────────────────────────────────────────────
    let minterAddress = findContract(registry, "TPIXBridgeMinter");
    let minter = null;
    if (minterAddress && process.env.REDEPLOY !== "1" && (await hre.ethers.provider.getCode(minterAddress)) !== "0x") {
        minter = await hre.ethers.getContractAt("TPIXBridgeMinter", minterAddress, deployer);
        if ((await minter.token()).toLowerCase() !== usdtAddress.toLowerCase()) {
            throw new Error(`TPIXBridgeMinter ใน registry ผูกกับเหรียญคนละตัว — ตั้ง REDEPLOY=1 ถ้าตั้งใจ deploy ใหม่`);
        }
        console.log("[1/3] TPIXBridgeMinter (reused):", minterAddress);
    } else {
        console.log("[1/3] Deploying TPIXBridgeMinter...");
        const Minter = await hre.ethers.getContractFactory("TPIXBridgeMinter", deployer);
        minter = await Minter.deploy(usdtAddress, maxPerTx, dailyCap);
        await minter.waitForDeployment();
        minterAddress = await minter.getAddress();
        if ((await hre.ethers.provider.getCode(minterAddress)) === "0x") {
            throw new Error("eth_getCode คืน 0x — สัญญาไม่ได้ขึ้นเชนจริง");
        }
        console.log("   TPIXBridgeMinter:", minterAddress);

        upsertContract(registry, {
            compilerVersion: "0.8.24",
            optimizer: { enabled: true, runs: 200 },
            evmVersion: "london",
            verified: false,
            deployedAt: new Date().toISOString().slice(0, 10),
            name: "TPIXBridgeMinter",
            category: "bridge",
            address: minterAddress,
            sourceFile: "contracts/src/bridge/TPIXBridgeMinter.sol",
            description: `ด่านจำกัดอัตรา mint ของ USDT_TPIX (maxPerTx ${fmt(maxPerTx)} · dailyCap ${fmt(dailyCap)} USDT) — relayer mint ได้, guardian pause ได้`,
        });
    }

    // ── ขั้นตอนของเจ้าของ (ไม่บังคับ) ───────────────────────────────────────
    const relayer = addressFromEnv("RELAYER_ADDRESS");
    const guardian = addressFromEnv("GUARDIAN_ADDRESS");
    const applySteps = process.env.APPLY_OWNER_STEPS === "1";
    const isUsdtOwner = usdtOwner.toLowerCase() === deployer.address.toLowerCase();
    const done = { setBridge: false, relayer: false, guardian: false };

    if (applySteps) {
        if (!isUsdtOwner) {
            console.log(`\n[2/3] ข้าม — deployer ไม่ใช่เจ้าของ USDT_TPIX (${usdtOwner}) จึงสั่ง setBridge ไม่ได้`);
        } else {
            console.log("\n[2/3] ขั้นตอนของเจ้าของ");
            if (!(await usdt.bridges(minterAddress))) {
                await (await usdt.setBridge(minterAddress, true)).wait();
                console.log("   USDT_TPIX.setBridge(minter, true) ✓");
            } else {
                console.log("   USDT_TPIX.bridges(minter) = true อยู่แล้ว");
            }
            done.setBridge = true;

            // กันลืม: deployer เคยเป็น bridge ชั่วคราวตอน seed พูล — ต้องไม่ค้างสิทธิ์ mint ไว้
            if (await usdt.bridges(deployer.address)) {
                await (await usdt.setBridge(deployer.address, false)).wait();
                console.log("   ถอนสิทธิ์ mint ตรงของ deployer ✓ (เหลือ minter เป็นทางเดียว)");
            }

            if (relayer) {
                if (!(await minter.relayers(relayer))) await (await minter.setRelayer(relayer, true)).wait();
                console.log(`   minter.setRelayer(${relayer}, true) ✓`);
                done.relayer = true;
            }
            if (guardian) {
                if (!(await minter.guardians(guardian))) await (await minter.setGuardian(guardian, true)).wait();
                console.log(`   minter.setGuardian(${guardian}, true) ✓`);
                done.guardian = true;
            }
        }
    } else {
        console.log("\n[2/3] APPLY_OWNER_STEPS ไม่ได้ตั้ง — ขั้นตอนของเจ้าของพิมพ์ไว้ด้านล่าง");
    }

    // ── บันทึก + ลงทะเบียนกับเว็บ ─────────────────────────────────────────────
    console.log("\n[3/3] Registry");
    if (isDryRun) {
        console.log(`   [dry-run] เครือข่าย ${hre.network.name} — ไม่เขียน deployed-contracts.json ไม่ลงทะเบียนกับเว็บ`);
    } else {
        registry.updated = new Date().toISOString().slice(0, 10);
        fs.writeFileSync(REGISTRY_PATH, JSON.stringify(registry, null, 2) + "\n");
        console.log("   Registry updated:", REGISTRY_PATH);
    }

    const payload = { bridge_minter: minterAddress };
    const registered = isDryRun ? false : await registerWithSite(payload);
    if (!registered && !isDryRun) printEnvFallback(payload);

    // ── สรุป + ขั้นตอนที่ยังเหลือ ─────────────────────────────────────────────
    console.log("\n=== TPIXBridgeMinter ===");
    console.log("Minter   :", minterAddress);
    console.log("Token    :", usdtAddress);
    console.log("Owner    :", await minter.owner());
    console.log("maxPerTx :", fmt(await minter.maxPerTx()), "USDT");
    console.log("dailyCap :", fmt(await minter.dailyCap()), "USDT");

    const todo = [];
    if (!done.setBridge) todo.push(`USDT_TPIX(${usdtAddress}).setBridge(${minterAddress}, true)   ← จากกระเป๋าเจ้าของ ${usdtOwner}`);
    if (!done.relayer) todo.push(`TPIXBridgeMinter(${minterAddress}).setRelayer(<ที่อยู่ keystore relayer>, true)`);
    if (!done.guardian) todo.push(`TPIXBridgeMinter(${minterAddress}).setGuardian(<ที่อยู่ keystore guardian>, true)`);
    todo.push("ตรวจว่าไม่มีที่อยู่อื่นค้าง bridges[...] = true บน USDT_TPIX (ดู event BridgeSet) — minter ต้องเป็นทางเดียว");
    todo.push("เติม TPIX เล็กน้อยให้ relayer และ guardian (แก๊สเป็น 0 แต่บัญชีต้องมีตัวตนบนเชน)");

    console.log("\nขั้นตอนที่ยังเหลือ:");
    todo.forEach((line, i) => console.log(`  ${i + 1}. ${line}`));
}

if (require.main === module) {
    main().catch((error) => {
        console.error("\n❌ deploy TPIXBridgeMinter ล้มเหลว:", error.message || error);
        process.exitCode = 1;
    });
}

module.exports = { capFromEnv };
