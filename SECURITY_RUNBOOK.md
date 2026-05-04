# TPIX Security Runbook — 2026-05-04

ทำตามลำดับเลย ทำได้คนเดียว ไม่ต้องรอใคร

---

## 🟥 PHASE 1 — STOP THE BLEEDING (ทำทันที, 15 นาที)

**สถานะปัจจุบัน:** rpc.tpix.online โดน scanner bot ยิง 968k req/24h, mitigated แค่ 57

### 1.1 เปิด Cloudflare proxy บน rpc.tpix.online

🌐 https://dash.cloudflare.com/e1073e47af620370eed1088f297c6dcf/tpix.online/dns/records

- หา DNS record ชื่อ `rpc`
- คลิกที่ "cloud icon" สีเทา → เปลี่ยนเป็น **สีส้ม (Proxied)**
- กด save

> ✅ เสร็จเมื่อ: cloud icon เป็นสีส้ม. WAF rules ทุกตัวข้างล่างนี้จะเริ่มทำงาน

### 1.2 เปิด Bot Fight Mode

🌐 https://dash.cloudflare.com/e1073e47af620370eed1088f297c6dcf/tpix.online/security/bots

- **Bot Fight Mode** → toggle **ON**

### 1.3 ตั้ง Security Level + Browser Integrity

🌐 https://dash.cloudflare.com/e1073e47af620370eed1088f297c6dcf/tpix.online/security/settings

- **Security Level** → เลือก **High**
- **Browser Integrity Check** → toggle **ON**
- **Challenge Passage** → 30 minutes

### 1.4 เพิ่ม WAF Custom Rules (3 rules)

🌐 https://dash.cloudflare.com/e1073e47af620370eed1088f297c6dcf/tpix.online/security/waf/custom-rules

คลิก **Create rule** แล้ว paste ทีละอัน:

#### Rule A — Block confirmed scanner IPs
```
Rule name:  Block scanner IPs
Expression: (ip.src in {8.229.118.104 34.82.237.212 34.169.208.60 65.108.125.227 216.73.216.187 103.153.183.69 51.81.167.217 117.189.23.44 20.119.78.66 172.215.216.215})
Action:     Block
```

#### Rule B — Block dangerous JSON-RPC methods
```
Rule name:  Block dangerous RPC methods
Expression: (http.host eq "rpc.tpix.online" and http.request.method eq "POST" and (lower(http.request.body.raw) contains "\"method\":\"debug_" or lower(http.request.body.raw) contains "\"method\":\"admin_" or lower(http.request.body.raw) contains "\"method\":\"personal_" or lower(http.request.body.raw) contains "\"method\":\"txpool_" or lower(http.request.body.raw) contains "\"method\":\"miner_"))
Action:     Block
```

#### Rule C — Challenge datacenter ASNs on RPC (allow GCP/Azure/AWS only with JS challenge)
```
Rule name:  Challenge datacenter on RPC
Expression: (http.host eq "rpc.tpix.online") and (ip.geoip.asnum in {15169 8075 16509 14061 24940 396982 53667 14618 9009 211252})
Action:     Managed Challenge
```

### 1.5 เพิ่ม Rate Limiting Rule

🌐 https://dash.cloudflare.com/e1073e47af620370eed1088f297c6dcf/tpix.online/security/waf/rate-limiting-rules

```
Rule name:    RPC POST throttle
Expression:   http.host eq "rpc.tpix.online" and http.request.method eq "POST"
Counting:     same IP
Period:       10 seconds
Threshold:    30 requests
Action:       Block, duration: 1 hour
```

### ⏱️ Phase 1 เสร็จแล้ว

ภายใน 5-10 นาทีหลัง save: ดู Security → Events → จะเห็น `Mitigated` พุ่งจาก 57 → หลายพัน. Server load ตก 90%+

---

## 🟧 PHASE 2 — RPC NODE LOCKDOWN (1-2 ชั่วโมง คืนนี้)

> ผม commit nginx-rpc.conf + fail2ban configs ที่ hardened ไว้แล้ว — คุณต้อง SSH ไปติดตั้งบน server

### 2.1 SSH ไป validator/RPC server

ใช้ PuTTY เปิด SSH เข้า server ที่รัน rpc.tpix.online (ผมไม่รู้ host/IP) — ตัวอย่าง:
```bash
ssh user@<your-rpc-server>
```

### 2.2 Pull configs ใหม่

```bash
cd ~/TPIX-Coin
git pull origin main
```

### 2.3 ติดตั้ง nginx-rpc.conf (hardened)

```bash
# Backup config เดิม
sudo cp /etc/nginx/sites-available/rpc.tpix.online /etc/nginx/sites-available/rpc.tpix.online.bak

# ก่อน install — เพิ่ม rate limit zones ใน /etc/nginx/nginx.conf inside http {} block
sudo nano /etc/nginx/nginx.conf
```

เพิ่ม 2 บรรทัดนี้ใน `http {}` block (วางก่อน `include` directives):
```nginx
limit_req_zone $binary_remote_addr zone=rpc_per_ip:10m rate=30r/s;
limit_conn_zone $binary_remote_addr zone=rpc_conn_per_ip:10m;
```

