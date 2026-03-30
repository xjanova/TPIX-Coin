#!/usr/bin/env node
/**
 * Create a token via TPIX Token Factory V2 contracts
 * Called by PHP backend (Web3DeploymentService)
 *
 * รองรับทุก token type:
 *   ERC-20: standard, mintable, burnable, mintable_burnable, utility, reward, governance, stablecoin
 *   ERC-721: nft, nft_collection
 *
 * Input: Environment variables + CLI args as JSON
 * Output: JSON to stdout
 *
 * Env vars:
 *   DEPLOYER_PRIVATE_KEY       - Wallet private key for signing
 *   TOKEN_FACTORY_ADDRESS      - V1 factory (legacy)
 *   TOKEN_FACTORY_V2_ADDRESS   - V2 ERC-20 factory
 *   NFT_FACTORY_ADDRESS        - NFT factory
 *   TPIX_RPC_URL               - RPC endpoint
 *
 * CLI: node create-token.js '{"name":"My Token","symbol":"MTK",...}'
 *
 * Developed by Xman Studio
 */

const { ethers } = require('ethers');
const path = require('path');
const fs = require('fs');

// ═══════════════════════════════════════════
//  ABI LOADING
// ═══════════════════════════════════════════

function loadABI(contractPath) {
    const artifactPath = path.resolve(__dirname, '../../artifacts/contracts/', contractPath);

    if (!fs.existsSync(artifactPath)) {
        throw new Error(`Artifact not found: ${artifactPath}. Run "npx hardhat compile" first.`);
    }

    const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
    return artifact.abi;
}

// ═══════════════════════════════════════════
//  TOKEN TYPE ROUTING
// ═══════════════════════════════════════════

const ERC20_TYPES = ['standard', 'mintable', 'burnable', 'mintable_burnable'];
const UTILITY_TYPE = 'utility';
const REWARD_TYPE = 'reward';
const GOVERNANCE_TYPE = 'governance';
const STABLECOIN_TYPE = 'stablecoin';
const NFT_TYPE = 'nft';
const NFT_COLLECTION_TYPE = 'nft_collection';

function getFactoryInfo(tokenType) {
    if (ERC20_TYPES.includes(tokenType)) {
        return {
            envKey: 'TOKEN_FACTORY_V2_ADDRESS',
            fallbackEnvKey: 'TOKEN_FACTORY_ADDRESS',
            abiPath: 'factory/TPIXTokenFactoryV2.sol/TPIXTokenFactoryV2.json',
            fallbackAbiPath: 'factory/TPIXTokenFactory.sol/TPIXTokenFactory.json',
            category: 'erc20v2',
        };
    }
    if (tokenType === UTILITY_TYPE) {
        return {
            envKey: 'TOKEN_FACTORY_V2_ADDRESS',
            abiPath: 'factory/TPIXTokenFactoryV2.sol/TPIXTokenFactoryV2.json',
            category: 'utility',
        };
    }
    if (tokenType === REWARD_TYPE) {
        return {
            envKey: 'TOKEN_FACTORY_V2_ADDRESS',
            abiPath: 'factory/TPIXTokenFactoryV2.sol/TPIXTokenFactoryV2.json',
            category: 'reward',
        };
    }
    if (tokenType === GOVERNANCE_TYPE) {
        return {
            envKey: 'TOKEN_FACTORY_V2_ADDRESS',
            abiPath: 'factory/TPIXTokenFactoryV2.sol/TPIXTokenFactoryV2.json',
            category: 'governance',
        };
    }
    if (tokenType === STABLECOIN_TYPE) {
        return {
            envKey: 'TOKEN_FACTORY_V2_ADDRESS',
            abiPath: 'factory/TPIXTokenFactoryV2.sol/TPIXTokenFactoryV2.json',
            category: 'stablecoin',
        };
    }
    if (tokenType === NFT_TYPE) {
        return {
            envKey: 'NFT_FACTORY_ADDRESS',
            abiPath: 'factory/TPIXNFTFactory.sol/TPIXNFTFactory.json',
            category: 'nft',
        };
    }
    if (tokenType === NFT_COLLECTION_TYPE) {
        return {
            envKey: 'NFT_FACTORY_ADDRESS',
            abiPath: 'factory/TPIXNFTFactory.sol/TPIXNFTFactory.json',
            category: 'nft_collection',
        };
    }

    throw new Error(`Unknown token type: ${tokenType}`);
}

