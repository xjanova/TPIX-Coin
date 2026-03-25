<p align="center">
  <img src="https://tpix.online/tpixlogo.webp" alt="TPIX" width="120" height="120" />
</p>

<h1 align="center">TPIX Chain</h1>

<p align="center">
  Official repository for the TPIX blockchain ecosystem — chain infrastructure, master node, and wallet.
</p>

<p align="center">
  <strong>Chain ID:</strong> 4289 &nbsp;|&nbsp;
  <strong>RPC:</strong> https://rpc.tpix.online &nbsp;|&nbsp;
  <strong>Explorer:</strong> https://explorer.tpix.online
</p>

---

## Project Structure

```
TPIX-Coin/
├── contracts/          # Smart contracts (NodeRegistry, Staking)
├── docs/               # Technical documentation & whitepaper
├── infrastructure/     # Chain infrastructure (genesis, validators)
├── masternode/         # Node configuration & scripts
├── masternode-app/     # Master Node backend service
├── masternode-ui/      # Master Node Electron app (Windows)
├── wallet/             # TPIX Wallet Flutter app (Android/iOS)
└── LICENSE
```

## Components

### 🖥️ Master Node (`masternode-ui/`)
Desktop application for running TPIX Chain validator nodes.
- **Platform:** Windows (Electron)
- **Features:** Multi-node management, auto-staking, network dashboard
- **Download:** [Releases](https://github.com/xjanova/TPIX-Coin/releases)

### 📱 TPIX Wallet (`wallet/`)
Beautiful mobile wallet with 3D animations for TPIX Chain.
- **Platform:** Android (Flutter)
- **Features:** Create/import wallet, send/receive TPIX, biometric auth, auto-update
- **Download:** [Releases](https://github.com/xjanova/TPIX-Coin/releases)

### ⛓️ Smart Contracts (`contracts/`)
- `NodeRegistry.sol` — Validator node registration & staking
- Staking tiers: Light (10K), Sentinel (100K), Validator (1M TPIX)

### 🌐 Infrastructure (`infrastructure/`)
- Genesis configuration for TPIX Chain
- Validator setup scripts
- IBFT2 consensus configuration

## Quick Links

| Resource | URL |
|----------|-----|
| 🌐 Website | https://tpix.online |
| 📊 Explorer | https://explorer.tpix.online |
| 🔗 RPC | https://rpc.tpix.online |
| 💱 DEX | https://tpix.online/trade |
| 📄 Whitepaper | https://tpix.online/whitepaper |
| 📥 Downloads | https://tpix.online/download |

## Development

```bash
# Wallet (Flutter)
cd wallet && flutter pub get && flutter run

# Master Node UI (Electron)
cd masternode-ui && npm install && npm start
```

## License

MIT License — Xman Studio © 2024-2026
