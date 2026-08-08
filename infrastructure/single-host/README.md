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
3. **Watchdog cron ทุก 1 นาที** (`../scripts/chain-watchdog.sh`) — จับ "container ยังขึ้นแต่บล็อกไม่ขยับ" (round escalation) แล้ว restart ทั้งวงให้เอง + ยิง heartbeat/alert เข้าหลังบ้าน tpix.online
4. **หลังบ้าน tpix.online** — ถ้า heartbeat ขาดเกิน 3 นาที (ทั้งเครื่องดับ) ระบบฝั่งเว็บขึ้นคาดแดงเอง เพราะเป็นคนละเครื่องกัน

## ขยายเป็นหลายเครื่อง (อนาคต)

ออกแบบให้ยกไปใช้ต่อได้เลย:

- แยก validator ไปเครื่องใหม่ → ใช้ compose นี้ตัดเหลือ service เดียว + เปิด libp2p 10001 จำกัด source IP (ดูคอมเมนต์หัวไฟล์)
- ติด watchdog ชุดเดิมทุกเครื่อง ตั้ง `TPIX_NODE_NAME` ไม่ซ้ำกัน (เช่น `chain-2`) ใน `/etc/tpix-watchdog.env`
- หลังบ้าน tpix.online รองรับหลาย node อยู่แล้ว — heartbeat แยกตาม node, คาดแดงบอกว่าเครื่องไหนมีปัญหา ไม่ต้องแก้โค้ดฝั่งเว็บ
- `../oracle/bootstrap-node.sh` มีขั้นตอนตั้งเครื่องใหม่
