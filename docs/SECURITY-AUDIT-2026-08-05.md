# TPIX — Security Audit 2026-08-05

> สแกนพร้อมกับงาน regenesis + กระจาย validator เพื่อจะได้แก้ทีเดียวจบ
> ขอบเขต: chain config · infrastructure · nginx/RPC · สัญญาที่จะ deploy บนเชนใหม่
> ระดับความรุนแรงตาม `CLAUDE.md`: **CRITICAL** · **LOGIC** · **UX** · **MINOR**

## สรุปหัวตาราง

> **อัปเดต 2026-08-05 รอบสอง** — แก้ในโค้ดไปแล้ว 8 ข้อ ดูคอลัมน์สถานะ
> **ไม่มีข้อไหนต้องรอ rechain** สิ่งเดียวที่ต้อง rechain จริงๆ คือ 700M TPIX
> ที่ล็อกอยู่ในกระเป๋า `0x3F8EB404…401A` ซึ่งไม่มีใครมี private key

| # | เรื่อง | ระดับ | สถานะ |
|---|---|---|---|
| C1 | Bonding curve — คนที่ไม่เคยซื้อ ขายเข้า curve ดูด USDT ออกได้ | **CRITICAL** | ✅ **แก้แล้ว** + เทสต์ 5 เคส (83/83 ผ่าน) |
| C2 | ถ้าแก้ C1 แบบง่ายๆ จะเปิดช่อง cap bypass ใหม่ | **LOGIC** | ✅ **กันแล้ว** — แยก `bought` / `redeemable` |
| G1 | ตารางจัดสรรเหรียญมีสองชุดขัดกัน ชุดหนึ่งคีย์หาย | **CRITICAL** | ✅ **แก้แล้ว** `chain/alloc.env` + ปิดตายสคริปต์เก่า |
| G2 | genesis ที่ validator ว่าง ผ่านออกมาได้โดยไม่มีใครทัก | **CRITICAL** | ✅ **แก้แล้ว** `genesis-verify.py` + เสียบเข้า CI |
| N1 | nginx method whitelist ข้ามได้ด้วยการยัดสตริงใน `params` | **CRITICAL** | ✅ **แก้แล้ว** — เพิ่ม deny-list ที่ข้ามไม่ได้ |
| N2 | batch request หลุด whitelist ทั้งชุดถ้ามีตัวแรกถูก | **CRITICAL** | ✅ **แก้แล้ว** — deny-list ครอบ batch ด้วย |
| N3 | `error_page 429 → 403` ทำให้ fail2ban ที่จับ 429 ไม่มีวันทำงาน | **LOGIC** | ✅ **แก้แล้ว** — เลิกดัก 429 |
| I1 | gRPC admin (10000) เปิด `0.0.0.0` | **CRITICAL** | ✅ **แก้แล้ว** ทั้ง compose เดิม + ตัวใหม่ · ⛔ ต้อง restart บนเซิร์ฟเวอร์ |
| I3 | ไฟล์ backup มีคีย์ validator ครบ ไม่มีคำเตือน | **LOGIC** | ✅ เตือนไว้ใน runbook แล้ว |
| N4 | origin token ถูก comment ไว้ → ข้าม Cloudflare ยิง origin ตรงได้ | **LOGIC** | 🟡 เตรียมไว้แล้ว (`map $origin_ok`) — **ต้องตั้ง token เอง** |
| I4 | Cloudflare → origin เป็น HTTP เปล่า (`listen 80`) | **LOGIC** | ⛔ ต้องทำที่ Cloudflare dashboard (ผมทำแทนไม่ได้) |
| I2 | private key validator เก็บแบบไม่เข้ารหัส (`--insecure`) | **LOGIC** | 🟡 สิทธิ์ไฟล์อยู่ใน bootstrap แล้ว — ต้องแก้บนเครื่องเดิมด้วย |
| I5 | `chain-watchdog.sh` ยังคิดว่า validator อยู่เครื่องเดียว | **LOGIC** | ⛔ ทำตอน Phase 5 (ยังไม่กระทบตอนนี้) |

## ⚠️ ยังไม่ได้ทดสอบ nginx config

