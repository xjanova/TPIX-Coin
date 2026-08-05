# TPIX Regenesis + Validator Decentralization — Runbook

> เอกสารสั่งการหลังบ้าน · เขียน 2026-08-05 · แทนที่ `infrastructure/scripts/path3-regenesis.sh` ทั้งฉบับ
> อ่านให้จบก่อนพิมพ์คำสั่งแรก โดยเฉพาะ **Phase 0**

---

## 0. ทำไมรอบก่อนพัง 8 ครั้ง (และรอบนี้จะไม่พังซ้ำ)

เปิด `infrastructure/genesis.json` ที่ deploy ลงไปจริง ดูฟิลด์ `extraData`:

```
0x0000000000000000000000000000000000000000000000000000000000000000 c7c080c28080c080
   └────────────── vanity 32 bytes ──────────────┘                 └── IstanbulExtra ──┘
```

ถอด RLP ส่วนหลัง:

| byte | ความหมาย | ค่า |
|---|---|---|
| `c7` | list ยาว 7 bytes | IstanbulExtra |
| `c0` | **Validators** | **list ว่าง — ไม่มี validator เลยสักตัว** |
| `80` | ProposerSeal | ว่าง |
| `c2 80 80` | CommittedSeals | ว่าง |
| `c0` | ParentCommittedSeals | ว่าง |
| `80` | RoundNumber | ว่าง |

**นี่คือคำตอบทั้งหมด** — engine โหลดคีย์ตัวเอง แล้วไปดูว่า "ใครอยู่ในชุด validator ของบล็อก 0"
เจอ list ว่าง → ไม่มีใครมีสิทธิ์ propose → เงียบตลอดกาล
ส่วน peers ที่เห็นต่อกัน 3/3 คือชั้น networking คนละเรื่องกับ consensus จึงหลงทางกันอยู่ 3 วัน

**ต้นเหตุ**: `--ibft-validators-prefix-path` — ถ้า polygon-edge หาคีย์ตาม path ไม่เจอ
มันไม่ error แต่สร้าง genesis ที่ validator ว่างออกมาเฉยๆ

**ตัวเร่งที่ทำให้แก้ไม่หาย**: ครั้งที่ 4 สร้าง extraData ได้ถูกต้อง (666 ตัวอักษร) แล้ว แต่ยังค้าง
เพราะ `data/validator-*/blockchain/` ของรอบก่อนยังอยู่ → โหนดใช้บล็อก 0 เดิม (ที่ validator ว่าง) ต่อ
**genesis.json ใหม่ไม่มีผลใดๆ ถ้าไม่ล้าง data dir**

**เกณฑ์ตรวจง่ายๆ ที่ใช้ได้ตลอดไป**

| extraData ยาว | หมายความว่า |
|---|---|
| 82 ตัวอักษร | validator set ว่าง — เชนจะค้างบล็อก 0 แน่นอน |
| ~666 ตัวอักษร | 4 validators แบบ BLS — ถูกต้อง |

ของใหม่ที่ป้องกันไว้แล้ว:

| ไฟล์ | หน้าที่ |
|---|---|
| `infrastructure/scripts/genesis-verify.py` | ถอด RLP + เช็ค 19 ข้อ **exit 1 ถ้าไม่ผ่าน** |
| `infrastructure/scripts/build-genesis.sh` | ใช้ `--ibft-validator <addr>:<bls>` ตรงๆ + เรียก verify ก่อนคืนไฟล์ |
| `infrastructure/chain/alloc.env` | ตารางจัดสรรที่เดียวในระบบ |
| `infrastructure/lab/run-lab.sh` | พิสูจน์ในเครื่องก่อน ไม่ต้องเสี่ยงกับ production |

---

## ⛔ Phase 0 — ด่านที่ต้องผ่านก่อนแตะอะไรทั้งสิ้น

### 0.1 คำถามที่ต้องตอบให้ได้ก่อน: **ยอดเหรียญของลูกค้าบนเชนเดิมจะหายไปไหม**

