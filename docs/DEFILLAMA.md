# DeFiLlama Integration Guide

This document describes how to submit TPIX Chain + the TPIX DEX to [DeFiLlama](https://defillama.com), the leading cross-chain TVL aggregator.

## Why DeFiLlama?

- **Free** — no listing fees, just a GitHub PR
- **Credible** — DeFiLlama data is consumed by CoinGecko, CoinMarketCap, The Graph, Dune Analytics, and hundreds of other tools
- **Self-serving** — TVL visibility helps users discover the DEX

## Two Separate Submissions

Getting TPIX DEX on DeFiLlama requires two PRs:

### 1. Add TPIX Chain to the chain registry

Repo: [`DefiLlama/chainlist`](https://github.com/DefiLlama/chainlist) (if they maintain one separately) OR inline inside `DefiLlama-Adapters/projects/helper/chains.js`.

Required:
- Chain name: `tpix`
- Chain ID: `4289`
- RPC URL: `https://rpc.tpix.online`
- Explorer: `https://explorer.tpix.online`
- Native coin symbol: `TPIX`

### 2. Add the TPIX DEX adapter

Repo: [`DefiLlama/DefiLlama-Adapters`](https://github.com/DefiLlama/DefiLlama-Adapters)

Path: `projects/tpix-dex/index.ts`

See the template below.

## Adapter Template

Because the TPIX DEX is a Uniswap V2 fork, DeFiLlama's built-in `uniV2Export` helper handles most of the work:

```javascript
// projects/tpix-dex/index.ts
const { uniV2Export } = require('../helper/uniswapForks')

module.exports = uniV2Export({
  tpix: {
    factory: '0x<TPIX_DEX_FACTORY_ADDRESS>',  // fill in after deployment
    useDefaultCoreAssets: false,
  },
})
```

**Core assets** (stablecoins + native wrapped token) must be registered in `projects/helper/coreAssets.json` under the `tpix` key — at minimum: WTPIX (wrapped native) + USDT bridged from BSC.

## Prerequisites

Before submitting, the TPIX DEX must have:

- [x] `TPIXDEXFactory` contract deployed and verified on explorer.tpix.online
- [x] `TPIXDEXRouter02` contract deployed and verified
- [x] At least 3 active liquidity pairs
- [x] Combined TVL ≥ $50,000 (DeFiLlama's quality bar — avoid clutter from dead forks)
- [x] Working RPC at `https://rpc.tpix.online` with stable uptime (>99%)
- [x] Public documentation of contract addresses (this README + explorer)
- [x] Open-source source code on GitHub under MIT or similar permissive license

## Submission Steps

```bash
# Fork https://github.com/DefiLlama/DefiLlama-Adapters
git clone git@github.com:<you>/DefiLlama-Adapters.git
cd DefiLlama-Adapters

# Create adapter
mkdir -p projects/tpix-dex
cat > projects/tpix-dex/index.ts <<EOF
const { uniV2Export } = require('../helper/uniswapForks')

module.exports = uniV2Export({
  tpix: {
    factory: '0x<FACTORY_ADDRESS>',
    useDefaultCoreAssets: false,
  },
})
EOF

# Register the chain if not already known
# Edit projects/helper/chains.js — add "tpix" with chainId 4289, RPC
# Edit projects/helper/coreAssets.json — add TPIX core assets

# Test locally
npm install
node test.js projects/tpix-dex/index.ts

# Should output: "TVL: $XXX,XXX.XX"

# Submit PR to DefiLlama/DefiLlama-Adapters main branch
# Title: "feat: add TPIX DEX adapter (chain 4289)"
```

## Review Timeline

DeFiLlama maintainers typically review PRs within 3-14 days. They will:

1. Check TVL calculation matches their expected methodology
2. Verify contract addresses match what's published in our docs
3. Confirm RPC responds reliably
4. Run the adapter in their CI

After merge, TPIX DEX appears on https://defillama.com/chain/TPIX within hours.

## Current Status

| Requirement | Status |
|-------------|--------|
| Chain infrastructure (RPC, explorer) | ✅ Live |
| DEX contracts deployed | 🔲 Not yet — see Roadmap |
| Contracts verified on explorer | 🔲 Pending deployment |
| Liquidity pools ≥ 3 active | 🔲 Pending |
| TVL ≥ $50K | 🔲 Pending |
| Adapter submitted to DefiLlama | 🔲 Pending all of the above |

## Related

- [CONTRIBUTING.md](../CONTRIBUTING.md) — general contribution workflow
- [README §Chain Listings](../README.md#chain-listings--registrations) — status of other registrations
- DeFiLlama API docs: https://docs.defillama.com
