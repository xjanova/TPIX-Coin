/**
 * Deploy TPIX DEX (AMM แบบ Uniswap V2) บน TPIX Chain 4289
 *
 * ลำดับ:
 *   1. WTPIX      — reuse จาก registry ถ้ามี ไม่มีก็ deploy ใหม่ (WETH9 wrapper)
 *   2. USDT_TPIX  — reuse จาก registry ถ้ามี ไม่มีก็ deploy ใหม่ (quote token, 6 decimals)
 *   3. TPIXDEXFactory   — feeToSetter = deployer
 *   4. TPIXDEXRouter02  — ผูก factory + WTPIX
 *   5. (option) setFeeTo(FEE_COLLECTOR) — เปิด protocol fee 1/6 ของ fee growth
 *   6. (option) seed pool TPIX/USDT — mint USDT ให้ deployer ชั่วคราวแล้ว addLiquidityETH
 *
 * Usage:
 *   cd contracts
 *   DEPLOYER_KEY=0x... npx hardhat run scripts/deploy-dex.js --network tpix
 *
 * Env (optional):
 *   FEE_COLLECTOR=0x...   address รับ protocol fee (แนะนำ = fee_collector_wallet ของ TPIX TRADE)
 *   LIQ_TPIX=1000000      จำนวน native TPIX ที่จะเติม pool (หน่วยเต็ม ไม่ใช่ wei)
 *   LIQ_USDT=100000       จำนวน USDT ที่จะเติม pool (หน่วยเต็ม — ราคาเปิด = LIQ_USDT/LIQ_TPIX $/TPIX)
 *                         seed จะทำงานก็ต่อเมื่อตั้งทั้งคู่ และ deployer เป็น owner ของ USDT_TPIX
 *
 * หลัง deploy: script เขียน address ลง
 *   - deployed-contracts.json (registry)
 *   - ../../ThaiXTrade/resources/js/Config/dexContracts.json (frontend, ถ้า repo อยู่ข้างกัน)
 *   - ../../ThaiXTrade/storage/app/tpix/deployments.json (backend)
 *
 * Developed by Xman Studio
 */

const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

const REGISTRY_PATH = path.join(__dirname, "..", "deployed-contracts.json");

function loadRegistry() {
    return JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
}

function findContract(registry, name) {
    const entry = registry.contracts.find((c) => c.name === name);
    return entry ? entry.address : null;
}

function upsertContract(registry, entry) {
    const idx = registry.contracts.findIndex((c) => c.name === entry.name);
    if (idx >= 0) {
        registry.contracts[idx] = { ...registry.contracts[idx], ...entry };
    } else {
        registry.contracts.push(entry);
    }
}

/**
 * ตรวจว่า registry ที่โหลดมาเป็นของเชนที่กำลัง deploy จริง
 *
 * เพิ่ม 2026-08-05 (SECURITY-AUDIT ข้อ R1):
 * deployed-contracts.json มี `chain.chainId` เดียวทั้งไฟล์ แต่ findContract()
 * กับ upsertContract() จับคู่ด้วย "ชื่อสัญญาเปล่าๆ" ไม่มี chainId กำกับ
 * และมีสัญญาชื่อซ้ำกันจริงระหว่างเชน — `WTPIX` มีทั้งบน BSC (WTPIX_BEP20)
 * และบน TPIX Chain (WTPIX_ERC20)
 *
 * ถ้าเผลอรัน deploy ของเชนอื่นแล้วเขียนลงไฟล์เดียวกัน:
 *   - findContract("WTPIX") จะคืน address ของ "อีกเชนหนึ่ง"
 *   - script จะข้ามการ deploy wrapper แล้วผูก Router กับ address ที่ผิด
 *   - WTPIX_BEP20 ไม่มี deposit()/withdraw() → ทุก path ที่ใช้ native TPIX
 *     (swapExactETHForTokens / addLiquidityETH) ตายหมด และรู้ตัวหลัง deploy แล้ว
 *
 * ด่านนี้ทำให้พลาดแบบนั้นหยุดก่อนเสียแก๊ส แทนที่จะไปเจอตอนใช้งาน
 */
