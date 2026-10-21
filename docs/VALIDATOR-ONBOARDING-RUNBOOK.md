# Runbook — จาก "stake ชั้น Validator" ถึง "ปิดบล็อก TPIX ได้จริง"

> เขียน 2026-10-22 · ยืนยันกับเชนจริง (polygon-edge 0.9.0, chainId 4289, IBFT PoA, `validator_type: bls`, epochSize 100,000)
> ไม่ต้องแก้สัญญา ไม่ต้อง regenesis

## 0. ภาพรวม — 7 ขั้น ใครทำอะไร

| # | ขั้น | ใคร | ที่ไหน |
|---|---|---|---|
| 1 | ให้ความยินยอม PDPA (`giveConsent`) | ผู้สมัคร (กระเป๋าตัวเอง) | tpix.online/masternode |
| 2 | ยื่น KYC ของเว็บ → ทีมอนุมัติ | ผู้สมัคร / ทีม | tpix.online/kyc · /admin/kyc |
| 3 | บันทึก hash เอกสาร + อนุมัติบนสัญญา ValidatorKYC | ทีม (**กระเป๋า owner ในเบราว์เซอร์**) | /admin/validators/kyc |
| 4 | stake 10M TPIX ชั้น Validator | ผู้สมัคร | โปรแกรม TPIX Master Node หรือเว็บ |
| 5 | รันโหนด `--seal` ให้ซิงก์ถึงบล็อกล่าสุด + เป็นเพียร์กับเครือข่าย | ผู้สมัคร | เซิร์ฟเวอร์ Linux ของผู้สมัคร |
| 6 | ผูกกุญแจ validator กับกระเป๋าที่ stake (เซ็น 2 ใบ) | ผู้สมัคร | เซิร์ฟเวอร์ (กุญแจ validator) + โปรแกรม (กระเป๋า) |
| 7 | โหวตเข้า (`ibft propose … --vote auth`) | **เจ้าของเชน** | เครื่องเชน 123.253.62.252 |

หลังจากนั้นตลอดอายุ: ตัวเฝ้าดู `validators:seal-monitor` (เว็บ) นับรายตัวว่าใครเสนอ/เซ็นรับรองบล็อก
ถอน stake / ถูก slash / ดับนาน → **เจ้าของต้องโหวตถอดเอง** (ไม่มีอะไรถอดให้อัตโนมัติ)

ขั้น 5 ขึ้นกับ public bootnode ([MASTERNODE_PUBLIC_BOOTNODE.md](MASTERNODE_PUBLIC_BOOTNODE.md)) — ตอนนี้ libp2p
ของ validator ไม่ได้เปิดออกเน็ต โหนดภายนอกจึงยังซิงก์ไม่ได้ ต้องเสร็จก่อนโหวตตัวแรกเข้า

---

## 1. ความเสี่ยงที่ต้องรู้ก่อนเพิ่มตัวไหนก็ตาม

polygon-edge 0.9 (`OptimalQuorumSize`): ปิดบล็อกต้องเห็นพ้อง `ceil(2N/3)` ตัว (ต่ำกว่า 4 ตัวต้องครบทุกตัว)
โหวตเพิ่ม/ถอดต้องได้เสียง `floor(N/2)+1`

| N | ต้องเห็นพ้อง | ทนดับได้ | โหวตต้องได้ |
|---|---|---|---|
| 4 (วันนี้) | 3 | 1 | 3 |
| 5 | 4 | 1 | 3 |
| 6 | 4 | 2 | 4 |
| 7 | 5 | 2 | 4 |

- **4 → 5 ไม่ได้ทนขึ้น** ตัวที่ 5 ดับ = ตัวเดิม 4 ตัวต้องอยู่ครบ ดับอีกตัวเดียวเชนหยุด → เพิ่มทีละ 2 ดีกว่า
- validator ที่ดับยังได้คิวเสนอบล็อก ทุกครั้งที่ถึงคิวบล็อกช้า 10+ วินาที (เหตุ 5 ส.ค. 2026)
- คะแนนโหวตที่ยังไม่ครบถูกล้างทุก epoch (100,000 บล็อก ≈ 55 ชม.)
- ช่องสั่งโหวต (gRPC) ไม่มีการยืนยันตัวตน — ต้องอยู่แค่ในเครื่องเชน ห้ามเปิดออกเน็ต

---

## 2. ผู้สมัคร: รันโหนด validator (ขั้น 5)

ใช้ image เดียวกับเชนหลัก `0xpolygon/polygon-edge:0.9.0` และธงชุดเดียวกับ validator หลัก
(`infrastructure/single-host/docker-compose.yml`) ยกเว้นพอร์ตที่ต้องเปิด:

