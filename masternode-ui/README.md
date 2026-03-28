# TPIX Master Node — Windows GUI

Easy-to-use Windows application for running a TPIX Chain master node with built-in staking and reward system.

## Quick Start

```bash
# Install dependencies
npm install

# Run in development
npm start

# Build portable .exe
npm run build:portable

# Build installer
npm run build
```

## Features

- **Dashboard** — Real-time node status, block height, chain health, system metrics, staking status card
- **4-Tier Staking** — Light (10K), Sentinel (100K), Guardian (1M), Validator (10M TPIX)
- **Balance Validation** — RPC balance check before staking, prevents insufficient-balance launches
- **Reward Accrual** — APY-based rewards calculated every 60s, stored in SQLite
- **Multi-Wallet** — Up to 128 HD wallets (BIP-39/BIP-44), AES-256-GCM encrypted
- **Reward Wallet** — Direct rewards to any wallet, not just the staking wallet
- **Setup Wizard** — 3-step guided setup (Choose Tier → Wallet → Configure & Run)
- **Network Monitor** — Live validator list, peer count, consensus status
- **Block Explorer** — Browse blocks and transactions via RPC
- **Masternode Map** — Leaflet world map with node locations, your node highlighted with green star
- **Living Identity** — Security questions + recovery key system
- **Send/Receive** — Built-in transaction signing with QR scanner
- **Bilingual** — Thai + English UI
- **System Tray** — Runs in background, minimize to tray
- **Auto-Update** — GitHub Releases auto-update

## Architecture

```
masternode-ui/
├── electron/
│   ├── main.js              # Electron main process, 50+ IPC handlers, tray
│   ├── preload.js           # IPC bridge (contextIsolation: true)
│   ├── node-manager.js      # Polygon Edge process, RPC, metrics, reward accrual
│   ├── wallet-manager.js    # Multi-wallet HD, AES-256-GCM encryption
│   ├── transaction-manager.js # TX signing, broadcasting, confirmation
│   ├── identity-manager.js  # Living Identity (security questions, recovery)
│   ├── database.js          # SQLite schema v3 (wallets, tx, rewards, staking)
│   ├── rpc-client.js        # JSON-RPC wrapper
│   └── auto-updater.js      # GitHub Releases updater
├── src/
│   ├── index.html           # Single-page Vue 3 app (10 tabs)
│   ├── renderer.js          # Vue app logic (~1750 lines)
│   └── styles.css           # Glass-morphism dark theme
└── assets/
    └── icon.ico             # App icon
```

## Staking System

| Tier | Stake | APY | Lock | Slashing | Max Nodes |
|------|-------|-----|------|----------|-----------|
| Light | 10,000 TPIX | 4-6% | 7 days | 0% | Unlimited |
| Sentinel | 100,000 TPIX | 7-9% | 30 days | 5% | 500 |
| Guardian | 1,000,000 TPIX | 10-12% | 90 days | 10% | 100 |
| Validator | 10,000,000 TPIX | 15-20% | 180 days | 15% | 21 |

### Flow
1. User selects tier → balance validated via RPC
2. User creates/imports wallet
3. User configures node name and reward wallet
4. "Launch Node" → staking registered in SQLite → node process starts
5. Every 60s: reward = `stake × avgAPY × elapsed / year` (BigInt precision)
6. Rewards stored in SQLite, displayed on Dashboard and Wallet page
7. "Stop Node" → staking deactivated, uptime saved

## Database Schema (v3)

- `wallets` — Multi-wallet with encrypted keys (AES-256-GCM)
- `hd_seeds` — Encrypted BIP-39 mnemonic
- `transactions` — TX history with status tracking
- `rewards` — Reward records (wallet_id, block_number, amount in wei, timestamp)
- `node_staking` — Staking state (wallet, tier, stake_amount, reward_wallet, uptime, status)
- `settings` — Key-value app config
- `security_questions`, `recovery_keys` — Living Identity tables

## Roadmap

| Phase | Year | Focus |
|-------|------|-------|
| **Phase 1** | 2025–2026 | Mainnet, 4-tier staking, masternode network, wallet, DEX, bridge |
| **Phase 2** | 2027 | AI-governed chain — AI replaces human validators for autonomous 24/7 governance |
| **Phase 3** | 2028 | Gaming platform, AI-produced products to market, quality food control system |

## Requirements

- Windows 10/11 (x64)
- 4GB RAM minimum
- Internet connection for TPIX Chain RPC

## Developed by Xman Studio