async function assertRegistryChain(registry) {
    const net = await hre.ethers.provider.getNetwork();
    const live = Number(net.chainId);
    const expected = Number(registry?.chain?.chainId);

    if (!expected) {
        throw new Error(
            `deployed-contracts.json ไม่มี chain.chainId — ห้าม deploy ต่อ ` +
            `เพราะ findContract() จับคู่ด้วยชื่อเปล่าๆ อาจหยิบ address ของเชนอื่นมาใช้`
        );
    }
    if (expected !== live) {
        throw new Error(
            `chainId ไม่ตรงกัน: registry = ${expected} (${registry.chain?.name ?? "?"}) ` +
            `แต่กำลังต่อกับเชน ${live}\n` +
            `ถ้าจะ deploy ลงเชน ${live} ให้ใช้ไฟล์ registry แยกของเชนนั้น ` +
            `อย่าเขียนทับไฟล์นี้ (ชื่อสัญญาซ้ำกันข้ามเชน เช่น WTPIX)`
        );
    }
    console.log(`Registry chain: ${expected} (${registry.chain?.name ?? "?"}) — ตรงกับเชนที่ต่ออยู่\n`);
}

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    const registry = loadRegistry();
    await assertRegistryChain(registry);

    console.log("Deployer:", deployer.address);
    console.log(
        "Balance:",
        hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)),
        "TPIX\n"
    );

    // -------------------------------------------------------------------
    // [1/6] WTPIX — reuse หรือ deploy
    // -------------------------------------------------------------------
    let wtpixAddress = findContract(registry, "WTPIX");
    if (wtpixAddress) {
        console.log("[1/6] WTPIX (reused):", wtpixAddress);
    } else {
        console.log("[1/6] Deploying WTPIX...");
        // fully qualified — กันชนกับ contract WTPIX ใน src/bridge/WTPIX_BEP20.sol
        const WTPIX = await hre.ethers.getContractFactory("src/sale/WTPIX_ERC20.sol:WTPIX");
        const wtpix = await WTPIX.deploy();
        await wtpix.waitForDeployment();
        wtpixAddress = await wtpix.getAddress();
        console.log("   WTPIX:", wtpixAddress);
        upsertContract(registry, {
            name: "WTPIX",
            category: "wrapper",
            address: wtpixAddress,
            sourceFile: "contracts/src/sale/WTPIX_ERC20.sol",
            compilerVersion: "0.8.20",
            optimizer: { enabled: true, runs: 200 },
            verified: false,
            description: "Wrapped TPIX (ERC-20) — WETH9 pattern. 1:1 backed by native TPIX.",
        });
    }

    // -------------------------------------------------------------------
    // [2/6] USDT_TPIX — reuse หรือ deploy
    // -------------------------------------------------------------------
    let usdtAddress = findContract(registry, "USDT_TPIX");
    if (usdtAddress) {
        console.log("[2/6] USDT_TPIX (reused):", usdtAddress);
    } else {
        console.log("[2/6] Deploying USDT_TPIX...");
        const USDT = await hre.ethers.getContractFactory("USDT_TPIX");
        const usdt = await USDT.deploy();
        await usdt.waitForDeployment();
        usdtAddress = await usdt.getAddress();
        console.log("   USDT_TPIX:", usdtAddress);
        upsertContract(registry, {
            name: "USDT_TPIX",
            category: "bridge-token",
            address: usdtAddress,
            sourceFile: "contracts/src/bridge/USDT_TPIX.sol",
            compilerVersion: "0.8.20",
            optimizer: { enabled: true, runs: 200 },
            verified: false,
            description: "Bridged Tether บน TPIX Chain (6 decimals) — mint/burn เฉพาะ relayer whitelist.",
        });
    }

    // -------------------------------------------------------------------
    // [3/6] TPIXDEXFactory
    // -------------------------------------------------------------------
    let factoryAddress = findContract(registry, "TPIXDEXFactory");
    let factory;
    if (factoryAddress) {
        console.log("[3/6] TPIXDEXFactory (reused):", factoryAddress);
        factory = await hre.ethers.getContractAt("TPIXDEXFactory", factoryAddress);
    } else {
        console.log("[3/6] Deploying TPIXDEXFactory...");
        const Factory = await hre.ethers.getContractFactory("TPIXDEXFactory");
        factory = await Factory.deploy(deployer.address);
        await factory.waitForDeployment();
        factoryAddress = await factory.getAddress();
        console.log("   TPIXDEXFactory:", factoryAddress);
        upsertContract(registry, {
            name: "TPIXDEXFactory",
            category: "dex",
            address: factoryAddress,
            sourceFile: "contracts/src/dex/amm/TPIXDEXFactory.sol",
            compilerVersion: "0.8.20",
            optimizer: { enabled: true, runs: 200 },
            verified: false,
            description: "Uniswap V2-style factory — ทะเบียน liquidity pair ทั้งหมดของ TPIX DEX",
        });
    }

    // -------------------------------------------------------------------
    // [4/6] TPIXDEXRouter02
    // -------------------------------------------------------------------
    let routerAddress = findContract(registry, "TPIXDEXRouter02");
    let router;
    if (routerAddress) {
        console.log("[4/6] TPIXDEXRouter02 (reused):", routerAddress);
        router = await hre.ethers.getContractAt("TPIXDEXRouter02", routerAddress);
    } else {
        console.log("[4/6] Deploying TPIXDEXRouter02...");
        const Router = await hre.ethers.getContractFactory("TPIXDEXRouter02");
        router = await Router.deploy(factoryAddress, wtpixAddress);
        await router.waitForDeployment();
        routerAddress = await router.getAddress();
        console.log("   TPIXDEXRouter02:", routerAddress);
        upsertContract(registry, {
            name: "TPIXDEXRouter02",
            category: "dex",
            address: routerAddress,
            sourceFile: "contracts/src/dex/amm/TPIXDEXRouter02.sol",
            compilerVersion: "0.8.20",
            optimizer: { enabled: true, runs: 200 },
            verified: false,
            description: "Uniswap V2-style router — swap + add/remove liquidity (WETH = WTPIX)",
        });
    }

    // -------------------------------------------------------------------
    // [5/6] Protocol fee (optional)
    // -------------------------------------------------------------------
    const feeCollector = process.env.FEE_COLLECTOR;
    if (feeCollector && hre.ethers.isAddress(feeCollector)) {
        const currentFeeTo = await factory.feeTo();
        if (currentFeeTo.toLowerCase() !== feeCollector.toLowerCase()) {
            console.log("[5/6] setFeeTo:", feeCollector);
            await (await factory.setFeeTo(feeCollector)).wait();
        } else {
            console.log("[5/6] feeTo already set:", currentFeeTo);
        }
    } else {
        console.log("[5/6] FEE_COLLECTOR not set — ข้าม protocol fee (LP ได้ fee 0.3% เต็ม)");
    }

    // -------------------------------------------------------------------
    // [6/6] Seed TPIX/USDT pool (optional)
    // -------------------------------------------------------------------
    const liqTpix = process.env.LIQ_TPIX;
    const liqUsdt = process.env.LIQ_USDT;
    if (liqTpix && liqUsdt) {
        console.log(`[6/6] Seeding pool: ${liqTpix} TPIX + ${liqUsdt} USDT`);
        const tpixWei = hre.ethers.parseEther(liqTpix);
        const usdtUnits = hre.ethers.parseUnits(liqUsdt, 6);

        const usdt = await hre.ethers.getContractAt("USDT_TPIX", usdtAddress);
        const owner = await usdt.owner();
        if (owner.toLowerCase() !== deployer.address.toLowerCase()) {
            throw new Error("Seed ต้องให้ deployer เป็น owner ของ USDT_TPIX (เพื่อ mint initial liquidity)");
        }

        const balance = await usdt.balanceOf(deployer.address);
        if (balance < usdtUnits) {
            // mint ส่วนที่ขาดผ่าน bridge whitelist ชั่วคราว — sourceTxHash ใช้ marker กัน replay
            console.log("   Minting USDT for initial liquidity...");
            await (await usdt.setBridge(deployer.address, true)).wait();
            const marker = hre.ethers.id(`dex-initial-liquidity-${Date.now()}`);
            await (await usdt.bridgeMint(deployer.address, usdtUnits - balance, marker)).wait();
            await (await usdt.setBridge(deployer.address, false)).wait();
        }

        console.log("   Approving router...");
        await (await usdt.approve(routerAddress, usdtUnits)).wait();

        console.log("   addLiquidityETH...");
        const deadline = Math.floor(Date.now() / 1000) + 1200;
        await (
            await router.addLiquidityETH(
                usdtAddress,
                usdtUnits,
                usdtUnits,   // pool ใหม่ — ไม่มี slippage
                tpixWei,
                deployer.address,
                deadline,
                { value: tpixWei }
            )
        ).wait();

        const pairAddress = await factory.getPair(wtpixAddress, usdtAddress);
        console.log("   Pair WTPIX/USDT:", pairAddress);
        console.log(`   ราคาเปิด: ${(Number(liqUsdt) / Number(liqTpix)).toFixed(6)} USDT/TPIX`);
        upsertContract(registry, {
            name: "TPIXDEXPair_WTPIX_USDT",
            category: "dex",
            address: pairAddress,
            sourceFile: "contracts/src/dex/amm/TPIXDEXPair.sol",
            compilerVersion: "0.8.20",
            optimizer: { enabled: true, runs: 200 },
            verified: false,
            description: "Liquidity pair WTPIX/USDT — pool หลักของกระดาน TPIX/USDT",
        });
    } else {
        console.log("[6/6] LIQ_TPIX/LIQ_USDT not set — ข้าม seed pool (เติมทีหลังผ่าน router ได้)");
    }

    // -------------------------------------------------------------------
    // Write registry + sync ไป ThaiXTrade (ถ้า repo อยู่ข้างกัน)
    // -------------------------------------------------------------------
    registry.updated = new Date().toISOString().slice(0, 10);
    fs.writeFileSync(REGISTRY_PATH, JSON.stringify(registry, null, 2) + "\n");
    console.log("\nRegistry updated:", REGISTRY_PATH);

    const dexConfig = {
        chainId: 4289,
        rpc: "https://rpc.tpix.online",
        updated: new Date().toISOString(),
        WTPIX: wtpixAddress,
        USDT: usdtAddress,
        FACTORY: factoryAddress,
        ROUTER: routerAddress,
    };

    const thaiXTradeRoot = path.join(__dirname, "..", "..", "..", "ThaiXTrade");
    const frontendConfig = path.join(thaiXTradeRoot, "resources", "js", "Config", "dexContracts.json");
    const backendDir = path.join(thaiXTradeRoot, "storage", "app", "tpix");

    if (fs.existsSync(path.dirname(frontendConfig))) {
        fs.writeFileSync(frontendConfig, JSON.stringify(dexConfig, null, 2) + "\n");
        console.log("Frontend config updated:", frontendConfig);
    } else {
        console.log("ThaiXTrade repo not found — copy addresses to dexContracts.json manually:");
        console.log(JSON.stringify(dexConfig, null, 2));
    }

    if (fs.existsSync(path.dirname(backendDir))) {
        fs.mkdirSync(backendDir, { recursive: true });
        fs.writeFileSync(
            path.join(backendDir, "deployments.json"),
            JSON.stringify(dexConfig, null, 2) + "\n"
        );
        console.log("Backend deployments.json updated");
    }

    console.log("\n=== TPIX DEX DEPLOYED ===");
    console.log("WTPIX:  ", wtpixAddress);
    console.log("USDT:   ", usdtAddress);
    console.log("Factory:", factoryAddress);
    console.log("Router: ", routerAddress);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
