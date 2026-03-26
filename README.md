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

## Repository Structure

```
TPIX-Coin/
├── contracts/              # Solidity smart contracts (Hardhat)
│   ├── identity/           # Living Identity recovery contract
│   │   └── TPIXIdentity.sol
│   ├── masternode/         # Node registry & staking
│   ├── bridge/             # Cross-chain bridge (BSC)
│   ├── dex/                # DEX router (Uniswap V2 fork)
│   ├── scripts/            # Deploy & verify scripts
│   └── hardhat.config.js
├── infrastructure/         # Genesis config & Docker deployment
│   ├── genesis.json        # Chain genesis (4 validators, 7B supply)
│   └── docker-compose.yml  # 4-node IBFT cluster
├── masternode/             # Polygon Edge node config & install scripts
├── masternode-app/         # Master Node CLI tools (Go/Wails)
├── masternode-ui/          # Master Node Electron GUI (Windows)
│   └── electron/           # HD wallet, identity manager, SQLite
├── wallet/                 # TPIX Wallet — Flutter mobile app
│   └── lib/
│       ├── services/       # wallet_service, identity_service
│       ├── screens/        # UI screens (home, send, identity, etc.)
│       └── providers/      # State management
├── .github/workflows/      # CI/CD — auto-build APK + EXE on tag push
└── LICENSE
```

---

## Products

### TPIX Wallet (Android/iOS)

Secure mobile wallet for TPIX Chain with premium 3D animated UI.

- **Multi-Wallet**: HD wallet with BIP-39/BIP-44 derivation (up to 128 wallets)
- **Living Identity Recovery**: Recover wallet without seed phrase using security questions + GPS location verification
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

### Living Identity (TPIXIdentity.sol)

A novel wallet recovery system that eliminates the need for seed phrases — **no other blockchain wallet has this**.

**How it works:**
1. User registers identity on-chain: `hash(security_questions + GPS_locations + recovery_PIN)` — only 32 bytes stored
2. User loses device or forgets seed phrase
3. User answers security questions + stands at registered GPS location
4. Smart contract starts **48-hour time-lock** recovery
5. Original owner can cancel within 48 hours (theft protection)
6. After 48 hours, wallet control transfers to new address

**Deploy:**
```bash
cd contracts
npm install
export DEPLOYER_KEY=0x...your_private_key...
npm run deploy:identity
```

**Gas cost:** FREE (TPIX Chain has zero gas fees)

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
| **Token Factory** | Create custom ERC-20 tokens for 100 TPIX |
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

| Tier | Stake Required | APY | Lock Period | Max Nodes | Hardware |
|------|---------------|-----|-------------|-----------|----------|
| **Validator** | 1,000,000 TPIX | 12-15% | 90 days | 100 | 8 CPU, 16GB RAM, 500GB SSD |
| **Sentinel** | 100,000 TPIX | 7-10% | 30 days | 500 | 4 CPU, 8GB RAM, 200GB SSD |
| **Light** | 10,000 TPIX | 4-6% | 7 days | Unlimited | 2 CPU, 4GB RAM, 100GB SSD |

**Reward Distribution**: 50% Validator (block producer), 30% Sentinel nodes, 20% Light nodes.
**Total Reward Pool**: 1.4 Billion TPIX over 5 years with decreasing annual emission.

### Annual Emission Schedule

| Year | Emission | Per Block | Share |
|------|---------|-----------|-------|
| Year 1 | 400,000,000 TPIX | ~25.5 TPIX | 28.6% |
| Year 2 | 350,000,000 TPIX | ~22.3 TPIX | 25.0% |
| Year 3 | 300,000,000 TPIX | ~19.1 TPIX | 21.4% |
| Year 4 | 200,000,000 TPIX | ~12.7 TPIX | 14.3% |
| Year 5 | 150,000,000 TPIX | ~9.6 TPIX | 10.7% |

---

## Network Configuration

### Add TPIX Chain to MetaMask

| Field | Value |
|-------|-------|
| Network Name | TPIX Chain |
| RPC URL | `https://rpc.tpix.online` |
| Chain ID | `4289` |
| Currency Symbol | `TPIX` |
| Block Explorer | `https://explorer.tpix.online` |

### Token Icon for Wallets

Official TPIX token icon for wallet integrations and CoinMarketCap/CoinGecko:

```
https://tpix.online/tpixlogo.webp
```

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
- **Contracts**: Node.js 20+, Hardhat (Solidity 0.8.20)

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

| Resource | URL |
|----------|-----|
| **TPIX TRADE (DEX)** | [tpix.online](https://tpix.online) |
| **Block Explorer** | [explorer.tpix.online](https://explorer.tpix.online) |
| **Whitepaper** | [tpix.online/whitepaper](https://tpix.online/whitepaper) |
| **Token Sale** | [tpix.online/token-sale](https://tpix.online/token-sale) |
| **Master Node Guide** | [tpix.online/masternode/guide](https://tpix.online/masternode/guide) |
| **Download Apps** | [tpix.online/download](https://tpix.online/download) |

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

<p align="center">
  Developed by <strong>Xman Studio</strong><br/>
  <a href="https://xmanstudio.com">xmanstudio.com</a>
</p>
