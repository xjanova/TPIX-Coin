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
 *   7. **ลงทะเบียนที่อยู่กับเว็บให้เอง** (wtpix / usdt_tpix / dex_factory / dex_router)
 *      → dex:sync บนเว็บเปิดเชน 4289 เป็น live และสร้างคู่เทรดจากพูลจริงภายใน 1 นาที
 *
 * Usage:
 *   cd contracts
 *   export DEPLOYER_KEY=0x...
 *   export TPIX_SITE_URL=https://tpix.online
 *   export CONTRACT_REGISTRY_TOKEN=<ค่าเดียวกับใน .env ของเว็บ>
 *   FEE_COLLECTOR=0x... LIQ_TPIX=1000000 LIQ_USDT=200000 npx hardhat run scripts/deploy-dex.js --network tpix
 *
 * Env (optional):
 *   FEE_COLLECTOR=0x...   address รับ protocol fee (แนะนำ = fee_collector_wallet ของ TPIX TRADE)
 *   LIQ_TPIX=1000000      จำนวน native TPIX ที่จะเติม pool (หน่วยเต็ม ไม่ใช่ wei)
 *   LIQ_USDT=100000       จำนวน USDT ที่จะเติม pool (หน่วยเต็ม — ราคาเปิด = LIQ_USDT/LIQ_TPIX $/TPIX)
 *                         seed จะทำงานก็ต่อเมื่อตั้งทั้งคู่ และ deployer เป็น owner ของ USDT_TPIX
 *
 * ⚠️ เชน TPIX รับได้แค่ถึง london — hardhat.config.js ตั้ง evmVersion "london" ไว้แล้ว
 *    ตรวจก่อนได้ด้วย node scripts/check-deployable.js (อ่านอย่างเดียว ไม่ต้องมีคีย์)
 *
 * หลัง deploy: script เขียน address ลง
 *   - deployed-contracts.json (registry)
 *   - ../../ThaiXTrade/resources/js/Config/dexContracts.json (ค่าตั้งต้นของหน้าเว็บ ถ้า repo อยู่ข้างกัน)
 *   - ../../ThaiXTrade/storage/app/tpix/deployments.json (backend)
 *
 * Developed by Xman Studio
 */

const hre = require("hardhat");
const fs = require("fs");
const path = require("path");
const { registerWithSite, printEnvFallback } = require("./lib/register-with-site");

const REGISTRY_PATH = path.join(__dirname, "..", "deployed-contracts.json");

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
    if (idx >= 0) {
        registry.contracts[idx] = { ...registry.contracts[idx], ...entry };
    } else {
        registry.contracts.push(entry);
    }
    delete registry._contractsNote;
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

/** ที่อยู่ที่ registry จำไว้ต้องมีโค้ดอยู่จริง — เชนเคย regenesis แล้วที่อยู่ค้างในไฟล์ */
async function reusable(registry, name) {
    const address = findContract(registry, name);
    if (!address) return null;
    const code = await hre.ethers.provider.getCode(address);
    if (code === "0x") {
        console.log(`   ${name} ใน registry (${address}) ไม่มีโค้ดบนเชนแล้ว — deploy ใหม่`);
        return null;
    }
    return address;
}

/** deploy แล้วยืนยันว่ามี bytecode อยู่บนเชนจริง (อย่าเชื่อแค่ receipt) */
async function deployVerified(label, factory, args = []) {
    const c = await factory.deploy(...args);
    await c.waitForDeployment();
    const address = await c.getAddress();
    if ((await hre.ethers.provider.getCode(address)) === "0x") {
        throw new Error(`${label}: eth_getCode คืน 0x — สัญญาไม่ได้ขึ้นเชนจริง`);
    }
    return { address, contract: c };
}

/**
 * deploy ชุด DEX ทั้งหมด — เรียกจาก main() ที่นี่ หรือจาก deploy-all.js
 *
 * @param {object} options
 * @param {import('ethers').Signer} options.deployer
 * @param {object} options.registry  deployed-contracts.json ที่โหลดแล้ว (จะถูก upsert ในที่)
 * @param {boolean} [options.quiet]
 * @returns {Promise<{WTPIX:string, USDT:string, FACTORY:string, ROUTER:string, PAIR_TPIX_USDT?:string}>}
 */
