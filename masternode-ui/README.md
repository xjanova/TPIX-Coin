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
│   ├── rpc-client.js        # JSON-RPC เส้นทางเดียวของทั้งแอป (UA, rate limit, breaker, failover)
│   ├── ibft-extra.js        # ถอดรายชื่อ validator จาก extraData ของบล็อก
│   ├── chain-health.js      # วัดจังหวะบล็อกจริง จับเชนค้าง เช็ค chainId
│   └── auto-updater.js      # GitHub Releases updater
├── chain/
│   └── genesis.json         # genesis ของเชนปัจจุบัน (ติดไปกับตัวติดตั้ง)
├── scripts/
│   └── verify-chain.js      # `npm run verify:chain` — ยิงเชนจริงทั้งชุด ไม่มี mock
├── src/
│   ├── index.html           # Single-page Vue 3 app (10 tabs)
│   ├── renderer.js          # Vue app logic (~1750 lines)
│   └── styles.css           # Glass-morphism dark theme
└── assets/
    └── icon.ico             # App icon
```

## การเชื่อมต่อเชน (อัปเดต 2026-08-12)

หลัง regenesis 6 ส.ค. 2026 เชนย้ายไปเครื่องใหม่ ค่าที่โปรแกรมยึดตอนนี้:

| รายการ | ค่า |
|---|---|
| RPC หลัก | `https://rpc1.tpix.online` (ไม่มี Cloudflare bot rule ใช้ได้ทุก client) |
| RPC สำรอง | `https://rpc.tpix.online` (**ต้องส่ง User-Agent แบบเบราว์เซอร์** ไม่งั้น 403) |
| chainId | 4289 (`0x10c1`) |
| จังหวะบล็อก | 2 วินาที |
| validator | 4 ตัว (อ่านจาก extraData — โหนดรุ่นนี้ไม่มีเมธอด `ibft_*`) |
| โหนด | polygon-edge v0.9.0 |

**กฎเหล็ก:** ทุกการเรียก RPC ต้องผ่าน `electron/rpc-client.js` เท่านั้น
Node `https.request` ไม่ส่ง User-Agent เองเลย และ Cloudflare ตอบ 403 ให้คำขอที่ไม่มี UA
เคยมีรอบที่เขียนตัวยิง HTTP ขึ้นมาเองซ้อนอีกชุดแล้วลืมใส่ UA จนแอปอ่านเชนไม่ได้ทั้งตัว

ตรวจว่ายังคุยกับเชนได้ครบ:

```bash
npm run verify:chain
```

### แอปแนะนำตัวยังไง (และวิธียกเว้นกฎ Cloudflare ให้ถูกต้อง)

ทุกคำขอที่ออกจาก `rpc-client.js` จะติดสองอย่างนี้ไปด้วย:

```
User-Agent:     TPIX-MasterNode/<version> (+https://tpix.online)
X-TPIX-Client:  tpix-masternode/<version>
```

**เลิกปลอมเป็น Chrome แล้ว** — ทดสอบกับ `rpc.tpix.online` เมื่อ 2026-08-12 พบว่ากฎที่นั่น
บล็อกเฉพาะ UA ที่ว่างเปล่า, `curl/*`, `python-requests/*` ส่วน UA ของผลิตภัณฑ์เราเองผ่าน 200
(ยิงซ้ำ 3 ครั้ง) การปลอมเป็นเบราว์เซอร์มีแต่เสีย: ดู log ไม่ออกว่าอันไหนคือแอปเรา
และถ้ากฎยกระดับเป็น JS challenge สำหรับเบราว์เซอร์ แอปจะไปยืนอยู่ในกลุ่มที่ถูกท้าทายทันที
ทั้งที่ไม่มีเบราว์เซอร์ให้รัน JS

ถ้า UA ตามจริงโดน 403 เมื่อไหร่ แอปจะ**ถอยไปใช้ UA แบบเบราว์เซอร์อัตโนมัติ**
พร้อมเขียน log เตือน — กันไม่ให้แอปดับเงียบซ้ำรอยเดิม แต่นั่นคือทางฉุกเฉิน ไม่ใช่ทางแก้

**ทางแก้ที่ถูกต้อง** คือเพิ่มกฎ Skip ที่ Cloudflare (กฎที่บล็อกอยู่ผูกกับ `rpc.tpix.online`
ตัวเดียว — `rpc1` / `tpix.online` / `explorer` ไม่โดน จึงเป็นกฎที่เราตั้งเอง แก้ได้):

```
Rule name:  Allow TPIX apps on RPC
Expression: (http.host eq "rpc.tpix.online"
             and any(http.request.headers["x-tpix-client"][*] contains "tpix-"))
Action:     Skip → Browser Integrity Check, Security Level, User Agent Blocking
ลำดับ:      วางไว้ "บนสุด" เหนือกฎ Managed Challenge ของ datacenter ASN
```

⚠️ `X-TPIX-Client` **ไม่ใช่ความลับและห้ามใช้แทนการยืนยันตัวตน** — แอปแจกเป็น `.exe`
ใครแกะไฟล์ก็อ่านค่านี้ได้ มันมีไว้ให้ Cloudflare แยกทราฟฟิกของเราออกจากบอทอย่างตั้งใจ
ไม่ได้มีไว้กันคนอื่นเข้า **ห้ามปิด rate limiting** เพราะคิดว่ามีกฎนี้แล้วปลอดภัย
ด่านกันจริงยังเป็น rate limit + allow-list เมธอดที่ nginx เหมือนเดิม

## ข้อจำกัดที่ยังแก้ในแอปไม่ได้ (ต้องทำฝั่งเซิร์ฟเวอร์)

การ "รันโหนดจริงจากบ้าน" **ยังทำไม่ได้** ตราบใดที่ข้อต่อไปนี้ยังไม่ถูกแก้
แอปจึงตรวจก่อนแล้วเปลี่ยนไปทำงาน **โหมดเฝ้าดูเชน** พร้อมบอกเหตุผล แทนที่จะเปิดโหนด
ที่ไม่มีวัน sync ขึ้นมาหลอกผู้ใช้

1. **พอร์ต P2P ปิดจากภายนอก** — validator ทั้ง 4 map ออกโฮสต์เป็นพอร์ต 10001-10004
   (`infrastructure/docker-compose-4v.yml`) แต่ทดสอบจากเน็ตนอกแล้วต่อไม่ติดสักตัว
   → ต้องเปิด firewall ของเครื่อง 123.253.62.252
2. **validator ไม่ประกาศที่อยู่สาธารณะ** — คำสั่ง polygon-edge ไม่มี `--nat <ไอพีสาธารณะ>`
   โหนดนอกที่ต่อเข้ามาจะได้รับที่อยู่ภายในของ Docker (172.x) ซึ่งวิ่งต่อไม่ได้
3. **bootnode ใน genesis ของเซิร์ฟเวอร์ยังเป็นชื่อ container** (`/ip4/tpix-validator-1/...`)
   ซึ่ง resolve ได้เฉพาะใน Docker network — ไฟล์ `chain/genesis.json` ที่ติดมากับแอป
   แก้เป็นรูปแบบสาธารณะแล้ว (ส่วน `genesis` กับ `params` เหมือนต้นฉบับทุกไบต์)
4. **ไม่มีที่ให้โหลด genesis** — `https://tpix.online/genesis.json` ตอบ 404
   ตอนนี้แอปพกไฟล์ไปเองแล้ว แต่ถ้าจะให้คนใช้เครื่องมืออื่นเข้าร่วมได้ ควรเปิดให้โหลด

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
