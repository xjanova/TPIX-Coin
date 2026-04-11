/**
 * Verify TPIXIdentity contract is working on TPIX Chain.
 *
 * Usage:
 *   export DEPLOYER_KEY=0x...
 *   export IDENTITY_CONTRACT=0x...deployed_address...
 *   npm run verify
 */

const hre = require("hardhat");

async function main() {
  const contractAddress = process.env.IDENTITY_CONTRACT;
  if (!contractAddress) {
    console.error("Set IDENTITY_CONTRACT=0x... environment variable");
    process.exit(1);
  }

  const [signer] = await hre.ethers.getSigners();
  const contract = await hre.ethers.getContractAt("TPIXIdentity", contractAddress);

  console.log("╔══════════════════════════════════════════════╗");
  console.log("║   TPIX Living Identity — Verify Contract     ║");
  console.log("╚══════════════════════════════════════════════╝");
  console.log();
  console.log("Contract:", contractAddress);
  console.log("Signer:  ", signer.address);
  console.log();

  // Check stats
  const total = await contract.totalRegistered();
  console.log("Total registered:", total.toString());

  // Test register
  const hasId = await contract.hasIdentity(signer.address);
  if (!hasId) {
    console.log("\nRegistering test identity...");
    const testRoot = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("test-identity-root"));
    const tx = await contract.register(testRoot);
    await tx.wait();
    console.log("✅ Registered! TX:", tx.hash);
    console.log("   Identity root (local):", testRoot);
  } else {
    console.log("✅ Already registered");
  }

  // Check cooldown constant
  const cooldown = await contract.RECOVERY_COOLDOWN();
  console.log("   Recovery cooldown:", cooldown.toString(), "seconds (24 hours)");

  // Check recovery status
  const [active, newOwner, executeAfter, executed] = await contract.getRecoveryStatus(signer.address);
  console.log("\nRecovery status:");
  console.log("   Active:", active);
  console.log("   New Owner:", newOwner);
  console.log("   Executed:", executed);

  console.log("\n✅ Contract is working correctly!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Verify failed:", error);
    process.exit(1);
  });
