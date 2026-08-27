# รันบุ๊ก — เปิดด่านกันยิงถล่มเชนค่าแก๊ส 0

> **ลำดับสำคัญมาก** ข้ามขั้นหรือสลับลำดับ = ตัดผู้ใช้ออกทั้งเว็บ หรือเชนไม่บูต
> ทุกขั้นมีคำสั่งตรวจของจริงต่อท้าย — **อย่าเชื่อว่า "ติดตั้งแล้ว" แปลว่า "ทำงาน"**
> (ตัวกรองรุ่นก่อนหน้า `nginx -t` ผ่านแล้วบล็อกทุกคำขอ ต้องคอมเมนต์ทิ้งทั้งชุด)

## ปัญหาที่กำลังแก้

เชนนี้ `--price-limit 0` เป็นจุดขาย แต่แปลว่า **ไม่มีต้นทุนต่อธุรกรรม**
ผู้ใช้จริงจึงแซงคิวสแปมด้วยการจ่ายแก๊สแพงกว่าไม่ได้ (บนเชนปกติทำได้)

| | ก่อนแก้ |
|---|---|
| เชนรับได้ | 20M gas ÷ 21,000 ÷ 2 วิ ≈ **476 tx/s** |
| IP เดียวยิงได้ | 30 r/s × batch 20 = **600 tx/s** |
| txpool | `--max-slots 4096` → เต็มใน **~7 วินาที** |
| ต่อ address | `--max-enqueued` ไม่ได้ตั้ง = 128 → **32 address กิน pool หมด** |

→ IP เดียว ต้นทุน 0 บาท ท่วม mempool ถาวร = เซ็นเซอร์ผู้ใช้จริงทั้งเชน

---

## ขั้น 0 — ตรวจว่ารุ่น polygon-edge รู้จักธงที่จะใส่ (5 วินาที)

ธงที่ไม่มีอยู่จริง = validator ไม่บูต = **เชนหยุดทั้งวง**

```bash
sudo docker run --rm 0xpolygon/polygon-edge:0.9.0 server --help \
  | grep -E 'max-enqueued|max-slots|block-gas-target|price-limit'
```

ต้องเห็นครบทั้ง 4 บรรทัด **ถ้า `max-enqueued` ไม่มี** → ตัดธงนั้นออกจาก
`single-host/docker-compose.yml` ก่อน แล้วค่อยไปขั้นถัดไป

---

## ขั้น 1 — ติดตั้งด่าน njs ที่ nginx

ตรวจก่อนว่ามีโมดูล (ต้อง njs ≥ 0.8.0 เพราะใช้ `js_shared_dict_zone`):

```bash
nginx -V 2>&1 | tr ' ' '\n' | grep -i njs ; dpkg -l | grep libnginx-mod-http-js
```

```bash
cd ~/TPIX-Coin && git pull

sudo mkdir -p /etc/nginx/njs
sudo cp infrastructure/njs/tpix-rpc.js /etc/nginx/njs/

# ⚠️ ไฟล์นี้ต้องมีก่อน ไม่งั้น geo ... include จะทำให้ nginx ไม่สตาร์ท
sudo cp infrastructure/single-host/tpix-banned.map /etc/nginx/conf.d/

# สำรองของเดิมไว้ก่อนเสมอ
sudo cp /etc/nginx/conf.d/10-tpix-http.conf{,.bak-$(date +%Y%m%d-%H%M%S)} 2>/dev/null || true
sudo cp /etc/nginx/sites-available/tpix-rpc.conf{,.bak-$(date +%Y%m%d-%H%M%S)} 2>/dev/null || true

sudo cp infrastructure/single-host/nginx-http-tpix.conf /etc/nginx/conf.d/10-tpix-http.conf
sudo cp infrastructure/single-host/nginx-rpc.conf       /etc/nginx/sites-available/tpix-rpc.conf

sudo nginx -t && sudo systemctl reload nginx
```