เครื่องที่ผมทำงานอยู่ไม่มี docker/nginx จึงยัง **ไม่ได้รัน `nginx -t`** ตรวจเองแล้วเท่าที่ทำได้:
วงเล็บสมดุล (depth ปิดที่ 0) · map ครบ 4 ตัว · ลำดับ deny ก่อน allow · ไม่มี `REPLACE_ME` ค้าง

ก่อน reload บนเซิร์ฟเวอร์ **ต้องรัน**:
```bash
sudo docker exec tpix-rpc-lb nginx -t     # ต้องได้ "syntax is ok" + "test is successful"
```
และก่อนหน้านั้นให้รัน `scripts/audit-rpc-exposure.sh` ก่อน เพราะยังไม่ยืนยันว่า container
`tpix-rpc-lb` รันอยู่จริงหรือเปล่า — โน้ต *"xman4289 server stack + DirectAdmin/Cloudflare setup"*
ระบุว่าเครื่อง DirectAdmin ใช้ Apache ไม่มี nginx บน host เลย ถ้า `rpc-lb` ไม่ได้รัน
การแก้ `nginx-rpc.conf` จะไม่มีผลอะไรทั้งสิ้น

---

## C1 — Bonding curve: ดูด USDT ออกได้โดยไม่เคยซื้อ  🔴 CRITICAL

**ไฟล์**: `contracts/src/sale/TPIXBondingCurve.sol:288-310` (และ `emergencySell` บรรทัด 318-339)

```solidity
function sell(uint256 tpixIn, uint256 minUsdtOut) external nonReentrant whenNotPaused
    returns (uint256 usdtOut)
{
    require(!migrated, "BC: migrated");
    require(tpixIn > 0 && tpixIn <= totalSold, "BC: invalid in");   // ← ตัวนับ "ทั้งระบบ"
    ...
    tpix.safeTransferFrom(msg.sender, address(this), tpixIn);
    usdt.safeTransfer(msg.sender, usdtOut);
}
```

`buy()` บันทึก `bought[msg.sender] += tpixOut` ไว้ครบ แต่ `sell()` **ไม่เคยอ่านค่านั้นเลย**
เงื่อนไขเดียวคือ `tpixIn <= totalSold` ซึ่งเป็นตัวนับรวมของทั้งสัญญา ไม่ผูกกับผู้เรียก

**สถานการณ์จริงที่เกิดได้**

1. กระเป๋าคลัง 6 ใบถือ TPIX จาก genesis รวม 6,960,000,000 เหรียญ (curve ตั้งใจให้ผ่านแค่ 700M)
2. นักลงทุนจริงซื้อผ่าน curve ไป 50,000,000 TPIX → `totalSold = 50M`, ในสัญญามี USDT ก้อนโต
3. คนที่ถือ TPIX จากที่อื่น (ทีม / ผู้รับ airdrop / ใครก็ตามที่ได้เหรียญมาโดยไม่ผ่าน curve)
   เรียก `sell(50_000_000e18, 0)` → ผ่านทุก `require`
4. ได้ USDT ตามราคา curve ปัจจุบัน หัก exit fee 5% — **เป็นเหรียญที่ไม่เคยจ่ายเงินซื้อ**
5. USDT ของนักลงทุนจริงออกจากสัญญา → คนที่ซื้อจริงถอนไม่ได้อีก

ไม่ต้องมีสิทธิ์พิเศษ ไม่ต้อง reentrancy ไม่ต้อง flash loan — แค่ถือ TPIX แล้วเรียกฟังก์ชันสาธารณะ

**แก้**

```solidity
// เพิ่ม state แยกสองตัว — อย่าใช้ bought[] ตัวเดียว (ดู C2)
mapping(address => uint256) public purchasedLifetime;  // สำหรับ cap เท่านั้น ไม่เคยลด
mapping(address => uint256) public redeemable;         // ขายคืนได้เท่านี้ ลดเมื่อขาย

// ใน buy()
purchasedLifetime[msg.sender] += tpixOut;
redeemable[msg.sender]        += tpixOut;
require(purchasedLifetime[msg.sender] <= maxBuyPerWallet, "BC: wallet cap");

// ใน sell() และ emergencySell()
require(tpixIn <= redeemable[msg.sender], "BC: exceeds purchased");
redeemable[msg.sender] -= tpixIn;
```

