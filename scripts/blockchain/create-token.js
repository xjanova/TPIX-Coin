#!/usr/bin/env node
/**
 * Create a token via TPIXTokenFactory contract
 *
 * Input: Environment variables + CLI args as JSON
 * Output: JSON to stdout
 *
 * Env vars:
 *   DEPLOYER_PRIVATE_KEY  - Wallet private key for signing
 *   TOKEN_FACTORY_ADDRESS - Deployed factory contract address
 *   TPIX_RPC_URL          - RPC endpoint (default: https://rpc.tpix.online)
 *
 * CLI: node create-token.js '{"name":"My Token","symbol":"MTK",...}'
 *
 * Developed by Xman Studio
 */

const { ethers } = require('ethers');
const path = require('path');
const fs = require('fs');

// Load factory ABI from Hardhat artifacts
function loadFactoryABI() {
    const artifactPath = path.resolve(
        __dirname,
        '../../contracts/artifacts/contracts/factory/TPIXTokenFactory.sol/TPIXTokenFactory.json'
    );

    if (!fs.existsSync(artifactPath)) {
        throw new Error(
            `Factory artifact not found at ${artifactPath}. Run "npx hardhat compile" first.`
        );
    }

    const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
    return artifact.abi;
}

async function main() {
    // Parse input
    const input = JSON.parse(process.argv[2]);
    const {
        name,
        symbol,
        decimals = 18,
        totalSupply, // Already in wei (smallest unit)
        tokenOwner,
        tokenType = 0, // 0=standard, 1=mintable, 2=burnable, 3=mintable_burnable
    } = input;

    // Validate required fields
    if (!name || !symbol || !totalSupply || !tokenOwner) {
        throw new Error('Missing required fields: name, symbol, totalSupply, tokenOwner');
    }

    // Read config from environment
    const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
    const factoryAddress = process.env.TOKEN_FACTORY_ADDRESS;
    const rpcUrl = process.env.TPIX_RPC_URL || 'https://rpc.tpix.online';

    if (!privateKey) throw new Error('DEPLOYER_PRIVATE_KEY not set');
    if (!factoryAddress) throw new Error('TOKEN_FACTORY_ADDRESS not set');

    // Connect to TPIX Chain
    const provider = new ethers.JsonRpcProvider(rpcUrl, {
        chainId: 4289,
        name: 'tpix',
    });

    const wallet = new ethers.Wallet(privateKey, provider);

    // Load factory contract
    const factoryABI = loadFactoryABI();
    const factory = new ethers.Contract(factoryAddress, factoryABI, wallet);

    // Call createToken (gasless on TPIX Chain)
    const tx = await factory.createToken(
        name,
        symbol,
        decimals,
        totalSupply,
        tokenOwner,
        tokenType,
        { gasPrice: 0 }
    );

    // Wait for confirmation
    const receipt = await tx.wait();

    // Parse TokenCreated event from logs
    const iface = new ethers.Interface(factoryABI);
    let tokenAddress = null;

    for (const log of receipt.logs) {
        try {
            const parsed = iface.parseLog({ topics: log.topics, data: log.data });
            if (parsed && parsed.name === 'TokenCreated') {
                tokenAddress = parsed.args.tokenAddress || parsed.args[0];
                break;
            }
        } catch {
            // Skip logs from other contracts
        }
    }

    if (!tokenAddress) {
        throw new Error('TokenCreated event not found in transaction receipt');
    }

    // Output result as JSON
    const result = {
        success: true,
        contractAddress: tokenAddress,
        txHash: receipt.hash,
        blockNumber: receipt.blockNumber,
    };

    process.stdout.write(JSON.stringify(result));
}

main().catch((error) => {
    const result = {
        success: false,
        error: error.message || String(error),
    };
    process.stdout.write(JSON.stringify(result));
    process.exit(1);
});