เชนปัจจุบันเดินมาถึงบล็อก ~2.7 ล้าน มี masternode operator จริง มีผู้ใช้ wallet จริง
**regenesis = ล้างสถานะทั้งหมด** ยอดคงเหลือ · สัญญาที่ deploy ไว้ · ประวัติใน explorer หายหมด

ก่อนอื่นต้องรู้ก่อนว่ามีใครถืออะไรอยู่บ้าง — Blockscout เก็บไว้ให้แล้ว:

```bash
sudo docker exec -i blockscout-db psql -U blockscout -d blockscout -t -A -F',' -c \
"SELECT '0x' || encode(hash,'hex'), fetched_coin_balance
 FROM addresses
 WHERE fetched_coin_balance > 0
 ORDER BY fetched_coin_balance DESC;" > /tmp/old-chain-balances.csv

wc -l /tmp/old-chain-balances.csv
head -30 /tmp/old-chain-balances.csv
```

จากผลลัพธ์ ให้เลือกหนึ่งทาง แล้วเขียนไว้ในบันทึกว่าเลือกอะไร:

| ทาง | ทำอย่างไร | เหมาะเมื่อ |
|---|---|---|
| **A. ยกยอดตามมา** | เอา address ที่มียอด (ที่ไม่ใช่ 6 กระเป๋าคลัง) ใส่เพิ่มใน `alloc.env` แล้วลดยอดกระเป๋าคลังลงให้รวมยังเป็น 7,000,000,000 | มีผู้ถือจริงจำนวนไม่มาก — **ทางที่แนะนำ** |
| **B. เริ่มใหม่หมด** | ประกาศล่วงหน้าอย่างน้อย 7 วัน + snapshot เก็บเป็นหลักฐาน | ยอดที่กระจายออกไปน้อยมาก/เป็นของทีมเอง |
| **C. เลื่อน regenesis** | ทำแค่ Phase 2 (กระจาย validator) โดยยกข้อมูลเชนเดิมตามไปด้วย | ถ้ายอดลูกค้าเยอะจนรับความเสี่ยงไม่ไหว |

> ถ้าเลือก C ให้ข้ามไปอ่านหัวข้อ **"ทางเลือก C — ย้ายโดยไม่ regenesis"** ท้ายเอกสาร

### 0.2 พิสูจน์ว่าปลดล็อกกระเป๋าคลังได้จริง

ทดสอบ **decrypt จริง 1 ครั้ง** ทั้ง 6 กระเป๋าใน `alloc.env` — อย่าเชื่อว่าไฟล์สำรองใช้ได้เพราะเห็นว่ามีไฟล์อยู่

```bash
# บนเครื่องออฟไลน์ ไม่ต่อเน็ต
node -e "
const {Wallet}=require('ethers');
const fs=require('fs');
const ks=fs.readFileSync('wallet-output/master-wallet.keystores.json','utf8');
Wallet.fromEncryptedJson(ks, process.env.KS_PASS).then(w=>console.log('ok', w.address));
"
```

รอบก่อนพลาดตรงนี้: กระเป๋า `0x3F8EB404…401A` ถือ 700M TPIX แต่ **ไม่มีใครมี private key**
เงินก้อนนั้นล็อกถาวรมาถึงวันนี้

### 0.3 ยืนยันว่าไม่มีตารางจัดสรรชุดเก่าหลงเหลือ

```bash
cd ~/TPIX-Coin
grep -rn "0x3F8EB4046F5C79fd0D67C7547B5830cB2Cfb401A" --include="*.yml" --include="*.sh" --include="*.js" .
```

ต้องเจอเฉพาะในไฟล์ที่ถูก mark DEAD แล้วเท่านั้น ถ้ายังเจอในสคริปต์ที่รันได้ → ลบทิ้งก่อน

**ไฟล์ที่ประกาศตายแล้ว ห้ามรัน:**
- `infrastructure/chain-regenesis-4v.yml`
- `infrastructure/chain-reset-fixed.yml`
- `infrastructure/scripts/path3-regenesis.sh`
- `infrastructure/re-genesis.sh`

### 0.4 สำรองของจริง

