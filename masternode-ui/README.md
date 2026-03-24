# TPIX Master Node — Windows GUI

Easy-to-use Windows application for running a TPIX Chain master node.

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

- **Dashboard** — Real-time node status, block height, chain health, system metrics
- **Built-in Wallet** — Create or import wallet directly in the app
- **Network Monitor** — Live validator list, peer count, consensus status
- **Logs Viewer** — Real-time node process logs
- **Settings** — Configure node name, tier, ports, and more
- **Portable** — Single .exe, no installation required
- **System Tray** — Runs in background, minimize to tray

## Architecture

```
masternode-ui/
├── electron/
│   ├── main.js           # Electron main process + window management
│   ├── preload.js        # IPC bridge (security sandbox)
│   ├── node-manager.js   # Polygon Edge process lifecycle + RPC
│   └── wallet-manager.js # Built-in wallet (create/import/encrypt)
├── src/
│   ├── index.html        # Single-page Vue 3 app
│   ├── renderer.js       # Vue app logic
│   └── styles.css        # Glass-morphism dark theme
└── assets/
    └── icon.svg          # App icon
```

## Requirements

- Windows 10/11 (x64)
- 4GB RAM minimum
- Internet connection for TPIX Chain RPC

## Developed by Xman Studio
