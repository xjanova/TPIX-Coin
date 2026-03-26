/**
 * Deploy TPIXIdentity contract to TPIX Chain.
 *
 * Usage:
 *   # Set your deployer private key (any wallet with some TPIX, or use validator)
 *   export DEPLOYER_KEY=0x...your_private_key...
 *
 *   # Deploy to TPIX mainnet
 *   npm run deploy:identity
 *
 *   # Deploy to local test
 *   npm run deploy:identity:local
 *
 * Gas: FREE on TPIX Chain (gasPrice = 0)
 * No TPIX balance needed to deploy!
 */

const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("╔══════════════════════════════════════════════╗");
  console.log("║   TPIX Living Identity — Contract Deploy     ║");
  console.log("╚══════════════════════════════════════════════╝");
  console.log();
  console.log("Network:  ", hre.network.name);
  console.log("Chain ID: ", (await hre.ethers.provider.getNetwork()).chainId.toString());
  console.log("Deployer: ", deployer.address);

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Balance:  ", hre.ethers.formatEther(balance), "TPIX");
  console.log();

  // Deploy
  console.log("Deploying TPIXIdentity...");
  const factory = await hre.ethers.getContractFactory("TPIXIdentity");
  const contract = await factory.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log();
  console.log("✅ TPIXIdentity deployed!");
  console.log("   Address:", address);
  console.log("   TX Hash:", contract.deploymentTransaction().hash);
  console.log();

  // Verify it works
  const totalRegistered = await contract.totalRegistered();
  console.log("   Total registered:", totalRegistered.toString());
  console.log("   Timelock:", (await contract.TIMELOCK_DURATION()).toString(), "seconds (48 hours)");
  console.log();
  console.log("════════════════════════════════════════════════");
  console.log("  Save this address in your wallet app config!");
  console.log("  " + address);
  console.log("════════════════════════════════════════════════");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Deploy failed:", error);
    process.exit(1);
  });
