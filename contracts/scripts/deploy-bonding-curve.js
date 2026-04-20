/**
 * Deploy USDT_TPIX + TPIXBondingCurve บน TPIX Chain
 *
 * Pre-requisites:
 *   - DEPLOYER_KEY env var = private key ของ Token Sale wallet (0x3F8E...)
 *   - Token Sale wallet ต้องมี TPIX wrapped (ERC-20 representation) อย่างน้อย 700M
 *     (ถ้ายังไม่มี TPIX wrapped บน TPIX chain ต้อง deploy WTPIX-on-TPIX ก่อน)
 *
 * Usage:
 *   cd contracts
 *   DEPLOYER_KEY=0x... npx hardhat run scripts/deploy-bonding-curve.js --network tpix
 *
 * After deploy:
 *   1. setBridge(relayerAddress, true) on USDT_TPIX
 *   2. Token Sale wallet: TPIX.transfer(bondingCurve, 700_000_000 × 10^18)
 *   3. Bonding curve พร้อมรับ USDT แล้ว — user buy ผ่าน frontend
 *
 * Developed by Xman Studio
 */

const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

// Constants ตาม WHITEPAPER.md
const SALE_SUPPLY = hre.ethers.parseUnits("700000000", 18);          // 700M TPIX
const START_PRICE = hre.ethers.parseUnits("0.10", 6);                 // $0.10 (USDT 6-dec)
const END_PRICE = hre.ethers.parseUnits("1.00", 6);                   // $1.00
const MIGRATION_USDT_THRESHOLD = hre.ethers.parseUnits("5000000", 6); // $5M raised
const MIGRATION_TPIX_THRESHOLD = hre.ethers.parseUnits("350000000", 18); // 350M sold

// Wallet addresses จาก whitepaper
const TOKEN_SALE_WALLET = "0x3F8EB4046F5C79fd0D67C7547B5830cB2Cfb401A";
const LIQUIDITY_WALLET = "0x3da3776e0AB0F442c181aa031f47FA83696859AF";

/**
 * TPIX wrapped address resolution order:
 *   1. TPIX_WRAPPED_ADDRESS env var (override สำหรับ testing)
 *   2. deployed-contracts.json registry (name: "WTPIX") — default path
 *
 * ต้อง deploy WTPIX ก่อนผ่าน scripts/deploy-wtpix.js
 */