// ═══════════════════════════════════════════
//  DEPLOY FUNCTIONS
// ═══════════════════════════════════════════

/**
 * Deploy basic ERC-20 via V2 factory (standard/mintable/burnable)
 */
async function deployERC20V2(factory, input) {
    const sub = input.subOptions || {};

    const tokenTypeInt = { standard: 0, mintable: 1, burnable: 2, mintable_burnable: 3 }[input.tokenType] || 0;
    const mintable = tokenTypeInt === 1 || tokenTypeInt === 3;
    const burnable = tokenTypeInt === 2 || tokenTypeInt === 3;

    const tx = await factory.createERC20V2(
        input.name,
        input.symbol,
        input.decimals,
        input.totalSupply,
        input.tokenOwner,
        mintable,
        burnable,
        sub.pausable || false,
        sub.blacklist || false,
        sub.mint_cap ? ethers.parseUnits(String(sub.mint_cap), input.decimals) : 0n,
        sub.auto_burn || false,
        sub.auto_burn_rate || 0,    // basis points
        sub.burn_floor ? ethers.parseUnits(String(sub.burn_floor), input.decimals) : 0n,
        { gasPrice: 0 }
    );

    return tx;
}

/**
 * Deploy basic ERC-20 via V1 factory (fallback สำหรับ backward compat)
 */
async function deployERC20V1(factory, input) {
    const tokenTypeInt = { standard: 0, mintable: 1, burnable: 2, mintable_burnable: 3 }[input.tokenType] || 0;

    const tx = await factory.createToken(
        input.name,
        input.symbol,
        input.decimals,
        input.totalSupply,
        input.tokenOwner,
        tokenTypeInt,
        { gasPrice: 0 }
    );

    return tx;
}

/**
 * Deploy Utility Token
 */
async function deployUtilityToken(factory, input) {
    const sub = input.subOptions || {};

    const taxConfig = {
        buyTaxBps: sub.buy_tax_rate ? Math.round(sub.buy_tax_rate * 100) : 0,
        sellTaxBps: sub.sell_tax_rate ? Math.round(sub.sell_tax_rate * 100) : 0,
        transferTaxBps: sub.transfer_tax_rate ? Math.round(sub.transfer_tax_rate * 100) : 0,
        taxWallet: sub.tax_wallet || input.tokenOwner,
        marketingWallet: sub.marketing_wallet || input.tokenOwner,
        marketingShareBps: sub.marketing_share ? Math.round(sub.marketing_share * 100) : 0,
    };

    const protectionConfig = {
        maxWalletBps: sub.max_wallet_percent ? Math.round(sub.max_wallet_percent * 100) : 0,
        maxTxBps: sub.max_tx_percent ? Math.round(sub.max_tx_percent * 100) : 0,
        antiBotDuration: sub.anti_bot_duration || 0,
        tradingCooldown: sub.trading_cooldown || 0,
    };

    const tx = await factory.createUtilityToken(
        input.name,
        input.symbol,
        input.decimals,
        input.totalSupply,
        input.tokenOwner,
        sub.mintable || false,
        sub.burnable || false,
        sub.pausable || false,
        sub.blacklist || false,
        taxConfig,
        protectionConfig,
        { gasPrice: 0 }
    );

    return tx;
}

/**
 * Deploy Reward Token
 */
