/**
 * Deploy the TPIX Launchpad — LaunchVestingDeployer + LaunchpadFactory on TPIX Chain (4289)
 *
 * Neither contract has an owner, a fee or an upgrade path: any wallet may deploy them and the deployer keeps
 * no power afterwards. LaunchpadFactory only accepts tokens registered by TPIXTokenFactoryV2 (anti-rug rules
 * in src/launch/LaunchpadFactory.sol), so the factory address is baked in at deploy. Each child-token creator later calls LaunchpadFactory.createLaunch() from their own
 * wallet (the Token Factory wizard on tpix.online does that) — see src/launch/LaunchpadFactory.sol.
 *
 * Usage:
 *   cd contracts
 *   .\scripts\deploy-launchpad.ps1                         (asks for the key hidden — recommended)
 *   or: DEPLOYER_KEY=0x... npx hardhat run scripts/deploy-launchpad.js --network tpix
 *   dry run: npx hardhat run scripts/deploy-launchpad.js   (local network, stand-in USDT + DEX)
 *
 * Env (optional):
 *   USDT_TPIX_ADDRESS / DEX_ROUTER_ADDRESS / TOKEN_FACTORY_V2_ADDRESS   default = deployed-contracts.json
 *   REDEPLOY=1                                 deploy new ones even if the registry has working ones
 *
 * Registration with tpix.online (contract keys launchpad_factory / launchpad_vesting_deployer) is done from
 * the server side after the deploy — this script only writes deployed-contracts.json.
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
    const entry = (registry.contracts || []).find((c) => c.name === name);
    return entry ? entry.address : null;
}

function upsertContract(registry, entry) {
    registry.contracts = registry.contracts || [];
    const idx = registry.contracts.findIndex((c) => c.name === entry.name);
    if (idx >= 0) registry.contracts[idx] = { ...registry.contracts[idx], ...entry };
    else registry.contracts.push(entry);
}

function addressFromEnv(name) {
    const v = (process.env[name] || "").trim();
    if (!v) return null;
    if (!hre.ethers.isAddress(v)) throw new Error(`${name} ไม่ใช่ที่อยู่: ${v}`);
    return hre.ethers.getAddress(v);
}

/** the deployed runtime equals this build's artifact, immutables masked */
async function codeMatches(address, name) {
    const live = (await hre.ethers.provider.getCode(address)).toLowerCase();
    if (live === "0x") return false;
    const artifact = await hre.artifacts.readArtifact(name);
    const full = await hre.artifacts.getBuildInfo(`${artifact.sourceName}:${name}`);
    const out = full.output.contracts[artifact.sourceName][name].evm.deployedBytecode;
    const mask = (hex) => {
        const b = hex.replace(/^0x/, "").split("");
        for (const refs of Object.values(out.immutableReferences || {})) {
            for (const r of refs) for (let i = r.start * 2; i < (r.start + r.length) * 2; i++) b[i] = "0";
        }
        return b.join("");
    };
    return mask(live) === mask(out.object.toLowerCase());
}

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    if (!deployer) throw new Error("ไม่มี signer — ตั้ง DEPLOYER_KEY ก่อน");
    const isDryRun = hre.network.name === "hardhat" || hre.network.name === "localhost";
    const registry = loadRegistry();
    const live = Number((await hre.ethers.provider.getNetwork()).chainId);
    if (!isDryRun && Number(registry?.chain?.chainId) !== live) {
        throw new Error(`chainId ไม่ตรงกัน: registry = ${registry?.chain?.chainId} แต่กำลังต่อกับเชน ${live}`);
    }

    let usdt = addressFromEnv("USDT_TPIX_ADDRESS") || findContract(registry, "USDT_TPIX");
    let router = addressFromEnv("DEX_ROUTER_ADDRESS") || findContract(registry, "TPIXDEXRouter02");
    let tokenRegistry = addressFromEnv("TOKEN_FACTORY_V2_ADDRESS") || findContract(registry, "TPIXTokenFactoryV2");
    if (isDryRun) {
        // local rehearsal: no real coins to bind to — stand-ins
        const [, owner] = await hre.ethers.getSigners();
        const W = await (await hre.ethers.getContractFactory("src/sale/WTPIX_ERC20.sol:WTPIX")).deploy();
        const U = await (await hre.ethers.getContractFactory("USDT_TPIX")).deploy();
        const F = await (await hre.ethers.getContractFactory("TPIXDEXFactory")).deploy((owner || deployer).address);
        const R = await (await hre.ethers.getContractFactory("TPIXDEXRouter02")).deploy(await F.getAddress(), await W.getAddress());
        const creators = [];
        for (const n of ["ERC20V2Creator", "UtilityTokenCreator", "RewardTokenCreator", "GovernanceTokenCreator", "StablecoinTokenCreator"]) {
            creators.push(await (await hre.ethers.getContractFactory(n)).deploy());
        }
        const TF = await (await hre.ethers.getContractFactory("TPIXTokenFactoryV2")).deploy(...(await Promise.all(creators.map((c) => c.getAddress()))));
        usdt = await U.getAddress();
        router = await R.getAddress();
        tokenRegistry = await TF.getAddress();
        console.log(`[dry-run] stand-in USDT_TPIX ${usdt} · router ${router} · token factory ${tokenRegistry}`);
    }
    if (!usdt || !router || !tokenRegistry) throw new Error("ไม่พบที่อยู่ USDT_TPIX / TPIXDEXRouter02 / TPIXTokenFactoryV2 ใน registry");
    for (const [n, a] of [["USDT_TPIX", usdt], ["TPIXDEXRouter02", router], ["TPIXTokenFactoryV2", tokenRegistry]]) {
        if ((await hre.ethers.provider.getCode(a)) === "0x") throw new Error(`${n} ${a} ไม่มีโค้ดบนเชนนี้`);
    }
    const usdtC = await hre.ethers.getContractAt("USDT_TPIX", usdt);
    if (Number(await usdtC.decimals()) !== 6) throw new Error("USDT_TPIX decimals ไม่ใช่ 6 — ผิดตัว?");
    // the register must answer the call LaunchpadFactory makes on every launch
    const tf = await hre.ethers.getContractAt("TPIXTokenFactoryV2", tokenRegistry);
    await tf.tokenRecords(hre.ethers.ZeroAddress);

    console.log("Deployer  :", deployer.address);
    console.log("USDT_TPIX :", usdt);
    console.log("Router    :", router);
    console.log("TokenFact.:", tokenRegistry, "\n");

    const redeploy = process.env.REDEPLOY === "1";
    const today = new Date().toISOString().slice(0, 10);
    const base = { compilerVersion: "0.8.24", optimizer: { enabled: true, runs: 200 }, evmVersion: "london", category: "launchpad" };

    // ── 1) LaunchVestingDeployer ───────────────────────────────────────────
    let vd = isDryRun ? null : findContract(registry, "LaunchVestingDeployer");
    if (vd && !redeploy && (await codeMatches(vd, "LaunchVestingDeployer"))) {
        console.log("[1/2] LaunchVestingDeployer (reused):", vd);
    } else {
        console.log("[1/2] Deploying LaunchVestingDeployer...");
        const c = await (await hre.ethers.getContractFactory("LaunchVestingDeployer", deployer)).deploy();
        await c.waitForDeployment();
        vd = await c.getAddress();
        if (!(await codeMatches(vd, "LaunchVestingDeployer"))) throw new Error("โค้ดบนเชนไม่ตรง artifact");
        console.log("      ", vd);
        upsertContract(registry, {
            ...base, verified: false, deployedAt: today, name: "LaunchVestingDeployer", address: vd,
            sourceFile: "contracts/src/launch/LaunchVestingDeployer.sol",
            description: "สร้าง TrancheVesting ให้ LaunchpadFactory (แยกออกมาเพื่อให้โรงงานไม่เกิน 24 KB) — ไม่มีเจ้าของ ไม่ถือเงิน",
        });
    }

    // ── 2) LaunchpadFactory ────────────────────────────────────────────────
    let lf = isDryRun ? null : findContract(registry, "LaunchpadFactory");
    let reuse = false;
    if (lf && !redeploy && (await codeMatches(lf, "LaunchpadFactory"))) {
        const c = await hre.ethers.getContractAt("LaunchpadFactory", lf);
        reuse = (await c.quote()).toLowerCase() === usdt.toLowerCase()
            && (await c.router()).toLowerCase() === router.toLowerCase()
            && (await c.vestingDeployer()).toLowerCase() === vd.toLowerCase()
            && (await c.tokenRegistry()).toLowerCase() === tokenRegistry.toLowerCase();
    }
    if (reuse) {
        console.log("[2/2] LaunchpadFactory (reused):", lf);
    } else {
        console.log("[2/2] Deploying LaunchpadFactory...");
        const c = await (await hre.ethers.getContractFactory("LaunchpadFactory", deployer)).deploy(usdt, router, vd, tokenRegistry);
        await c.waitForDeployment();
        lf = await c.getAddress();
        if (!(await codeMatches(lf, "LaunchpadFactory"))) throw new Error("โค้ดบนเชนไม่ตรง artifact");
        console.log("      ", lf);
        upsertContract(registry, {
            ...base, verified: false, deployedAt: today, name: "LaunchpadFactory", address: lf,
            sourceFile: "contracts/src/launch/LaunchpadFactory.sol",
            description: "เปิดขายเหรียญลูกในธุรกรรมเดียว: FixedPriceSale + PoolFeeder (เงินขายเข้าพูลอัตโนมัติ LP ล็อก ≥180 วัน) + TrancheVesting — รับเฉพาะเหรียญจาก TPIXTokenFactoryV2 ที่ปิด mint/pause/blacklist/auto-burn, ≥50% เข้าพูล, ≥80% ของซัพพลายล็อก — ไม่มีเจ้าของ ไม่มีค่าธรรมเนียม",
        });
    }

    if (isDryRun) {
        console.log("\n[dry-run] ไม่เขียน deployed-contracts.json");
    } else {
        registry.updated = today;
        fs.writeFileSync(REGISTRY_PATH, JSON.stringify(registry, null, 2) + "\n");
        console.log("\nRegistry updated:", REGISTRY_PATH);
    }
    console.log("\n=== TPIX Launchpad ===");
    console.log("LaunchpadFactory      :", lf);
    console.log("LaunchVestingDeployer :", vd);
    console.log("\nถัดไป: verify บน explorer (node scripts/verify-blockscout.js LaunchVestingDeployer LaunchpadFactory) แล้วลงทะเบียนกับเว็บจากฝั่งเซิร์ฟเวอร์");
}

main().catch((error) => {
    console.error("\n❌ deploy launchpad ล้มเหลว:", error.message || error);
    process.exitCode = 1;
});
