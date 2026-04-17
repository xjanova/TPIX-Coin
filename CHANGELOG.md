# Changelog

All notable changes to TPIX Chain will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `SECURITY.md` — formal vulnerability disclosure policy with coordinated disclosure timeline
- `CONTRIBUTING.md` — contributor guide with Conventional Commits and scenario-based review workflow
- `CHANGELOG.md` — this file (Keep a Changelog format)
- README: "Chain Listings & Registrations" section with transparent registry status
- README: IPFS-pinned chain icon (CID `bafybeiby5mwnwdi53fye4iurjxlddfzonsj67ejl4sjy7qda53za6jlgo4`)
- README: developer quick-connect snippets (ethers v6, viem, Hardhat)

### Changed
- README: expanded "Network Configuration" with 1-click auto-add and manual options
- README: split Links section into Product / Documentation / Registry groups

### Submitted (pending external review)
- [`ethereum-lists/chains#8231`](https://github.com/ethereum-lists/chains/pull/8231) — registers TPIX Chain (4289) + icon for chainlist.org, chainid.network, Rabby, OKX, Trust

---

## [1.6.1] — 2026-04

### Added
- Masternode UI v1.6.1 Windows Electron installer + portable builds via GitHub Actions
- Staking registration table (`node_staking`) with wallet, tier, reward wallet, uptime tracking
- Reward accrual engine (60s cadence, BigInt wei precision)
- Leaflet-based masternode map with green-star highlight for user's own node
- Tier badges with APY display on dashboard

### Fixed
- Leaflet map lifecycle bug on tab switch (destroy + recreate on `v-if` DOM removal)
- Double-tap guards on `startNode`, `stopNode`, `confirmSend`
- TextEditingController disposal in wallet dialogs (Flutter)
- Timer cleanup in `onUnmounted` (Masternode UI Vue component)

### Security
- AES-256-GCM per-wallet encryption (Masternode UI wallet manager)
- PBKDF2 key derivation for password-based wallet unlock
- Private key auto-clear from memory after 60 seconds
- Rate limiting on Living Identity recovery (5 failed attempts → 5-min lockout)

---

## [1.6.0] — 2026-03

### Added
- **Token Factory V2** — Coordinator + Sub-Factory Creator architecture to stay within EIP-170 24KB limit
  - `TPIXTokenFactoryV2` coordinator at [`0xCdE5…dfF2`](https://explorer.tpix.online/address/0xCdE5792A556A2D8571Efb31843CF6C15c3BDdfF2)
  - 5 ERC-20 creators: Enhanced ERC-20, Utility (tax/anti-whale), Reward (reflection/vesting), Governance (ERC20Votes), Stablecoin (freeze/KYC)
- **NFT Factory** — `TPIXNFTFactory` at [`0x3871…76F9`](https://explorer.tpix.online/address/0x38713C76036eb4Ff438eF8CEC12b6D676ad776F9)
  - Single NFT creator (royalty, soulbound SBT)
  - Collection creator (mint config, delayed reveal, royalty)
- Deploy via GitHub Actions — compile on runner, SCP artifacts to server, deploy with validator key

---

## [1.5.0] — 2026-02

### Added
- **Living Identity Recovery** — on-chain wallet recovery without seed phrase (`TPIXIdentity.sol`)
  - Security questions (PBKDF2, 100K rounds)
  - GPS location (SHA-256 hashed, ~111m grid, ±200m verification radius)
  - Recovery PIN (6-8 digit, PBKDF2)
  - 48h time-lock for theft protection
- GPS privacy: only hash stored, never raw/rounded coordinates
- Mobile wallet integration (`identity_service.dart`)
- Masternode UI integration (`identity-manager.js`)

---

## [1.4.0] — 2025-Q4

### Added
- Cross-chain Bridge to BSC (`WTPIX_BEP20`)
- Mobile wallet release (Android APK + iOS TestFlight)
- Multi-wallet support (up to 128 wallets per device, BIP-44 HD)

---

## [1.3.0] — 2025-Q3

### Added
- TPIX TRADE DEX at [tpix.online](https://tpix.online) — Uniswap V2 fork
- NodeRegistryV2 with tier-based staking (Light / Sentinel / Guardian / Validator)
- Block Explorer at [explorer.tpix.online](https://explorer.tpix.online) — Blockscout-powered

---

## [1.0.0] — 2023-Q4

### Added
- TPIX Chain mainnet launch
- Chain ID 4289 (EIP-155)
- IBFT 2.0 consensus with 4 genesis validators
- 7,000,000,000 TPIX pre-mined supply, 6 allocation pools (BIP-44 HD wallet)
- Zero gas fees (hardcoded in genesis)
- 2-second block time, ~1,500 TPS capacity

---

[Unreleased]: https://github.com/xjanova/TPIX-Coin/compare/v1.6.1...HEAD
[1.6.1]: https://github.com/xjanova/TPIX-Coin/releases/tag/v1.6.1
[1.6.0]: https://github.com/xjanova/TPIX-Coin/releases/tag/v1.6.0
[1.5.0]: https://github.com/xjanova/TPIX-Coin/releases/tag/v1.5.0
[1.4.0]: https://github.com/xjanova/TPIX-Coin/releases/tag/v1.4.0
[1.3.0]: https://github.com/xjanova/TPIX-Coin/releases/tag/v1.3.0
[1.0.0]: https://github.com/xjanova/TPIX-Coin/releases/tag/v1.0.0