**เทสต์ที่ต้องเพิ่ม**
- `test_sell_reverts_when_caller_never_bought`
- `test_sell_reverts_when_exceeding_own_purchase`
- `test_emergency_sell_also_bounded_by_purchase`
- `test_buy_sell_buy_cannot_exceed_lifetime_cap`

---

## C2 — กับดักตอนแก้ C1  🟠 LOGIC

ถ้าแก้ C1 ด้วยวิธีสั้นที่สุด คือใช้ `bought[]` ตัวเดิมแล้วลดค่าตอนขาย จะได้ช่องใหม่ทันที:

```
ซื้อจนชน maxBuyPerWallet → ขายคืนทั้งหมด (bought กลับเป็น 0) → ซื้อใหม่จนชน cap อีกรอบ
```
วนได้ไม่จำกัด = `maxBuyPerWallet` ไม่มีความหมาย

จึงต้องแยกเป็นสองตัวนับตามที่เขียนไว้ใน C1 — `purchasedLifetime` คุม cap (ไม่เคยลด),
`redeemable` คุมสิทธิ์ขายคืน (ลดได้)

---

## G1 — ตารางจัดสรรสองชุดขัดกัน  🔴 CRITICAL · แก้แล้ว

ใน repo มีตารางจัดสรรเหรียญ **สองชุดที่ให้ผลต่างกัน**:

| ชุด | อยู่ที่ | Token Sale wallet |
|---|---|---|
| ใหม่ (คุมคีย์ได้) | memory + `path3-regenesis` | `0x4BcC1844…F463` |
| เก่า (**คีย์หาย**) | `chain-regenesis-4v.yml:101`, `chain-reset-fixed.yml:61` | `0x3F8EB404…401A` |

`0x3F8EB404…401A` ถือ 700,000,000 TPIX บนเชนปัจจุบันและไม่มีใครมี private key — เหรียญล็อกถาวร
ถ้าเผลอรัน yml สองไฟล์นั้นตอน regenesis จะเผาซ้ำรอบสอง

**แก้แล้ว**: ย้ายตารางไป `infrastructure/chain/alloc.env` ที่เดียว · `build-genesis.sh` อ่านจากที่นั่น
· `genesis-verify.py --expect-alloc` เทียบยอดรายกระเป๋า และ **เตือนถ้ามีกระเป๋าแปลกปลอม**

**ยังต้องทำ**: ลบหรือเปลี่ยนชื่อไฟล์ตายทั้ง 4
`chain-regenesis-4v.yml` · `chain-reset-fixed.yml` · `scripts/path3-regenesis.sh` · `re-genesis.sh`

---

## G2 — genesis ที่ validator ว่าง หลุดขึ้น production ได้  🔴 CRITICAL · แก้แล้ว

polygon-edge ไม่ error เมื่อ `--ibft-validators-prefix-path` หาคีย์ไม่เจอ — มันสร้าง genesis
ที่ `extraData` มี validator list ว่างให้เฉยๆ ผลคือเชนค้างบล็อก 0 โดยไม่มี error message ที่ไหนเลย
กินเวลาไป 3 วันกับความพยายาม 8 ครั้ง (2026-05-04 → 05-07)

**แก้แล้ว**: `genesis-verify.py` ถอด RLP ของ `extraData` ตรงๆ นับ validator ตรวจความยาว BLS key
เทียบยอดจัดสรร ตรวจรูปแบบ multiaddr — 19 ข้อ · `build-genesis.sh` เรียกก่อนคืนไฟล์เสมอ · exit 1 ถ้าไม่ผ่าน

---

## I1 — gRPC admin เปิดออกเน็ต  🔴 CRITICAL

**ไฟล์**: `infrastructure/docker-compose.yml:61`

```yaml
ports:
  - "8545:8545"    # JSON-RPC (public)
  - "10000:10000"  # gRPC (admin)   ← ผูก 0.0.0.0
  - "10001:10001"
```

