# CLAUDE.md — TPIX Chain Project Guidelines

## Project Overview
TPIX Chain: EVM blockchain (Polygon Edge/IBFT2, Chain ID 4289, zero gas, 2s blocks).
Version: 1.5.0

### Products
| Product | Tech | Platform |
|---------|------|----------|
| **Flutter Wallet** | Flutter 3.38+, Dart 3.x, Provider | Android/iOS |
| **Masternode UI** | Electron 29, Vue 3.5, SQLite, ethers 6 | Windows x64 |
| **Masternode Backend** | Go 1.22, go-ethereum, gorilla/mux | Linux/Docker |
| **Smart Contracts** | Hardhat 2.22, Solidity 0.8.20, OpenZeppelin 5.6 | EVM |

### Repository Structure
```
TPIX-Coin/
├── wallet/              # Flutter mobile wallet (Android/iOS)
├── masternode-ui/       # Electron desktop GUI (Windows)
│   ├── electron/        # Main process (node-manager, wallet-manager, database, identity, tx, auto-updater)
│   └── src/             # Vue 3 SPA (renderer.js, index.html, styles.css)
├── masternode/          # Go backend (API server, monitoring, Docker)
├── contracts/           # Hardhat smart contracts
│   ├── masternode/      # NodeRegistry, NodeRegistryV2, ValidatorGovernance, ValidatorKYC
│   ├── identity/        # TPIXIdentity
│   ├── dex/             # TPIXRouter, IUniswapV2Router02
│   ├── bridge/          # WTPIX_BEP20
│   └── TPIXTokenSale.sol
├── infrastructure/      # Infra setup
├── scripts/             # Utility scripts
├── docs/                # Documentation
└── .github/workflows/   # CI/CD (build-apk, build-masternode, release-masternode-ui)
```

## Masternode UI Architecture

### Backend (Electron Main Process)
| File | Role |
|------|------|
| `main.js` | Window management, 50+ IPC handlers, tray icon |
| `node-manager.js` | Polygon Edge process lifecycle, RPC, metrics, **reward accrual system** |
| `wallet-manager.js` | Multi-wallet HD (BIP-39/BIP-44), AES-256-GCM encryption, up to 128 wallets |
| `transaction-manager.js` | TX signing, broadcasting, confirmation polling, scan |
| `database.js` | SQLite schema v3: wallets, transactions, rewards, **node_staking**, hd_seeds, identity |
| `identity-manager.js` | Living Identity: security questions, recovery keys, rate limiting |
| `rpc-client.js` | JSON-RPC wrapper for TPIX Chain |
| `auto-updater.js` | GitHub Releases auto-update (xjanova/TPIX-Coin) |

### Frontend (Vue 3 SPA)
- **10 tabs**: Dashboard, Setup (3-step wizard), Wallet, Network, Explorer, Masternodes, Links, Logs, Settings, About
- **Navigation**: `activeTab` ref with `v-if` per page (DOM destroyed on switch)
- **Map**: Leaflet 1.9.4 with CARTO dark tiles — **must destroy/recreate on tab switch** because `v-if` removes DOM

### Staking & Reward System
- **4 tiers**: Light (10K, 4-6% APY), Sentinel (100K, 7-9%), Guardian (1M, 10-12%), Validator (10M, 15-20%)
- **Balance validation**: RPC `eth_getBalance` check before node launch
- **Staking registration**: Stored in SQLite `node_staking` table (wallet, tier, stake_amount, reward_wallet, uptime)
- **Reward accrual**: Every 60s while node is running, calculates `stake × avgAPY × elapsed / year` in wei precision (BigInt)
- **Reward storage**: Inserted to `rewards` table per accrual cycle
- **Reward wallet**: User can direct rewards to a different wallet than staking wallet
- **Dashboard**: Shows staking card with tier, staked amount, total rewards, uptime
- **Masternodes map**: User's own node appears with green star highlight (`isMyNode: true`)

### Living Identity Recovery System
- **Layer 1: Knowledge** — 3-5 security questions, answers hashed with PBKDF2 (100K rounds), stored per wallet
- **Layer 2: Location** — GPS coordinates rounded to ~111m grid, SHA-256 hashed, up to 3 locations per wallet
  - **Privacy**: Only hash stored, never raw/rounded coordinates. Verification checks 9 neighboring grid cells (±200m)
  - **Flutter**: Uses `geolocator` package for GPS → `identity_service.dart`
  - **Electron**: Uses browser `navigator.geolocation` API → `identity-manager.js`
- **Layer 3: Recovery PIN** — 6-8 digit PIN, PBKDF2 hashed, backup when GPS unavailable
- **Layer 4: Time Lock** — 48h recovery delay (future, on-chain via TPIXIdentity.sol)
- **Layer 5: Social Proof** — Guardian wallets approve recovery (future)
- **Recovery flow**: Questions (60%+) + GPS (or PIN fallback) = identity proven
- **Rate limiting**: 5 failed attempts → 5-minute lockout. Self-tests (`isTest: true`) skip rate limiting
- **Tables**: `security_questions`, `gps_locations`, `recovery_keys`, `identity_anchors`, `recovery_requests`

### Key Patterns (Masternode UI)
| Pattern | Details |
|---------|---------|
| **Leaflet map lifecycle** | `v-if` destroys DOM → must call `leafletMap.remove()` and set to null → recreate via `initLeafletMap()` on tab return |
| **Double-tap guards** | `startNode`, `stopNode`, `confirmSend` all have early-return guards |
| **Timer cleanup** | `onUnmounted` clears: networkInterval, metricsInterval, uptimeInterval, gasEstimateTimer, leafletMap |
| **Password modal** | Promise-based `askPassword()` with resolve/reject for wallet operations |
| **BigInt math** | All TPIX amounts in wei (18 decimals), use BigInt for precision, never Number for storage |