```bash
STAMP=$(date +%Y%m%d-%H%M)
sudo tar czf ~/tpix-backup-$STAMP.tgz \
  /home/admin/tpix-infrastructure/genesis.json \
  /home/admin/tpix-infrastructure/docker-compose.yml \
  /home/admin/tpix-infrastructure/data
sudo chown $USER ~/tpix-backup-$STAMP.tgz
sha256sum ~/tpix-backup-$STAMP.tgz
```

> ⚠️ ไฟล์นี้มี **private key ของ validator ทั้ง 4 ตัวแบบไม่เข้ารหัส** (`secrets init --insecure`)
> ห้ามอัปขึ้น cloud storage / Google Drive / แชท เก็บออฟไลน์เท่านั้น
> ถ้าจะเก็บไว้ที่อื่น เข้ารหัสก่อน: `gpg -c ~/tpix-backup-$STAMP.tgz`

**เก็บ genesis ตัวที่ใช้งานจริงเข้า repo ด้วย** — ตอนนี้ใน repo ไม่มีสำเนาเลย ทั้ง `genesis.json`
และ `genesis.json.pre-regenesis…` ต่างก็เป็นตัวที่ validator ว่าง (82 ตัวอักษร):

```bash
sudo cp /home/admin/tpix-infrastructure/genesis.json \
        ~/TPIX-Coin/infrastructure/chain/genesis.LIVE-2026-08-05.json
python3 ~/TPIX-Coin/infrastructure/scripts/genesis-verify.py \
        ~/TPIX-Coin/infrastructure/chain/genesis.LIVE-2026-08-05.json --validators 4
# ต้องได้ extraData ~666 ตัวอักษร = ยืนยันว่านี่คือตัวที่ใช้งานได้จริง
```

### ✅ เกณฑ์ผ่าน Phase 0

- [ ] ตัดสินใจแล้วว่าจะทำทาง A / B / C และบันทึกเหตุผลไว้
- [ ] decrypt กระเป๋าคลังสำเร็จครบ 6 ใบ
- [ ] `grep` ไม่เจอที่อยู่ชุดเก่าในสคริปต์ที่รันได้
- [ ] มี backup + sha256 + เก็บ genesis ตัวเป็นๆ เข้า repo แล้ว

---

## Phase 1 — พิสูจน์ใน LAB (ไม่แตะ production, พังได้ไม่จำกัด)

รันบนโน้ตบุ๊กหรือ VPS ตัวทิ้งก็ได้ ขอแค่มี docker

```bash
cd ~/TPIX-Coin/infrastructure
sed -i 's/\r$//' scripts/*.sh lab/*.sh oracle/*.sh    # กันปัญหา CRLF จาก Windows
chmod +x scripts/build-genesis.sh lab/run-lab.sh oracle/bootstrap-node.sh
bash lab/run-lab.sh
```

สคริปต์จะ: ล้างของเก่า → สร้างคีย์ 4 ชุด → สร้าง genesis → **verify 19 ข้อ** → สตาร์ท → รอบล็อกเดิน

**ผลที่ต้องได้:**

```
════════════════════ ผลลัพธ์: สำเร็จ ════════════════════
  ความสูงครั้งแรก : 7
  อีก 12 วินาที   : 13  (+6 บล็อก)
```

ถ้ายังค้างที่ 0 ทั้งที่ verify ผ่าน → สคริปต์จะพิมพ์ extraData + log + peer count ให้แล้ว ลองตามลำดับ:
1. เปลี่ยน `POLYGON_EDGE_IMAGE` ใน `alloc.env` เป็น `0xpolygon/polygon-edge:0.10.0` → รัน lab ใหม่
2. `--log-level DEBUG` แล้วหาบรรทัดที่มี `ibft`
3. ลดเหลือ validator เดียว เพื่อแยกว่าเป็นปัญหา consensus หรือ networking

### ✅ เกณฑ์ผ่าน Phase 1
- [ ] lab ผลิตบล็อกต่อเนื่อง (สูงเพิ่มขึ้นจริงในรอบที่สอง)
- [ ] `./run-lab.sh --down` เก็บกวาดเรียบร้อย