**ตรวจของจริงทันที:**

```bash
sudo bash infrastructure/scripts/verify-rpc-gate.sh
```

ต้องผ่านทุกข้อ ถ้าไม่ผ่าน → `sudo cp <ไฟล์ .bak ล่าสุด> กลับ && sudo systemctl reload nginx`

> ขั้นนี้ทำให้ `real_ip_header CF-Connecting-IP` เริ่มทำงาน → `$remote_addr`
> ในล็อกกลายเป็น IP ผู้ใช้จริง ไม่ใช่ IP ของ Cloudflare
> **ต้องทำก่อนขั้น 3 เสมอ** ไม่งั้น fail2ban จะแบน IP ของ Cloudflare = ตัดผู้ใช้ทั้งเว็บ

---

## ขั้น 2 — ปิดทางยิงตรงเข้า origin

ตอนนี้เดินอ้อม Cloudflare ได้จริง (พิสูจน์ 2026-08-27 ตอบ 200 พร้อมเลขบล็อก)
ตราบใดที่ยังเดินอ้อมได้ **โควตาเขียนของ njs หลบได้ทั้งดุ้น** ด้วยการปลอม
`CF-Connecting-IP` เป็นค่าอะไรก็ได้ทุกใบ

```bash
# ดูก่อนว่าจะใส่กฎอะไรบ้าง — ไม่แตะไฟร์วอลล์
bash infrastructure/scripts/allow-cloudflare-only.sh

# ลงมือจริง (เปิด 80/443 ให้เฉพาะช่วง Cloudflare + IP ที่ SSH เข้ามา)
sudo ADMIN_IP=$(echo $SSH_CLIENT | cut -d' ' -f1) \
  bash infrastructure/scripts/allow-cloudflare-only.sh --apply
```

**ตรวจจากเครื่องนอก:**

```bash
ORIGIN_IP=123.253.62.252 bash infrastructure/scripts/verify-rpc-gate.sh
```

ถ้าเว็บล่ม → `sudo ufw allow 443/tcp` กลับทันที แล้วค่อยหาสาเหตุ

---

## ขั้น 3 — ซ่อม fail2ban (ตอนนี้แบนใครไม่ได้เลย)

ของเดิม vhost เขียนล็อกลง `tpix-dbg.log` ด้วยฟอร์แมตกำหนดเอง
แต่ jail ไปเฝ้า `access.log` ด้วย regex ของฟอร์แมต combined → **ไม่เคยแมตช์เลย**

```bash
sudo cp infrastructure/fail2ban/filter.d/tpix-rpc.conf /etc/fail2ban/filter.d/
sudo cp infrastructure/fail2ban/jail.d/tpix-rpc.conf   /etc/fail2ban/jail.d/

# ต้องได้ matched มากกว่า 0 — ถ้าเป็น 0 แปลว่า regex ยังไม่ตรงกับล็อกจริง
sudo fail2ban-regex /var/log/nginx/tpix-rpc.access.log \
     /etc/fail2ban/filter.d/tpix-rpc.conf

sudo fail2ban-client reload tpix-rpc
sudo fail2ban-client status tpix-rpc     # "File list" ต้องเป็น tpix-rpc.access.log
```

> ⚠️ jail ใหม่ตัดช่วง IP ของ Cloudflare ออกจาก `ignoreip` แล้ว
> **ทำได้ก็ต่อเมื่อขั้น 1 ผ่านแล้วเท่านั้น** (real_ip ทำงาน)
> ยืนยันด้วยการดูล็อก: คอลัมน์แรกต้องเป็น IP ผู้ใช้ ไม่ใช่ 172.64.x / 104.16.x
> ```bash
> sudo tail -5 /var/log/nginx/tpix-rpc.access.log
> ```

---

## ขั้น 4 — จำกัด txpool ที่ตัวเชน (rolling ห้าม down ทั้งวง)

