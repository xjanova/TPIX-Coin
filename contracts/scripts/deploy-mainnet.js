/**
 * One-shot mainnet deploy orchestrator — TPIX bonding curve token sale
 *
 * รันคำสั่งเดียวจบ: deploy WTPIX → wrap 700M native → deploy USDT_TPIX +
 * BondingCurve → transfer 700M WTPIX to curve → set bridge relayer
 *
 * Pre-requisites:
 *   - DEPLOYER_KEY = private key ของ Token Sale wallet (ต้องมี 700M+ native TPIX)
 *   - Optional RELAYER_ADDRESS — ถ้าตั้งจะ setBridge ให้เลย (multisig แนะนำ)
 *
 * Usage:
 *   cd contracts
 *   export DEPLOYER_KEY=0x...
 *   export RELAYER_ADDRESS=0x...   # optional
 *   npx hardhat run scripts/deploy-mainnet.js --network tpix
 *
 * Idempotent: ถ้า WTPIX/USDT/Curve เคย deploy แล้วจะข้าม step deploy
 * แต่ยัง execute step ที่เหลือ (wrap/fund/set-relayer) ให้ครบ
 *
 * Output: เขียน ../../ThaiXTrade/resources/js/Config/launchContracts.js
 *         ให้ frontend ใช้ทันที (ถ้าพบ path)
 *
 * Developed by Xman Studio
 */

const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

// ──── WHITEPAPER constants ────────────────────────────────────────────
const SALE_SUPPLY = hre.ethers.parseUnits("700000000", 18);             // 700M TPIX
const START_PRICE = hre.ethers.parseUnits("0.10", 6);                   // $0.10
const END_PRICE = hre.ethers.parseUnits("1.00", 6);                     // $1.00
const MIGRATION_USDT_THRESHOLD = hre.ethers.parseUnits("5000000", 6);   // $5M
const MIGRATION_TPIX_THRESHOLD = hre.ethers.parseUnits("350000000", 18); // 350M

const TOKEN_SALE_WALLET = "0x3F8EB4046F5C79fd0D67C7547B5830cB2Cfb401A";
const LIQUIDITY_WALLET = "0x3da3776e0AB0F442c181aa031f47FA83696859AF";

const REGISTRY_PATH = path.join(__dirname, "..", "deployed-contracts.json");
const FRONTEND_CONFIG_PATH = path.join(
    __dirname,
    "..",
    "..",
    "..",
    "ThaiXTrade",
    "resources",
    "js",
    "Config",
    "launchContracts.js"
);

// ──── helpers ────────────────────────────────────────────────────────
function loadRegistry() {
    return JSON.parse(fs.readFileSync(REGISTRY_PATH, "utf8"));
}

function saveRegistry(registry) {
    registry.updated = new Date().toISOString().slice(0, 10);
    fs.writeFileSync(REGISTRY_PATH, JSON.stringify(registry, null, 2));
}

function upsertContract(registry, entry) {
    const idx = registry.contracts.findIndex((c) => c.name === entry.name);
    if (idx >= 0) registry.contracts[idx] = entry;
    else registry.contracts.push(entry);
}

function getDeployedAddress(registry, name) {
    const entry = registry.contracts.find((c) => c.name === name);
    return entry ? entry.address : null;
}

async function isContract(addr) {
    if (!addr) return false;
    const code = await hre.ethers.provider.getCode(addr);
    return code && code !== "0x";
}

// ──── steps ──────────────────────────────────────────────────────────