> **ห้ามข้าม Phase 1** ต่อให้มั่นใจแค่ไหน — รอบก่อนที่พัง 8 ครั้งคือรอบที่ข้ามขั้นนี้

---

## Phase 2 — สร้าง VPS

### 2.1 Oracle Cloud (Always Free)

| ค่า | ที่ต้องใช้ |
|---|---|
| Shape | `VM.Standard.A1.Flex` (Ampere ARM) |
| ต่อเครื่อง | 1 OCPU / 6 GB |
| จำนวน | 4 เครื่อง (โควต้าฟรีรวม 4 OCPU / 24 GB พอดี) |
| Boot volume | 50 GB × 4 = 200 GB **เต็มโควต้าพอดี ไม่เหลือ** |
| Image | Ubuntu 22.04 (ARM) หรือ Oracle Linux 9 |

ยืนยันแล้วว่า `0xpolygon/polygon-edge:0.9.0` มี manifest ทั้ง `linux/amd64` และ `linux/arm64`
→ Ampere A1 รันได้เลย ไม่ต้อง build เอง

**ข้อจำกัดที่หลีกไม่ได้**: Always Free ผูกกับ **home region เดียว** ที่เลือกตอนสมัคร เปลี่ยนไม่ได้
→ Phase 2 นี้จึงเป็นการแยก "คนละเครื่อง" ยังไม่ใช่ "คนละทวีป" ซึ่งแก้ปัญหาหลัก
(เครื่องเดียวดับ = เชนดับ) ได้แล้ว ส่วนการกระจายทวีปอยู่ใน Phase 6

**ถ้าเจอ "Out of host capacity"** — พบบ่อยมากกับ A1 ให้วนขอทุก 5 นาที:

```bash
while ! oci compute instance launch --from-json file://instance.json 2>/dev/null; do
  echo "$(date +%H:%M) เต็ม — รอ 5 นาที"; sleep 300
done
```

**กัน instance โดนยึด**: Always Free ที่ CPU ต่ำกว่า 10% ติดกัน 7 วันจะถูก reclaim
→ อัปเกรดบัญชีเป็น Pay As You Go ทรัพยากร Always Free ยังฟรีเหมือนเดิมแต่ไม่โดนยึด

### 2.2 ไฟร์วอลล์ชั้นที่ 1 (OCI Console — ต้องทำด้วยมือ)

Networking → VCN → Security Lists (หรือ NSG ที่ผูกกับ instance) → Add Ingress Rules

| Source | Protocol | Dest Port | หมายเหตุ |
|---|---|---|---|
| `<IP โหนดที่ 1>/32` | TCP | 10001 | ทำซ้ำทีละโหนด |
| `<IP โหนดที่ 2>/32` | TCP | 10001 | |
| `<IP โหนดที่ 3>/32` | TCP | 10001 | |
| `<IP โหนดที่ 4>/32` | TCP | 10001 | |

**ห้าม** ใช้ `0.0.0.0/0` และ **ห้าม** เปิด 8545 หรือ 10000 ออกเน็ตเด็ดขาด
(10000 คือ gRPC แอดมิน สั่งเพิ่ม-ถอด validator ได้)

### 2.3 ไฟร์วอลล์ชั้นที่ 2 + ติดตั้ง (ทำบนแต่ละเครื่อง)

```bash
curl -fsSL https://raw.githubusercontent.com/xjanova/TPIX-Coin/main/infrastructure/oracle/bootstrap-node.sh \
  -o bootstrap-node.sh
sudo bash bootstrap-node.sh --index 1 --peers "IP2,IP3,IP4"
```

ทำครบทั้ง 4 เครื่อง (เปลี่ยน `--index` และรายการ `--peers` ให้ตรง) แล้ว **จดค่า `PUBLIC_IP` ที่มันพิมพ์ออกมา**

### ✅ เกณฑ์ผ่าน Phase 2
- [ ] VPS 4 เครื่อง ping ถึงกัน
- [ ] `nc -zv <ip-เพื่อน> 10001` เปิดถึงกันครบทุกคู่
- [ ] `nc -zv <ip-เพื่อน> 8545` **ต้องต่อไม่ได้** (ถ้าต่อได้ = ไฟร์วอลล์รั่ว หยุดแก้ก่อน)
- [ ] `docker --version` ขึ้นครบ 4 เครื่อง