async function deployRewardToken(factory, input) {
    const sub = input.subOptions || {};

    const rewardTypeMap = { reflection: 0, dividend: 1, staking: 2 };
    const rewardType = rewardTypeMap[sub.reward_type] ?? 0;

    const tx = await factory.createRewardToken(
        input.name,
        input.symbol,
        input.decimals,
        input.totalSupply,
        input.tokenOwner,
        sub.mintable || false,
        sub.burnable || false,
        sub.pausable || false,
        sub.blacklist || false,
        rewardType,
        sub.reward_rate ? Math.round(sub.reward_rate * 100) : 200, // default 2%
        sub.min_hold_for_reward ? ethers.parseUnits(String(sub.min_hold_for_reward), input.decimals) : 0n,
        sub.vesting_cliff_days ? sub.vesting_cliff_days * 86400 : 0, // days → seconds
        sub.vesting_duration_days ? sub.vesting_duration_days * 86400 : 0,
        { gasPrice: 0 }
    );

    return tx;
}

/**
 * Deploy Governance Token
 */
async function deployGovernanceToken(factory, input) {
    const sub = input.subOptions || {};

    const tx = await factory.createGovernanceToken(
        input.name,
        input.symbol,
        input.decimals,
        input.totalSupply,
        input.tokenOwner,
        sub.mintable || false,
        sub.burnable || false,
        sub.pausable || false,
        sub.blacklist || false,
        sub.delegation !== false, // default true
        sub.mint_cap ? ethers.parseUnits(String(sub.mint_cap), input.decimals) : 0n,
        sub.proposal_threshold ? ethers.parseUnits(String(sub.proposal_threshold), input.decimals) : 0n,
        sub.quorum_percent ? Math.round(sub.quorum_percent * 100) : 400, // default 4%
        sub.voting_period_days ? sub.voting_period_days * 86400 : 259200, // default 3 days
        { gasPrice: 0 }
    );

    return tx;
}

/**
 * Deploy Stablecoin Token
 */
async function deployStablecoinToken(factory, input) {
    const sub = input.subOptions || {};

    const tx = await factory.createStablecoinToken(
        input.name,
        input.symbol,
        input.decimals,
        input.totalSupply,
        input.tokenOwner,
        sub.reserve_wallet || input.tokenOwner,
        sub.pausable || false,
        sub.freeze || false,
        sub.kyc || false,
        { gasPrice: 0 }
    );

    return tx;
}

/**
 * Deploy Single NFT
 */
async function deployNFT(factory, input) {
    const sub = input.subOptions || {};

    const tx = await factory.createNFT(
        input.name,
        input.symbol,
        input.tokenOwner,
        sub.metadata_uri || input.logoUrl || '',
        input.totalSupply ? BigInt(input.totalSupply) : 1n,
        sub.mintable || false,
        sub.soulbound || false,
        sub.royalty || false,
        sub.royalty_recipient || input.tokenOwner,
        sub.royalty_rate ? Math.round(sub.royalty_rate * 100) : 0,
        { gasPrice: 0 }
    );

    return tx;
}

/**
 * Deploy NFT Collection
 */
async function deployNFTCollection(factory, input) {
    const sub = input.subOptions || {};

    const mintTypeMap = { public: 0, whitelist: 1, free: 2 };
    const mintType = mintTypeMap[sub.mint_type] ?? 0;

    const tx = await factory.createNFTCollection(
        input.name,
        input.symbol,
        input.tokenOwner,
        input.totalSupply ? BigInt(input.totalSupply) : 10000n,
        mintType,
        sub.mint_price ? ethers.parseEther(String(sub.mint_price)) : 0n,
        sub.max_per_wallet || 0,
        sub.max_per_tx || 0,
        sub.reserve_count || 0,
        sub.base_uri || '',
        sub.placeholder_uri || '',
        sub.delayed_reveal || false,
        sub.royalty || false,
        sub.royalty_recipient || input.tokenOwner,
        sub.royalty_rate ? Math.round(sub.royalty_rate * 100) : 0,
        { gasPrice: 0 }
    );

    return tx;
}