แล้ว install:
```bash
sudo cp infrastructure/nginx-rpc.conf /etc/nginx/sites-available/rpc.tpix.online
sudo nginx -t                        # ตรวจ syntax
sudo systemctl reload nginx          # apply (ไม่มี downtime)
```

### 2.4 ติดตั้ง fail2ban

```bash
sudo apt-get install -y fail2ban
sudo cp infrastructure/fail2ban/filter.d/tpix-rpc.conf /etc/fail2ban/filter.d/
sudo cp infrastructure/fail2ban/jail.d/tpix-rpc.conf /etc/fail2ban/jail.d/
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
sudo fail2ban-client status tpix-rpc   # ตรวจสถานะ
```

### 2.5 ตั้ง UFW firewall (เปิดเฉพาะ port ที่ใช้)

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp                  # SSH
sudo ufw allow 80/tcp                  # HTTP (CF → nginx)
sudo ufw allow 443/tcp                 # HTTPS
sudo ufw allow from <validator-ip-1> to any port 30303,30304,30305,30306  # P2P internal
sudo ufw enable
sudo ufw status verbose
```

### 2.6 ปิด debug/admin namespaces ใน geth/erigon (ถ้ายังเปิด)

ตรวจ docker-compose-4v.yml ว่า geth-validator-* รันด้วย args อะไร:
```bash
grep -A5 "command:\|http.api" infrastructure/docker-compose-4v.yml
```

ถ้าเห็น `--http.api debug,admin,personal` → ลบ `debug,admin,personal,miner,txpool` ออก เหลือเพียง `eth,net,web3` เท่านั้น

แล้ว restart:
```bash
cd infrastructure
docker compose -f docker-compose-4v.yml down
docker compose -f docker-compose-4v.yml up -d
```

---

## 🟨 PHASE 3 — DEPLOY HARDENED CONTRACTS TO MAINNET (15 นาที)

### 3.1 Pre-flight check

```bash
cd D:\Code\TPIX\TPIX-Coin\contracts
git pull origin main          # ดึง security fixes
npm install                   # ตรวจ dependencies
npx hardhat compile           # ตรวจ compile (7 contracts)
npx hardhat test              # ต้องผ่าน 63/63
```

### 3.2 Deploy ด้วย DEPLOYER_KEY ของคุณ

> ⚠️ Token Sale wallet `0x3F8EB4046F5C79fd0D67C7547B5830cB2Cfb401A` มี 700M TPIX แล้ว — ต้องใช้ key ของ wallet นี้

**Git Bash (Windows):**
```bash
cd D:/Code/TPIX/TPIX-Coin/contracts
export DEPLOYER_KEY=0xYOUR_TOKEN_SALE_WALLET_PRIVATE_KEY
# Optional: ถ้ามี relayer multisig แล้ว
# export RELAYER_ADDRESS=0xYOUR_RELAYER_MULTISIG
npx hardhat run scripts/deploy-mainnet.js --network tpix
```

**PowerShell:**
```powershell
cd D:\Code\TPIX\TPIX-Coin\contracts
$env:DEPLOYER_KEY = "0xYOUR_TOKEN_SALE_WALLET_PRIVATE_KEY"
npx hardhat run scripts/deploy-mainnet.js --network tpix
```

Script จะทำ 5 steps อัตโนมัติ (idempotent — รันซ้ำได้ปลอดภัย):
1. Deploy WTPIX
2. Wrap 700M native → WTPIX
3. Deploy USDT_TPIX + TPIXBondingCurve
4. Transfer 700M WTPIX → BondingCurve
5. Set bridge relayer (ถ้าตั้ง RELAYER_ADDRESS)

ผลลัพธ์: ได้ addresses + เขียน `ThaiXTrade/resources/js/Config/launchContracts.js` อัตโนมัติ

### 3.3 Verify บน Blockscout

```bash
npm run verify:sources
```

### 3.4 Build + deploy ThaiXTrade frontend

```bash
cd D:\Code\TPIX\ThaiXTrade
npx vite build
git add resources/js/Config/launchContracts.js
git commit -m "chore(launch): wire mainnet contract addresses"
git push origin main
```

(auto-deploy.yml จะ deploy ให้อัตโนมัติ)

---

## 🟦 PHASE 4 — POST-DEPLOY HARDENING (free, ทำได้ทันที)

### 4.1 ย้าย ownership ไป multisig

ก่อน mainnet ใครเข้าใช้: ย้าย contract ownership ไป Gnosis Safe multisig

```bash
# ใน Hardhat console:
npx hardhat console --network tpix

> const usdt = await ethers.getContractAt("USDT_TPIX", "<USDT_address>")
> const curve = await ethers.getContractAt("TPIXBondingCurve", "<curve_address>")
> const wtpixBep = await ethers.getContractAt("WTPIX", "<wtpix_bep_address_on_BSC>")  // ถ้ามี

# Step 1: transferOwnership (จะกลายเป็น pendingOwner)
> await usdt.transferOwnership("0xMULTISIG_ADDRESS")
> await curve.transferOwnership("0xMULTISIG_ADDRESS")