---

## Phase 3 — สร้าง genesis จริง

ทำจาก **เครื่องคุมกลาง** เครื่องเดียว (โน้ตบุ๊กคุณ) ไม่ใช่บน VPS

```bash
cd ~/TPIX-Coin/infrastructure

# ถ้าเลือกทาง A ใน Phase 0 — เติมยอดผู้ถือเดิมลง alloc.env ให้เรียบร้อยก่อนขั้นนี้
#   แล้วลดยอดกระเป๋าคลังลงเท่ากัน ให้รวมยังเป็น 7,000,000,000 พอดี

bash scripts/build-genesis.sh \
  --out chain/genesis.NEW.json \
  --keys-dir chain/keys \
  --node-ips "IP1,IP2,IP3,IP4"
```

จะมีจังหวะให้ยืนยันตารางจัดสรรด้วยการพิมพ์ `YES` — **อ่านตารางทีละบรรทัดจริงๆ ตรงนี้**
หลังจากนี้แก้ไม่ได้แล้ว

ผลลัพธ์ที่ต้องเห็น:
```
ผลรวม: ผ่านครบ 19 ข้อ — genesis พร้อมใช้
  sha256  : a1b2c3…
```

ถ้า verify ไม่ผ่าน สคริปต์จะเก็บไฟล์ที่ถูกปฏิเสธไว้ที่ `/tmp/genesis.REJECTED.json` และ **ไม่เขียนไฟล์ปลายทาง**

### ✅ เกณฑ์ผ่าน Phase 3
- [ ] `genesis-verify.py` ผ่าน 19/19
- [ ] extraData ยาว ~666 ตัวอักษร (ไม่ใช่ 82)
- [ ] bootnodes เป็น IP สาธารณะจริงทั้ง 4 ตัว
- [ ] จด sha256 ไว้

---

## Phase 4 — กระจายไฟล์ + สตาร์ท

```bash
IPS=(IP1 IP2 IP3 IP4)
for i in 1 2 3 4; do
  H="ubuntu@${IPS[$((i-1))]}"
  scp infrastructure/oracle/docker-compose.node.yml "$H:/tmp/dc.yml"
  scp infrastructure/chain/genesis.NEW.json        "$H:/tmp/genesis.json"
  scp -r infrastructure/chain/keys/validator-$i/consensus "$H:/tmp/consensus"
  scp -r infrastructure/chain/keys/validator-$i/libp2p    "$H:/tmp/libp2p"

  ssh "$H" "sudo mv /tmp/dc.yml /opt/tpix-node/docker-compose.yml
            sudo mv /tmp/genesis.json /opt/tpix-node/genesis.json
            sudo mv /tmp/consensus /tmp/libp2p /opt/tpix-node/data/
            sudo chmod 700 /opt/tpix-node/data/consensus
            sudo chmod 600 /opt/tpix-node/data/consensus/*
            sudo sha256sum /opt/tpix-node/genesis.json"
done
```

**sha256 ต้องตรงกันเป๊ะทั้ง 4 เครื่อง และตรงกับที่ Phase 3 พิมพ์ออกมา** ถ้าต่างแม้ตัวเดียว หยุดแล้วส่งใหม่

สตาร์ทตามลำดับ โหนดที่ 1 ก่อน แล้วรอ 15 วินาทีค่อยตัวถัดไป:

```bash
for i in 1 2 3 4; do
  ssh "ubuntu@${IPS[$((i-1))]}" "cd /opt/tpix-node && sudo docker compose up -d"
  sleep 15
done
```

### ตรวจผล

```bash
ssh ubuntu@IP1 "curl -s -X POST -H 'Content-Type: application/json' \
  --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' \
  http://127.0.0.1:8545"
```