// ═══════════════════════════════════════════
//  MAIN
// ═══════════════════════════════════════════

async function main() {
    const input = JSON.parse(process.argv[2]);
    const {
        name,
        symbol,
        decimals = 18,
        totalSupply,
        tokenOwner,
        tokenType = 'standard',
        subOptions = {},
        logoUrl = '',
    } = input;

    if (!name || !symbol || !tokenOwner) {
        throw new Error('Missing required fields: name, symbol, tokenOwner');
    }

    // Read config from environment
    const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
    const rpcUrl = process.env.TPIX_RPC_URL || 'https://rpc.tpix.online';

    if (!privateKey) throw new Error('DEPLOYER_PRIVATE_KEY not set');

    // Connect to TPIX Chain
    const provider = new ethers.JsonRpcProvider(rpcUrl, {
        chainId: 4289,
        name: 'tpix',
    });

    const wallet = new ethers.Wallet(privateKey, provider);

    // Get factory info
    const factoryInfo = getFactoryInfo(tokenType);
    let factoryAddress = process.env[factoryInfo.envKey];

    // Fallback to V1 factory for basic ERC-20 types
    let useV1 = false;
    if (!factoryAddress && factoryInfo.fallbackEnvKey) {
        factoryAddress = process.env[factoryInfo.fallbackEnvKey];
        useV1 = true;
    }

    if (!factoryAddress) {
        throw new Error(`Factory address not configured (${factoryInfo.envKey})`);
    }

    // Load factory ABI
    const abiPath = useV1 ? factoryInfo.fallbackAbiPath : factoryInfo.abiPath;
    const factoryABI = loadABI(abiPath);
    const factory = new ethers.Contract(factoryAddress, factoryABI, wallet);

    // Build deploy input
    const deployInput = {
        name,
        symbol,
        decimals,
        totalSupply: totalSupply || '0',
        tokenOwner,
        tokenType,
        subOptions,
        logoUrl,
    };

    // Route to correct deploy function
    let tx;

    if (useV1) {
        tx = await deployERC20V1(factory, deployInput);
    } else {
        switch (factoryInfo.category) {
            case 'erc20v2':
                tx = await deployERC20V2(factory, deployInput);
                break;
            case 'utility':
                tx = await deployUtilityToken(factory, deployInput);
                break;
            case 'reward':
                tx = await deployRewardToken(factory, deployInput);
                break;
            case 'governance':
                tx = await deployGovernanceToken(factory, deployInput);
                break;
            case 'stablecoin':
                tx = await deployStablecoinToken(factory, deployInput);
                break;
            case 'nft':
                tx = await deployNFT(factory, deployInput);
                break;
            case 'nft_collection':
                tx = await deployNFTCollection(factory, deployInput);
                break;
            default:
                throw new Error(`No deploy handler for category: ${factoryInfo.category}`);
        }
    }

    // Wait for confirmation
    const receipt = await tx.wait();

    // Parse TokenCreated / NFTCreated event from logs
    const iface = new ethers.Interface(factoryABI);
    let tokenAddress = null;

    for (const log of receipt.logs) {
        try {
            const parsed = iface.parseLog({ topics: log.topics, data: log.data });
            if (parsed && (parsed.name === 'TokenCreated' || parsed.name === 'NFTCreated')) {
                tokenAddress = parsed.args.tokenAddress || parsed.args.nftAddress || parsed.args[0];
                break;
            }
        } catch {
            // Skip logs from other contracts
        }
    }

    if (!tokenAddress) {
        throw new Error('Token/NFT created event not found in transaction receipt');
    }

    // Output result
    const result = {
        success: true,
        contractAddress: tokenAddress,
        txHash: receipt.hash,
        blockNumber: receipt.blockNumber,
        factoryVersion: useV1 ? 'v1' : 'v2',
        category: factoryInfo.category,
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