async function deployDex({ deployer, registry }) {
    const meta = (extra) => ({
        compilerVersion: "0.8.20",
        optimizer: { enabled: true, runs: 200 },
        evmVersion: "london",
        verified: false,
        deployedAt: new Date().toISOString().slice(0, 10),
        ...extra,
    });

    // -------------------------------------------------------------------
    // [1/6] WTPIX — reuse หรือ deploy
    // -------------------------------------------------------------------
    let wtpixAddress = await reusable(registry, "WTPIX");
    if (wtpixAddress) {
        console.log("[1/6] WTPIX (reused):", wtpixAddress);
    } else {
        console.log("[1/6] Deploying WTPIX...");
        // fully qualified — กันชนกับ contract WTPIX ใน src/bridge/WTPIX_BEP20.sol
        const WTPIX = await hre.ethers.getContractFactory("src/sale/WTPIX_ERC20.sol:WTPIX", deployer);
        wtpixAddress = (await deployVerified("WTPIX", WTPIX)).address;
        console.log("   WTPIX:", wtpixAddress);
        upsertContract(registry, meta({
            name: "WTPIX",
            category: "wrapper",
            address: wtpixAddress,
            sourceFile: "contracts/src/sale/WTPIX_ERC20.sol",
            description: "Wrapped TPIX (ERC-20) — WETH9 pattern. 1:1 backed by native TPIX.",
        }));
    }

    // -------------------------------------------------------------------
    // [2/6] USDT_TPIX — reuse หรือ deploy
    // -------------------------------------------------------------------
    let usdtAddress = await reusable(registry, "USDT_TPIX");
    if (usdtAddress) {
        console.log("[2/6] USDT_TPIX (reused):", usdtAddress);
    } else {
        console.log("[2/6] Deploying USDT_TPIX...");
        const USDT = await hre.ethers.getContractFactory("USDT_TPIX", deployer);
        usdtAddress = (await deployVerified("USDT_TPIX", USDT)).address;
        console.log("   USDT_TPIX:", usdtAddress);
        upsertContract(registry, meta({
            name: "USDT_TPIX",
            category: "bridge-token",
            address: usdtAddress,
            sourceFile: "contracts/src/bridge/USDT_TPIX.sol",
            description: "Bridged Tether บน TPIX Chain (6 decimals) — mint/burn เฉพาะ relayer whitelist.",
        }));
    }

    // -------------------------------------------------------------------
    // [3/6] TPIXDEXFactory
    // -------------------------------------------------------------------
    let factoryAddress = await reusable(registry, "TPIXDEXFactory");
    let factory;
    if (factoryAddress) {
        console.log("[3/6] TPIXDEXFactory (reused):", factoryAddress);
        factory = await hre.ethers.getContractAt("TPIXDEXFactory", factoryAddress, deployer);
    } else {
        console.log("[3/6] Deploying TPIXDEXFactory...");
        const Factory = await hre.ethers.getContractFactory("TPIXDEXFactory", deployer);
        const d = await deployVerified("TPIXDEXFactory", Factory, [deployer.address]);
        factory = d.contract;
        factoryAddress = d.address;
        console.log("   TPIXDEXFactory:", factoryAddress);
        upsertContract(registry, meta({
            name: "TPIXDEXFactory",
            category: "dex",
            address: factoryAddress,
            sourceFile: "contracts/src/dex/amm/TPIXDEXFactory.sol",
            description: "Uniswap V2-style factory — ทะเบียน liquidity pair ทั้งหมดของ TPIX DEX",
        }));
    }

    // -------------------------------------------------------------------
    // [4/6] TPIXDEXRouter02
    // -------------------------------------------------------------------
    let routerAddress = await reusable(registry, "TPIXDEXRouter02");
    let router;
    if (routerAddress) {
        console.log("[4/6] TPIXDEXRouter02 (reused):", routerAddress);
        router = await hre.ethers.getContractAt("TPIXDEXRouter02", routerAddress, deployer);
        const boundFactory = await router.factory();
        const boundWeth = await router.WETH();
        if (boundFactory.toLowerCase() !== factoryAddress.toLowerCase() || boundWeth.toLowerCase() !== wtpixAddress.toLowerCase()) {
            throw new Error(
                `Router ใน registry ผูกกับ factory/WTPIX คนละตัว (factory ${boundFactory}, WETH ${boundWeth}) ` +
                `— ลบ TPIXDEXRouter02 ออกจาก deployed-contracts.json แล้วรันใหม่เพื่อ deploy router ใหม่`
            );
        }
    } else {
        console.log("[4/6] Deploying TPIXDEXRouter02...");
        const Router = await hre.ethers.getContractFactory("TPIXDEXRouter02", deployer);
        const d = await deployVerified("TPIXDEXRouter02", Router, [factoryAddress, wtpixAddress]);
        router = d.contract;
        routerAddress = d.address;
        console.log("   TPIXDEXRouter02:", routerAddress);
        upsertContract(registry, meta({
            name: "TPIXDEXRouter02",
            category: "dex",
            address: routerAddress,
            sourceFile: "contracts/src/dex/amm/TPIXDEXRouter02.sol",
            description: "Uniswap V2-style router — swap + add/remove liquidity (WETH = WTPIX)",
        }));
    }

    // -------------------------------------------------------------------
    // [5/6] Protocol fee (optional)
    // -------------------------------------------------------------------
    // ที่อยู่จากหลังบ้านเว็บอาจพิมพ์มาแบบ checksum ไม่ตรง — isAddress() จะตอบเท็จแล้วสคริปต์
    // ข้ามการตั้ง feeTo ไปเงียบ ๆ (เจอจริงตอนซ้อม 2026-09-05) จึง normalize เป็น lowercase ก่อน
    // และถ้าตั้งมาแต่ไม่ใช่ที่อยู่ ให้หยุดดัง ๆ แทนที่จะปล่อยผ่าน
    const feeCollectorRaw = (process.env.FEE_COLLECTOR || "").trim();
    let feeCollector = null;
    if (feeCollectorRaw) {
        if (!/^0x[0-9a-fA-F]{40}$/.test(feeCollectorRaw)) {
            throw new Error(`FEE_COLLECTOR ไม่ใช่ที่อยู่: ${feeCollectorRaw}`);
        }
        feeCollector = hre.ethers.getAddress(feeCollectorRaw.toLowerCase());
    }
    if (feeCollector) {
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
    const out = { WTPIX: wtpixAddress, USDT: usdtAddress, FACTORY: factoryAddress, ROUTER: routerAddress };

    const liqTpix = process.env.LIQ_TPIX;
    const liqUsdt = process.env.LIQ_USDT;
    if (liqTpix && liqUsdt) {
        console.log(`[6/6] Seeding pool: ${liqTpix} TPIX + ${liqUsdt} USDT`);
        const tpixWei = hre.ethers.parseEther(liqTpix);
        const usdtUnits = hre.ethers.parseUnits(liqUsdt, 6);

        const balance = await hre.ethers.provider.getBalance(deployer.address);
        if (balance < tpixWei) {
            throw new Error(`จะเติม ${liqTpix} TPIX แต่กระเป๋ามี ${hre.ethers.formatEther(balance)} TPIX`);
        }

        const usdt = await hre.ethers.getContractAt("USDT_TPIX", usdtAddress, deployer);
        const owner = await usdt.owner();
        if (owner.toLowerCase() !== deployer.address.toLowerCase()) {
            throw new Error("Seed ต้องให้ deployer เป็น owner ของ USDT_TPIX (เพื่อ mint initial liquidity)");
        }

        const usdtBalance = await usdt.balanceOf(deployer.address);
        if (usdtBalance < usdtUnits) {
            // mint ส่วนที่ขาดผ่าน bridge whitelist ชั่วคราว — sourceTxHash ใช้ marker กัน replay
            console.log("   Minting USDT for initial liquidity...");
            await (await usdt.setBridge(deployer.address, true)).wait();
            const marker = hre.ethers.id(`dex-initial-liquidity-${Date.now()}`);
            await (await usdt.bridgeMint(deployer.address, usdtUnits - usdtBalance, marker)).wait();
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
        out.PAIR_TPIX_USDT = pairAddress;
        console.log("   Pair WTPIX/USDT:", pairAddress);
        console.log(`   ราคาเปิด: ${(Number(liqUsdt) / Number(liqTpix)).toFixed(6)} USDT/TPIX`);
        upsertContract(registry, meta({
            name: "TPIXDEXPair_WTPIX_USDT",
            category: "dex",
            address: pairAddress,
            sourceFile: "contracts/src/dex/amm/TPIXDEXPair.sol",
            description: "Liquidity pair WTPIX/USDT — pool หลักของกระดาน TPIX/USDT",
        }));
    } else {
        console.log("[6/6] LIQ_TPIX/LIQ_USDT not set — ข้าม seed pool (เติมทีหลังได้ที่หน้า /liquidity ของเว็บ)");
    }

    return out;
}

/** เขียนไฟล์ config ฝั่ง ThaiXTrade ถ้า repo อยู่ข้างกัน (ค่าตั้งต้นของหน้าเว็บ — ทะเบียนบนเซิร์ฟเวอร์เป็นตัวจริง) */
function writeSiteConfigs(dexConfig) {
    const thaiXTradeRoot = path.join(__dirname, "..", "..", "..", "ThaiXTrade");
    const frontendConfig = path.join(thaiXTradeRoot, "resources", "js", "Config", "dexContracts.json");
    const backendDir = path.join(thaiXTradeRoot, "storage", "app", "tpix");

    if (fs.existsSync(path.dirname(frontendConfig))) {
        fs.writeFileSync(frontendConfig, JSON.stringify(dexConfig, null, 2) + "\n");
        console.log("Frontend config updated:", frontendConfig);
    } else {
        console.log("ThaiXTrade repo not found — ค่าตั้งต้น dexContracts.json:");
        console.log(JSON.stringify(dexConfig, null, 2));
    }

    if (fs.existsSync(path.dirname(backendDir))) {
        fs.mkdirSync(backendDir, { recursive: true });
        fs.writeFileSync(path.join(backendDir, "deployments.json"), JSON.stringify(dexConfig, null, 2) + "\n");
        console.log("Backend deployments.json updated");
    }
}

/** payload สำหรับทะเบียนบนเว็บ */
function dexRegistryPayload(addresses) {
    return {
        wtpix: addresses.WTPIX,
        usdt_tpix: addresses.USDT,
        dex_factory: addresses.FACTORY,
        dex_router: addresses.ROUTER,
    };
}

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    if (!deployer) {
        throw new Error("ไม่มี signer — ตั้ง DEPLOYER_KEY ก่อน เช่น  export DEPLOYER_KEY=0x...");
    }
    const registry = loadRegistry();
    await assertRegistryChain(registry);

    const balance = await hre.ethers.provider.getBalance(deployer.address);
    console.log("Deployer:", deployer.address);
    console.log("Balance:", hre.ethers.formatEther(balance), "TPIX\n");
    if (balance === 0n) {
        throw new Error("deployer ไม่มี TPIX เลย — เชนนี้ gas = 0 แต่บัญชีต้องมีอยู่จริง");
    }

    const addresses = await deployDex({ deployer, registry });

    // -------------------------------------------------------------------
    // Write registry + sync ไป ThaiXTrade
    // -------------------------------------------------------------------
    const isDryRun = hre.network.name === "hardhat" || hre.network.name === "localhost";
    if (isDryRun) {
        console.log(`\n[dry-run] เครือข่าย ${hre.network.name} — ไม่เขียน deployed-contracts.json`);
    } else {
        registry.updated = new Date().toISOString().slice(0, 10);
        fs.writeFileSync(REGISTRY_PATH, JSON.stringify(registry, null, 2) + "\n");
        console.log("\nRegistry updated:", REGISTRY_PATH);

        writeSiteConfigs({
            chainId: 4289,
            rpc: "https://rpc.tpix.online",
            updated: new Date().toISOString(),
            WTPIX: addresses.WTPIX,
            USDT: addresses.USDT,
            FACTORY: addresses.FACTORY,
            ROUTER: addresses.ROUTER,
        });
    }

    const payload = dexRegistryPayload(addresses);
    const registered = isDryRun ? false : await registerWithSite(payload);

    console.log("\n=== TPIX DEX DEPLOYED ===");
    console.log("WTPIX:  ", addresses.WTPIX);
    console.log("USDT:   ", addresses.USDT);
    console.log("Factory:", addresses.FACTORY);
    console.log("Router: ", addresses.ROUTER);
    if (addresses.PAIR_TPIX_USDT) console.log("Pair TPIX/USDT:", addresses.PAIR_TPIX_USDT);

    if (!registered && !isDryRun) {
        printEnvFallback(payload);
    } else if (registered) {
        console.log("\nเว็บรับที่อยู่แล้ว — dex:sync จะเปิดเชน 4289 เป็น live และสร้างคู่เทรดจากพูลภายใน 1 นาที");
    }
}

module.exports = { deployDex, dexRegistryPayload, writeSiteConfigs };

if (require.main === module) {
    main().catch((error) => {
        console.error("\n❌ deploy DEX ล้มเหลว:", error.message || error);
        process.exitCode = 1;
    });
}
