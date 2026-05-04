/**
 * Deploy all TPIX security-hardened contracts to TPIX Chain.
 *
 * Usage:
 *   export DEPLOYER_KEY=0x...your_private_key...
 *   npx hardhat run scripts/deploy-all.js --network tpix
 *
 * Gas: FREE on TPIX Chain (gasPrice = 0)
 */

const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("╔══════════════════════════════════════════════════╗");
  console.log("║   TPIX Chain — Deploy Security-Hardened Contracts ║");
  console.log("╚══════════════════════════════════════════════════╝");
  console.log();
  console.log("Network:  ", hre.network.name);
  console.log("Chain ID: ", (await hre.ethers.provider.getNetwork()).chainId.toString());
  console.log("Deployer: ", deployer.address);

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Balance:  ", hre.ethers.formatEther(balance), "TPIX");
  console.log();

  const deployed = {};

  // ─── 1. TPIXIdentity ──────────────────────────────────────
  console.log("━━━ [1/3] Deploying TPIXIdentity ━━━");
  const identityFactory = await hre.ethers.getContractFactory("TPIXIdentity");
  const identity = await identityFactory.deploy();
  await identity.waitForDeployment();
  deployed.TPIXIdentity = await identity.getAddress();
  console.log("  Address:", deployed.TPIXIdentity);
  console.log("  TX:", identity.deploymentTransaction().hash);

  // Verify
  const timelock = await identity.TIMELOCK_DURATION();
  const cooldown = await identity.RECOVERY_COOLDOWN();
  console.log("  Timelock:", timelock.toString(), "s | Cooldown:", cooldown.toString(), "s");
  console.log();

  // ─── 2. TPIXRouter ────────────────────────────────────────
  // NOTE: TPIXRouter requires a DEX router address and fee collector.
  // Skip if no DEX router is deployed on TPIX Chain yet.
  console.log("━━━ [2/3] TPIXRouter ━━━");
  console.log("  SKIPPED — Requires DEX router address (Uniswap V2 compatible).");
  console.log("  Deploy manually when DEX is ready:");
  console.log("    npx hardhat run scripts/deploy-router.js --network tpix");
  console.log();

  // ─── 3. TPIXTokenSale ─────────────────────────────────────
  // NOTE: TPIXTokenSale is designed for BSC, not TPIX Chain.
  console.log("━━━ [3/3] TPIXTokenSale ━━━");
  console.log("  SKIPPED — This contract deploys on BSC, not TPIX Chain.");
  console.log("  Deploy to BSC with:");
  console.log("    npx hardhat run scripts/deploy-tokensale.js --network bsc");
  console.log();

  // ─── Summary ──────────────────────────────────────────────
  console.log("╔══════════════════════════════════════════════════╗");
  console.log("║   DEPLOYMENT COMPLETE                            ║");
  console.log("╚══════════════════════════════════════════════════╝");
  console.log();
  for (const [name, addr] of Object.entries(deployed)) {
    console.log(`  ${name}: ${addr}`);
  }
  console.log();
  console.log("  Save these addresses in your app configuration!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Deploy failed:", error);
    process.exit(1);
  });
