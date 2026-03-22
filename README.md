<p align="center">
  <img src="https://tpix.online/logo.png" alt="TPIX" width="120" height="120" style="border-radius: 24px;" />
</p>

<h1 align="center">TPIX Chain</h1>

<p align="center">
  <strong>A Next-Generation EVM Blockchain for the ASEAN Digital Economy</strong>
</p>

<p align="center">
  <a href="https://tpix.online/whitepaper"><img src="https://img.shields.io/badge/Whitepaper-v2.0-06B6D4?style=for-the-badge" alt="Whitepaper" /></a>
  <a href="https://explorer.tpix.online"><img src="https://img.shields.io/badge/Explorer-Live-10B981?style=for-the-badge" alt="Explorer" /></a>
  <a href="https://rpc.tpix.online"><img src="https://img.shields.io/badge/RPC-Online-F59E0B?style=for-the-badge" alt="RPC" /></a>
  <a href="https://tpix.online"><img src="https://img.shields.io/badge/DEX-TPIX%20TRADE-8B5CF6?style=for-the-badge" alt="DEX" /></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Chain%20ID-4289-blue" alt="Chain ID" />
  <img src="https://img.shields.io/badge/Consensus-IBFT%20PoA-green" alt="Consensus" />
  <img src="https://img.shields.io/badge/Block%20Time-2s-orange" alt="Block Time" />
  <img src="https://img.shields.io/badge/Gas-FREE-brightgreen" alt="Gas Free" />
  <img src="https://img.shields.io/badge/EVM-Compatible-purple" alt="EVM" />
  <img src="https://img.shields.io/badge/Supply-7B%20TPIX-cyan" alt="Supply" />
</p>

---

## Overview