```bash
sudo cp /opt/tpix/docker-compose.yml /opt/tpix/docker-compose.yml.bak-$(date +%Y%m%d-%H%M%S)
sudo cp infrastructure/single-host/docker-compose.yml /opt/tpix/docker-compose.yml
sudo bash infrastructure/single-host/apply-rolling.sh
```

`apply-rolling.sh` เปลี่ยนทีละตัวและรอ healthcheck ก่อนแตะตัวถัดไป
**ห้าม `docker compose down`** — เชนจะหยุดทั้งวง

**ตรวจ:**

```bash
sudo docker logs tpix-validator-1 --tail 20      # ต้องไม่มี "unknown flag"
curl -s -X POST http://127.0.0.1:8545 -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}'    # เลขบล็อกต้องเดินต่อ
```

---

## ขั้น 5 — watchdog เฝ้าดิสก์ + สแปม

```bash
sudo cp infrastructure/scripts/chain-watchdog.sh /usr/local/bin/tpix-chain-watchdog.sh
sudo bash /usr/local/bin/tpix-chain-watchdog.sh        # รันมือ 1 รอบดูผล
sudo tail -20 /var/log/tpix-watchdog.log
```

ปรับเพดานได้ที่ `/etc/tpix-watchdog.env`:

```bash
TPIX_DISK_PATH=/opt/tpix
TPIX_DISK_WARN_PCT=75
TPIX_DISK_CRIT_PCT=88
TPIX_MEMPOOL_WARN=1000
TPIX_BLOCK_FULL_PCT=80
```

---

## หลังทำครบ — ภาพที่ควรเป็น

| ชั้น | กันอะไร |
|---|---|
| ufw เปิดเฉพาะ Cloudflare | บังคับให้ทุกคนผ่าน CF จริง ๆ (WAF/DDoS/rate limit ของ CF เริ่มมีผล) |
| `limit_req` 30 r/s + `limit_conn` 10 | เพดานหยาบต่อ IP จริง (หลัง real_ip) |
| njs deny-list | `admin_*` `debug_*` `txpool_*` `eth_sign` ฯลฯ ถูกปฏิเสธ แกะ JSON จริงจึงหลอกด้วย escape ไม่ได้ |
| njs allow-list | เมธอดที่ไม่รู้จัก = ปฏิเสธ (default deny) |
| **njs โควตาเขียน 10 tx / 10 วิ / IP** | **แกนของงานนี้** — นับรายธุรกรรม batch 20 ใบ = 20 หน่วย |
| `--max-enqueued 16` | 1 address จองได้ 16 ช่อง (เดิม 128) |
| `--block-gas-target 10M` | ครึ่งเดียวของอัตราถมดิสก์สูงสุด |
| fail2ban | ยิงโดนปฏิเสธ 10 ครั้ง/60 วิ → แบน 1 ชม. เพิ่มเป็นเท่าตัวถ้าซ้ำ |
| watchdog | ดิสก์ 75/88% · mempool ค้าง · บล็อกเต็ม → แจ้งหลังบ้าน |

**คนยิงถล่มต้องมี ~400 IP จริงที่ผ่าน Cloudflare** ถึงจะได้ปริมาณเท่าที่เมื่อก่อน
IP เดียวทำได้ และทุกใบที่โดนปฏิเสธจะพาไปสู่การถูกแบนเร็วขึ้น

---

## ยังไม่ได้แก้ในรอบนี้

- โหนด RPC สาธารณะยังชี้เข้า validator ที่ `--seal` และถือคีย์ — ควรมีโหนดที่ไม่ seal แยก
- validator 4 ตัวอยู่เครื่องเดียว ทน BFT ได้แค่ 1 ตัวพัง
- คีย์ validator ยังเก็บแบบไม่เข้ารหัส (`--insecure`)
- `$origin_ok` token gate ยัง `default 1` (ตั้ง Transform Rule ที่ Cloudflare ก่อน)