```bash
mkdir -p /opt/tpix-node/data && cd /opt/tpix-node
# genesis ต้องเป็นไฟล์เดียวกับเชนจริง (มี bootnode สาธารณะอยู่ในไฟล์ — polygon-edge 0.9 ไม่มีธง --bootnode)
docker run --rm -v /opt/tpix-node/data:/data 0xpolygon/polygon-edge:0.9.0 secrets init --insecure --data-dir /data
docker run -d --name tpix-node --restart always \
  -v /opt/tpix-node/data:/data -v /opt/tpix-node/genesis.json:/genesis.json:ro \
  -p 10001:10001 -p 127.0.0.1:8545:8545 \
  0xpolygon/polygon-edge:0.9.0 server --data-dir /data --chain /genesis.json \
    --grpc-address 127.0.0.1:10000 --libp2p 0.0.0.0:10001 --jsonrpc 0.0.0.0:8545 \
    --seal --price-limit 0 --max-slots 4096 --max-enqueued 16 --block-gas-target 10000000
```

- `--seal` ต้องมีตั้งแต่แรก — ก่อนถูกโหวตเข้ามันแค่ซิงก์ หลังโหวตเข้าเริ่มเซ็นทันที
- `secrets init` สร้าง `consensus/validator.key` (ECDSA) + `consensus/validator-bls.key` + `libp2p/libp2p.key`
  **สำรองโฟลเดอร์ data ไว้นอกเครื่อง** — กุญแจหาย = ต้องโหวตถอดแล้วผูกกุญแจใหม่
- ตรวจว่าซิงก์ทัน: `curl -s 127.0.0.1:8545 -H 'content-type: application/json' -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'`
  เทียบกับ https://explorer.tpix.online

## 3. ผู้สมัคร: ผูกกุญแจ (ขั้น 6)

ลายเซ็น 2 ใบบนข้อความเดียวกัน — เว็บตรวจทั้งคู่ (ThaiXTrade `ValidatorKeyBindingService`)

1. **บนเซิร์ฟเวอร์โหนด** (กุญแจ validator ไม่ออกจากเครื่อง — Python 3 อย่างเดียว ไม่ต้องติดตั้งอะไร):
   ```bash
   sudo python3 validator_sign_binding.py --staking-wallet 0x<กระเป๋าที่stake> \
     --data-dir /opt/tpix-node/data --edge "docker exec tpix-node polygon-edge" --edge-data-dir /data
   ```
   ได้ JSON หนึ่งบรรทัด (ที่อยู่ validator + BLS + node ID + ลายเซ็นของกุญแจ validator)
   สคริปต์อยู่ที่ `infrastructure/validator/validator_sign_binding.py`
2. **ในโปรแกรม TPIX Master Node** → แท็บ Validator → "โหนดอยู่บนเซิร์ฟเวอร์" → วาง JSON → ใส่รหัสผ่านกระเป๋า
   โปรแกรมตรวจลายเซ็นของกุญแจ validator ก่อน แล้วเซ็นด้วยกระเป๋าที่ stake และส่งเข้าเว็บ — ทำภายใน 30 นาที
   (ถ้าโปรแกรมรันโหนดเองในเครื่อง ใช้ปุ่ม "ใช้กุญแจของเครื่องนี้" แทนได้ ไม่ต้องใช้สคริปต์)

เว็บปฏิเสธเมื่อ: ลายเซ็นไม่ครบ/ไม่ตรง · เกิน 30 นาที · กระเป๋าไม่มีโหนด Validator ที่ active ·
ที่อยู่/BLS เป็นของ validator ที่ปิดบล็อกอยู่แล้ว · กุญแจผูกกับกระเป๋าอื่นแล้ว · กุญแจเดิมยังปิดบล็อกอยู่ (ต้องถอดก่อนเปลี่ยน)

## 4. เจ้าของ: โหวตเข้า (ขั้น 7)

หน้า /admin/validators → แท็บ "ผูกกุญแจ / รอโหวต" แสดงคำสั่งพร้อมคัดลอก แล้วบนเครื่องเชน:

```bash
ssh tpixadmin@123.253.62.252
cd ~/TPIX-Coin && git pull
# 1) ซ้อม — ตรวจชุดปัจจุบัน / เชนเดิน / โหนดใหม่เป็นเพียร์ / BLS ไม่ซ้ำ ไม่ส่งอะไร
sudo bash infrastructure/single-host/validator-vote.sh auth --addr 0x… --bls 0x… --node-id 16Uiu2…
# 2) ทำจริง — โหวตบน validator ทุกตัวในเครื่อง แล้วรอจนเห็นใน ibft snapshot
sudo bash infrastructure/single-host/validator-vote.sh auth --addr 0x… --bls 0x… --node-id 16Uiu2… --yes
```

ภายใน 1–2 นาทีหน้า /admin/validators ต้องเห็นตัวใหม่ "เซ็น %" ขึ้นจาก 0 — ถ้าค้าง 0 เกิน 5 นาที
ขึ้นคาดแดงเอง และควรโหวตถอดทันที (มันกินตัวสำรองของเชนไปแล้ว)

