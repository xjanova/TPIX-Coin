# TPIX Chain — Single-host production (123.253.62.252)

ไฟล์ต้นฉบับของ `/opt/tpix/docker-compose.yml` บนเซิร์ฟเวอร์เชน — แก้ที่นี่ commit แล้วค่อยเอาขึ้น อย่าแก้สดบนเซิร์ฟเวอร์ (จะ drift)

## ไฟล์

| ไฟล์ | หน้าที่ |
|---|---|
| `docker-compose.yml` | validator 4 ตัว + Blockscout พร้อม Go runtime tuning กัน IBFT stall |
| `apply-rolling.sh` | recreate validator ทีละตัวรักษา quorum — เชนไม่หยุดระหว่างอัปเดต |

## ชั้นป้องกัน stall (เรียงจากเร็วไปช้า)

1. **Go runtime tuning** (ใน compose) — GOGC=50 + GOMEMLIMIT ลดโอกาส GC pause ยาวจน proposer พลาดรอบ ซึ่งเป็นจุดสตาร์ทของ round escalation
2. **Docker healthcheck ทุก validator** — container ตายจริงถูก restart โดย docker เอง
3. **Watchdog cron ทุก 1 นาที** (`../scripts/chain-watchdog.sh`) — จับ "container ยังขึ้นแต่บล็อกไม่ขยับ" (round escalation) แล้ว restart ทั้งวงให้เอง + ยิง heartbeat/alert เข้าหลังบ้าน tpix.online · เทียบหัวเชน/hash ของ validator ทั้ง 4 ทุกนาทีด้วย — ตัวที่แยกเชน (`validator_forked`) หรือตามไม่ทัน (`validator_lagging`) **แจ้งเตือนอย่างเดียว ไม่ restart และไม่กินโควตา restart** เพราะ fork ไม่หายด้วย restart (ดูหัวข้อถัดไป)
4. **หลังบ้าน tpix.online** — ถ้า heartbeat ขาดเกิน 3 นาที (ทั้งเครื่องดับ) ระบบฝั่งเว็บขึ้นคาดแดงเอง เพราะเป็นคนละเครื่องกัน

## validator แยกเชน (fork) — ซ่อมมือ

เกิดจริง 2026-09-26: VM ดับกะทันหัน validator-1/2/4 เสียบล็อกท้ายที่ยังไม่ลงดิสก์แล้วออกบล็อกใหม่ทับ ส่วน validator-3 ยังถือชุดเก่า → ค้าง `unable to verify block` ถาวรทั้งที่ container healthy และเห็น peer ครบ เชนเหลือ 3/4 (~6 วิ/บล็อก เพราะ IBFT หมดรอบทุกครั้งที่ถึงคิวตัวเสีย) · restart ทั้งวงไม่ช่วย

ข้อความ `validator_forked` บอกชื่อตัวเสีย ตัวต้นแบบ และ path จริงให้แล้ว — ขั้นตอน (ตัวอย่าง: เสีย = 3, ต้นแบบ = 4):

1. ถือคิวบำรุงรักษาตลอดงาน: `sudo flock /run/tpix-chain-maint.lock bash` แล้วทำทุกขั้นในเชลล์นี้ (watchdog/backup จะข้ามรอบ ไม่ restart ทับ)
2. `docker stop tpix-validator-3 tpix-validator-4` — ต้นแบบต้องหยุดด้วย เพราะ LevelDB ที่คัดลอกขณะเปิดอยู่ไม่สอดคล้องกัน · เชนหยุดตั้งแต่ขั้นนี้
3. ย้าย `/opt/tpix/chain/data/validator-3/{blockchain,trie}` ไปเก็บ (เช่น `validator-3/forked-<วันเวลา>/`)
4. `cp -a` `blockchain`, `trie`, `consensus/metadata`, `consensus/snapshots` จาก `validator-4/` ไปไว้ใน `validator-3/` — **ห้ามทับ** คีย์ validator ใน `consensus/` และ `libp2p/` ของ validator-3
5. `docker start tpix-validator-4` แล้วค่อย `docker start tpix-validator-3` → เชนเดินต่อเองเมื่อครบ 4 (ครั้งจริงหยุด 114 วิ) แล้วออกจากเชลล์ flock

ถ้าข้อความบอกว่า "ไม่มีฝั่งไหนครบ 3 ตัว" (เช่นแยก 2:2) ห้ามทำตามนี้จนกว่าจะเทียบ hash กับ explorer ได้ว่าฝั่งไหนเป็นเชนหลัก — ทับผิดฝั่ง = เสียบล็อกจริง

## ขยายเป็นหลายเครื่อง (อนาคต)

ออกแบบให้ยกไปใช้ต่อได้เลย:

- แยก validator ไปเครื่องใหม่ → ใช้ compose นี้ตัดเหลือ service เดียว + เปิด libp2p 10001 จำกัด source IP (ดูคอมเมนต์หัวไฟล์)
- ติด watchdog ชุดเดิมทุกเครื่อง ตั้ง `TPIX_NODE_NAME` ไม่ซ้ำกัน (เช่น `chain-2`) ใน `/etc/tpix-watchdog.env`
- หลังบ้าน tpix.online รองรับหลาย node อยู่แล้ว — heartbeat แยกตาม node, คาดแดงบอกว่าเครื่องไหนมีปัญหา ไม่ต้องแก้โค้ดฝั่งเว็บ
- `../oracle/bootstrap-node.sh` มีขั้นตอนตั้งเครื่องใหม่