async function deployWTPIXIfNeeded(registry) {
    const existing = getDeployedAddress(registry, "WTPIX");
    if (existing && (await isContract(existing))) {
        console.log(`✓ [1/5] WTPIX already deployed at ${existing}`);
        return existing;
    }

    console.log("→ [1/5] Deploying WTPIX (sale wrapper)...");
    const WTPIX = await hre.ethers.getContractFactory("src/sale/WTPIX_ERC20.sol:WTPIX");
    const wtpix = await WTPIX.deploy();
    await wtpix.waitForDeployment();
    const addr = await wtpix.getAddress();
    console.log(`  ✓ WTPIX at ${addr}`);

    upsertContract(registry, {
        name: "WTPIX",
        category: "wrapper",
        address: addr,
        sourceFile: "contracts/src/sale/WTPIX_ERC20.sol",
        compilerVersion: "0.8.20",
        optimizer: { enabled: true, runs: 200 },
        verified: false,
        description:
            "Wrapped TPIX (ERC-20) — WETH9 pattern. 1:1 backed by native TPIX. Required by TPIXBondingCurve and DEX routers.",
    });
    saveRegistry(registry);
    return addr;
}

async function wrapNativeIfNeeded(wtpixAddress, deployer) {
    const wtpix = await hre.ethers.getContractAt(
        "src/sale/WTPIX_ERC20.sol:WTPIX",
        wtpixAddress
    );
    const currentBalance = await wtpix.balanceOf(deployer.address);

    if (currentBalance >= SALE_SUPPLY) {
        console.log(
            `✓ [2/5] Deployer already holds ${hre.ethers.formatEther(currentBalance)} WTPIX`
        );
        return;
    }

    const needed = SALE_SUPPLY - currentBalance;
    const nativeBalance = await hre.ethers.provider.getBalance(deployer.address);
    if (nativeBalance < needed) {
        throw new Error(
            `Insufficient native TPIX. Have ${hre.ethers.formatEther(
                nativeBalance
            )}, need ${hre.ethers.formatEther(needed)} more to wrap.`
        );
    }

    console.log(
        `→ [2/5] Wrapping ${hre.ethers.formatEther(needed)} native → WTPIX...`
    );
    const tx = await wtpix.deposit({ value: needed });
    await tx.wait();
    console.log(`  ✓ Wrapped (tx: ${tx.hash})`);
}

async function deployUSDTIfNeeded(registry) {
    const existing = getDeployedAddress(registry, "USDT_TPIX");
    if (existing && (await isContract(existing))) {
        console.log(`✓ [3a/5] USDT_TPIX already deployed at ${existing}`);
        return existing;
    }

    console.log("→ [3a/5] Deploying USDT_TPIX (bridged Tether)...");
    const USDT = await hre.ethers.getContractFactory("USDT_TPIX");
    const usdt = await USDT.deploy();
    await usdt.waitForDeployment();
    const addr = await usdt.getAddress();
    console.log(`  ✓ USDT_TPIX at ${addr}`);

    upsertContract(registry, {
        name: "USDT_TPIX",
        category: "bridge",
        address: addr,
        sourceFile: "contracts/src/bridge/USDT_TPIX.sol",
        compilerVersion: "0.8.20",
        optimizer: { enabled: true, runs: 200 },
        verified: false,
        description:
            "Bridged USDT บน TPIX chain — peg 1:1 กับ USDT จริง (BSC/ETH) ผ่าน relayer. Replay protection enabled.",
    });
    saveRegistry(registry);
    return addr;
}

async function deployBondingCurveIfNeeded(registry, wtpixAddress, usdtAddress) {
    const existing = getDeployedAddress(registry, "TPIXBondingCurve");
    if (existing && (await isContract(existing))) {
        console.log(`✓ [3b/5] TPIXBondingCurve already deployed at ${existing}`);
        return existing;
    }

    console.log("→ [3b/5] Deploying TPIXBondingCurve...");
    const Curve = await hre.ethers.getContractFactory("TPIXBondingCurve");
    const curve = await Curve.deploy(
        wtpixAddress,
        usdtAddress,
        LIQUIDITY_WALLET,
        SALE_SUPPLY,
        START_PRICE,
        END_PRICE,
        MIGRATION_USDT_THRESHOLD,
        MIGRATION_TPIX_THRESHOLD
    );
    await curve.waitForDeployment();
    const addr = await curve.getAddress();
    console.log(`  ✓ TPIXBondingCurve at ${addr}`);

    upsertContract(registry, {
        name: "TPIXBondingCurve",
        category: "sale",
        address: addr,
        sourceFile: "contracts/src/sale/TPIXBondingCurve.sol",
        compilerVersion: "0.8.20",
        optimizer: { enabled: true, runs: 200 },
        verified: false,
        description: `Linear bonding curve — 700M TPIX @ $0.10→$1.00, migrate @ $5M raised. 24h migration delay, 1% wallet cap, emergency sell after 30d pause. Sale wallet: ${TOKEN_SALE_WALLET}, Liquidity wallet: ${LIQUIDITY_WALLET}`,
    });
    saveRegistry(registry);
    return addr;
}