gRPC ของ polygon-edge คือช่องแอดมิน สั่ง `ibft propose` (เสนอเพิ่ม/ถอด validator),
`peers add/remove`, อ่าน status ได้ทั้งหมด ตอนนี้อยู่หลังไฟร์วอลล์เครื่องเดียวจึงยังพอทน
แต่ **วินาทีที่ย้ายขึ้น VPS ที่มี public IP นี่คือช่องยึดเชน**

**แก้แล้วใน** `infrastructure/oracle/docker-compose.node.yml` — ผูก `127.0.0.1` ทั้ง 8545 และ 10000
**ยังต้องทำ**: แก้ compose ตัวที่รันอยู่จริงบนเซิร์ฟเวอร์ปัจจุบันด้วย ไม่ต้องรอ regenesis

---

## N1 — nginx method whitelist ข้ามได้  🔴 CRITICAL

**ไฟล์**: `infrastructure/nginx-rpc.conf:42-69`

```nginx
map $request_body $rpc_method_allowed {
    default 0;
    "~*\"method\"\s*:\s*\"eth_call\""  1;
    ...
}
```

map จับ **สตริงที่ไหนก็ได้ในทั้ง body** ไม่ได้แกะ JSON ผู้โจมตีจึงยัดข้อความให้ตรง pattern
ลงใน `params` แล้วเรียกเมธอดอะไรก็ได้:

```json
{"jsonrpc":"2.0","id":1,
 "method":"admin_addPeer",
 "params":["ข้อความหลอก \"method\":\"eth_call\" "]}
```

body มีสตริง `"method":"eth_call"` → map ให้ผ่าน → nginx ส่งต่อขึ้น upstream โดยเมธอดจริงคือ `admin_addPeer`

> ผลกระทบวันนี้จำกัด เพราะ polygon-edge ไม่ได้เปิด namespace `admin`/`debug`/`personal` บน JSON-RPC
> แต่ด่านนี้ "ดูเหมือนป้องกัน" ทั้งที่ไม่ได้ป้องกัน — และถ้าวันหนึ่งเอา nginx ตัวนี้ไปหน้า geth/erigon
> หรือ polygon-edge รุ่นที่เปิด namespace เพิ่ม จะกลายเป็นช่องเต็มตัวทันที

**แก้**: อย่ากรองเมธอดด้วย regex บนสตริงดิบ เลือกทางใดทางหนึ่ง
- ใช้ `njs` (โมดูล nginx JavaScript) `JSON.parse` แล้วอ่าน `.method` จริง
- หรือวาง proxy เล็กๆ (Go/Node) คั่นกลางที่แกะ JSON แล้วค่อยกรอง
- หรือยอมรับตรงๆ ว่ากรองไม่ได้ ลบ map ทิ้ง แล้วพึ่ง rate limit + การที่ polygon-edge ไม่มีเมธอดอันตราย
  (**อย่าเก็บด่านที่หลอกตัวเองไว้เฉยๆ**)

---

## N2 — batch request หลุดยกชุด  🔴 CRITICAL

**ไฟล์**: `infrastructure/nginx-rpc.conf:68`

```nginx
"~*\\[\\s*\\{[^\\]]*\"method\"\\s*:\\s*\"(eth_|net_|web3_)" 1;
```

กติกาคือ "ถ้า batch มีเมธอดขึ้นต้นด้วย `eth_`/`net_`/`web3_` อยู่ตัวหนึ่ง ให้ผ่านทั้ง batch"
รายการที่เหลือไม่ถูกตรวจเลย:

```json
[{"method":"eth_chainId","id":1},
 {"method":"debug_traceCall","params":[...],"id":2}]
```

แก้พร้อมกับ N1 (ทางแก้เดียวกัน — ต้องแกะ JSON จริงถึงจะตรวจทุกรายการใน batch ได้)

---

## N3 — 429 ถูกเปลี่ยนเป็น 403 ทำให้ fail2ban ไม่ทำงาน  🟠 LOGIC

**ไฟล์**: `infrastructure/nginx-rpc.conf:12` เทียบกับ `:159`

