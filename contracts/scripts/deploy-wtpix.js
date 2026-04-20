/**
 * Deploy WTPIX (Wrapped TPIX as ERC-20) บน TPIX Chain
 *
 * WTPIX เป็น prerequisite ของ TPIXBondingCurve — bonding curve ต้อง ERC-20
 * interface แต่ TPIX เป็น native coin จึงต้อง wrap ก่อน
 *
 * Usage:
 *   cd contracts
 *   DEPLOYER_KEY=0x... npx hardhat run scripts/deploy-wtpix.js --network tpix
 *
 * After deploy:
 *   1. Token Sale wallet wrap native TPIX → WTPIX:
 *      wtpix.deposit({ value: 700_000_000 × 10^18 })
 *   2. แล้วโอนให้ bonding curve หลัง deploy:
 *      wtpix.transfer(bondingCurveAddress, 700_000_000 × 10^18)
 *
 * Registry เก็บ address ลง deployed-contracts.json — deploy-bonding-curve.js
 * จะอ่านจาก registry อัตโนมัติ (ไม่ต้อง set env var TPIX_WRAPPED_ADDRESS)
 *
 * Developed by Xman Studio
 */

const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    console.log("Deploying WTPIX with:", deployer.address);
    console.log(
        "Balance:",
        hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)),
        "TPIX"
    );

    console.log("\n[1/1] Deploying WTPIX...");
    const WTPIX = await hre.ethers.getContractFactory("WTPIX");
    const wtpix = await WTPIX.deploy();
    await wtpix.waitForDeployment();
    const wtpixAddress = await wtpix.getAddress();
    console.log("   WTPIX:", wtpixAddress);

    // Update registry
    const registryPath = path.join(__dirname, "..", "deployed-contracts.json");
    const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
    registry.updated = new Date().toISOString().slice(0, 10);

    const entry = {
        name: "WTPIX",
        category: "wrapper",
        address: wtpixAddress,
        sourceFile: "contracts/src/sale/WTPIX_ERC20.sol",
        compilerVersion: "0.8.20",
        optimizer: { enabled: true, runs: 200 },
        verified: false,
        description:
            "Wrapped TPIX (ERC-20) — WETH9 pattern. 1:1 backed by native TPIX. Required by TPIXBondingCurve and DEX routers.",
    };

    const idx = registry.contracts.findIndex((c) => c.name === "WTPIX");
    if (idx >= 0) registry.contracts[idx] = entry;
    else registry.contracts.push(entry);
    fs.writeFileSync(registryPath, JSON.stringify(registry, null, 2));
    console.log("\n📝 Updated deployed-contracts.json");

    console.log("\n" + "=".repeat(60));
    console.log("✅ WTPIX DEPLOY SUCCESS");
    console.log("=".repeat(60));
    console.log("WTPIX:", wtpixAddress);
    console.log("\nNext steps:");
    console.log("  1. Wrap native TPIX from Token Sale wallet:");
    console.log(`     wtpix.deposit({ value: '700000000000000000000000000' })`);
    console.log("  2. Deploy bonding curve (will read WTPIX from registry):");
    console.log(`     npx hardhat run scripts/deploy-bonding-curve.js --network tpix`);
    console.log("  3. Transfer WTPIX to bonding curve after deploy.");
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
