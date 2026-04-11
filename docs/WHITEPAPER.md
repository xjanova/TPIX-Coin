# TPIX Chain Whitepaper v2.0

> **A Next-Generation EVM Blockchain for the ASEAN Digital Economy**
> Developed by Xman Studio | [tpix.online](https://tpix.online)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Vision & Mission](#2-vision--mission)
3. [Technical Architecture](#3-technical-architecture)
4. [Consensus Mechanism](#4-consensus-mechanism)
5. [Native Coin — TPIX](#5-native-coin--tpix)
6. [Tokenomics](#6-tokenomics)
7. [Master Node System](#7-master-node-system)
8. [Decentralized Exchange (DEX)](#8-decentralized-exchange-dex)
9. [Token Factory](#9-token-factory)
10. [Living Identity Recovery](#10-living-identity-recovery)
11. [Cross-Chain Bridge](#11-cross-chain-bridge)
12. [Ecosystem & Use Cases](#12-ecosystem--use-cases)
13. [Carbon Credit System](#13-carbon-credit-system)
14. [FoodPassport — Farm-to-Table Traceability](#14-foodpassport--farm-to-table-traceability)
15. [Security Architecture](#15-security-architecture)
16. [Roadmap](#16-roadmap)
17. [Team & Governance](#17-team--governance)
18. [Legal & Compliance](#18-legal--compliance)

---

## 1. Executive Summary

TPIX Chain is a high-performance EVM-compatible blockchain built on **Polygon Edge** technology, designed specifically for the Thai and Southeast Asian digital economy. With gasless transactions, 2-second block times, and IBFT Proof-of-Authority consensus, TPIX Chain provides an unmatched platform for decentralized applications, DeFi, and real-world asset tokenization.

**Key Differentiators:**

- **Zero Gas Fees** — All transactions are free, removing barriers for mainstream adoption
- **2-Second Blocks** — Near-instant finality (~10 seconds / 5 blocks)
- **~1,500 TPS** — Enterprise-grade throughput
- **Living Identity** — World's first seedless wallet recovery via security questions + GPS
- **Full EVM Compatibility** — Deploy any Solidity smart contract without modification
- **Real-World Integration** — Connected to 500,000+ enterprise users via Thaiprompt platform

---

## 2. Vision & Mission

### Vision
To become the leading blockchain infrastructure for Southeast Asia's digital economy, enabling frictionless value transfer, transparent supply chains, and inclusive financial services for all.

### Mission
- Eliminate gas fee barriers that prevent mainstream blockchain adoption
- Provide enterprise-grade infrastructure for Thai and ASEAN businesses
- Bridge traditional commerce with decentralized technology
- Create real-world utility through FoodPassport, Carbon Credits, and IoT integration

### Problem Statement

| Problem | TPIX Solution |
|---------|---------------|
| High gas fees on Ethereum/BSC | Zero gas fees (hardcoded in genesis) |
| Slow confirmation times | 2-second blocks, ~10s finality |
| Complex wallet recovery | Living Identity — no seed phrase needed |
| Limited real-world utility | FoodPassport, Carbon Credits, IoT integration |
| Language barriers | Full Thai + English support across all products |

---

## 3. Technical Architecture

### Chain Specifications

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
| **VM** | EVM (Full Solidity & ERC-20/721/1155 support) |
| **Native Coin** | TPIX (18 decimals) |
| **Total Supply** | 7,000,000,000 TPIX (pre-mined in genesis) |
| **Validators** | 4 IBFT nodes (BFT tolerates 1 faulty) |

### Network Endpoints

| Service | URL |
|---------|-----|
| **JSON-RPC** | `https://rpc.tpix.online` |
| **WebSocket** | `wss://rpc.tpix.online` |
| **Block Explorer** | `https://explorer.tpix.online` |
| **DEX** | `https://tpix.online` |

### Technology Stack

```
┌──────────────────────────────────┐
│        User Applications         │
│  (Wallet, DEX, FoodPassport)     │
├──────────────────────────────────┤
│         JSON-RPC / WSS           │
├──────────────────────────────────┤
│     Polygon Edge (Go Client)     │
│  ┌────────┐ ┌────────┐          │
│  │ IBFT   │ │  EVM   │          │
│  │ 2.0    │ │ Engine │          │
│  └────────┘ └────────┘          │
├──────────────────────────────────┤
│      LevelDB + libp2p           │
├──────────────────────────────────┤
│     4 Validator Nodes (Docker)   │
└──────────────────────────────────┘
```

### Infrastructure

The chain runs on a 4-node IBFT cluster deployed via Docker Compose:

- **Validator 1** (Boot node) — Port 8545 (JSON-RPC), 10000 (gRPC), 10001 (libp2p)
- **Validator 2** — Port 8546
- **Validator 3** — Port 8547
- **Validator 4** — Port 8548

Block Explorer is powered by **Blockscout** with PostgreSQL backend and smart contract verification service.

---

## 4. Consensus Mechanism

### IBFT 2.0 (Istanbul Byzantine Fault Tolerant)

TPIX Chain uses IBFT 2.0 Proof-of-Authority consensus, providing:

- **Immediate finality** — No chain reorganizations possible
- **Byzantine fault tolerance** — Tolerates up to ⌊(n-1)/3⌋ faulty validators (1 of 4)
- **Deterministic block production** — Round-robin proposer selection
- **Energy efficient** — No mining or staking required for consensus

### Block Production Flow

```
1. Proposer selected (round-robin among 4 validators)
2. Proposer creates block with pending transactions
3. Block broadcast to all validators via libp2p
4. Validators verify and send PREPARE message
5. Upon 2/3+ PREPARE: validators send COMMIT
6. Upon 2/3+ COMMIT: block is finalized (irreversible)
7. Next round begins (2 seconds later)
```

### Validator Requirements

| Specification | Minimum |
|--------------|---------|
| CPU | 8 cores |
| RAM | 16 GB |
| Storage | 500 GB SSD |
| Network | 100 Mbps |
| OS | Ubuntu 22.04 / Windows Server 2022 |

---

## 5. Native Coin — TPIX

TPIX is the native cryptocurrency of TPIX Chain with a fixed supply of **7 billion tokens**.

### Coin Properties

| Property | Value |
|----------|-------|
| Name | TPIX |
| Decimals | 18 |
| Total Supply | 7,000,000,000 |
| Type | Pre-mined (genesis block) |
| Gas Cost | 0 (all transactions free) |
| Standard | Native coin (like ETH on Ethereum) |

### Utility

1. **DEX Trading** — Base pair for all trading on TPIX TRADE
2. **Master Node Staking** — Required collateral for running validator nodes
3. **Token Factory** — Fee payment for creating custom tokens (50-150+ TPIX, dynamic pricing)
4. **Carbon Credits** — Purchase and trade verified carbon credits
5. **FoodPassport** — Pay for food traceability verification services
6. **Governance** — Future DAO voting rights
7. **Cross-Chain Bridge** — Lock TPIX to mint wrapped tokens on BSC

---

## 6. Tokenomics

### Distribution

| Allocation | Amount | Percentage | Wallet Address | BIP-44 Path |
|-----------|--------|------------|----------------|-------------|
| **Master Node Rewards** | 1,400,000,000 TPIX | 20.00% | `0x2112b98e3ec5A252b7b2A8f02d498B64a2186A7f` | m/44'/60'/0'/0/1 |
| **Ecosystem Development** | 1,710,000,000 TPIX | 24.43% | `0xD2eAB07809921fcB36c7AB72D7B5D8D2C12A67d7` | m/44'/60'/0'/0/2 |
| **Team & Advisors** | 700,000,000 TPIX | 10.00% | `0xf46131C82819d7621163F482b3fe88a228A7807c` | m/44'/60'/0'/0/3 |
| **Token Sale** | 700,000,000 TPIX | 10.00% | `0x3F8EB4046F5C79fd0D67C7547B5830cB2Cfb401A` | m/44'/60'/0'/0/4 |
| **Liquidity & Market Making** | 1,050,000,000 TPIX | 15.00% | `0x3da3776e0AB0F442c181aa031f47FA83696859AF` | m/44'/60'/0'/0/5 |
| **Community & Rewards** | 1,400,000,000 TPIX | 20.00% | `0xA945d1bE9c1DDeaE75BBb9B39981D1CE6Ed7d9d5` | m/44'/60'/0'/0/6 |
| **Validator Stakes** (4x 10M) | 40,000,000 TPIX | 0.57% | 4 validator addresses (generated at genesis) | — |
| **Total** | **7,000,000,000 TPIX** | **100%** | | |

> **Note:** Ecosystem Development was originally allocated 1,750,000,000 TPIX (25%). 40,000,000 TPIX was allocated to fund 4 genesis Validator nodes (10M TPIX each, Validator tier — the highest staking tier). All allocation wallets are derived from a single BIP-44 HD wallet for unified treasury management. The main reward receiver wallet is at path m/44'/60'/0'/0/0 (`0x0B263D083969946fA2bB44Af2debA69D3d3d0220`).

### Token Sale Phases

| Phase | Price (USD) | Allocation | TGE Unlock | Vesting |
|-------|-------------|-----------|------------|---------|
| Private Sale | $0.05 | 100M TPIX | 10% | 30-day cliff, 180-day linear |
| Pre-Sale | $0.08 | 200M TPIX | 15% | 14-day cliff, 120-day linear |
| Public Sale | $0.10 | 400M TPIX | 25% | No cliff, 90-day linear |

### Deflationary Mechanisms

- **Token Factory Burn** — 50% of token creation fees burned permanently
- **DEX Protocol Fee** — 0.05% of swap volume allocated to buyback-and-burn
- **Bridge Fee Burn** — 10% of bridge fees burned

---

## 7. Master Node System

### Four-Tier Architecture

| Tier | Stake Required | APY | Lock Period | Max Nodes | Hardware | Role |
|------|---------------|-----|-------------|-----------|----------|------|
| **Validator** | 10,000,000 TPIX | 15-20% | 180 days | 21 | 16 CPU, 32GB RAM, 1TB SSD | IBFT2 block sealer + governance |
| **Guardian** | 1,000,000 TPIX | 10-12% | 90 days | 100 | 8 CPU, 16GB RAM, 500GB SSD | Premium masternode |
| **Sentinel** | 100,000 TPIX | 7-9% | 30 days | 500 | 4 CPU, 8GB RAM, 200GB SSD | Standard masternode |
| **Light** | 10,000 TPIX | 4-6% | 7 days | Unlimited | 2 CPU, 4GB RAM, 100GB SSD | Light node |

#### Validator Tier — Chain Governance ("Board of Directors")

Validators are the real IBFT2 block sealers who produce and validate blocks on TPIX Chain. They form the governance council with the power to vote on protocol changes, new validator admissions, parameter adjustments, and contract upgrades.

**Requirements:**
- 10,000,000 TPIX stake (180-day lock)
- Company-only applicants (registered business entity)
- KYC/PDPA-compliant verification: company registration, authorized person passport/ID, server specs, dedicated server proof
- Admin review + existing validator vote via IBFT2 consensus
- Maximum 21 validators (BFT tolerates ⌊(n-1)/3⌋ faulty)

**Governance Powers:**
- Propose and vote on protocol parameter changes
- Vote to admit or remove validators
- Propose smart contract upgrades
- 7-day voting period, >50% quorum, 48-hour timelock

### Reward Distribution

- **20%** — Validator nodes (IBFT2 block sealers + governance)
- **35%** — Guardian nodes (premium masternodes)
- **30%** — Sentinel nodes (standard masternodes)
- **15%** — Light nodes (data relays)

**Total Reward Pool:** 1.4 Billion TPIX over 3 years (ending 2028) with decreasing annual emission.

### Annual Emission Schedule

| Year | Period | Emission | Per Block (~) | Share |
|------|--------|---------|---------------|-------|
| Year 1 | 2025-2026 | 600,000,000 TPIX | 38.3 TPIX | 42.9% |
| Year 2 | 2026-2027 | 500,000,000 TPIX | 31.9 TPIX | 35.7% |
| Year 3 | 2027-2028 | 300,000,000 TPIX | 19.1 TPIX | 21.4% |

### KYC & PDPA Compliance (Validator Tier)

Validator KYC follows Thai Personal Data Protection Act (PDPA):
- **On-chain**: Only `keccak256(kycData)` hash stored — no PII on blockchain
- **Off-chain**: Encrypted KYC documents in admin system with access logging
- **Explicit consent**: Applicant must give PDPA consent before submission
- **Purpose limitation**: KYC data used only for validator admission review
- **Right to erasure**: Applicant can revoke consent; admin erases off-chain data

### Master Node Software

- **TPIX Wallet (Android/iOS)** — Mobile wallet with HD wallet, Living Identity recovery, QR scanner
- **Master Node UI (Windows)** — Electron desktop app with one-click node setup, multi-node management, real-time dashboard

---

## 8. Decentralized Exchange (DEX)

### TPIX TRADE — [tpix.online](https://tpix.online)

A full-featured DEX built on Uniswap V2 AMM protocol, optimized for TPIX Chain's gasless environment.

### Core Features

| Feature | Description |
|---------|-------------|
| **Spot Trading** | Real-time candlestick charts with TradingView integration |
| **Token Swap** | Instant token exchange with 0.3% fee |
| **Liquidity Pools** | Provide liquidity and earn LP token rewards |
| **Order Book** | Hybrid AMM + limit orders |
| **Multi-Chain** | Support for TPIX Chain, BSC, Ethereum, Polygon |
| **Portfolio** | Track all holdings across chains |

### Fee Structure

| Fee Type | Rate | Distribution |
|----------|------|-------------|
| Swap Fee | 0.3% | 0.25% to LPs, 0.05% to protocol |
| Trading Fee | 0.1% maker / 0.2% taker | Revenue pool |
| Bridge Fee | 0.1% | 90% to treasury, 10% burned |

### Smart Contracts

| Contract | Description |
|----------|-------------|
| `TPIXDEXFactory` | Creates and manages trading pair contracts |
| `TPIXDEXRouter02` | Handles multi-hop swaps and liquidity operations |
| `TPIXDEXPair` | Individual liquidity pool with ERC-20 LP tokens |
| `WTPIX` | Wrapped TPIX for ERC-20 compatibility |

---

## 9. Token Factory

Create custom tokens on TPIX Chain with zero gas fees. Full-featured 5-step wizard supporting ERC-20 and ERC-721 tokens with advanced DeFi features.

**Platform:** [tpix.online/token-factory](https://tpix.online/token-factory)

### Token Categories

| Category | Types | Description |
|----------|-------|-------------|
| **Fungible (ERC-20)** | Standard, Mintable, Burnable, Mintable+Burnable | Basic ERC-20 tokens with optional mint/burn |
| **Fungible Advanced** | Utility, Reward | DeFi tokens with tax, anti-whale, reflection, vesting |
| **NFT (ERC-721)** | Single NFT, NFT Collection | Non-fungible tokens with royalty, soulbound, delayed reveal |
| **Special** | Governance, Stablecoin | Governance voting tokens and compliance-ready stablecoins |

### ERC-20 Token Types

| Type | Features | Base Fee |
|------|----------|----------|
| **Standard** | Fixed supply, transferable | 50 TPIX |
| **Mintable** | Owner can mint additional tokens | 70 TPIX |
| **Burnable** | Holders can burn their tokens | 70 TPIX |
| **Mintable + Burnable** | Both mint and burn capabilities | 85 TPIX |
| **Utility** | Tax system, anti-whale, anti-bot, auto-liquidity | 60 TPIX |
| **Reward** | Reflection/dividend/staking, vesting schedule | 60 TPIX |
| **Governance** | ERC20Votes, delegation, proposal/quorum parameters | 130 TPIX |
| **Stablecoin** | Freeze, KYC allowlist, authority mint/burn | 150 TPIX |

### NFT Token Types

| Type | Features | Base Fee |
|------|----------|----------|
| **Single NFT** | ERC-721, royalty (ERC-2981), soulbound (SBT) | 80 TPIX |
| **NFT Collection** | Public/whitelist/free mint, delayed reveal, royalty | 100 TPIX |

### Advanced Sub-Options

Every token type supports additional features (each with an add-on fee):

| Option | Description | Fee |
|--------|-------------|-----|
| **Pausable** | Owner can pause/unpause all transfers | +5 TPIX |
| **Blacklist** | Owner can blacklist addresses | +5 TPIX |
| **Tax System** | Buy/sell/transfer tax with configurable wallets | +15 TPIX |
| **Anti-Whale** | Max wallet % and max transaction % limits | +10 TPIX |
| **Anti-Bot** | Launch protection period + cooldown between trades | +10 TPIX |
| **Auto-Liquidity** | Auto-add portion of tax to LP pool | +15 TPIX |
| **Reflection** | Auto-distribute rewards to all holders proportionally | +20 TPIX |
| **Vesting** | Cliff + linear release schedule for token locks | +10 TPIX |
| **Royalty (ERC-2981)** | NFT royalty standard for secondary sales | +5 TPIX |
| **Soulbound (SBT)** | Non-transferable token | +5 TPIX |
| **Delayed Reveal** | Placeholder metadata until owner reveals | +10 TPIX |
| **Treasury** | Governance treasury contract | +15 TPIX |
| **Delegation** | Vote delegation support (ERC20Votes) | +5 TPIX |
| **Freeze** | Owner can freeze specific addresses (compliance) | +5 TPIX |
| **KYC Required** | Only KYC-verified addresses can transfer | +5 TPIX |
| **Auto-Burn** | Automatic burn on each transfer | +10 TPIX |

### Smart Contracts

| Contract | Description |
|----------|-------------|
| **TPIXTokenFactory** | V1 factory for basic ERC-20 (standard/mintable/burnable) |
| **TPIXTokenFactoryV2** | V2 factory for all ERC-20 types (utility, reward, governance, stablecoin) |
| **TPIXNFTFactory** | Factory for NFT tokens (single + collection) |
| **FactoryERC20V2** | Enhanced ERC-20 with pausable, blacklist, mint cap, auto-burn |
| **UtilityToken** | ERC-20 with tax system, anti-whale, anti-bot |
| **RewardToken** | ERC-20 with reflection/dividend, vesting |
| **GovernanceToken** | ERC-20 with ERC20Votes, delegation, permit |
| **StablecoinToken** | ERC-20 with freeze, KYC, authority mint/burn |
| **FactoryERC721** | Single NFT with royalty (ERC-2981), soulbound |
| **NFTCollection** | NFT collection with mint config, delayed reveal, royalty |

All contracts use CREATE2 for deterministic addresses, OpenZeppelin 5.x, and are auto-verified on Blockscout.

### Creation Flow

```
1. User connects wallet on tpix.online/token-factory
2. Step 1 — Select category: Fungible / NFT / Special
3. Step 2 — Select token type (e.g., Utility, Governance, NFT Collection)
4. Step 3 — Configure advanced sub-options (tax, anti-whale, royalty, etc.)
5. Step 4 — Fill token details (name, symbol, supply, logo, description)
6. Step 5 — Review all settings + fee breakdown → confirm and pay
7. Backend validates, calculates fee, and queues deployment
8. Factory contract deploys token via CREATE2 (gas-free on TPIX Chain)
9. Token auto-verified on Blockscout Explorer
10. Token immediately tradeable on TPIX TRADE DEX
```

**Testnet:** Free token creation on TPIX Testnet (Chain ID: 4290), Sepolia, and BSC Testnet.

### Dynamic Fee Calculation

```
Total Fee = Base Fee + Category Fee + Type Fee + Sub-Option Fees

Example: Utility Token with Tax + Anti-Whale + Pausable
  Base Fee:       50 TPIX
  Category Fee:    0 TPIX (fungible)
  Type Fee:       10 TPIX (utility)
  Tax System:    +15 TPIX
  Anti-Whale:    +10 TPIX
  Pausable:       +5 TPIX
  ─────────────────────
  Total:          90 TPIX
```

### Use Cases

- **Business Loyalty Points** — Retail chains, restaurants, hotels
- **Community Tokens** — DAOs, social clubs, fan tokens
- **Real-World Assets (RWA)** — Property tokens, commodity tokens
- **Carbon Credits** — Tokenized verified emission reductions
- **DeFi Tokens** — Utility tokens with built-in tax and anti-whale protection
- **Governance DAOs** — Create governance tokens with voting and delegation
- **Stablecoins** — Compliance-ready stablecoins pegged to THB/USD/EUR
- **Digital Art & Collectibles** — NFT collections with royalty and delayed reveal
- **Membership / Certificates** — Soulbound tokens (SBT) for non-transferable credentials

---

## 10. Living Identity Recovery

**World's first seedless wallet recovery system** — no other blockchain wallet has this.

### How It Works

```
Registration:
1. User sets 3-5 security questions + answers
2. User registers up to 3 GPS locations (home, work, etc.)
3. User creates 6-8 digit recovery PIN (backup when GPS unavailable)
4. Each layer stored independently as one-way hashes — never plaintext

Recovery:
1. User answers security questions (60%+ correct required)
2. User stands at registered GPS location (±200m tolerance)
   — OR enters recovery PIN if GPS is unavailable
3. Smart contract initiates 48-hour time-lock (future)
4. Original owner can cancel within 48 hours (theft protection)
5. After 48 hours, wallet control transfers to new address
```

### GPS Privacy Model

GPS is the most sensitive data in Living Identity. Here's how we protect it:

```
Your GPS coordinates are NEVER stored — not even encrypted.

Step 1: Round to ~111m grid    13.7563, 100.5018 → 13.756, 100.502
Step 2: Create hash input      "tpix-loc:13.756:100.502"
Step 3: SHA-256 hash           → "a3f8c2e9b7d1..."
Step 4: Store ONLY the hash    ← This is all that exists in the database

What's stored:  "a3f8c2e9b7d1..." (meaningless without the original coordinates)
What's NOT:     Any latitude, longitude, address, city, or country
```

**Verification** checks 9 grid cells (exact + 8 neighbors), giving ±200m tolerance. You don't need to stand on the exact spot.

**Why it's safe:**
- The hash is **one-way** — you cannot reverse SHA-256 to get coordinates
- The grid rounding means even you don't know the exact stored precision
- An attacker would need to brute-force all grid cells on Earth (~500 billion combinations) while also matching the correct wallet
- Combined with security questions + rate limiting = practically unbreakable

**Compared to seed phrases:**
| | Seed Phrase | Living Identity |
|--|------------|-----------------|
| **Remember** | 12-24 words exactly | Nothing — just be you |
| **Stolen paper** | Total loss | Attacker needs 3 factors simultaneously |
| **Lost/forgot** | Gone forever | Answer questions + go to your location |
| **Privacy** | No personal data | GPS hashed, never stored raw |

### Security Features

| Feature | Description |
|---------|-------------|
| **Hash-only storage** | No personal data stored — only SHA-256/PBKDF2 hashes |
| **GPS grid + hash** | Coordinates rounded to ~111m then hashed. Cannot be reversed |
| **9-cell verification** | Checks ±200m around your position for tolerance |
| **Recovery PIN** | 6-8 digit backup when GPS is unavailable (PBKDF2 100K rounds) |
| **Rate limiting** | 5 attempts per 5-minute lockout window |
| **48-hour time-lock** | Original owner can cancel unauthorized recovery (future) |
| **Self-test mode** | Test your recovery setup without triggering rate limits |

### Smart Contract: TPIXIdentity.sol

```solidity
// Deployed on TPIX Chain — Zero gas cost
function registerIdentity(bytes32 identityHash) external;
function initiateRecovery(bytes32 proof, address newWallet) external;
function cancelRecovery() external;  // Only original owner
function completeRecovery() external; // After 48-hour lock
```

---

## 11. Cross-Chain Bridge

### TPIX Chain ↔ BSC Bridge

Lock-and-mint bridge enabling TPIX tokens to move between TPIX Chain and Binance Smart Chain.

### Architecture

```
TPIX Chain                          BSC (Chain ID: 56)
┌──────────┐    Lock TPIX    ┌──────────────┐
│  Bridge   │ ──────────────→│ Mint wTPIX   │
│  Contract │                │ (BEP-20)     │
│           │←──────────────│              │
└──────────┘    Burn wTPIX   └──────────────┘
                 Unlock TPIX
```

### Bridge Security

- **Multi-sig validators** — 3-of-5 signature required
- **Time-lock** — 15-minute delay for large transfers (>1M TPIX)
- **Rate limiting** — Maximum 10M TPIX per 24 hours
- **Audit trail** — All bridge transactions logged on both chains

---

## 12. Ecosystem & Use Cases

| Application | Description | Status |
|-------------|-------------|--------|
| **TPIX TRADE DEX** | AMM-based DEX with zero gas trading | Live |
| **Token Factory** | Create custom ERC-20/ERC-721 tokens (10 types, 16+ sub-options) | Live |
| **FoodPassport** | Blockchain food traceability (farm-to-table) | Live |
| **Carbon Credit** | On-chain carbon credit trading with IoT verification | Live |
| **Master Node Network** | 3-tier validator system with staking rewards | Live |
| **Cross-Chain Bridge** | TPIX Chain ↔ BSC bridge | In Development |
| **IoT Smart Farm** | AI + IoT sensors for precision agriculture | Live |
| **Delivery Platform** | Multi-service delivery with TPIX cashback | Live |
| **AI Bot Marketplace** | Buy/sell AI bots for trading & customer service | Planned |
| **Hotel Booking** | Decentralized travel booking with TPIX payment | Planned |
| **E-Commerce** | Multi-vendor marketplace with 5% cashback | In Development |
| **Thaiprompt Affiliate** | Enterprise MLM platform (500,000+ users) | Live |

---

## 13. Carbon Credit System

### Overview

TPIX Chain's Carbon Credit system enables transparent trading of verified carbon credits using blockchain technology combined with IoT sensor verification.

### Supported Standards

| Standard | Full Name | Focus |
|----------|-----------|-------|
| **VCS** | Verified Carbon Standard | Global, largest voluntary market |
| **Gold Standard** | Gold Standard for the Global Goals | Premium, SDG co-benefits |
| **CDM** | Clean Development Mechanism | UN Framework, developing nations |
| **ACR** | American Carbon Registry | North America focus |

### How It Works

```
1. Project Registration — Solar farm, reforestation, etc.
2. IoT Verification — Sensors measure actual carbon reduction
3. Credit Issuance — Verified credits minted as tokens on TPIX Chain
4. Marketplace Trading — Buy/sell credits on tpix.online/carbon-credits
5. Retirement — Credits permanently burned when used for offsetting
6. Certificate — On-chain proof of retirement for compliance
```

### On-Chain Architecture

- **Hybrid Model** — Metadata stored off-chain (IPFS), ownership on-chain
- **NFT Certificates** — Each credit batch is an ERC-721 with verification data
- **Transparent Audit Trail** — All transfers and retirements recorded on blockchain
- **IoT Integration** — Real-time sensor data feeds into verification oracle

Full documentation: [docs/CARBON-CREDIT.md](CARBON-CREDIT.md) | [tpix.online/carbon-credits/whitepaper](https://tpix.online/carbon-credits/whitepaper)

---

## 14. FoodPassport — Farm-to-Table Traceability

### Overview

FoodPassport uses TPIX Chain + IoT sensors to track food from farm to consumer, ensuring safety, quality, and authenticity.

### Data Points Tracked

| Stage | Data | IoT Sensor |
|-------|------|-----------|
| **Farm** | Soil quality, pesticide use, harvest date | Soil moisture, pH sensor |
| **Processing** | Temperature, humidity, processing method | Thermometer, hygrometer |
| **Transport** | Cold chain temperature, GPS route | GPS tracker, temp logger |
| **Storage** | Warehouse conditions, duration | Environmental sensor |
| **Retail** | Shelf life, display temperature | Smart shelf sensor |

### Consumer Verification

```
1. Scan QR code on product packaging
2. View complete journey from farm to shelf
3. Verify IoT sensor readings at each stage
4. Check certification and safety standards
5. Rate and review the product
```

### Verify Online

Visit: `tpix.online/food-passport/verify/{productId}`

---

## 15. Security Architecture

### Smart Contract Security

| Measure | Implementation |
|---------|---------------|
| **Reentrancy Guard** | OpenZeppelin ReentrancyGuard on all value-transfer functions |
| **Access Control** | Role-based with Ownable2Step (two-step ownership transfer) |
| **Integer Safety** | Solidity 0.8.20 built-in overflow/underflow protection |
| **Signature Verification** | EIP-191 personal_sign with server-side ecrecover |
| **Nonce System** | One-time nonces with 5-minute expiry for replay prevention |

### Network Security

| Measure | Implementation |
|---------|---------------|
| **IBFT BFT** | Tolerates 1 faulty validator (25% fault tolerance) |
| **Rate Limiting** | API: 50 req/min, Bridge: 10M TPIX/24h |
| **HTTPS/WSS** | All endpoints encrypted with TLS 1.3 |
| **Wallet Verification** | Cryptographic signature required for write operations |

### Wallet Security

| Feature | Mobile Wallet | Master Node UI |
|---------|--------------|----------------|
| **Key Storage** | AES-256 encrypted keystore | AES-256 + SQLite |
| **PIN Protection** | 6-digit PIN with lockout | PIN + biometric |
| **Backup** | BIP-39 seed phrase + Living Identity | BIP-39 + Identity |
| **Auto-lock** | 5 minutes inactivity | Configurable |

---

## 16. Roadmap

### Phase 1 — Foundation & Infrastructure (2023–2026)

| Period | Status | Milestones |
|--------|--------|------------|
| Q1-Q2 2023 | Done | Whitepaper, architecture design, team formation |
| Q3-Q4 2023 | Done | Polygon Edge mainnet, TPIX coin, IBFT2 consensus, testnet |
| Q1-Q2 2024 | Done | Laravel services, REST API, block explorer |
| Q3-Q4 2024 | Done | DEX (AMM), master node network, SDK development |
| Q1-Q2 2025 | Done | FoodPassport, delivery platform, IoT smart farm, AI bot marketplace |
| Q3-Q4 2025 | Done | Cross-chain bridge (BSC), Flutter mobile wallet, multi-wallet HD (128 slots) |
| Q1 2026 | Done | Living Identity recovery (security questions + GPS hash + recovery PIN) |
| Q2 2026 | In Progress | Enterprise toolkit, government compliance, carbon credit trading |
| Q3-Q4 2026 | Planned | ASEAN expansion, 100+ dApps, multi-language support, DAO governance proposal |

### Phase 2 — AI-Governed Chain (2027)

The year AI becomes intelligent enough to govern a blockchain better than humans — permanently, 24/7, with zero downtime.

| Quarter | Milestone | Details |
|---------|-----------|---------|
| Q1 2027 | **AI Validator Agent** | Deploy AI agents that monitor chain health, detect anomalies, and recommend validator rotations. Initial "shadow mode" — AI suggests, humans approve |
| Q2 2027 | **Autonomous Slashing** | AI takes over slashing decisions: detecting malicious validators, double-signing, and prolonged downtime. Removes human bias from enforcement |
| Q3 2027 | **AI Parameter Tuning** | AI optimizes chain parameters in real-time: block size, gas limits, consensus timeouts, reward distribution — based on network telemetry |
| Q4 2027 | **Full AI Governance** | Complete handover from human validator committee to AI governance. AI manages consensus, validator selection, threat detection, and network scaling autonomously |

**Why AI governance?**
- **Zero downtime** — AI doesn't sleep, take vacations, or get distracted
- **No human bias** — Consistent enforcement of rules without politics or corruption
- **Predictive scaling** — AI trained on network telemetry anticipates load spikes before they happen
- **Faster response** — Millisecond threat detection vs. minutes/hours for human committees
- **Permanent operation** — Once deployed, AI governance runs indefinitely without management overhead

**Technical approach:**
- On-chain AI models trained on TPIX Chain telemetry data (block times, validator uptime, transaction patterns)
- Federated learning across masternode network — AI improves without exposing private node data
- Governance decisions recorded on-chain as transparent, auditable AI proposals
- Emergency circuit breaker: community multi-sig can pause AI governance if critical anomaly detected

### Phase 3 — Real-World Ecosystem Expansion (2028)

Bringing blockchain value beyond finance — into gaming, manufacturing, and food safety.

| Quarter | Milestone | Details |
|---------|-----------|---------|
| Q1 2028 | **Gaming Platform** | On-chain gaming platform built on TPIX Chain. TPIX token economy for in-game transactions, NFT-based game assets (weapons, characters, land), AI-driven game mechanics and NPCs. Play-to-earn model with verifiable fairness via smart contracts |
| Q2 2028 | **AI Product Manufacturing** | AI-designed and AI-manufactured consumer products launched to market. Full supply chain tracked on TPIX Chain — from raw materials to finished product to customer delivery. Each product gets an NFT certificate of origin and AI quality score |
| Q3 2028 | **Food Quality Control** | Blockchain-verified food quality control system: farm-to-table traceability powered by IoT sensors + AI inspection. Every step recorded on-chain — soil quality, pesticide levels, processing conditions, cold chain temperature, shelf life. Consumers scan QR code → see full journey with AI quality rating |
| Q4 2028 | **Ecosystem Integration** | Unified TPIX ecosystem: gaming rewards can buy AI-manufactured products, food quality scores influence marketplace rankings, all powered by single TPIX token economy |

**Gaming platform features:**
- Zero-gas gaming transactions (TPIX Chain advantage)
- AI-powered NPCs and dynamic game worlds
- Cross-game NFT asset interoperability
- Tournament system with TPIX prize pools
- Game developer SDK for building on TPIX Chain

**AI manufacturing pipeline:**
```
Design (AI) → Prototype (AI) → Quality Check (AI) → Manufacture →
Track on TPIX Chain → Ship → Customer scans NFT certificate
```

**Food quality control flow:**
```
Farm (IoT sensors) → Processing (AI inspection) → Transport (GPS + cold chain) →
Storage (environmental monitoring) → Retail (smart shelf) → Consumer (QR verify)
```
All data points recorded on TPIX Chain, scored by AI, accessible to consumers.

---

## 17. Team & Governance

### Development

TPIX Chain is developed by **Xman Studio** — a Thai technology studio specializing in blockchain, AI, and enterprise software.

### Governance Roadmap

| Phase | Governance Model |
|-------|-----------------|
| **2025-2026** | Centralized development by Xman Studio |
| **2026 Q3** | Community advisory board + DAO governance proposal |
| **2027 Q1-Q3** | AI governance in shadow mode (AI suggests, humans approve) |
| **2027 Q4** | Full AI governance — autonomous chain management |
| **2028+** | AI governance + community multi-sig emergency override |

---

## 18. Legal & Compliance

- TPIX Chain operates under Thai digital asset regulations
- Token sale conducted in compliance with SEC Thailand guidelines
- KYC/AML verification required for fiat on-ramp
- Carbon credit system follows VCS and Gold Standard verification protocols
- Smart contracts are open-source and auditable
- No financial advice — all trading involves risk

---

## Links

| Resource | URL |
|----------|-----|
| **TPIX TRADE (DEX)** | [tpix.online](https://tpix.online) |
| **Block Explorer** | [explorer.tpix.online](https://explorer.tpix.online) |
| **Interactive Whitepaper** | [tpix.online/whitepaper](https://tpix.online/whitepaper) |
| **Carbon Credit Docs** | [tpix.online/carbon-credits/whitepaper](https://tpix.online/carbon-credits/whitepaper) |
| **Token Sale** | [tpix.online/token-sale](https://tpix.online/token-sale) |
| **Master Node Guide** | [tpix.online/masternode/guide](https://tpix.online/masternode/guide) |
| **Download Apps** | [tpix.online/download](https://tpix.online/download) |
| **GitHub** | [github.com/xjanova/TPIX-Coin](https://github.com/xjanova/TPIX-Coin) |

---

## Add TPIX Chain to MetaMask

| Field | Value |
|-------|-------|
| Network Name | TPIX Chain |
| RPC URL | `https://rpc.tpix.online` |
| Chain ID | `4289` |
| Currency Symbol | `TPIX` |
| Block Explorer | `https://explorer.tpix.online` |

---

<p align="center">
  <strong>TPIX Chain Whitepaper v2.2</strong><br/>
  Last updated: March 2026<br/>
  Developed by <a href="https://xmanstudio.com">Xman Studio</a>
</p>