async function fundCurveIfNeeded(wtpixAddress, curveAddress, deployer) {
    const wtpix = await hre.ethers.getContractAt(
        "src/sale/WTPIX_ERC20.sol:WTPIX",
        wtpixAddress
    );
    const curveBalance = await wtpix.balanceOf(curveAddress);

    if (curveBalance >= SALE_SUPPLY) {
        console.log(
            `✓ [4/5] BondingCurve already funded with ${hre.ethers.formatEther(
                curveBalance
            )} WTPIX`
        );
        return;
    }

    const needed = SALE_SUPPLY - curveBalance;
    const deployerBalance = await wtpix.balanceOf(deployer.address);
    if (deployerBalance < needed) {
        throw new Error(
            `Deployer doesn't have enough WTPIX to fund curve. Have ${hre.ethers.formatEther(
                deployerBalance
            )}, need ${hre.ethers.formatEther(needed)}.`
        );
    }

    console.log(
        `→ [4/5] Transferring ${hre.ethers.formatEther(needed)} WTPIX → BondingCurve...`
    );
    const tx = await wtpix.transfer(curveAddress, needed);
    await tx.wait();
    console.log(`  ✓ Funded (tx: ${tx.hash})`);
}

async function setRelayerIfRequested(usdtAddress) {
    const relayer = process.env.RELAYER_ADDRESS;
    if (!relayer) {
        console.log("⊘ [5/5] RELAYER_ADDRESS not set — skipping setBridge() (set later via console)");
        return;
    }

    const usdt = await hre.ethers.getContractAt("USDT_TPIX", usdtAddress);
    const isBridge = await usdt.bridges(relayer);
    if (isBridge) {
        console.log(`✓ [5/5] Relayer ${relayer} already whitelisted`);
        return;
    }

    console.log(`→ [5/5] Setting bridge relayer: ${relayer}...`);
    const tx = await usdt.setBridge(relayer, true);
    await tx.wait();
    console.log(`  ✓ Relayer set (tx: ${tx.hash})`);
}

function writeFrontendConfig(wtpixAddress, usdtAddress, curveAddress) {
    if (!fs.existsSync(FRONTEND_CONFIG_PATH)) {
        console.log(`⊘ [bonus] Frontend config not found at ${FRONTEND_CONFIG_PATH} — skipped`);
        return;
    }

    const content = fs.readFileSync(FRONTEND_CONFIG_PATH, "utf8");
    let updated = content;

    // Replace common placeholder patterns — exact matching depends on actual file
    // We try several reasonable patterns; the script logs what it changed.
    const replacements = [
        [/WTPIX_ADDRESS\s*=\s*['"][^'"]*['"]/g, `WTPIX_ADDRESS = '${wtpixAddress}'`],
        [/USDT_ADDRESS\s*=\s*['"][^'"]*['"]/g, `USDT_ADDRESS = '${usdtAddress}'`],
        [
            /BONDING_CURVE_ADDRESS\s*=\s*['"][^'"]*['"]/g,
            `BONDING_CURVE_ADDRESS = '${curveAddress}'`,
        ],
        [/wtpix:\s*['"][^'"]*['"]/g, `wtpix: '${wtpixAddress}'`],
        [/usdt:\s*['"][^'"]*['"]/g, `usdt: '${usdtAddress}'`],
        [/bondingCurve:\s*['"][^'"]*['"]/g, `bondingCurve: '${curveAddress}'`],
    ];

    let changes = 0;
    for (const [pattern, replacement] of replacements) {
        const matches = updated.match(pattern);
        if (matches) {
            changes += matches.length;
            updated = updated.replace(pattern, replacement);
        }
    }

    if (changes === 0) {
        console.log(
            `⚠ [bonus] No placeholder patterns matched in ${FRONTEND_CONFIG_PATH} — please update manually`
        );
        return;
    }

    fs.writeFileSync(FRONTEND_CONFIG_PATH, updated);
    console.log(`✓ [bonus] Updated ${changes} address reference(s) in launchContracts.js`);
}

