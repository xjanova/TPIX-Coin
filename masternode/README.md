# TPIX Master Node

<div align="center">

![TPIX Logo](https://tpix.online/logo.png)

**Decentralized Blockchain Node for TPIX Chain**

[![Go Version](https://img.shields.io/badge/Go-1.22+-00ADD8?logo=go)](https://go.dev)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20Docker-lightgrey)]()
[![Chain](https://img.shields.io/badge/Chain-TPIX%20(4289)-06B6D4)]()

[Download](https://github.com/xjanova/TPIX-Coin/releases) |
[Documentation](#installation) |
[Whitepaper](https://tpix.online/whitepaper) |
[Dashboard](#dashboard)

</div>

---

## What is TPIX Master Node?

TPIX Master Node is a software that allows you to participate in the TPIX blockchain network as a validator, earn rewards by securing the network, and contribute to decentralization.

### Key Features

- **Earn Rewards** — Stake TPIX and earn 4-15% APY from block validation
- **3-Tier System** — Choose Validator, Sentinel, or Light node based on your resources
- **Cross-Platform** — Runs on Windows Server, Linux, and Docker
- **Web Dashboard** — Beautiful real-time monitoring at `http://localhost:3847`
- **Auto-Updates** — Stay current with automatic update checks
- **Low Resource** — Light nodes run on minimal hardware

---

## Node Tiers

| Tier | Min Stake | APY | Lock | Max Nodes | Reward Share |
|------|-----------|-----|------|-----------|--------------|
| **Validator** | 1,000,000 TPIX | 12-15% | 90 days | 100 | 50% of block reward |
| **Sentinel** | 100,000 TPIX | 7-10% | 30 days | 500 | 30% of block reward |
| **Light** | 10,000 TPIX | 4-6% | 7 days | Unlimited | 20% of block reward |

### Hardware Requirements

| | Validator | Sentinel | Light |
|---|-----------|----------|-------|
| CPU | 8 cores | 4 cores | 2 cores |
| RAM | 16 GB | 8 GB | 4 GB |
| Storage | 500 GB SSD | 200 GB SSD | 100 GB SSD |
| Network | 100 Mbps | 50 Mbps | 20 Mbps |

---

## Reward Economics

**Total Reward Pool: 1,400,000,000 TPIX** (20% of 7B total supply)

Distributed over 5 years with decreasing emission:

| Year | Reward | Per Block (~2s) | % of Pool |
|------|--------|-----------------|-----------|
| Year 1 | 400,000,000 TPIX | ~25.5 TPIX | 28.6% |
| Year 2 | 350,000,000 TPIX | ~22.3 TPIX | 25.0% |
| Year 3 | 300,000,000 TPIX | ~19.1 TPIX | 21.4% |
| Year 4 | 200,000,000 TPIX | ~12.7 TPIX | 14.3% |
| Year 5 | 150,000,000 TPIX | ~9.6 TPIX | 10.7% |

### Block Reward Distribution

```
Each Block Reward:
├── 50% → Validator (block producer)
├── 30% → Sentinel nodes (shared equally)
└── 20% → Light nodes (weighted by stake & uptime)
```

### After Year 5

Sustainable rewards from:
- Transaction fee sharing (dApp/token creator fees)
- Cross-chain bridge fees
- Token Factory listing fees
- Governance voting rewards

---

## Installation

### Quick Install (Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/xjanova/TPIX-Coin/main/masternode/scripts/install.sh | bash
```

With options:
```bash
./install.sh --tier=sentinel --wallet=0xYourAddress --name=my-node
```

### Quick Install (Windows)

Run PowerShell as Administrator:
```powershell
irm https://raw.githubusercontent.com/xjanova/TPIX-Coin/main/masternode/scripts/install.ps1 | iex
```

With options:
```powershell
.\install.ps1 -Tier sentinel -Wallet "0xYourAddress" -Name "my-node"
```

### Docker

```bash
docker run -d \
  --name tpix-node \
  -p 30303:30303 \
  -p 3847:3847 \
  -e TPIX_TIER=light \
  -e TPIX_WALLET=0xYourAddress \
  -v tpix-data:/root/.tpix-node \
  tpix-node:latest
```

### Build from Source

```bash
git clone https://github.com/xjanova/TPIX-Coin.git
cd TPIX-Coin/masternode
go build -o tpix-node ./cmd/tpix-node/
./tpix-node init --tier=light --wallet=0xYourAddress
./tpix-node
```

---

## Usage

### Initialize Node

```bash
tpix-node init --tier=light --wallet=0xYourWalletAddress --name=my-node
```

### Start Node

```bash
tpix-node
# or with config
tpix-node --config=/path/to/tpix-node.yaml
```

### Check Status

```bash
tpix-node status
```

### Open Dashboard

```bash
tpix-node dashboard
# Opens http://localhost:3847 in your browser
```

---

## Dashboard

The built-in web dashboard provides real-time monitoring:

- **Node Status** — State, tier, uptime, connected peers
- **Staking Info** — Staked amount, pending rewards, total earned
- **Network Stats** — Total nodes, validators, block height
- **System Resources** — CPU, RAM, disk, network usage
- **Reward History** — Detailed reward transaction log
- **Emission Progress** — Visual reward pool tracking

Access at: `http://localhost:3847`

---

## Configuration

Config file location: `~/.tpix-node/tpix-node.yaml`

```yaml
node_name: "my-tpix-node"
tier: "light"                          # validator, sentinel, light
wallet_address: "0xYourAddress"

chain_rpc: "https://rpc.tpix.online"
chain_id: 4289

p2p_port: 30303
rpc_port: 8545
dashboard_port: 3847

max_peers: 50
sync_mode: "full"
enable_metrics: true

log_level: "info"
auto_update: true
```

---

## Smart Contracts

The Master Node system is governed by on-chain smart contracts:

| Contract | Purpose |
|----------|---------|
| `NodeRegistry.sol` | Node registration, staking, reward distribution |

Key functions:
- `registerNode(tier, endpoint)` — Register as a master node (payable)
- `deregisterNode()` — Exit and unstake (after lock period)
- `claimRewards()` — Claim pending block rewards
- `pendingReward(address)` — View pending reward amount
- `getNetworkStats()` — Get network-wide statistics
- `getActiveNodes(offset, limit)` — List active nodes (paginated)

---

## Slashing

| Event | Validator | Sentinel | Light |
|-------|-----------|----------|-------|
| Offline > 24h | -10% stake | — | — |
| Offline > 48h | — | -5% stake | — |
| Double signing | -50% stake + ban | — | — |
| Offline > 7 days | Deregistered | Deregistered | Deregistered |

Slashed funds are returned to the reward pool.

---

## Network Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 30303 | TCP/UDP | P2P networking |
| 3847 | TCP | Dashboard web UI |
| 8545 | TCP | JSON-RPC API |
| 9090 | TCP | Prometheus metrics |

---

## Architecture

```
tpix-node/
├── cmd/tpix-node/        # CLI entry point
├── internal/
│   ├── node/             # Core node logic
│   ├── consensus/        # DPoS consensus adapter
│   ├── staking/          # Staking contract interaction
│   ├── p2p/              # P2P networking (libp2p)
│   ├── rpc/              # JSON-RPC server
│   ├── monitor/          # System monitoring
│   └── dashboard/        # Web UI dashboard
├── config/               # Configuration management
├── scripts/              # Install scripts (Linux/Windows)
├── web/                  # Static assets
├── Dockerfile            # Docker build
└── go.mod                # Go module
```

---

## Links

- **Website:** https://tpix.online
- **Explorer:** https://explorer.tpix.online
- **RPC:** https://rpc.tpix.online
- **Whitepaper:** https://tpix.online/whitepaper
- **GitHub:** https://github.com/xjanova/TPIX-Coin

---

## License

MIT License - see [LICENSE](LICENSE) for details.

---

<div align="center">

**Built with Go by [Xman Studio](https://xmanstudio.com)**

TPIX Chain (ID: 4289) | Block Time: 2s | Zero Gas Fees

</div>
