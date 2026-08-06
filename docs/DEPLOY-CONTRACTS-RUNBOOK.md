# คู่มือ deploy สัญญาทั้งชุดบนเชนใหม่

> สถานะ ณ 6 ส.ค. 2026 — **ทุกอย่างพร้อม เหลือแค่ตัดสินใจ 2 เรื่องแล้วรัน**
>
> เชนใหม่ (regenesis 6 ส.ค.) มี **0 transaction** สัญญาที่เคย deploy ก่อนหน้านี้
> หายไปหมด ตรวจด้วย `eth_getCode` แล้วได้ `0x` ทุกตัว — ต้อง deploy ใหม่ทั้งชุด

---

## ตรวจก่อนเริ่ม

```bash
cd contracts
npx hardhat compile          # ต้องขึ้น "Nothing to compile" หรือคอมไพล์ผ่าน
npx hardhat test             # ต้องผ่าน 95 เทสต์
npx hardhat run scripts/deploy-preflight.js --network tpix
```

preflight ตรวจให้ครบว่า: ต่อเชนได้ · กระเป๋า Token Sale มี 700M · กระเป๋า
Liquidity มีเงิน · ยังไม่เคย deploy ซ้ำ · artifact ครบ · path ของ frontend config ถูก

ผลล่าสุด (6 ส.ค. บล็อก 10,308): **ผ่านทุกข้อ** เหลือเตือนอย่างเดียวคือยังไม่ตั้ง
`DEPLOYER_KEY` ซึ่งเป็นของที่ต้องใส่ตอนรันจริง

---

## ⚠️ ต้องตัดสินใจก่อน 2 เรื่อง

### 1. ใช้กระเป๋าไหน deploy

`preflight` แนะนำ **กระเป๋า Token Sale** `0x4BcC1844Ad9E8587f7005f092928a5D14C30F463`
เพราะ `deploy-mainnet.js` ต้องโอน 700M TPIX เข้าสัญญาขาย ซึ่งเงินอยู่ในกระเป๋าใบนั้น

คีย์ derive จาก mnemonic คลังที่ path `m/44'/60'/0'/0/4`

> คีย์นี้เป็นคีย์ของกระเป๋าคลัง **ห้าม commit ห้ามใส่ใน .env ที่ค้างไว้**
> ตั้งเป็น env ตอนรันแล้วปิดเทอร์มินัลทิ้ง

### 2. ราคาเปิดของเหรียญ (เฉพาะตอน seed DEX pool)

`deploy-dex.js` อ่าน `LIQ_TPIX` กับ `LIQ_USDT` — **ราคาเปิด = LIQ_USDT ÷ LIQ_TPIX**

ตัวอย่าง: `LIQ_TPIX=1000000` `LIQ_USDT=100000` → เปิดที่ $0.10/TPIX

**ถ้ายังไม่พร้อมตัดสิน ไม่ต้องใส่สองตัวนี้** สคริปต์จะข้ามขั้น seed pool
แล้ว deploy สัญญา DEX ไว้ก่อน เติมสภาพคล่องทีหลังผ่าน router ได้
— แนะนำให้ทำแบบนี้ ไม่ต้องรีบผูกราคา

---

## ลำดับการ deploy

```bash
cd contracts
export DEPLOYER_KEY=0x...          # อย่าพิมพ์ค้างใน history — ใช้ read -s ก็ได้
```

### ขั้นที่ 1 — ชุดขายเหรียญ

```bash
npx hardhat run scripts/deploy-mainnet.js --network tpix
```

deploy: WTPIX (ตัวห่อสำหรับการขาย) → wrap 700M → USDT_TPIX → TPIXBondingCurve
เขียนผลลง `contracts/deployed-contracts.json` และ
`ThaiXTrade/resources/js/Config/launchContracts.js` ให้เอง

พารามิเตอร์ที่ฝังไว้แล้ว: ราคาเริ่ม $0.10 → จบ $1.00 · เกณฑ์ย้าย $5M / 350M TPIX

### ขั้นที่ 2 — DEX

```bash
export FEE_COLLECTOR=0x...         # กระเป๋าที่รับค่าธรรมเนียม
# ใส่สองบรรทัดนี้เฉพาะเมื่อพร้อมกำหนดราคาเปิด
# export LIQ_TPIX=1000000
# export LIQ_USDT=100000
npx hardhat run scripts/deploy-dex.js --network tpix
```

### ขั้นที่ 3 — masternode / identity

`contracts/masternode/NodeRegistry.sol` และ `contracts/identity/TPIXIdentity.sol`
ยังไม่มีสคริปต์ deploy สำเร็จรูป (`deploy-identity.js.disabled` ปิดไว้)
ต้องเขียนสคริปต์หรือ deploy ด้วยมือ

ตอนนี้ `/api/v1/masternode/stats` รายงาน `registry_deployed: false` เพราะข้อนี้

---

## หลัง deploy ต้องทำ

1. **ตรวจ `deployed-contracts.json`** ว่าที่อยู่ครบและถูก
2. **verify source บน explorer** — `npm run verify:sources`
   (CoinGecko / CMC / DeFiLlama ดูสถานะ verify ก่อนรับ listing)
3. **อัปเดตที่อยู่สัญญาในแอปทั้งหมด**
   - `ThaiXTrade` — `.env`: `TOKEN_FACTORY_ADDRESS`, `TOKEN_FACTORY_V2_ADDRESS`,
     `NFT_FACTORY_ADDRESS`, `MASTERNODE_REGISTRY_ADDRESS`
   - `wallet/` (Flutter) — ที่อยู่สัญญาใน chain config
   - `masternode-ui/` (Electron) — registry address
4. **ทดสอบ end-to-end** — ซื้อเหรียญหนึ่งรายการจริงแล้วดูว่า claim → คิวคลัง →
   ส่งขึ้นเชน → สมุดบัญชี ครบวง

---

## ของที่ไม่เกี่ยวกับ deploy แต่ต้องทำก่อนเปิดขายจริง

ระบบจ่ายเงินจากคลัง (ชั้นคลังบน tpix.online) พร้อมแล้วแต่ยังปิดอยู่ ต้อง:

1. วาง keystore ที่ `/etc/tpix/hot-wallet.keystore.json` (สิทธิ์ 600)
2. `.env`: `TPIX_HOT_WALLET_PASS=…`
3. `.env`: `TPIX_TREASURY_PAYOUTS_ENABLED=true`
4. โอนเงินจากคลังเข้ากระเป๋าร้อน (เสนอ 10–20M TPIX)

ดูสถานะได้ที่ `/admin/treasury` — หน้าจะไล่เช็คลิสต์ให้ว่าเหลืออะไร

`tpix:treasury-sync` จะเก็บรายการโอนเข้ากระเป๋าร้อนลงสมุดบัญชีให้เองภายใน 5 นาที
ตัวกระทบยอดจึงไม่ฟ้องว่ายอดไม่ตรง
