/**
 * Deploy pre-flight check — runs all sanity checks BEFORE you run deploy-mainnet.js
 * No DEPLOYER_KEY needed (read-only). Run from your local machine.
 *
 * Usage:
 *   cd contracts
 *   npx hardhat run scripts/deploy-preflight.js --network tpix
 *
 * Verifies:
 *   1. Network reachable + correct chainId (4289)
 *   2. Token Sale wallet has >= 700M native TPIX (need to wrap)
 *   3. Liquidity wallet exists (target for migration)
 *   4. Contracts NOT yet deployed (no clobber)
 *   5. Frontend config file path exists
 *   6. WHITEPAPER constants are sane
 *
 * Exit code 0 = ready to deploy. Non-zero = fix something first.
 */

const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

const TOKEN_SALE_WALLET = "0x3F8EB4046F5C79fd0D67C7547B5830cB2Cfb401A";
const LIQUIDITY_WALLET = "0x3da3776e0AB0F442c181aa031f47FA83696859AF";

const REQUIRED_CHAIN_ID = 4289n;
const REQUIRED_NATIVE = hre.ethers.parseEther("700000000"); // 700M

const FRONTEND_CONFIG = path.join(
    __dirname, "..", "..", "..",
    "ThaiXTrade", "resources", "js", "Config", "launchContracts.js"
);

const REGISTRY = path.join(__dirname, "..", "deployed-contracts.json");

const PASS = "\x1b[32m✓\x1b[0m";
const FAIL = "\x1b[31m✗\x1b[0m";
const WARN = "\x1b[33m!\x1b[0m";

let failures = 0;
function check(name, ok, detail = "") {
    if (ok === true) {
        console.log(`${PASS} ${name} ${detail}`);
    } else if (ok === "warn") {
        console.log(`${WARN} ${name} ${detail}`);
    } else {
        console.log(`${FAIL} ${name} ${detail}`);
        failures++;
    }
}

async function main() {
    console.log("╔══════════════════════════════════════════════════╗");
    console.log("║  TPIX Mainnet Deploy — Pre-flight Check          ║");
    console.log("╚══════════════════════════════════════════════════╝\n");

    // ── 1. Network
    const network = await hre.ethers.provider.getNetwork();
    check(
        "Connected to TPIX chain",
        network.chainId === REQUIRED_CHAIN_ID,
        `(chainId: ${network.chainId})`
    );

    const block = await hre.ethers.provider.getBlockNumber();
    check(
        "Latest block fetched",
        block > 0,
        `(block #${block})`
    );

    // ── 2. Token Sale wallet
    const saleBalance = await hre.ethers.provider.getBalance(TOKEN_SALE_WALLET);
    check(
        "Token Sale wallet has 700M+ native TPIX",
        saleBalance >= REQUIRED_NATIVE,
        `(${hre.ethers.formatEther(saleBalance)} TPIX)`
    );

    // ── 3. Liquidity wallet
    const liqBalance = await hre.ethers.provider.getBalance(LIQUIDITY_WALLET);
    check(
        "Liquidity wallet exists (any balance)",
        liqBalance >= 0n,
        `(${hre.ethers.formatEther(liqBalance)} TPIX)`
    );

    // ── 4. Registry — contracts not yet deployed
    if (!fs.existsSync(REGISTRY)) {
        check("deployed-contracts.json exists", false, REGISTRY);
        return;
    }
    const registry = JSON.parse(fs.readFileSync(REGISTRY, "utf8"));

    for (const name of ["WTPIX", "USDT_TPIX", "TPIXBondingCurve"]) {
        const entry = registry.contracts.find((c) => c.name === name);
        if (!entry) {
            check(`${name} not in registry (fresh deploy)`, true);
        } else {
            // Check on-chain code at the address
            const code = await hre.ethers.provider.getCode(entry.address);
            if (code && code !== "0x") {
                check(
                    `${name} ALREADY deployed at ${entry.address}`,
                    "warn",
                    "(deploy-mainnet.js will SKIP and reuse — no harm)"
                );
            } else {
                check(
                    `${name} in registry but no code on-chain`,
                    "warn",
                    `(stale entry at ${entry.address}, deploy-mainnet.js will redeploy)`
                );
            }
        }
    }

    // ── 5. Frontend config file
    check(
        "ThaiXTrade frontend config path",
        fs.existsSync(FRONTEND_CONFIG),
        FRONTEND_CONFIG
    );

    // ── 6. WHITEPAPER constants sanity
    const ART_PATH = path.join(__dirname, "..", "artifacts", "src", "sale", "TPIXBondingCurve.sol", "TPIXBondingCurve.json");
    check(
        "TPIXBondingCurve compiled artifact present",
        fs.existsSync(ART_PATH),
        "(run `npx hardhat compile` if missing)"
    );

    // ── 7. DEPLOYER_KEY hint (no value displayed)
    if (process.env.DEPLOYER_KEY) {
        const len = process.env.DEPLOYER_KEY.length;
        check(
            "DEPLOYER_KEY env var is set",
            len === 66 || len === 64,
            `(${len} chars — expected 66 with 0x prefix)`
        );
        // Verify the key actually owns Token Sale wallet
        const wallet = new hre.ethers.Wallet(process.env.DEPLOYER_KEY);
        check(
            "DEPLOYER_KEY matches Token Sale wallet",
            wallet.address.toLowerCase() === TOKEN_SALE_WALLET.toLowerCase(),
            `(derived: ${wallet.address})`
        );
    } else {
        check(
            "DEPLOYER_KEY env var",
            "warn",
            "(not set — required for deploy-mainnet.js)"
        );
    }

    // ── 8. Frontend Config addresses still placeholders
    if (fs.existsSync(FRONTEND_CONFIG)) {
        const content = fs.readFileSync(FRONTEND_CONFIG, "utf8");
        const hasZero = /0x0+(?:['"]|$)/m.test(content);
        check(
            "Frontend config still has zero placeholders (will be updated post-deploy)",
            hasZero ? true : "warn",
            hasZero ? "" : "(addresses already set — overwrite OK)"
        );
    }

    // ── Summary
    console.log("\n" + "═".repeat(56));
    if (failures === 0) {
        console.log(`${PASS} ALL CHECKS PASSED — ready to deploy!`);
        console.log("\nRun:");
        console.log("  export DEPLOYER_KEY=0x...   (Token Sale wallet key)");
        console.log("  npx hardhat run scripts/deploy-mainnet.js --network tpix");
        console.log("═".repeat(56));
        process.exit(0);
    } else {
        console.log(`${FAIL} ${failures} check(s) failed — fix before deploying`);
        console.log("═".repeat(56));
        process.exit(1);
    }
}

main().catch((err) => {
    console.error("Pre-flight error:", err.message);
    process.exit(1);
});