function resolveWtpixAddress(registry) {
    if (process.env.TPIX_WRAPPED_ADDRESS) return process.env.TPIX_WRAPPED_ADDRESS;
    const entry = registry.contracts.find((c) => c.name === "WTPIX");
    return entry ? entry.address : "";
}

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    console.log("Deploying with:", deployer.address);
    console.log("Balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "TPIX");

    if (deployer.address.toLowerCase() !== TOKEN_SALE_WALLET.toLowerCase()) {
        console.warn(`⚠️ Deployer ไม่ใช่ Token Sale wallet (${TOKEN_SALE_WALLET}) — proceed อยู่ดี`);
    }

    // Load registry first (ใช้หา WTPIX + เขียน entry ใหม่ทีหลัง)
    const registryPath = path.join(__dirname, "..", "deployed-contracts.json");
    const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));

    const TPIX_WRAPPED_ADDRESS = resolveWtpixAddress(registry);
    if (!TPIX_WRAPPED_ADDRESS) {
        console.error("\n❌ ไม่พบ WTPIX address");
        console.error("   วิธีแก้ (เลือก 1):");
        console.error("   (a) Deploy WTPIX ก่อน: npx hardhat run scripts/deploy-wtpix.js --network tpix");
        console.error("   (b) ใช้ address ที่มีอยู่แล้ว: set TPIX_WRAPPED_ADDRESS=0x...");
        process.exit(1);
    }

    // 1. Deploy USDT_TPIX
    console.log("\n[1/2] Deploying USDT_TPIX...");
    const USDT = await hre.ethers.getContractFactory("USDT_TPIX");
    const usdt = await USDT.deploy();
    await usdt.waitForDeployment();
    const usdtAddress = await usdt.getAddress();
    console.log("   USDT_TPIX:", usdtAddress);

    console.log("\n[2/2] Deploying TPIXBondingCurve...");
    console.log("   TPIX wrapped:", TPIX_WRAPPED_ADDRESS);
    console.log("   USDT:", usdtAddress);
    console.log("   Liquidity wallet:", LIQUIDITY_WALLET);
    console.log("   Sale supply:", hre.ethers.formatUnits(SALE_SUPPLY, 18), "TPIX");
    console.log("   Price range: $", hre.ethers.formatUnits(START_PRICE, 6), "→ $", hre.ethers.formatUnits(END_PRICE, 6));
    console.log("   Migration trigger: $", hre.ethers.formatUnits(MIGRATION_USDT_THRESHOLD, 6),
                "raised OR", hre.ethers.formatUnits(MIGRATION_TPIX_THRESHOLD, 18), "TPIX sold");

    const Curve = await hre.ethers.getContractFactory("TPIXBondingCurve");
    const curve = await Curve.deploy(
        TPIX_WRAPPED_ADDRESS,
        usdtAddress,
        LIQUIDITY_WALLET,
        SALE_SUPPLY,
        START_PRICE,
        END_PRICE,
        MIGRATION_USDT_THRESHOLD,
        MIGRATION_TPIX_THRESHOLD,
    );
    await curve.waitForDeployment();
    const curveAddress = await curve.getAddress();
    console.log("   TPIXBondingCurve:", curveAddress);

    // 3. Update deployed-contracts.json (registry โหลดไว้ข้างบนแล้ว)
    registry.updated = new Date().toISOString().slice(0, 10);

    const newEntries = [
        {
            name: "USDT_TPIX",
            category: "bridge",
            address: usdtAddress,
            sourceFile: "contracts/src/bridge/USDT_TPIX.sol",
            compilerVersion: "0.8.20",
            optimizer: { enabled: true, runs: 200 },
            verified: false,
            description: "Bridged USDT บน TPIX chain — peg 1:1 กับ USDT จริง (BSC/ETH) ผ่าน relayer",
        },
        {
            name: "TPIXBondingCurve",
            category: "sale",
            address: curveAddress,
            sourceFile: "contracts/src/sale/TPIXBondingCurve.sol",
            compilerVersion: "0.8.20",
            optimizer: { enabled: true, runs: 200 },
            verified: false,
            description: `Linear bonding curve token sale — 700M TPIX @ $0.10→$1.00, migrate to DEX @ $5M raised. Sale wallet: ${TOKEN_SALE_WALLET}, Liquidity wallet: ${LIQUIDITY_WALLET}`,
        },
    ];
    // Replace if exists, else append
    for (const entry of newEntries) {
        const idx = registry.contracts.findIndex(c => c.name === entry.name);
        if (idx >= 0) registry.contracts[idx] = entry;
        else registry.contracts.push(entry);
    }
    fs.writeFileSync(registryPath, JSON.stringify(registry, null, 2));
    console.log("\n📝 Updated deployed-contracts.json");

    // 4. Summary
    console.log("\n" + "=".repeat(60));
    console.log("✅ DEPLOY SUCCESS");
    console.log("=".repeat(60));
    console.log("USDT_TPIX:        ", usdtAddress);
    console.log("TPIXBondingCurve: ", curveAddress);
    console.log("\nNext steps:");
    console.log("  1. Set bridge relayer:");
    console.log(`     usdt.setBridge('<RELAYER_ADDRESS>', true)`);
    console.log("  2. Wrap 700M native TPIX → WTPIX (Token Sale wallet):");
    console.log(`     wtpix.deposit({ value: '700000000000000000000000000' })`);
    console.log("  3. Fund bonding curve with WTPIX:");
    console.log(`     wtpix.transfer('${curveAddress}', '${SALE_SUPPLY.toString()}')`);
    console.log("  4. Frontend integration → user สามารถ buy ผ่าน curve ได้");
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