หัวไฟล์เขียนไว้ว่า *"Returns 429 (not 200) so fail2ban can ban abusers"* แต่ท้ายไฟล์:

```nginx
error_page 403 404 405 429 = @blocked;
location @blocked { return 403 '...'; }
```

`= @blocked` เปลี่ยน status ที่ตอบและที่ลง access log เป็น **403** ทั้งหมด
→ jail ที่จับ `429` ใน log จะไม่มีวันเจอสักบรรทัด rate limit ยังทำงาน แต่ **ไม่มีการแบนเกิดขึ้นจริง**

**แก้**: แยก 429 ออกมา
```nginx
error_page 403 404 405 = @blocked;
error_page 429 = @toomany;
location @toomany {
    default_type application/json;
    return 429 '{"error":{"code":-32005,"message":"rate limited"}}';
}
```
แล้วตรวจว่า jail ของ fail2ban match `" 429 "` จริง

---

## N4 + I4 — origin เข้าถึงตรงได้ และเป็น HTTP เปล่า  🟠 LOGIC

**ไฟล์**: `infrastructure/nginx-rpc.conf:73` และ `:95`

```nginx
listen 80;                       # ไม่มี TLS ที่ origin
# if ($http_x_cf_origin_token != "REPLACE_ME…") { return 403; }   ← ถูก comment ไว้
```

สองข้อนี้ทำให้:
1. ใครก็ตามที่รู้ IP origin ยิงตรงได้ ข้าม WAF/rate limit/bot rule ของ Cloudflare ทั้งหมด
2. ถ้า Cloudflare SSL mode เป็น **Flexible** ช่วง Cloudflare → origin วิ่งเป็น HTTP เปล่าบนเน็ต
   → ดักแก้ผลลัพธ์ `eth_call` / ยอดคงเหลือ / quote ราคา ระหว่างทางได้

> โน้ตในสมองเรื่อง *"BrainX origin IP already public in repo history"* บอกว่า IP origin หลุด repo
> มาแล้วครั้งหนึ่ง สมมติฐานว่า "ไม่มีใครรู้ IP" จึงใช้ไม่ได้

**แก้** (ทำครบทั้ง 3 ข้อ ไม่ใช่เลือกข้อเดียว)
1. Cloudflare SSL/TLS mode → **Full (strict)** + ติดตั้ง origin certificate แล้ว `listen 443 ssl`
2. เปิดบรรทัด origin token คืน แล้วตั้งค่าเป็นสตริงสุ่มยาว (ตั้งคู่กับ Page Rule / Transform Rule)
3. ไฟร์วอลล์เครื่อง origin อนุญาต 443 เฉพาะช่วง IP ของ Cloudflare (`https://www.cloudflare.com/ips/`)

---

## I2 — private key validator เก็บแบบไม่เข้ารหัส  🟠 LOGIC

ทุกสคริปต์ใช้ `secrets init --insecure` → `validator.key`, `validator-bls.key`, `libp2p.key`
วางเป็นไฟล์ธรรมดาใน data dir ใครอ่านไฟล์ได้ = ปลอมเป็น validator ตัวนั้นได้ทันที

บนเครื่องเดียวหลังไฟร์วอลล์ยังพอรับได้ แต่บน VPS ของผู้ให้บริการภายนอกความเสี่ยงเพิ่มขึ้นชัดเจน
(snapshot ของ boot volume, การ support access, การ decommission เครื่อง)

**ลดความเสี่ยงได้ทันที (ฟรี)**
- `chmod 700 data/consensus && chmod 600 data/consensus/*` — ใส่ไว้ใน `bootstrap-node.sh` แล้ว
- เปิด **boot volume encryption** ตอนสร้าง instance (Oracle เปิดให้ default — ยืนยันว่าไม่ได้ปิด)
- ห้ามเปิด instance snapshot ไปเก็บใน Object Storage ที่แชร์
- backup ต้อง `gpg -c` ก่อนออกจากเครื่องเสมอ

**ทางที่ดีกว่า (มีค่าใช้จ่าย/งานเพิ่ม)**: polygon-edge รองรับ secrets manager แบบ HashiCorp Vault
(`--secrets-config`) แทน local FS — คุ้มเมื่อ validator กระจายหลายเจ้าของ

