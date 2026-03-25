<p align="center">
  <img src="wallet/assets/images/tpixlogo.webp" alt="TPIX Chain" width="120" />
</p>

<h1 align="center">TPIX Chain</h1>

<p align="center">
  <strong>EVM-Compatible Blockchain with Zero Gas Fees</strong><br/>
  Built on Polygon Edge (IBFT 2.0 Consensus) — 2-second block time, instant finality
</p>

<p align="center">
  <a href="https://tpix.online"><img src="https://img.shields.io/badge/Website-tpix.online-blue?style=flat-square" alt="Website" /></a>
  <a href="https://explorer.tpix.online"><img src="https://img.shields.io/badge/Explorer-explorer.tpix.online-green?style=flat-square" alt="Explorer" /></a>
  <a href="https://tpix.online/whitepaper"><img src="https://img.shields.io/badge/Whitepaper-Read-orange?style=flat-square" alt="Whitepaper" /></a>
  <a href="https://github.com/xjanova/TPIX-Coin/releases"><img src="https://img.shields.io/github/v/release/xjanova/TPIX-Coin?style=flat-square&color=cyan" alt="Release" /></a>
</p>

---

## Overview

TPIX Chain is a high-performance EVM-compatible blockchain designed for the TPIX ecosystem. It features zero gas fees, 2-second block production, and IBFT 2.0 consensus with Byzantine fault tolerance.

### Key Specifications

| Parameter | Value |
|-----------|-------|
| **Consensus** | IBFT 2.0 (Istanbul BFT) |
| **Block Time** | 2 seconds |
| **Finality** | ~10 seconds |
| **Gas Fee** | Zero (free transactions) |
| **EVM Compatible** | Full Solidity & ERC-20/721 support |
| **Chain ID** | 8899 |
| **Native Token** | TPIX |
| **Total Supply** | 10,000,000,000 TPIX |
| **RPC** | `https://rpc.tpix.online` |
| **Explorer** | [explorer.tpix.online](https://explorer.tpix.online) |

---

## Repository Structure

```
TPIX-Coin/
├── contracts/           # Solidity smart contracts
│   ├── NodeRegistry.sol # Validator node registration
│   ├── StakingPool.sol  # TPIX staking for node operators
│   └── RewardDistributor.sol
├── docs/                # Technical documentation
├── infrastructure/      # Genesis config & deployment scripts
│   ├── genesis.json     # Chain genesis configuration
│   └── deploy/          # Node deployment scripts
├── masternode/          # Polygon Edge node configuration
├── masternode-app/      # Master Node CLI tools
├── masternode-ui/       # Master Node Electron GUI (Windows)
│   ├── electron/        # Electron main process
│   ├── src/             # Vue.js renderer
│   └── package.json
├── wallet/              # TPIX Wallet — Flutter mobile app
│   ├── lib/             # Dart source code
│   ├── android/         # Android build config
│   ├── ios/             # iOS build config
│   └── pubspec.yaml
├── .github/workflows/   # CI/CD — auto-build APK + releases
└── LICENSE              # MIT License
```

---

## Products

### TPIX Wallet (Android)

Secure mobile wallet for TPIX Chain with 3D animated UI.

- Create/import wallet with 12-word seed phrase
- Send & receive TPIX with animated confirmations
- PIN + biometric (fingerprint/face) protection
- AES-256 encrypted keystore
- Auto-update from GitHub Releases
- QR code for receiving payments

**Download:** [Latest Release](https://github.com/xjanova/TPIX-Coin/releases/latest)

### Master Node (Windows)

Desktop application to run TPIX Chain validator nodes.

- One-click node setup with auto-configuration
- Multi-node management (different ports)
- Real-time network dashboard
- 3 staking tiers: Light (10K), Sentinel (100K), Validator (1M TPIX)
- Up to 15% APY rewards

**Setup Guide:** [tpix.online/masternode/guide](https://tpix.online/masternode/guide)

---

## Smart Contracts

| Contract | Description |
|----------|-------------|
| `NodeRegistry.sol` | Register/deregister validator nodes, manage validator set |
| `StakingPool.sol` | Lock TPIX tokens for node operation, handle unstaking |
| `RewardDistributor.sol` | Calculate and distribute block rewards to validators |

---

## Network Configuration

### Add TPIX Chain to MetaMask

| Field | Value |
|-------|-------|
| Network Name | TPIX Chain |
| RPC URL | `https://rpc.tpix.online` |
| Chain ID | `8899` |
| Currency Symbol | `TPIX` |
| Block Explorer | `https://explorer.tpix.online` |

### Token Icon for Wallets

Use the official TPIX token icon in wallet integrations:

```
https://tpix.online/tpixlogo.webp
```

---

## Node Tiers & Rewards

| Tier | Stake Required | APY | Lock Period | Min Hardware |
|------|---------------|-----|-------------|-------------|
| **Light Node** | 10,000 TPIX | 4-6% | 7 days | 2 CPU, 4GB RAM |
| **Sentinel Node** | 100,000 TPIX | 7-10% | 30 days | 4 CPU, 8GB RAM |
| **Validator Node** | 1,000,000 TPIX | 12-15% | 90 days | 8 CPU, 16GB RAM |

Total reward pool: **1.4 Billion TPIX** distributed over 5 years.

---

## Development

### Prerequisites

- **Wallet:** Flutter 3.x, Dart 3.x, Android SDK
- **Master Node UI:** Node.js 18+, Electron
- **Contracts:** Solidity 0.8.x, Hardhat

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

---

## Links

| Resource | URL |
|----------|-----|
| TPIX TRADE (DEX) | [tpix.online](https://tpix.online) |
| Block Explorer | [explorer.tpix.online](https://explorer.tpix.online) |
| Whitepaper | [tpix.online/whitepaper](https://tpix.online/whitepaper) |
| Token Sale | [tpix.online/token-sale](https://tpix.online/token-sale) |
| Master Node Guide | [tpix.online/masternode/guide](https://tpix.online/masternode/guide) |
| Download Apps | [tpix.online/download](https://tpix.online/download) |

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

<p align="center">
  Developed by <strong>Xman Studio</strong><br/>
  <a href="https://xmanstudio.com">xmanstudio.com</a>
</p>