// ──── main ───────────────────────────────────────────────────────────
async function main() {
    console.log("╔══════════════════════════════════════════════════╗");
    console.log("║    TPIX Mainnet Deploy Orchestrator (one-shot)   ║");
    console.log("╚══════════════════════════════════════════════════╝\n");

    const [deployer] = await hre.ethers.getSigners();
    const network = await hre.ethers.provider.getNetwork();
    const balance = await hre.ethers.provider.getBalance(deployer.address);

    console.log(`Network:  ${hre.network.name} (chainId ${network.chainId})`);
    console.log(`Deployer: ${deployer.address}`);
    console.log(`Balance:  ${hre.ethers.formatEther(balance)} TPIX`);
    console.log();

    if (deployer.address.toLowerCase() !== TOKEN_SALE_WALLET.toLowerCase()) {
        console.warn(
            `⚠ Deployer is NOT the Token Sale wallet (${TOKEN_SALE_WALLET}).`
        );
        console.warn(`  Continuing anyway — but tokenomics expect deployer == Token Sale wallet.\n`);
    }

    const registry = loadRegistry();

    // ── Step 1: WTPIX
    const wtpixAddress = await deployWTPIXIfNeeded(registry);

    // ── Step 2: Wrap native → WTPIX
    await wrapNativeIfNeeded(wtpixAddress, deployer);

    // ── Step 3a/b: USDT + BondingCurve
    const usdtAddress = await deployUSDTIfNeeded(registry);
    const curveAddress = await deployBondingCurveIfNeeded(
        registry,
        wtpixAddress,
        usdtAddress
    );

    // ── Step 4: Fund curve with 700M WTPIX
    await fundCurveIfNeeded(wtpixAddress, curveAddress, deployer);

    // ── Step 5: Optional setBridge
    await setRelayerIfRequested(usdtAddress);

    // ── Bonus: update frontend config
    writeFrontendConfig(wtpixAddress, usdtAddress, curveAddress);

    // ── Summary
    console.log("\n" + "═".repeat(60));
    console.log("✅ DEPLOY COMPLETE");
    console.log("═".repeat(60));
    console.log(`WTPIX            ${wtpixAddress}`);
    console.log(`USDT_TPIX        ${usdtAddress}`);
    console.log(`TPIXBondingCurve ${curveAddress}`);
    console.log();
    console.log("Next:");
    if (!process.env.RELAYER_ADDRESS) {
        console.log("  • Set bridge relayer (multisig recommended):");
        console.log(`    usdt.setBridge('<RELAYER_MULTISIG>', true)`);
    }
    console.log("  • Verify contracts on Blockscout: npm run verify:sources");
    console.log("  • Update ThaiXTrade Config/launchContracts.js if not auto-updated");
    console.log("  • Transfer ownership to multisig: usdt.transferOwnership('<MULTISIG>')");
    console.log("    (then multisig must call acceptOwnership())");
    console.log();
}

main().catch((err) => {
    console.error("\n❌ DEPLOY FAILED:", err.message);
    if (err.stack) console.error(err.stack);
    process.exit(1);
});