**สั่งเองทีละตัว (สำรอง)** — ค่าเริ่มต้นของ `--grpc-address` คือ 9632 ซึ่งผิด ต้องระบุเสมอ:
```bash
for i in 1 2 3 4; do sudo docker exec tpix-validator-$i polygon-edge ibft propose \
  --addr 0x… --bls 0x… --vote auth --grpc-address 127.0.0.1:10000; done
sudo docker exec tpix-validator-1 polygon-edge ibft snapshot --grpc-address 127.0.0.1:10000
```

## 5. ถอดออก

เมื่อ: ถอน stake (deregister) · ถูก slash · ดับเกิน 30 นาที · กุญแจรั่ว · ผู้ให้บริการขอออก
หน้า /admin/validators ขึ้น "ต้องโหวตถอด" + คาดแดงเมื่อ stake ไม่ active แต่ยังปิดบล็อกอยู่

```bash
sudo bash infrastructure/single-host/validator-vote.sh drop --addr 0x…          # ซ้อม
sudo bash infrastructure/single-host/validator-vote.sh drop --addr 0x… --yes    # จริง (ไม่ต้องใช้ BLS)
```

สคริปต์ไม่ยอมถอดจนเหลือต่ำกว่า 4 ตัว (ต้อง `--allow-small-set`) — 3 ตัวต้องอยู่ครบทุกตัว

## 6. ดูสถานะ / แก้ปัญหา

```bash
sudo bash infrastructure/single-host/validator-vote.sh status   # ชุด + เกณฑ์ + candidates ของแต่ละตัว
```

| อาการ | สาเหตุ / ทางแก้ |
|---|---|
| `ไม่ได้ต่อกับ validator หรือ bootnode` | โหนดใหม่ต่อเครือข่ายไม่ได้ (ไฟร์วอลล์/genesis) — ห้ามข้ามด้วย `--skip-peer-check` ถ้าไม่แน่ใจ |
| `ต่ออยู่กับ tpix-bootnode แต่ยังไม่เป็นเพียร์ตรงกับ validator` | validator หลักอยู่หลัง docker bridge โหนดภายนอกอาจเห็นแค่ bootnode — ไปต่อได้ แต่หลังโหวตต้องเห็น "เซ็น %" ขึ้นใน 5 นาที |
| โหวตแล้วไม่เข้าชุด | ดู `status` ว่า candidates ยังค้างไหม · ครบเสียงเมื่อ validator แต่ละตัวได้คิวเสนอ · ข้าม epoch = ถูกล้าง โหวตใหม่ |
| `เชนไม่เดิน` | ห้ามเปลี่ยนชุดตอนเชนค้าง — ดู chain-watchdog / REGENESIS-RUNBOOK ก่อน |
| ตัวใหม่เซ็น 0% | BLS ที่ผูกไม่ตรงกับกุญแจจริง หรือโหนดหลุด — ถอด แล้วให้ผู้สมัครผูกใหม่ |

## 7. ที่มาของแต่ละชิ้น

| ชิ้น | repo / ไฟล์ |
|---|---|
| หน้า KYC แอดมิน (กระเป๋า owner เซ็นในเบราว์เซอร์) | ThaiXTrade `Admin/Validators/Kyc.vue`, `ValidatorKycAdminController` |
| API ผูกกุญแจ + ตรวจลายเซ็น 2 ใบ | ThaiXTrade `POST /api/v1/validators/key-binding`, `ValidatorKeyBindingService` |
| ตัวเฝ้าดูการปิดบล็อกรายตัว | ThaiXTrade `validators:seal-monitor` (`SealMonitor`, `IbftExtraDecoder`) |
| สคริปต์โหวต | TPIX-Coin `infrastructure/single-host/validator-vote.sh` (+ `tests/validator-vote.test.sh`) |
| ตัวช่วยเซ็นฝั่งกุญแจ validator | TPIX-Coin `infrastructure/validator/validator_sign_binding.py` (+ เทสต์) |
| แผงกุญแจ validator ในแอป | TPIX-Masternode `electron/validator-binding.js` |

ข้อเท็จจริงทางเทคนิคที่ใช้ (ยืนยันกับบล็อกจริง 2026-10-22):
- extraData = vanity 32 ไบต์ + RLP `[validators[[addr,bls]], proposerSeal, [bitmap, sig], [bitmap, sig], round]`
- ผู้เสนอ = `ecrecover(keccak256(blockHash), proposerSeal)` · คิวถัดไป = ลำดับผู้เสนอก่อนหน้า + round + 1
- RPC `ibft_*` ทุกเมธอดตอบ -32601 บน 0.9 — ใช้ extraData หรือ gRPC เท่านั้น
