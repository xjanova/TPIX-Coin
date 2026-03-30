#!/usr/bin/env node
/**
 * Deploy TPIX Token Factory V2 + NFT Factory contracts
 *
 * Usage:
 *   npx hardhat run scripts/deploy/deploy-factory-v2.js --network tpix
 *   npx hardhat run scripts/deploy/deploy-factory-v2.js --network tpixTestnet
 *
 * Output:
 *   Prints deployed contract addresses for .env configuration
 *
 * Developed by Xman Studio
 */

const hre = require('hardhat');

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    const network = hre.network.name;
    const chainId = (await hre.ethers.provider.getNetwork()).chainId;

    console.log('═══════════════════════════════════════════');
    console.log(' TPIX Token Factory V2 — Deployment');
    console.log('═══════════════════════════════════════════');
    console.log(`Network:  ${network} (Chain ID: ${chainId})`);
    console.log(`Deployer: ${deployer.address}`);
    console.log(`Balance:  ${hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address))} TPIX`);
    console.log('');

    // ──────────────────────────────────────────
    //  1. Deploy TPIXTokenFactoryV2 (ERC-20 tokens)
    // ──────────────────────────────────────────
    console.log('[1/2] Deploying TPIXTokenFactoryV2...');
    const TokenFactoryV2 = await hre.ethers.getContractFactory('TPIXTokenFactoryV2');
    const tokenFactory = await TokenFactoryV2.deploy({ gasPrice: 0 });
    await tokenFactory.waitForDeployment();
    const tokenFactoryAddr = await tokenFactory.getAddress();
    console.log(`  ✅ TPIXTokenFactoryV2: ${tokenFactoryAddr}`);

    // ──────────────────────────────────────────
    //  2. Deploy TPIXNFTFactory (NFT tokens)
    // ──────────────────────────────────────────
    console.log('[2/2] Deploying TPIXNFTFactory...');
    const NFTFactory = await hre.ethers.getContractFactory('TPIXNFTFactory');
    const nftFactory = await NFTFactory.deploy({ gasPrice: 0 });
    await nftFactory.waitForDeployment();
    const nftFactoryAddr = await nftFactory.getAddress();
    console.log(`  ✅ TPIXNFTFactory:     ${nftFactoryAddr}`);

    // ──────────────────────────────────────────
    //  Summary
    // ──────────────────────────────────────────
    console.log('');
    console.log('═══════════════════════════════════════════');
    console.log(' Deployment Complete!');
    console.log('═══════════════════════════════════════════');
    console.log('');
    console.log('Add to .env:');
    console.log('');
    console.log(`TOKEN_FACTORY_V2_ADDRESS=${tokenFactoryAddr}`);
    console.log(`NFT_FACTORY_ADDRESS=${nftFactoryAddr}`);
    console.log('');
    console.log('Note: V1 factory (TOKEN_FACTORY_ADDRESS) remains');
    console.log('active for backward compatibility.');
    console.log('═══════════════════════════════════════════');
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error('Deployment failed:', error);
        process.exit(1);
    });
