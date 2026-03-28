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
3. **Token Factory** — Fee payment for creating custom ERC-20 tokens (100 TPIX)
4. **Carbon Credits** — Purchase and trade verified carbon credits
5. **FoodPassport** — Pay for food traceability verification services
6. **Governance** — Future DAO voting rights
7. **Cross-Chain Bridge** — Lock TPIX to mint wrapped tokens on BSC

---

## 6. Tokenomics

### Distribution

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

Create custom ERC-20 tokens on TPIX Chain with zero gas fees.

### Token Types

| Type | Features | Fee |
|------|----------|-----|
| **Standard** | Fixed supply, transferable | 100 TPIX |
| **Mintable** | Owner can mint additional tokens | 100 TPIX |
| **Burnable** | Holders can burn their tokens | 100 TPIX |
| **Mintable + Burnable** | Both mint and burn capabilities | 100 TPIX |

### Creation Flow

```
1. User connects wallet on tpix.online/token-factory
2. Fills token details (name, symbol, supply, type)
3. Pays 100 TPIX creation fee
4. TPIXTokenFactory deploys new ERC-20 contract
5. Token is immediately tradeable on TPIX TRADE DEX
6. Token appears on Block Explorer with verified source
```

### Use Cases

- **Business Loyalty Points** — Retail chains, restaurants, hotels
- **Community Tokens** — DAOs, social clubs, fan tokens
- **Real-World Assets (RWA)** — Property tokens, commodity tokens
- **Carbon Credits** — Tokenized verified emission reductions

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
| **Token Factory** | Create custom ERC-20 tokens for 100 TPIX | Live |
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

| Phase | Period | Status | Milestones |
|-------|--------|--------|------------|
| **Foundation** | Q1-Q2 2023 | Done | Whitepaper, architecture, team formation |
| **Blockchain** | Q3-Q4 2023 | Done | Polygon Edge, TPIX coin, IBFT consensus, testnet |
| **Integration** | Q1-Q2 2024 | Done | Laravel services, REST API, block explorer |
| **Ecosystem** | Q3-Q4 2024 | Done | DEX, master node network, SDK development |
| **Real-World** | Q1-Q2 2025 | Done | FoodPassport, delivery, IoT, AI bots |
| **Scale** | Q3-Q4 2025 | Done | Cross-chain bridge, mobile wallet, multi-wallet |
| **Identity** | Q1 2026 | Done | Living Identity recovery, GPS verification, on-chain identity |
| **Enterprise** | Q2 2026 | In Progress | Enterprise toolkit, government compliance, carbon credits |
| **Global** | Q3-Q4 2026 | Planned | ASEAN expansion, 100+ dApps, multi-language support |

---

## 17. Team & Governance

### Development

TPIX Chain is developed by **Xman Studio** — a Thai technology studio specializing in blockchain, AI, and enterprise software.

### Governance Roadmap

| Phase | Governance Model |
|-------|-----------------|
| **Current** | Centralized development by Xman Studio |
| **2026 Q3** | Community advisory board |
| **2026 Q4** | DAO governance proposal system |
| **2027** | Full on-chain governance with TPIX voting |

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
  <strong>TPIX Chain Whitepaper v2.0</strong><br/>
  Last updated: March 2026<br/>
  Developed by <a href="https://xmanstudio.com">Xman Studio</a>
</p>
