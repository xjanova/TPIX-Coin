<p align="center">
  <img src="wallet/assets/images/tpixlogo.webp" alt="TPIX Chain" width="120" />
</p>

<h1 align="center">TPIX Chain</h1>

<p align="center">
  <strong>A Next-Generation EVM Blockchain for the ASEAN Digital Economy</strong><br/>
  Zero Gas Fees — 2-Second Blocks — IBFT 2.0 Consensus — ~1,500 TPS
</p>

<p align="center">
  <a href="https://tpix.online"><img src="https://img.shields.io/badge/DEX-tpix.online-blue?style=flat-square" alt="DEX" /></a>
  <a href="https://explorer.tpix.online"><img src="https://img.shields.io/badge/Explorer-explorer.tpix.online-green?style=flat-square" alt="Explorer" /></a>
  <a href="https://tpix.online/whitepaper"><img src="https://img.shields.io/badge/Whitepaper-v2.0-orange?style=flat-square" alt="Whitepaper" /></a>
  <a href="https://github.com/xjanova/TPIX-Coin/releases"><img src="https://img.shields.io/github/v/release/xjanova/TPIX-Coin?style=flat-square&color=cyan" alt="Release" /></a>
</p>

<p align="center">
  <a href="https://github.com/ethereum-lists/chains/pull/8231"><img src="https://img.shields.io/badge/EIP--155-4289-6366f1?style=flat-square" alt="EIP-155 ID 4289" /></a>
  <img src="https://img.shields.io/badge/Gas-FREE-22c55e?style=flat-square" alt="Gas: FREE" />
  <img src="https://img.shields.io/badge/Block-2s-06b6d4?style=flat-square" alt="Block Time: 2s" />
  <img src="https://img.shields.io/badge/Consensus-IBFT%202.0-f97316?style=flat-square" alt="IBFT 2.0" />
  <img src="https://img.shields.io/badge/Supply-7B%20TPIX-facc15?style=flat-square" alt="7B TPIX fixed supply" />
</p>

---

## Executive Summary

TPIX Chain is a high-performance EVM-compatible blockchain built on **Polygon Edge** technology, designed specifically for the Thai and Southeast Asian digital economy. With gasless transactions, 2-second block times, and IBFT Proof-of-Authority consensus, TPIX Chain provides an unmatched platform for decentralized applications, DeFi, and real-world asset tokenization.

The native **TPIX coin** (7 billion fixed supply, 18 decimals) powers the entire ecosystem including: a built-in Uniswap V2 DEX, multi-tier master node system, a token factory for custom ERC-20 creation, cross-chain bridge to BSC, and integration with enterprise platforms serving 500,000+ users.

---

## Chain Specifications