**TPIX (Thaiprompt Index)** is the native coin of TPIX Chain, an EVM-compatible blockchain built on [Polygon Edge](https://polygon.technology/polygon-edge) technology. Designed specifically for the Thai and Southeast Asian digital economy, TPIX Chain provides gasless transactions, 2-second block times, and full Solidity smart contract support.

TPIX is not just a cryptocurrency - it is the backbone of a complete digital economy spanning food supply chain traceability, IoT smart farming, delivery services, e-commerce, AI marketplace, hotel booking, carbon credit trading, and enterprise affiliate marketing.

## Chain Specifications

| Parameter | Value |
|-----------|-------|
| **Chain Name** | TPIX Chain |
| **Chain ID** | `4289` (Mainnet) / `4290` (Testnet) |
| **Native Coin** | TPIX (Thaiprompt Index) |
| **Decimals** | 18 |
| **Total Supply** | 7,000,000,000 TPIX (pre-mined in genesis) |
| **Consensus** | IBFT (Istanbul Byzantine Fault Tolerant) |
| **Block Time** | ~2 seconds |
| **Finality** | ~10 seconds (5 blocks) |
| **Gas Price** | 0 (gasless - hardcoded in genesis) |
| **TPS Capacity** | ~1,500 transactions/second |
| **VM** | EVM (Ethereum Virtual Machine) |
| **Framework** | Polygon Edge v0.9.0 |
| **RPC Endpoint** | `https://rpc.tpix.online` |
| **Explorer** | `https://explorer.tpix.online` |
| **Website** | `https://tpix.online` |

## Add TPIX Chain to MetaMask

| Field | Value |
|-------|-------|
| Network Name | `TPIX Chain` |
| RPC URL | `https://rpc.tpix.online` |
| Chain ID | `4289` |
| Currency Symbol | `TPIX` |
| Block Explorer | `https://explorer.tpix.online` |

## Tokenomics

```
Total Supply: 7,000,000,000 TPIX (Fixed - No inflation, no minting)

Distribution:
  Ecosystem Development  30%  2,100,000,000 TPIX
  Affiliate Rewards      25%  1,750,000,000 TPIX
  Staking Rewards        20%  1,400,000,000 TPIX
  Team & Advisors        15%  1,050,000,000 TPIX
  Marketing              10%    700,000,000 TPIX
```

## Smart Contracts

### DEX (Uniswap V2 Fork)
| Contract | Description |
|----------|-------------|
| `TPIXDEXFactory` | Creates and manages trading pair contracts |
| `TPIXDEXRouter02` | Handles multi-hop swaps and liquidity operations |
| `TPIXDEXPair` | Individual liquidity pool with ERC-20 LP tokens |
| `WTPIX` | Wrapped TPIX for ERC-20 compatibility within DEX |

- **Swap Fee:** 0.3% (0.25% to LPs, 0.05% to protocol)
- **AMM Formula:** Constant product (x * y = k)

### Bridge
| Contract | Description |
|----------|-------------|
| `WTPIX_BEP20` | Wrapped TPIX on BSC (BEP-20 standard) |

### Token Sale (ICO)
| Contract | Description |
|----------|-------------|
| `TPIXTokenSale` | ICO contract accepting USDT on BSC |

## Project Structure

```
TPIX-Coin/
├── contracts/
│   ├── TPIXTokenSale.sol        # ICO/IDO contract
│   ├── dex/
│   │   ├── TPIXRouter.sol       # DEX router (Uniswap V2)
│   │   └── IUniswapV2Router02.sol
│   ├── bridge/
│   │   └── WTPIX_BEP20.sol      # Wrapped TPIX on BSC
│   ├── staking/                  # Staking pool contracts
│   └── token-factory/            # ERC-20 token factory
├── infrastructure/
│   ├── genesis.json              # TPIX Chain genesis block
│   └── docker-compose.yml        # Polygon Edge node setup
├── docs/
│   └── WHITEPAPER.md             # Whitepaper reference
└── README.md
```

## Use Cases

TPIX powers 12+ real-world applications in the Thaiprompt ecosystem:

| Application | Description | TPIX Usage |
|-------------|-------------|------------|
| **Decentralized Exchange** | AMM-based token trading | Swap fees, liquidity rewards |
| **FoodPassport** | Food supply chain traceability | Quality verification, certificate NFTs |
| **Multi-Service Delivery** | Food & service delivery platform | Payment, 3% cashback, rider earnings |
| **IoT Smart Farm** | AI-powered agriculture system | Sensor data marketplace, carbon credits |
| **AI Bot Marketplace** | Buy/sell AI-powered bots | Subscription payments, creator rewards |
| **Hotel & Travel** | Decentralized booking system | Direct payment, 3% cashback |
| **E-Commerce** | Multi-vendor marketplace | Payment, 5% cashback |
| **Token Factory** | Create custom ERC-20 tokens | 100 TPIX creation fee |
| **Carbon Credit** | Blockchain carbon credit trading | Tokenization, trading |
| **AI Ecosystem** | Self-improving AI agents | Automation services |
| **Staking Pools** | Earn APY on TPIX | 5%-200% APY based on lock period |
| **Affiliate Program** | Multi-level referral system | Commission payouts |

## Master Node Program

TPIX uses a **3-tier master node system** with sustainable rewards from a 1.4B TPIX pool over 5 years.

| Tier | Min Stake | APY | Lock | Max Nodes | Block Reward Share |
|------|-----------|-----|------|-----------|-------------------|
| **Validator** | 1,000,000 TPIX | 12-15% | 90 days | 100 | 50% |
| **Sentinel** | 100,000 TPIX | 7-10% | 30 days | 500 | 30% |
| **Light** | 10,000 TPIX | 4-6% | 7 days | Unlimited | 20% |

### Emission Schedule (Decreasing)

| Year | Reward | Per Block | % of Pool |
|------|--------|-----------|-----------|
| Year 1 | 400M TPIX | ~25.5 TPIX | 28.6% |
| Year 2 | 350M TPIX | ~22.3 TPIX | 25.0% |
| Year 3 | 300M TPIX | ~19.1 TPIX | 21.4% |
| Year 4 | 200M TPIX | ~12.7 TPIX | 14.3% |
| Year 5 | 150M TPIX | ~9.6 TPIX | 10.7% |

> See full details: [masternode/README.md](masternode/README.md)

## Run a Master Node

### Quick Install (Linux)
```bash
curl -fsSL https://raw.githubusercontent.com/xjanova/TPIX-Coin/main/masternode/scripts/install.sh | bash
```

### Quick Install (Windows PowerShell)
```powershell
irm https://raw.githubusercontent.com/xjanova/TPIX-Coin/main/masternode/scripts/install.ps1 | iex
```

### Docker
```bash
docker run -d --name tpix-node -p 30303:30303 -p 3847:3847 -e TPIX_TIER=light -e TPIX_WALLET=0xYourAddress tpix-node:latest
```

### Build from Source
```bash
git clone https://github.com/xjanova/TPIX-Coin.git
cd TPIX-Coin/masternode
go build -o tpix-node ./cmd/tpix-node/
./tpix-node init --tier=light --wallet=0xYourAddress
./tpix-node
```

Dashboard: `http://localhost:3847` | Full docs: [masternode/README.md](masternode/README.md)


## Roadmap

| Phase | Period | Status |
|-------|--------|--------|
| Concept & Foundation | Q1-Q2 2023 | Completed |
| Blockchain Development | Q3-Q4 2023 | Completed |
| Platform Integration | Q1-Q2 2024 | Completed |
| Ecosystem Expansion (DEX, Staking) | Q3-Q4 2024 | In Progress |
| Real-World Applications | Q1-Q2 2025 | In Progress |
| Mainnet & Scaling | Q3-Q4 2025 | In Progress |
| Global Expansion | Q1-Q2 2026 | Planned |
| Advanced Features (L2, Cross-chain) | Q3-Q4 2026 | Planned |

## Technology Stack

| Layer | Technology |
|-------|-----------|
| **Blockchain** | Polygon Edge (Go) |
| **Consensus** | IBFT Proof of Authority |
| **Smart Contracts** | Solidity ^0.8.20, OpenZeppelin |
| **Development** | Hardhat, ethers.js |
| **Backend** | Laravel 11, PHP 8.2+ |
| **Frontend** | Vue 3, TailwindCSS |
| **Infrastructure** | Docker, Nginx |
| **Explorer** | Custom RPC-based Explorer |

## Security

- IBFT consensus with BFT fault tolerance
- All smart contracts use OpenZeppelin security libraries
- Rate-limited RPC endpoints
- Docker containerized infrastructure
- Encrypted validator keys
- Ongoing bug bounty program (up to 10,000 TPIX)

## Links

| Resource | URL |
|----------|-----|
| Website | https://tpix.online |
| DEX (TPIX TRADE) | https://tpix.online/trade |
| Whitepaper | https://tpix.online/whitepaper |
| Explorer | https://explorer.tpix.online |
| RPC Endpoint | https://rpc.tpix.online |
| Token Sale | https://tpix.online/token-sale |
| Chainlist Registration | [PR #8148](https://github.com/ethereum-lists/chains/pull/8148) |

## License

Copyright (c) 2023-2026 Xman Studio. All rights reserved.

Smart contracts are open source under the MIT License. Chain infrastructure code is proprietary.

---

<p align="center">
  <strong>Developed by <a href="https://xmanstudio.com">Xman Studio</a></strong><br/>
  Building the future of ASEAN digital economy
</p>