# Step 2: ที่ multisig — เข้า Safe → submit tx → call acceptOwnership() ของแต่ละ contract
# ต้องทำ on-chain จาก multisig wallet
```

**Multisig wallet:** ใช้ Safe (https://safe.global) — สร้างที่ TPIX chain โดย:
- เข้า https://app.safe.global
- เปลี่ยน network เป็น TPIX (ใส่ chainId 4289 manually ถ้าไม่มี)
- "Create new Safe" → 2-of-3 หรือ 3-of-5 owners
- **ฟรี** (gas TPIX = 0)

### 4.2 ตั้ง monitoring ที่ฟรี

#### Sentry (5k errors/mo ฟรี)
🌐 https://sentry.io/signup
- สร้าง 2 projects: `tpix-trade-laravel`, `tpix-trade-vue`
- เอา DSN มา set `.env`:
  ```
  SENTRY_LARAVEL_DSN=https://...
  SENTRY_VUE_DSN=https://...
  ```
- ผมพร้อมเขียน Laravel + Vue SDK install ให้เมื่อคุณได้ DSN

#### Tenderly (free tier)
🌐 https://dashboard.tenderly.co/register
- Add TPIX network (custom RPC)
- Add 3 contracts: WTPIX, USDT_TPIX, TPIXBondingCurve
- ตั้ง alerts:
  - `Migrated` event fires
  - `pause()` called
  - Transfer > 1M USDT
  - Owner change

### 4.3 ตั้ง Cloudflare Logpush (forensics)

🌐 https://dash.cloudflare.com/e1073e47af620370eed1088f297c6dcf/tpix.online/analytics/logs
- Destination: R2 bucket (free 10GB)
- Dataset: HTTP requests + Firewall events
- Retention: 30 วัน

---

## 🟢 PHASE 5 — ONGOING MAINTENANCE (สัปดาห์ละครั้ง)

### Weekly checklist
- [ ] `npm audit` ใน ThaiXTrade + TPIX-Coin/contracts
- [ ] `composer audit` ใน ThaiXTrade
- [ ] ตรวจ Cloudflare Security Events — ดูว่ามี IP/ASN ใหม่ที่ต้อง block
- [ ] ตรวจ fail2ban: `sudo fail2ban-client status tpix-rpc`
- [ ] backup `deployed-contracts.json` + `genesis.json` ขึ้น offline storage
- [ ] ตรวจ Sentry/Tenderly alerts มีอะไรน่าสงสัย

### Monthly checklist
- [ ] Rotate API keys (Reown, Sentry DSN ถ้าใช้, etc.)
- [ ] Review Cloudflare WAF rules — เพิ่ม IP/ASN block ตาม pattern ที่เจอ
- [ ] ตรวจ `git log` ของ TPIX-Coin/contracts ว่ามี untracked changes ไหม

---

## 📌 สิ่งที่ defer (จ่ายเงินเมื่อพร้อม)

ดูในรายละเอียด: brain note `Notes/TPIX/TPIX Security — Paid Services Backlog (deferred).md`

- External smart contract audit ($5k–$50k)
- Immunefi bug bounty
- Cloudflare Pro ($25/mo)
- Tenderly Pro ($50–$300/mo)
- Sentry Team ($26/mo)

---

## 🆘 Emergency contacts

ถ้ามี exploit / suspected attack:
1. **ทันที:** call `pause()` ของ contract ที่กระทบ:
   ```
   npx hardhat console --network tpix
   > const c = await ethers.getContractAt("TPIXBondingCurve", "<addr>")
   > await c.pause()
   ```
2. **ทันที:** Cloudflare → Security → Under Attack mode (ON)
3. ดู Tenderly transactions / Sentry errors เพื่อหา root cause

หลัง 30 วัน user ยังถอนเงินคืนได้ผ่าน `emergencySell(amount)` ที่ floor price (anti-rug).

---

## ✅ Status checklist

ติ๊กเมื่อทำเสร็จ:

- [ ] Phase 1.1 — RPC orange-cloud ON
- [ ] Phase 1.2 — Bot Fight Mode ON
- [ ] Phase 1.3 — Security Level High + BIC ON
- [ ] Phase 1.4 — WAF Rules A, B, C added
- [ ] Phase 1.5 — Rate Limiting Rule added
- [ ] Phase 2.3 — nginx-rpc.conf installed + reloaded
- [ ] Phase 2.4 — fail2ban installed + active
- [ ] Phase 2.5 — UFW rules in place
- [ ] Phase 2.6 — geth/erigon namespaces locked down
- [ ] Phase 3.2 — `deploy-mainnet.js` ran successfully
- [ ] Phase 3.3 — Contracts verified on Blockscout
- [ ] Phase 3.4 — ThaiXTrade frontend deployed with addresses
- [ ] Phase 4.1 — Ownership moved to Safe multisig
- [ ] Phase 4.2 — Sentry + Tenderly free tiers active
- [ ] Phase 4.3 — Cloudflare Logpush to R2 active

ถาม Claude (ผม) เมื่อติด — ผมจะ guide ทีละขั้น 🚀