| Parameter | Value |
|-----------|-------|
| **Chain Name** | TPIX Chain |
| **Chain ID (Mainnet)** | `4289` |
| **Chain ID (Testnet)** | `4290` |
| **Consensus** | IBFT 2.0 (Istanbul Byzantine Fault Tolerant) |
| **Block Time** | 2 seconds |
| **Finality** | ~10 seconds (5 blocks) |
| **Gas Price** | 0 (Free — hardcoded in genesis) |
| **TPS Capacity** | ~1,500 transactions/second |
| **VM** | EVM (Full Solidity & ERC-20/721 support) |
| **Native Coin** | TPIX (18 decimals) |
| **Total Supply** | 7,000,000,000 TPIX (pre-mined in genesis) |
| **Validators** | 4 IBFT nodes (BFT tolerates 1 faulty) |
| **RPC URL** | `https://rpc.tpix.online` |
| **Block Explorer** | [explorer.tpix.online](https://explorer.tpix.online) |

---

## Chain Listings & Registrations

We believe in public, verifiable infrastructure. Here is the real-time status of TPIX Chain's registration across the ecosystem — no overclaims, no marketing fluff.

### Public Registries

| Registry | Status | Source |
|----------|--------|--------|
| **[ethereum-lists/chains](https://github.com/ethereum-lists/chains)** | ⏳ Under review | [PR #8231](https://github.com/ethereum-lists/chains/pull/8231) opened 2026-04-17 — source of truth for chainlist.org, chainid.network, and most EVM wallets |
| **[chainlist.org](https://chainlist.org)** | ⏳ Pending merge | Auto-populates within hours after ethereum-lists merges PR #8231 |
| **[chainid.network](https://chainid.network)** | ⏳ Pending merge | Same data source as chainlist.org |
| **Rabby Wallet** | ⏳ Pending merge | Pulls from ethereum-lists — logo appears automatically after merge |
| **OKX Web3 Wallet** | ⏳ Pending merge | Pulls from ethereum-lists |
| **Trust Wallet** | ⏳ Pending merge | Partial — pulls chain data from ethereum-lists; native-icon submission to `trustwallet/assets` is a separate future step |
| **MetaMask (built-in icon)** | 🔲 Not yet | Requires separate PR to `MetaMask/metamask-extension` — planned after PR #8231 merges |
| **CoinGecko** | 🔲 Not yet | Listing application requires active market data from at least one exchange |
| **CoinMarketCap** | 🔲 Not yet | Listing application requires verified circulating supply + exchange listings |
| **DeFiLlama** | 🔲 Not yet | Requires TVL data via subgraph or adapter |

### Icon Asset — Verifiable & Content-Addressed

The official TPIX Chain logo is published both via IPFS (content-addressed, immutable) and via our own CDN.

| Source | URL / Identifier |
|--------|------------------|
| **IPFS (primary, content-addressed)** | `ipfs://bafybeiby5mwnwdi53fye4iurjxlddfzonsj67ejl4sjy7qda53za6jlgo4` |
| **IPFS Gateway (HTTPS)** | [ipfs.io/ipfs/bafybeiby5mwnwdi53fye4iurjxlddfzonsj67ejl4sjy7qda53za6jlgo4](https://ipfs.io/ipfs/bafybeiby5mwnwdi53fye4iurjxlddfzonsj67ejl4sjy7qda53za6jlgo4) |
| **Canonical CDN (HTTPS)** | [`https://tpix.online/images/tpix-logo-512.png`](https://tpix.online/images/tpix-logo-512.png) |
| **Format** | 512×512 PNG, transparent background, 323 KB |

Anyone can verify the icon has not been tampered with: `ipfs get bafybeiby5mwnwdi53fye4iurjxlddfzonsj67ejl4sjy7qda53za6jlgo4` → SHA-256 matches.

### Native DEX Integration (tpix.online)

Our DEX at [tpix.online](https://tpix.online) acts as the primary on-ramp for chain adoption. Any visitor connecting a wallet gets TPIX Chain auto-added with icon (where the wallet supports it) — **no separate registry required**.

| Feature | Implementation | Covered Wallets |
|---------|----------------|-----------------|
| **Auto-add TPIX Chain after connect** | [EIP-3085](https://eips.ethereum.org/EIPS/eip-3085) `wallet_addEthereumChain` with `iconUrls` | MetaMask, Rabby, OKX, Trust, Coinbase, WalletConnect |
| **Chain icon displayed** | `iconUrls: ["https://tpix.online/images/tpix-logo-512.png"]` | Rabby, OKX, Trust (MetaMask ignores `iconUrls`; awaits PR to their repo) |
| **1-click "Add to Wallet" for custom tokens** | [EIP-747](https://eips.ethereum.org/EIPS/eip-747) `wallet_watchAsset` | MetaMask, Rabby, OKX, Trust, Coinbase |
| **Auto chain-switch before token add** | `wallet_switchEthereumChain` fallback + error toast if declined | All EIP-1193 wallets |

Implementation reference: [`resources/js/utils/web3.js`](https://github.com/xjanova/ThaiXTrade/blob/main/resources/js/utils/web3.js) — `addTPIXChainToWallet()`, `addTokenToWallet()`, `buildAddChainParams()`.

### What's Missing — Honest Gap Analysis

| Gap | Effort | Blocker |
|-----|--------|---------|
| MetaMask built-in chain icon | Medium (SVG + PR) | Waiting for ethereum-lists/chains#8231 to merge first |
| Trust Wallet native asset entry | Medium (PR to `trustwallet/assets`) | Low priority — chain already visible via chainlist import |
| CoinGecko listing | High (needs DEX volume + supply proof) | Launch liquidity on external CEX/DEX needed |
| CoinMarketCap listing | High (needs verified supply audit) | Token contract audit + exchange listings |
| DeFiLlama adapter | Medium (SDK integration) | Our DEX factory needs subgraph indexing |
| Wallet Connect v2 project listing | Low | Submit project metadata to WalletConnect Cloud |

---

## Repository Structure

```
TPIX-Coin/
├── contracts/              # Solidity smart contracts (Hardhat)
│   ├── identity/           # Living Identity recovery contract
│   │   └── TPIXIdentity.sol
│   ├── masternode/         # Node registry & staking
│   ├── bridge/             # Cross-chain bridge (BSC)
│   ├── dex/                # DEX router (Uniswap V2 fork)
│   ├── token-factory/      # Token Factory contracts (Phase 2)
│   │   ├── TPIXTokenFactory.sol     # V1 factory (basic ERC-20)
│   │   ├── TPIXTokenFactoryV2.sol   # V2 coordinator (all ERC-20 types)
│   │   ├── TPIXNFTFactory.sol       # NFT coordinator (single + collection)
│   │   ├── interfaces/              # Lightweight creator interfaces
│   │   │   ├── ITokenCreators.sol   # ERC-20 creator interfaces
│   │   │   └── INFTCreators.sol     # NFT creator interfaces
│   │   ├── ERC20V2Creator.sol       # Sub-factory: Enhanced ERC-20
│   │   ├── UtilityTokenCreator.sol  # Sub-factory: Utility token
│   │   ├── RewardTokenCreator.sol   # Sub-factory: Reward token
│   │   ├── GovernanceTokenCreator.sol # Sub-factory: Governance token
│   │   ├── StablecoinTokenCreator.sol # Sub-factory: Stablecoin
│   │   ├── FactoryERC721Creator.sol # Sub-factory: Single NFT
│   │   ├── NFTCollectionCreator.sol # Sub-factory: NFT collection
│   │   ├── FactoryERC20.sol         # Basic ERC-20 template
│   │   ├── FactoryERC20V2.sol       # Enhanced ERC-20 (pausable, blacklist, auto-burn)
│   │   ├── UtilityToken.sol         # Tax, anti-whale, anti-bot
│   │   ├── RewardToken.sol          # Reflection, dividend, vesting
│   │   ├── GovernanceToken.sol      # ERC20Votes, delegation
│   │   ├── StablecoinToken.sol      # Freeze, KYC, authority mint/burn
│   │   ├── FactoryERC721.sol        # Single NFT (royalty, soulbound)
│   │   └── NFTCollection.sol        # Collection (mint, reveal, royalty)
│   ├── scripts/            # Deploy & verify scripts
│   └── hardhat.config.js
├── infrastructure/         # Genesis config & Docker deployment
│   ├── genesis.json        # Chain genesis (4 validators, 7B supply)
│   ├── docker-compose.yml  # 4-node IBFT cluster
│   └── blockscout/         # Block Explorer (Blockscout)
│       ├── docker-compose.yml  # Explorer + PostgreSQL + Verifier
│       └── .env.example    # Environment configuration
├── scripts/
│   └── blockchain/
│       ├── create-token.js               # Token Factory V1 deployment
│       └── deploy-factory-v2-remote.mjs  # Factory V2 + NFT deploy (GitHub Actions)
├── masternode/             # Polygon Edge node config & install scripts
├── masternode-app/         # Master Node CLI tools (Go/Wails)
├── masternode-ui/          # Master Node Electron GUI (Windows)
│   └── electron/           # HD wallet, identity manager, SQLite
├── wallet/                 # TPIX Wallet — Flutter mobile app
│   └── lib/
│       ├── services/       # wallet_service, identity_service
│       ├── screens/        # UI screens (home, send, identity, etc.)
│       └── providers/      # State management
├── docs/                   # Documentation
│   ├── WHITEPAPER.md       # Comprehensive whitepaper (v2.0)
│   ├── CARBON-CREDIT.md    # Carbon Credit system documentation
│   └── EXPLORER.md         # Block Explorer setup guide
├── .github/workflows/      # CI/CD — auto-build APK + EXE on tag push
└── LICENSE
```

---

## Products

### TPIX Wallet (Android/iOS)

Secure mobile wallet for TPIX Chain with premium 3D animated UI.

- **Multi-Wallet**: HD wallet with BIP-39/BIP-44 derivation (up to 128 wallets)
- **Living Identity Recovery**: Recover wallet without seed phrase using security questions + GPS location (hashed, never stored raw) + recovery PIN
- **QR Scanner**: Scan QR codes to send TPIX instantly
- **Transaction History**: Local storage + blockchain scanning
- **Security**: AES-256 encrypted keystore, PIN protection, 6-digit recovery PIN
- **Bilingual**: Thai + English with one-tap switching
- **Auto-update**: Check GitHub Releases for latest version

**Download**: [Latest Release](https://github.com/xjanova/TPIX-Coin/releases/latest)

### Master Node (Windows)

Desktop application to run TPIX Chain validator nodes.

- **HD Wallet**: BIP-39 seed phrase with multi-wallet management (128 slots)
- **Living Identity**: Security questions + recovery PIN protection
- **QR Scanner**: Camera-based address scanning for sending TPIX
- **One-click setup**: Auto-configuration with smart port/IP allocation
- **Multi-node**: Run multiple nodes on different ports
- **Dashboard**: Real-time network monitoring with SQLite persistence
- **3 Tiers**: Light (10K TPIX), Sentinel (100K), Validator (1M)
- **Rewards**: Up to 15% APY from 1.4B reward pool

**Guide**: [tpix.online/masternode/guide](https://tpix.online/masternode/guide)

### TPIX TRADE (DEX)

Decentralized exchange at [tpix.online](https://tpix.online) — Uniswap V2 fork optimized for TPIX Chain.

- Spot trading with real-time charts
- Token swap with 0.3% fee (0.25% to LPs, 0.05% to protocol)
- Liquidity provision with LP token rewards
- Multi-chain support: TPIX Chain, BSC, Ethereum, Polygon

### Block Explorer (Blockscout)

Self-hosted block explorer at [explorer.tpix.online](https://explorer.tpix.online) powered by Blockscout.

- **Transaction & Address Search** — Look up any tx, address, or token
- **Smart Contract Verification** — Verify Solidity source code
- **Token Tracker** — List all ERC-20 tokens on TPIX Chain
- **API v2** — REST API for programmatic access
- **Real-Time Stats** — Transaction charts, network activity

**Setup guide**: [docs/EXPLORER.md](docs/EXPLORER.md) | **Docker**: `infrastructure/blockscout/docker-compose.yml`

### Carbon Credit System

On-chain carbon credit trading with IoT verification at [tpix.online/carbon-credits](https://tpix.online/carbon-credits).

- **Verified Credits** — VCS, Gold Standard, CDM, ACR standards
- **IoT Integration** — Real-time sensor verification
- **Fractional Trading** — Buy as little as 0.001 tCO₂e
- **Zero Gas Fees** — Trade and retire credits for free
- **Retirement Certificates** — On-chain NFT proof of carbon offset

**Documentation**: [docs/CARBON-CREDIT.md](docs/CARBON-CREDIT.md) | **Whitepaper**: [tpix.online/carbon-credits/whitepaper](https://tpix.online/carbon-credits/whitepaper)

---

## Smart Contracts

| Contract | Description |
|----------|-------------|
| `TPIXIdentity` | **Living Identity** — on-chain wallet recovery without seed phrase |
| `TPIXDEXFactory` | Creates and manages trading pair contracts |
| `TPIXDEXRouter02` | Handles multi-hop swaps and liquidity operations |
| `TPIXDEXPair` | Individual liquidity pool with ERC-20 LP tokens |
| `WTPIX` | Wrapped TPIX for ERC-20 compatibility |
| `TPIXTokenSale` | Public sale contract with vesting schedule |
| `NodeRegistry` | Validator node registration and management |
| `StakingPool` | TPIX staking for node operators |
| `RewardDistributor` | Block reward distribution to validators |
| `TPIXTokenFactory` | V1 ERC-20 token factory (standard/mintable/burnable) |
| `TPIXTokenFactoryV2` | V2 coordinator for all ERC-20 types — [`0xCdE5…dfF2`](https://explorer.tpix.online/address/0xCdE5792A556A2D8571Efb31843CF6C15c3BDdfF2) |
| `TPIXNFTFactory` | NFT coordinator (single + collection) — [`0x3871…76F9`](https://explorer.tpix.online/address/0x38713C76036eb4Ff438eF8CEC12b6D676ad776F9) |
| `ERC20V2Creator` | Sub-factory: deploys enhanced ERC-20 tokens |
| `UtilityTokenCreator` | Sub-factory: deploys utility tokens (tax, anti-whale) |
| `RewardTokenCreator` | Sub-factory: deploys reward tokens (reflection, vesting) |
| `GovernanceTokenCreator` | Sub-factory: deploys governance tokens (ERC20Votes) |
| `StablecoinTokenCreator` | Sub-factory: deploys stablecoins (freeze, KYC) |
| `FactoryERC721Creator` | Sub-factory: deploys single NFTs (royalty, soulbound) |
| `NFTCollectionCreator` | Sub-factory: deploys NFT collections (mint, reveal) |
| `FactoryERC20V2` | Enhanced ERC-20 with pausable, blacklist, mint cap, auto-burn |
| `UtilityToken` | ERC-20 with tax system, anti-whale, anti-bot |
| `RewardToken` | ERC-20 with reflection/dividend, vesting |
| `GovernanceToken` | ERC-20 with ERC20Votes, delegation, permit |
| `StablecoinToken` | ERC-20 with freeze, KYC allowlist, authority mint/burn |
| `FactoryERC721` | Single NFT with ERC-2981 royalty, soulbound (SBT) |
| `NFTCollection` | NFT collection with mint config, delayed reveal, royalty |

### Living Identity (TPIXIdentity.sol)

A novel wallet recovery system that eliminates the need for seed phrases — **no other blockchain wallet has this**.

**How it works:**
1. User sets 3-5 security questions, registers up to 3 GPS locations, and creates a 6-8 digit recovery PIN
2. Each factor is stored as a one-way hash — **never plaintext**
3. User loses device or forgets seed phrase
4. User answers security questions (60%+) + stands at registered GPS location (±200m) — or uses recovery PIN as backup
5. Smart contract starts **48-hour time-lock** recovery
6. Original owner can cancel within 48 hours (theft protection)
7. After 48 hours, wallet control transfers to new address

**GPS Privacy:** Coordinates are rounded to ~111m grid then SHA-256 hashed. Only the hash is stored — no one can see your actual location, not even with full database access. See [Whitepaper §10](docs/WHITEPAPER.md#10-living-identity-recovery) for the full privacy model.

**Deploy:**
```bash
cd contracts
npm install
export DEPLOYER_KEY=0x...your_private_key...
npm run deploy:identity
```

**Gas cost:** FREE (TPIX Chain has zero gas fees)

### Token Factory V2 (Coordinator + Creator Architecture)

The Token Factory uses a **Coordinator + Sub-Factory Creator** pattern to stay within EVM's 24KB contract size limit (EIP-170). Each token type has its own Creator contract that embeds the token bytecode, while the Coordinator provides a unified entry point with registry and nonce management.

```
TPIXTokenFactoryV2 (coordinator)
├── ERC20V2Creator       → FactoryERC20V2
├── UtilityTokenCreator  → UtilityToken
├── RewardTokenCreator   → RewardToken
├── GovernanceTokenCreator → GovernanceToken
└── StablecoinTokenCreator → StablecoinToken

TPIXNFTFactory (coordinator)
├── FactoryERC721Creator → FactoryERC721
└── NFTCollectionCreator → NFTCollection
```

**Deployed via GitHub Actions** — compile on runner, SCP artifacts to server, deploy with validator key. See `.github/workflows/deploy-factory-v2.yml`.

---

## Ecosystem & Use Cases

| Application | Description |
|-------------|-------------|
| **Decentralized Exchange** | AMM-based DEX with zero gas trading |
| **FoodPassport** | Blockchain food traceability (farm-to-table) |
| **IoT Smart Farm** | AI + IoT sensors for precision agriculture |
| **Delivery Platform** | Multi-service delivery with TPIX cashback |
| **AI Bot Marketplace** | Buy/sell AI bots for trading & customer service |
| **Hotel Booking** | Decentralized travel booking with TPIX payment |
| **E-Commerce** | Multi-vendor marketplace with 5% cashback |
| **Token Factory** | Create custom ERC-20/ERC-721 tokens (10 types, 16 sub-options) |
| **Carbon Credit** | On-chain carbon credit trading with IoT verification |
| **Thaiprompt Affiliate** | Enterprise MLM platform (500,000+ users) |

---

## Tokenomics

| Allocation | Amount | Percentage |
|-----------|--------|------------|
| **Master Node Rewards** | 1,400,000,000 TPIX | 20.0% |
| **Ecosystem Development** | 1,750,000,000 TPIX | 25.0% |
| **Team & Advisors** | 700,000,000 TPIX | 10.0% |
| **Token Sale** | 700,000,000 TPIX | 10.0% |
| **Liquidity & Market Making** | 1,050,000,000 TPIX | 15.0% |
| **Community & Rewards** | 1,400,000,000 TPIX | 20.0% |
| **Total** | **7,000,000,000 TPIX** | **100%** |

### Token Sale Phases

| Phase | Price | Allocation | TGE Unlock | Vesting |
|-------|-------|-----------|------------|---------|
| Private Sale | $0.05 | 100M TPIX | 10% | 30d cliff, 180d linear |
| Pre-Sale | $0.08 | 200M TPIX | 15% | 14d cliff, 120d linear |
| Public Sale | $0.10 | 400M TPIX | 25% | No cliff, 90d linear |

---

## Master Node Tiers & Rewards

| Tier | Stake Required | APY | Lock Period | Max Nodes | Role |
|------|---------------|-----|-------------|-----------|------|
| **Validator** | 10,000,000 TPIX | 15-20% | 180 days | 21 | IBFT2 block sealer + governance |
| **Guardian** | 1,000,000 TPIX | 10-12% | 90 days | 100 | Premium masternode |
| **Sentinel** | 100,000 TPIX | 7-9% | 30 days | 500 | Standard masternode |
| **Light** | 10,000 TPIX | 4-6% | 7 days | Unlimited | Light node |

**Reward Distribution**: 20% Validator (IBFT2 sealers), 35% Guardian, 30% Sentinel, 15% Light.
**Total Reward Pool**: 1.4 Billion TPIX over 3 years (ending 2028) with decreasing annual emission.
**Validator Governance**: Validators form the chain's "board of directors" — vote on protocol changes, new admissions, and contract upgrades. Requires 10M TPIX + company KYC (PDPA-compliant).

### Annual Emission Schedule

| Year | Period | Emission | Per Block | Share |
|------|--------|---------|-----------|-------|
| Year 1 | 2025-2026 | 600,000,000 TPIX | ~38.3 TPIX | 42.9% |
| Year 2 | 2026-2027 | 500,000,000 TPIX | ~31.9 TPIX | 35.7% |
| Year 3 | 2027-2028 | 300,000,000 TPIX | ~19.1 TPIX | 21.4% |

---

## Network Configuration

### Option A — 1-Click Auto-Add (Recommended)

Visit **[tpix.online](https://tpix.online)** and connect your wallet. TPIX Chain is added automatically with icon (on supported wallets) via EIP-3085. No manual setup required.

### Option B — Manual Add to Any EVM Wallet

| Field | Value |
|-------|-------|
| **Network Name** | `TPIX Chain` |
| **RPC URL** | `https://rpc.tpix.online` |
| **Chain ID** | `4289` |
| **Currency Symbol** | `TPIX` |
| **Decimals** | `18` |
| **Block Explorer** | `https://explorer.tpix.online` |
| **Icon URL** (if wallet asks) | `https://tpix.online/images/tpix-logo-512.png` |

### Developer Quick-Connect

Ethers.js v6:
```js
const provider = new ethers.JsonRpcProvider('https://rpc.tpix.online', {
  chainId: 4289,
  name: 'TPIX Chain',
});
```

Viem:
```js
import { defineChain } from 'viem';
export const tpixChain = defineChain({
  id: 4289,
  name: 'TPIX Chain',
  nativeCurrency: { name: 'TPIX', symbol: 'TPIX', decimals: 18 },
  rpcUrls: { default: { http: ['https://rpc.tpix.online'] } },
  blockExplorers: { default: { name: 'TPIX Explorer', url: 'https://explorer.tpix.online' } },
});
```

Hardhat (`hardhat.config.js`):
```js
networks: {
  tpix: {
    url: 'https://rpc.tpix.online',
    chainId: 4289,
    accounts: [process.env.DEPLOYER_KEY],
  },
}
```

---

## Brand Assets

All logo assets are open for use by integrators, exchanges, and listing services. **Please do not modify the logo.** Use the 512×512 PNG for wallet/app integrations and the SVG (when published) for scalable UI.

| Asset | Size | URL | Purpose |
|-------|------|-----|---------|
| **Primary PNG** | 512×512, transparent | [`tpix.online/images/tpix-logo-512.png`](https://tpix.online/images/tpix-logo-512.png) | Wallet integration, chainlist icon |
| **IPFS CID** | 512×512, transparent | `ipfs://bafybeiby5mwnwdi53fye4iurjxlddfzonsj67ejl4sjy7qda53za6jlgo4` | Content-addressed (for ethereum-lists) |
| **Legacy WebP** | variable | [`tpix.online/tpixlogo.webp`](https://tpix.online/tpixlogo.webp) | Web UI, legacy links |

For exchange listings (CoinGecko, CoinMarketCap, CEX partners), please use the **Primary PNG** — the content hash matches what is registered in `ethereum-lists/chains`.

---

## Roadmap

| Phase | Period | Status | Milestones |
|-------|--------|--------|------------|
| **Foundation** | Q1-Q2 2023 | Done | Whitepaper, architecture, team formation |
| **Blockchain** | Q3-Q4 2023 | Done | Polygon Edge, TPIX coin, IBFT consensus, testnet |
| **Integration** | Q1-Q2 2024 | Done | Laravel services, REST API, block explorer |
| **Ecosystem** | Q3-Q4 2024 | Done | DEX, master node network, SDK development |
| **Real-World** | Q1-Q2 2025 | Done | FoodPassport, delivery, IoT, AI bots |
| **Scale** | Q3-Q4 2025 | Done | Cross-chain bridge, mobile wallet app, multi-wallet |
| **Identity** | Q1 2026 | Done | Living Identity recovery, GPS verification, on-chain identity contract |
| **Enterprise** | Q2 2026 | In Progress | Enterprise toolkit, government compliance |
| **Global** | Q3-Q4 2026 | Planned | ASEAN expansion, 100+ dApps, multi-language |

---

## Development

### Prerequisites

- **Wallet**: Flutter 3.38+, Dart 3.x, Android SDK 34+
- **Master Node UI**: Node.js 20+, Electron
- **Contracts**: Node.js 20+, Hardhat (Solidity 0.8.20 + 0.8.24), OpenZeppelin 5.x

### Build Wallet APK

```bash
cd wallet
flutter pub get
flutter build apk --release
```

### Build Master Node (Windows)

```bash
cd masternode-ui
npm install
npm run build
```

### Deploy Smart Contracts

```bash
cd contracts
npm install

# Deploy Living Identity contract to TPIX Chain
export DEPLOYER_KEY=0x...your_private_key...
npm run deploy:identity

# Verify deployment
export IDENTITY_CONTRACT=0x...deployed_address...
npm run verify
```

---

## Links

### Product & Ecosystem
| Resource | URL |
|----------|-----|
| **TPIX TRADE (DEX)** | [tpix.online](https://tpix.online) |
| **Block Explorer** | [explorer.tpix.online](https://explorer.tpix.online) |
| **JSON-RPC Endpoint** | `https://rpc.tpix.online` |
| **Whitepaper** | [tpix.online/whitepaper](https://tpix.online/whitepaper) |
| **Carbon Credits** | [tpix.online/carbon-credits](https://tpix.online/carbon-credits) |
| **Token Sale** | [tpix.online/token-sale](https://tpix.online/token-sale) |
| **Master Node Guide** | [tpix.online/masternode/guide](https://tpix.online/masternode/guide) |
| **Download Apps** | [tpix.online/download](https://tpix.online/download) |

### Documentation
| Resource | URL |
|----------|-----|
| **Whitepaper (MD)** | [docs/WHITEPAPER.md](docs/WHITEPAPER.md) |
| **Carbon Credit Docs** | [docs/CARBON-CREDIT.md](docs/CARBON-CREDIT.md) |
| **Explorer Setup** | [docs/EXPLORER.md](docs/EXPLORER.md) |

### Registry & Listings
| Resource | URL |
|----------|-----|
| **ethereum-lists/chains PR** | [pull/8231](https://github.com/ethereum-lists/chains/pull/8231) |
| **Chain ID Registry** | [chainid.network/chain/4289](https://chainid.network/chain/4289) (post-merge) |
| **Chainlist** | [chainlist.org/chain/4289](https://chainlist.org/chain/4289) (post-merge) |
| **IPFS Logo (CID)** | `bafybeiby5mwnwdi53fye4iurjxlddfzonsj67ejl4sjy7qda53za6jlgo4` |

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

<p align="center">
  Developed by <strong>Xman Studio</strong><br/>
  <a href="https://xmanstudio.com">xmanstudio.com</a>
</p>