---

## I5 — watchdog ยังคิดว่าทุกโหนดอยู่เครื่องเดียว  🟠 LOGIC

`infrastructure/scripts/chain-watchdog.sh` เขียนบนสมมติฐาน "4 validator เป็น container ในเครื่องนี้"
(เช็ค `docker ps`, `docker restart`) พอแยกเครื่องแล้วจะรายงานว่าทุกอย่างปกติทั้งที่โหนดอื่นตายไปแล้ว

**แก้ตอน Phase 5**: เปลี่ยนเป็นเช็คผ่าน RPC ข้ามเครื่อง — ดึง `eth_blockNumber` + `net_peerCount`
จากทุกโหนด แล้ว alert เมื่อ (ก) ความสูงต่างกันเกิน 10 บล็อก (ข) peer < 2 (ค) ความสูงไม่ขยับ 60 วินาที
และติดตั้ง watchdog แยกตัวบนทุกโหนดสำหรับ restart เฉพาะที่

---

## ✅ ส่วนที่ตรวจแล้วไม่พบปัญหาเพิ่ม

**MasterNode heartbeat / allowlist (ฝั่ง ThaiXTrade)** — ผ่าน audit เต็มรูปแบบไปแล้วเมื่อ 2026-05-15
แก้ครบ 6 ข้อ (L1 `ltrim` กัดสตริง signature, L2 replay window, L3 spoof `CF-Connecting-IP`,
L4 leak IP operator, L5 `orWhereNotIn` ทำ scope พัง, L6 delegation อายุไม่จำกัด) พร้อมเทสต์ 74/74
**ไม่ต้องรื้อซ้ำ** ยกเว้นตอน Phase 5 ให้ยืนยันว่า `MASTERNODE_TRUST_CF_HEADERS` ยังตั้งถูกหลังย้ายโครงสร้าง

**USDT_TPIX** — `bridgeMint` มี whitelist relayer + กัน replay ด้วย `processedTxHashes[sourceTxHash]`
+ Pausable + ตัวนับ mint/burn สะสมสำหรับกระทบยอดกับเชนต้นทาง โครงถูกต้อง
ความเสี่ยงที่เหลืออยู่นอกสัญญา: **คีย์ relayer** — ควรเป็น multisig ก่อนเปิดใช้จริง

**TPIXBondingCurve ส่วนที่เหลือ** — `nonReentrant` ครบ, ลำดับ checks-effects-interactions ถูกต้อง
(state ก่อน `safeTransfer` ทุกจุด), `migrate()` มีดีเลย์หน่วงเวลา, `rescueToken` กัน TPIX/USDT ไว้แล้ว,
`emergencySell` กัน owner pause ค้างเพื่อ rug ปัญหาเดียวคือ C1

---

## ลำดับที่ควรลงมือ

| ลำดับ | ทำอะไร | บล็อกอะไรอยู่ |
|---|---|---|
| 1 | **C1 + C2** แก้ + เทสต์ | บล็อก deploy สัญญาบนเชนใหม่ (Phase 7) |
| 2 | **I1** ผูก gRPC เป็น 127.0.0.1 บนเซิร์ฟเวอร์ปัจจุบัน | ทำได้เลยวันนี้ ไม่ต้องรออะไร |
| 3 | **G1** ลบไฟล์ตาย 4 ไฟล์ | บล็อก Phase 0 |
| 4 | **N3** แยก 429 ออกจาก 403 | แก้ 3 บรรทัด ทำเลย |
| 5 | **N4 + I4** Full(strict) + origin token + จำกัด IP Cloudflare | ทำได้เลย |
| 6 | **N1 + N2** เลือกทาง: njs / proxy / ลบด่านลวงทิ้ง | ตัดสินใจก่อน Phase 5 |
| 7 | **I5** watchdog ข้ามเครื่อง | Phase 5 |
| 8 | **I2** สิทธิ์ไฟล์ + encrypt backup | อยู่ใน bootstrap แล้ว ตรวจซ้ำตอน Phase 4 |
