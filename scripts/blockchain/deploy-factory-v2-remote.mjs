#!/usr/bin/env node
/**
 * Deploy TPIX Token Factory V2 (Coordinator + 5 Creators) + NFT Factory
 * Runs on production server via GitHub Actions
 *
 * Env vars:
 *   DEPLOYER_KEY    - Private key for deploying
 *   ARTIFACTS_DIR   - Path to compiled artifacts directory
 *
 * Developed by Xman Studio
 */

import { readFileSync } from "fs";

process.on("unhandledRejection", (reason) => {
  console.log("UNHANDLED REJECTION:", reason);
  process.exit(1);
});

const { ethers } = await import("ethers");
console.log("ethers version:", ethers.version);

async function deployContract(name, factory, wallet, provider, args = []) {
  const block = await provider.getBlock("latest");
  const blockGasLimit = Number(block.gasLimit);
  const nonce = await wallet.getNonce();
  // Use half block gas limit, capped at 20M
  const gasLimit = Math.min(Math.floor(blockGasLimit / 2), 20_000_000);
  console.log(`  Block gas limit: ${blockGasLimit}, using gasLimit: ${gasLimit}, nonce: ${nonce}`);

  // Build deploy transaction data
  const deployTx = await factory.getDeployTransaction(...args);
  const dataLen = deployTx.data?.length || 0;
  console.log(`  ${name} tx data: ${dataLen} chars (${Math.round(dataLen / 2)} bytes)`);

  // Deploy using raw sendTransaction for full control
  const tx = await wallet.sendTransaction({
    data: deployTx.data,
    gasPrice: 0,
    gasLimit,
    nonce,
  });
  console.log(`  ${name} tx hash: ${tx.hash}`);
  const receipt = await tx.wait();

  if (receipt.status === 0) {
    console.log(`  ERROR: ${name} deployment REVERTED (gasUsed: ${receipt.gasUsed.toString()})`);
    console.log(`  Receipt: ${JSON.stringify({ blockNumber: receipt.blockNumber, contractAddress: receipt.contractAddress, gasUsed: receipt.gasUsed.toString(), status: receipt.status })}`);
    throw new Error(`${name} deployment reverted`);
  }

  const addr = receipt.contractAddress;
  console.log(`  ${name}: ${addr} (gas: ${receipt.gasUsed.toString()})`);
  return addr;
}

function loadArtifact(dir, path) {
  const art = JSON.parse(readFileSync(`${dir}/${path}`, "utf8"));
  console.log(`  ${path}: ${Math.round(art.bytecode.length / 2)} bytes`);
  return art;
}