## Tech Stack
- **Wallet**: Flutter 3.38+, Dart 3.x, Provider, web3dart, bip39/bip32, flutter_secure_storage
- **Masternode UI**: Electron 29, Vue 3.5, better-sqlite3, ethers 6.11, Leaflet 1.9.4, qrcode, jsQR
- **Masternode Backend**: Go 1.22, go-ethereum 1.14, gorilla/mux, gopsutil
- **Contracts**: Hardhat 2.22, Solidity 0.8.20, OpenZeppelin 5.6.1, ethers v6
- **CI/CD**: GitHub Actions — `v*` tag triggers builds (APK, Go binaries, Electron installer/portable)

## Roadmap

| Phase | Year | Focus | Details |
|-------|------|-------|---------|
| **Phase 1** | 2025–2026 | Foundation | Mainnet launch, 4-tier staking, masternode network, Flutter wallet, DEX, bridge (BSC), smart contracts (NodeRegistry, ValidatorGovernance, KYC, Identity) |
| **Phase 2** | 2027 | AI-Governed Chain | Transition chain governance from human validators to AI systems. AI manages consensus, validator selection, slashing, and network optimization autonomously 24/7 — eliminating human error and downtime |
| **Phase 3** | 2028 | Ecosystem Expansion | Gaming platform on TPIX Chain, AI-manufactured products to market, quality food control and certification system powered by on-chain AI verification |

### Phase 2 — AI Chain Governance (2027)
- Replace human validator committees with AI agents that monitor, govern, and optimize the chain
- AI handles validator rotation, slashing decisions, parameter tuning, and threat detection
- Permanent autonomous operation — no downtime, no human bias, consistent enforcement
- On-chain AI models trained on network telemetry for predictive scaling and security

### Phase 3 — Real-World Integration (2028)
- **Gaming**: On-chain gaming platform with TPIX token economy, NFT assets, and AI-driven game mechanics
- **AI Products**: AI-designed and AI-manufactured consumer products brought to market via TPIX supply chain tracking
- **Food Quality**: Blockchain-verified food quality control — from farm to table traceability, AI inspection, and certification on TPIX Chain

## Conventions
- Commit messages: `type: description` (feat, fix, chore, docs)
- Thai + English bilingual UI
  - Wallet: `LocaleProvider` with `l.t('key')`
  - Masternode UI: `LANG[lang.value]` with computed `i18n`
- Dark theme with glass-morphism (gradients, rgba borders, box-shadows)
- Wallet security: FlutterSecureStorage with AndroidOptions(encryptedSharedPreferences: true)
- Masternode UI security: AES-256-GCM per wallet, PBKDF2 key derivation, contextIsolation: true

## Code Review Protocol: Scenario-Based Testing

**Every code review MUST simulate real-world usage scenarios before approving.**

### Mandatory Checklist

Before marking any feature code as "done", walk through these scenario categories:

#### 1. State Management Scenarios
- [ ] **Leaflet map lifecycle**: `v-if` destroys DOM. Map instance must be destroyed and recreated on tab return.
- [ ] **Loading state flash**: Avoid showing full-screen loading spinners for incremental updates.
- [ ] **BigInt precision**: Never convert wei amounts to Number for storage or comparison. Use BigInt throughout.

#### 2. User Flow Scenarios
- [ ] **First-time user**: Screen with no data — does it look correct and guide the user?
- [ ] **Returning user**: User already has data — are fields pre-filled? Is there an overwrite warning?
- [ ] **Fat-finger protection**: Destructive actions (delete, overwrite, send) require confirmation. All async buttons have double-tap guards.
- [ ] **Error messages**: Never show raw `Exception: ...` to users. Strip prefixes, use localized messages.
- [ ] **Rapid taps**: Can the user double-tap a button and trigger duplicate operations?
- [ ] **Balance validation**: Before staking, wallet balance must be validated via RPC against tier requirement.

#### 3. Security Scenarios
- [ ] **Rate limiting scope**: Self-tests and diagnostics must NOT count against security rate limits.
- [ ] **Multi-wallet isolation**: Identity/security data is per-wallet. Staking is per-wallet.
- [ ] **Private key auto-clear**: Wallet creation private key auto-clears from memory after 60 seconds.
- [ ] **Exported key auto-clear**: Exported key auto-clears after 30 seconds.

#### 4. Cross-Device / Cross-Platform Scenarios
- [ ] **Float-to-string consistency**: Never use `double.toString()` for values that will be hashed or compared across devices. Use `toStringAsFixed(n)`.
- [ ] **Storage key collisions**: Multi-wallet storage keys must include wallet identifier.

#### 5. Resource Management
- [ ] **Timer cleanup**: All intervals/timeouts (network, metrics, uptime, gas, rewards) must be cleared in `onUnmounted`.
- [ ] **Leaflet cleanup**: Map instance must be removed in `onUnmounted`.
- [ ] **QR scanner cleanup**: Camera stream and scan interval must be stopped.
- [ ] **TextEditingController disposal** (Flutter): Controllers created in dialogs must be disposed.
- [ ] **Subscription cleanup**: Stream subscriptions must be cancelled in `dispose()`.

### How to Apply

When reviewing code, mentally execute these scenarios:
```
For each screen/feature:
  1. New user opens it (empty state)
  2. User fills all fields and saves (happy path)
  3. User has existing data and re-opens (edit mode)
  4. User does something wrong (error handling)
  5. User cancels mid-operation (cleanup)
  6. User loses network during operation (timeout)
  7. User switches wallet/language during operation
  8. User rapid-taps buttons (debounce)
  9. Tab switch and return (DOM lifecycle for v-if pages)
  10. Insufficient balance for staking tier
```