- ภายใน 60 วินาที ต้องได้ค่ามากกว่า `0x0`
- `net_peerCount` ต้องได้ `0x3` ทุกโหนด
- ถ้าค้าง `0x0` → **อย่าลองสุ่มแก้** ให้ทำตามลำดับใน Phase 1 บน lab ก่อน แล้วค่อยกลับมา

### ✅ เกณฑ์ผ่าน Phase 4
- [ ] ทั้ง 4 โหนดความสูงเท่ากัน (ต่างกันไม่เกิน 2 บล็อก)
- [ ] ลองปิดโหนด 1 ตัว → เชนยังเดิน (นี่คือข้อพิสูจน์ว่าเลิกเป็น single point of failure แล้ว)
- [ ] เปิดกลับมา → sync ตามทันภายใน 1 นาที

---

## Phase 5 — ชั้น RPC + บริการรอบข้าง

**อย่าเอา RPC สาธารณะไปไว้บน validator** ให้แยกโหนด:

```bash
sudo bash bootstrap-node.sh --index 5 --peers "IP1,IP2,IP3,IP4" --rpc-only
```

โหนด `--rpc-only` ไม่มี `--seal` และไม่มีคีย์ validator → ไม่มีอะไรให้ขโมย และพังกี่ตัวก็ไม่กระทบ consensus

จากนั้น:
1. nginx (`infrastructure/nginx-rpc.conf`) เปลี่ยน `upstream` ให้ชี้โหนด RPC ตัวใหม่ — **แก้ตามหัวข้อ N1–N4 ใน `docs/SECURITY-AUDIT-2026-08-05.md` ก่อน**
2. Cloudflare SSL mode → **Full (strict)** + origin certificate (ตอนนี้ origin เป็น `listen 80` เปล่าๆ)
3. Cloudflare firewall → อนุญาตเฉพาะ IP ของ Cloudflare เข้า origin
4. Blockscout — DB ต้องล้างใหม่หมด เพราะเชนใหม่ genesis hash คนละตัว
5. `chain-watchdog.sh` — ตอนนี้เขียนมาสำหรับ 4 validator บนเครื่องเดียว ต้องแก้เป็นเช็คข้ามเครื่อง

---

## Phase 6 — กระจายทวีป (หลังทุกอย่างนิ่งแล้ว)

Oracle ฟรีให้ region เดียว ถ้าจะข้ามทวีปจริงต้องผสมผู้ให้บริการ และ **โควต้าความเสี่ยงมีจำกัด**:

IBFT 4 validator → quorum 3 → ทนพังพร้อมกันได้ **1 ตัว**
บัญชี Oracle ถูกปิด = โหนดทุกตัวในบัญชีนั้นดับพร้อมกัน (correlated failure)
→ **Oracle ถือ validator ได้ไม่เกิน 1 ตัว** ถ้าอยากได้ 2 ต้องขยายชุดเป็น 7 ก่อน (quorum 5, ทนพัง 2)

ลำดับที่ปลอดภัย:
1. เพิ่ม validator ทีละตัวด้วย `polygon-edge ibft propose --addr X --bls Y --vote auth` จากโหนดที่เป็น majority
   (ต้องใส่ BLS pubkey ด้วย เพราะ `validator_type = bls`) — **ซ้อมใน lab ก่อนทุกครั้ง**
2. ค่อยย้ายตัวใหม่ไปทวีปอื่น
3. ห้ามให้ validator ห่างกันเกิน ~150 ms RTT — IBFT ต้องแลกข้อความ 3 เฟสต่อบล็อก
   ที่ block time 2 วินาที กรุงเทพ↔แฟรงก์เฟิร์ต (~250 ms) จะเริ่มเจอ round-change ถี่
4. ส่วน **RPC full node** กระจายได้เต็มที่ทุกทวีป ไม่มีความเสี่ยงต่อ consensus — ผู้ใช้ทั่วโลกได้ latency
   ดีขึ้นจากชั้นนี้ ไม่ใช่จากการที่ validator อยู่ใกล้

---

## Phase 7 — deploy สัญญาใหม่

เชนใหม่ = สัญญาเดิมหายหมด ต้อง deploy ใหม่ตามลำดับ:

```bash
cd contracts
npx hardhat test                       # ต้องผ่าน 78/78 ก่อน
node scripts/deploy-wtpix.js           # 1. WTPIX wrapper
node scripts/deploy-bonding-curve.js   # 2. USDT_TPIX + BondingCurve
node scripts/deploy-dex.js             # 3. AMM Factory/Pair/Router02
```

แล้วอัปเดตที่อยู่สัญญาใน:
- `ThaiXTrade/resources/js/Config/launchContracts.js`
- `ThaiXTrade` ฝั่ง DEX config
- `wallet/` (Flutter) — token list + RPC
- `masternode-ui/` — RPC endpoint

---

## แผนถอย (rollback)

ทุก phase ถอยได้ เพราะเชนเดิมยัง **ไม่ถูกแตะ** จนกว่าจะถึงขั้นสลับ DNS

```bash
# เชนเดิมยังอยู่ที่เครื่องเดิม สั่งกลับมาเดินได้ทันที
cd /home/admin/tpix-infrastructure
sudo docker compose -f docker-compose.yml up -d
sudo docker compose -f docker-compose-explorer.yml up -d
```

แล้วชี้ `rpc.tpix.online` กลับที่เดิมใน Cloudflare

**หลักการ**: อย่าปิดเชนเดิมจนกว่าเชนใหม่จะเดินครบ 24 ชั่วโมงโดยไม่สะดุด
ค่า VPS 4 ตัวเป็นศูนย์อยู่แล้ว ไม่มีเหตุผลต้องรีบปิดของเก่า

---

## ทางเลือก C — ย้ายโดยไม่ regenesis

ถ้า Phase 0.1 สรุปว่ายอดลูกค้าเยอะเกินกว่าจะล้าง ให้ยกเชนเดิมตามไปเลย ประวัติ 2.7M บล็อกอยู่ครบ:

1. ทำ Phase 2 (สร้าง VPS) ตามปกติ
2. **ห้าม** สร้าง genesis ใหม่ — ใช้ `genesis.LIVE-2026-08-05.json` ที่สำรองไว้ใน Phase 0.4
3. แก้เฉพาะ `bootnodes` ให้เป็น IP สาธารณะ (ฟิลด์ `bootnodes` อยู่นอก object `genesis`
   จึงไม่กระทบ genesis hash — ยืนยันด้วยการเทียบ genesis hash หลังสตาร์ท)
4. ย้ายทีละโหนด เชนยังเดินด้วย 3/4 ตลอด:
   ```
   หยุด validator-N ตัวเก่า
   → rsync data dir ทั้งก้อน (blockchain/ + trie/ + consensus/ + libp2p/) ไป VPS
   → แก้ bootnodes ทุกโหนด → เพิ่ม --nat <public-ip> → สตาร์ท
   → รอ peer ครบ → ค่อยทำตัวถัดไป
   ```
5. **ห้ามรันคีย์ validator ตัวเดียวกันสองเครื่องพร้อมกัน** (double-sign)

ข้อดี: ไม่มีใครเสียเหรียญ · ข้อเสีย: ยอดจัดสรรที่ผิดกับกระเป๋า `0x3F8E…401A` ที่คีย์หาย ยังค้างอยู่เหมือนเดิม

---

## สรุปลำดับสั้นๆ

```
Phase 0  ตัดสินใจเรื่องยอดลูกค้า + พิสูจน์คีย์ + backup      ← ด่านสำคัญที่สุด
Phase 1  bash lab/run-lab.sh                              ← ต้องเห็นบล็อกเดินก่อน
Phase 2  สร้าง VPS 4 ตัว + ไฟร์วอลล์สองชั้น
Phase 3  bash scripts/build-genesis.sh --node-ips …       ← verify 19/19
Phase 4  scp + docker compose up -d + ทดสอบดับ 1 ตัว
Phase 5  แยกโหนด RPC + แก้ nginx ตาม SECURITY-AUDIT
Phase 6  ขยายเป็น 7 validator แล้วค่อยกระจายทวีป
Phase 7  deploy สัญญา + อัปเดต frontend
```