async function main() {
  const rpc = "http://127.0.0.1:8545";
  const privateKey = process.env.DEPLOYER_KEY;
  if (!privateKey) {
    console.log("ERROR: DEPLOYER_KEY not set");
    process.exit(1);
  }

  const dir = process.env.ARTIFACTS_DIR || "/tmp/factory-deploy";

  const provider = new ethers.JsonRpcProvider(rpc, { chainId: 4289, name: "TPIX Chain" });
  const wallet = new ethers.Wallet(privateKey, provider);
  console.log("Deployer:", wallet.address);
  console.log("Balance:", ethers.formatEther(await provider.getBalance(wallet.address)), "TPIX");

  // Check block gas limit
  const block = await provider.getBlock("latest");
  console.log("Current block:", block.number, "gasLimit:", Number(block.gasLimit));

  // Load all artifacts
  console.log("\nLoading artifacts...");
  const erc20V2CreatorArt = loadArtifact(dir, "ERC20V2Creator.json");
  const utilityCreatorArt = loadArtifact(dir, "UtilityTokenCreator.json");
  const rewardCreatorArt = loadArtifact(dir, "RewardTokenCreator.json");
  const governanceCreatorArt = loadArtifact(dir, "GovernanceTokenCreator.json");
  const stablecoinCreatorArt = loadArtifact(dir, "StablecoinTokenCreator.json");
  const factoryV2Art = loadArtifact(dir, "TPIXTokenFactoryV2.json");
  const erc721CreatorArt = loadArtifact(dir, "FactoryERC721Creator.json");
  const collectionCreatorArt = loadArtifact(dir, "NFTCollectionCreator.json");
  const nftFactoryArt = loadArtifact(dir, "TPIXNFTFactory.json");

  const total = 9;

  // Deploy 5 ERC-20 creators
  console.log(`\n[1/${total}] Deploying ERC20V2Creator...`);
  const erc20V2Addr = await deployContract("ERC20V2Creator",
    new ethers.ContractFactory(erc20V2CreatorArt.abi, erc20V2CreatorArt.bytecode, wallet),
    wallet, provider);

  console.log(`\n[2/${total}] Deploying UtilityTokenCreator...`);
  const utilityAddr = await deployContract("UtilityTokenCreator",
    new ethers.ContractFactory(utilityCreatorArt.abi, utilityCreatorArt.bytecode, wallet),
    wallet, provider);

  console.log(`\n[3/${total}] Deploying RewardTokenCreator...`);
  const rewardAddr = await deployContract("RewardTokenCreator",
    new ethers.ContractFactory(rewardCreatorArt.abi, rewardCreatorArt.bytecode, wallet),
    wallet, provider);

  console.log(`\n[4/${total}] Deploying GovernanceTokenCreator...`);
  const governanceAddr = await deployContract("GovernanceTokenCreator",
    new ethers.ContractFactory(governanceCreatorArt.abi, governanceCreatorArt.bytecode, wallet),
    wallet, provider);

  console.log(`\n[5/${total}] Deploying StablecoinTokenCreator...`);
  const stablecoinAddr = await deployContract("StablecoinTokenCreator",
    new ethers.ContractFactory(stablecoinCreatorArt.abi, stablecoinCreatorArt.bytecode, wallet),
    wallet, provider);

  // Deploy ERC-20 coordinator
  console.log(`\n[6/${total}] Deploying TPIXTokenFactoryV2 (coordinator)...`);
  const v2Addr = await deployContract("TPIXTokenFactoryV2",
    new ethers.ContractFactory(factoryV2Art.abi, factoryV2Art.bytecode, wallet),
    wallet, provider,
    [erc20V2Addr, utilityAddr, rewardAddr, governanceAddr, stablecoinAddr]);

  // Deploy 2 NFT creators
  console.log(`\n[7/${total}] Deploying FactoryERC721Creator...`);
  const erc721Addr = await deployContract("FactoryERC721Creator",
    new ethers.ContractFactory(erc721CreatorArt.abi, erc721CreatorArt.bytecode, wallet),
    wallet, provider);

  console.log(`\n[8/${total}] Deploying NFTCollectionCreator...`);
  const collectionAddr = await deployContract("NFTCollectionCreator",
    new ethers.ContractFactory(collectionCreatorArt.abi, collectionCreatorArt.bytecode, wallet),
    wallet, provider);

  // Deploy NFT coordinator
  console.log(`\n[9/${total}] Deploying TPIXNFTFactory (coordinator)...`);
  const nftAddr = await deployContract("TPIXNFTFactory",
    new ethers.ContractFactory(nftFactoryArt.abi, nftFactoryArt.bytecode, wallet),
    wallet, provider,
    [erc721Addr, collectionAddr]);

  // Verify
  console.log("\nVerification:");
  const v2Contract = new ethers.Contract(v2Addr, factoryV2Art.abi, provider);
  const nftContract = new ethers.Contract(nftAddr, nftFactoryArt.abi, provider);
  console.log("  V2 owner:", await v2Contract.owner());
  console.log("  V2 totalTokens:", (await v2Contract.totalTokens()).toString());
  console.log("  NFT owner:", await nftContract.owner());
  console.log("  NFT totalNFTs:", (await nftContract.totalNFTs()).toString());

  // Output for parsing
  console.log("\nTOKEN_FACTORY_V2_ADDRESS=" + v2Addr);
  console.log("NFT_FACTORY_ADDRESS=" + nftAddr);
}

main().catch((e) => {
  console.log("Fatal:", e.message || e);
  console.log("Stack:", e.stack || "no stack");
  process.exit(1);
});
