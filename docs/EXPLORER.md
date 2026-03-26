# TPIX Chain Block Explorer — Setup Guide

> **Blockscout-based Block Explorer for TPIX Chain**
> Live: [explorer.tpix.online](https://explorer.tpix.online)

---

## Overview

TPIX Chain uses [Blockscout](https://blockscout.com) as its block explorer, providing:

- **Transaction Search** — Look up any transaction by hash
- **Address Explorer** — View balances, token holdings, transaction history
- **Block Browser** — Navigate blocks with validator info
- **Token Tracker** — List all ERC-20 tokens on TPIX Chain
- **Smart Contract Verification** — Verify and read/write contract source code
- **API v2** — REST API for programmatic access
- **Real-Time Stats** — Transaction charts, gas usage, network activity

---

## Architecture

```
┌───────────────────────────────────────┐
│           Blockscout Frontend          │
│            (Port 4000)                 │
├───────────────────────────────────────┤
│           Blockscout Backend           │
│    (Elixir/Phoenix + Indexer)          │
├──────────┬────────────────────────────┤
│ PostgreSQL│  Smart Contract Verifier   │
│ (Port 5432)│     (Port 8050)           │
├──────────┴────────────────────────────┤
│       TPIX Chain RPC (Port 8545)       │
│    (Polygon Edge Validator Node)       │
└───────────────────────────────────────┘
```

---

## Quick Start

### Prerequisites

- Docker & Docker Compose
- Running TPIX Chain node (validator or RPC) on port 8545

### 1. Navigate to Explorer Directory

```bash
cd infrastructure/blockscout
```

### 2. Configure Environment

```bash
cp .env.example .env
```

Edit `.env` with your settings:

```env
# Database — use a strong password in production
DB_PASSWORD=your_secure_password_here

# TPIX Chain RPC — point to your running node
RPC_URL=http://localhost:8545
WS_URL=ws://localhost:8545

# Security — generate a random 64-char string
SECRET_KEY_BASE=$(openssl rand -hex 32)
```

### 3. Start Explorer

```bash
docker-compose up -d
```

### 4. Access

| Service | URL |
|---------|-----|
| **Explorer UI** | `http://localhost:4000` |
| **API v2** | `http://localhost:4000/api/v2` |
| **Contract Verifier** | `http://localhost:8050` |
| **Database** | `localhost:5432` |

---

## Services

### PostgreSQL Database

- **Image**: `postgres:16-alpine`
- **Purpose**: Stores indexed blockchain data (blocks, transactions, addresses, tokens)
- **Data**: Persisted in Docker volume `explorer-db-data`

### Blockscout Backend

- **Image**: `blockscout/blockscout:latest`
- **Purpose**: Indexes blockchain, serves web UI and API
- **Configuration**:
  - Chain ID: `4289` (TPIX Chain)
  - Network name: `TPIX Chain`
  - Coin: `TPIX`
  - API v2 enabled with rate limit of 50 req/min

### Smart Contract Verifier

- **Image**: `ghcr.io/blockscout/smart-contract-verifier:latest`
- **Purpose**: Verifies Solidity source code against deployed bytecode
- **Supports**: Solidity 0.4.x — 0.8.x, multiple EVM versions

---

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_PASSWORD` | (required) | PostgreSQL password |
| `RPC_URL` | `http://host.docker.internal:8545` | TPIX Chain JSON-RPC endpoint |
| `WS_URL` | `ws://host.docker.internal:8545` | TPIX Chain WebSocket endpoint |
| `SECRET_KEY_BASE` | (required) | 64-char random string for session security |
| `API_RATE_LIMIT` | `50` | API requests per minute |
| `HISTORY_FETCH_INTERVAL` | `10` | Seconds between block indexing |

### Chain Configuration (Pre-set)

| Parameter | Value |
|-----------|-------|
| `CHAIN_ID` | `4289` |
| `NETWORK` | `TPIX Chain` |
| `SUBNETWORK` | `Mainnet` |
| `COIN` / `COIN_NAME` | `TPIX` |
| `ETHEREUM_JSONRPC_VARIANT` | `geth` |
| `BLOCK_TRANSFORMER` | `base` |

---

## Production Deployment

### Recommended Setup

1. **Separate server** from validator nodes (avoid resource contention)
2. **Reverse proxy** (Nginx/Caddy) with SSL termination
3. **Strong database password** (not the default)
4. **Random SECRET_KEY_BASE** — generate with `openssl rand -hex 32`
5. **Regular backups** of PostgreSQL data

### Nginx Reverse Proxy Example

```nginx
server {
    listen 443 ssl http2;
    server_name explorer.tpix.online;

    ssl_certificate /etc/letsencrypt/live/explorer.tpix.online/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/explorer.tpix.online/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

### Resource Requirements

| Component | CPU | RAM | Storage |
|-----------|-----|-----|---------|
| Blockscout Backend | 4 cores | 8 GB | 50 GB |
| PostgreSQL | 2 cores | 4 GB | 100 GB+ (grows with chain) |
| Contract Verifier | 2 cores | 4 GB | 10 GB |
| **Total** | **8 cores** | **16 GB** | **160 GB+** |

---

## Troubleshooting

### Explorer not indexing blocks

```bash
# Check if RPC is reachable from Docker
docker exec tpix-explorer-backend curl -s http://host.docker.internal:8545 \
  -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

### Database connection error

```bash
# Check PostgreSQL is running
docker logs tpix-explorer-db

# Reset database (WARNING: deletes all indexed data)
docker-compose down -v
docker-compose up -d
```

### View logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f backend
```

---

## API Usage

### Get latest block

```bash
curl https://explorer.tpix.online/api/v2/blocks?type=block&limit=1
```

### Search address

```bash
curl https://explorer.tpix.online/api/v2/addresses/0x...
```

### Get token list

```bash
curl https://explorer.tpix.online/api/v2/tokens
```

### Verify smart contract

Use the verification UI at `https://explorer.tpix.online/contract-verification` or the API:

```bash
curl -X POST https://explorer.tpix.online/api/v2/smart-contracts/verification \
  -H "Content-Type: application/json" \
  -d '{
    "address": "0x...",
    "compiler_version": "v0.8.20",
    "source_code": "...",
    "contract_name": "MyContract"
  }'
```

---

## Links

| Resource | URL |
|----------|-----|
| **TPIX Explorer** | [explorer.tpix.online](https://explorer.tpix.online) |
| **Blockscout Docs** | [docs.blockscout.com](https://docs.blockscout.com) |
| **TPIX Chain RPC** | `https://rpc.tpix.online` |
| **Chain Genesis** | [infrastructure/genesis.json](../infrastructure/genesis.json) |
| **Validator Setup** | [infrastructure/docker-compose.yml](../infrastructure/docker-compose.yml) |

---

<p align="center">
  Developed by <a href="https://xmanstudio.com">Xman Studio</a>
</p>
