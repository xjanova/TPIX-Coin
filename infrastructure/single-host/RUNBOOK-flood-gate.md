# รันบุ๊ก — ด่านกันยิงถล่มเชนค่าแก๊ส 0

> **สถานะ: ติดตั้งครบบน `tpixserver` (123.253.62.252) แล้ว เมื่อ 2026-08-28**
> เอกสารนี้เขียนใหม่หลังลงมือจริง — ทุกขั้นและทุกกับดักด้านล่างเกิดขึ้นจริงระหว่างติดตั้ง
> ใช้ตอนตั้งเครื่องใหม่ กู้คืน หรือย้ายเชนไปเครื่องอื่น

## ปัญหาที่แก้

`--price-limit 0` เป็นจุดขาย แต่แปลว่าไม่มีต้นทุนต่อธุรกรรม
ผู้ใช้จริงจึง **แซงคิวสแปมด้วยการ bid gas สูงกว่าไม่ได้** (บนเชนทั่วไปทำได้)
→ ด่านกันสแปมต้องอยู่นอกเชนทั้งหมด และจำกัดที่ **อัตรา** ไม่ใช่ **ราคา**

วัดกับ prod ก่อนแก้: batch 20 ใบของ `eth_sendRawTransaction` ในคำขอเดียว
ได้ 200 ใน 0.23 วิ และทุกใบไปถึงขั้นถอด RLP ของโหนดจริง
= **1 คำขอ HTTP เท่ากับ 20 ครั้งที่พยายามยัดเข้า mempool** เทียบกับ txpool ที่มี 4096 ช่อง

---

## ⛔ กับดักที่เจอจริง — อ่านก่อนลงมือทุกครั้ง

| กับดัก | อาการ | ทางที่ถูก |
|---|---|---|
| `js_shared_dict_zone` ไม่ใส่ `type=number` | **ธุรกรรมทุกใบได้ 500** (แย่กว่าไม่มีด่าน) `nginx -t` ผ่านฉลุย เห็นแค่ `TypeError: shared dict is not a number dict` ใน error log | ใส่ `type=number` เสมอ |
| เปลี่ยนชนิดโซนแล้ว `reload` | `systemctl reload` **คืนค่าสำเร็จ** แต่ nginx ปฏิเสธ config ใหม่ (`[emerg] ... had previously a different type`) ตัวเก่าวิ่งต่อเงียบ ๆ | ต้อง `restart` และอ่าน error log ยืนยัน อย่าเชื่อ exit code |
| ทับ `10-tpix-http.conf` ทั้งไฟล์ | `99-tpix-debug.conf` อ้าง `$rpc_method_denied` ฯลฯ จาก map ในไฟล์นั้น ลบ map = **nginx ไม่สตาร์ท** | เพิ่มไฟล์ `05-tpix-njs.conf` แยก อย่าไปแตะของเดิม |
| `failregex` ของ fail2ban ใส่ `\[วันที่\]` | ไม่แมตช์สักบรรทัด รายงานแค่ "0 matched" ไม่มี error | fail2ban **ตัดวันที่ออกก่อน** ใช้ `.*` ข้ามช่วงนั้น |
| jail ไม่ระบุ `backend = auto` | fail2ban ไปอ่าน journald **มองข้าม logpath** status ขึ้น `Journal matches:` แทน `File list:` | ระบุ `backend = auto` เสมอ |
| `grep -r load_module /etc/nginx/modules-enabled/` | ได้ผลว่าง แล้วสรุปผิดว่าโมดูล njs ไม่ได้โหลด | `-r` ไม่ตาม symlink ต้องใช้ `-R` |
| curl ไม่ส่ง UA | Cloudflare bot rule ตอบ **403** ทำให้นึกว่าด่านเราพัง | ส่ง `User-Agent` แบบเบราว์เซอร์เสมอ |
| copy watchdog ไป `/usr/local/bin` | cron เรียก `/usr/local/sbin/tpix-chain-watchdog` (ไม่มี `.sh`) — ตัวใหม่ไม่เคยถูกเรียก | ตรวจ `/etc/cron.d/tpix-chain-watchdog` ก่อนเสมอ |
| ลง `tpix-rpc.js` รุ่นงบแก๊สก่อนโซน `rpc_gas_budget` | **ธุรกรรมทุกใบได้ 429** (`gas rate limit exceeded`) เพราะด่าน fail-closed เมื่อโซนหาย | ลง `05-tpix-njs.conf` + reload ให้โซนเกิดก่อน แล้วค่อยลง `tpix-rpc.js` (ขั้น 1b) |

---

## ขั้น 1b — งบแก๊สต่อ IP (เพิ่ม 2026-11-13 · **ยังไม่ได้ลงเครื่องจริง**)

โควตาเดิมนับจำนวนใบ (10 ใบ / 10 วิ / IP) — ธุรกรรม 21,000 gas กับ 10,000,000 gas กิน 1 หน่วยเท่ากัน
IP เดียวที่ส่งใบละ 5M gas วินาทีละใบจึงทำให้ทุกบล็อกเต็มได้ (เชนรับ 5M gas/วินาที)
ด่านใหม่อ่าน gas limit จากธุรกรรมที่เซ็นแล้ว และให้ IP ละ **12M gas / 60 วิ** (4% ของความจุเชน)

| สิ่งที่ผู้ใช้จะเห็นต่างจากเดิม | |
|---|---|
| ธุรกรรมที่ขอแก๊สเกิน 10M | 400 `transaction gas limit above block gas limit` (เดิมโหนดเป็นคนปฏิเสธ) |
| ใช้แก๊สรวมเกิน 12M ใน 1 นาทีจาก IP เดียว | 429 `gas rate limit exceeded` — ลองใหม่ได้เมื่อขึ้นนาทีใหม่ |
| สคริปต์ deploy สัญญาหลายตัวติดกัน (`contracts/scripts/deploy-*.js`) | ได้ราว 12M gas ต่อนาที เกินแล้วเจอ 429 — hardhat ลองใหม่จำกัดครั้ง จึง **อาจล้มกลางทาง** `pace()` ในสคริปต์ยังพักตามโควตาจำนวนใบอย่างเดียว ยังไม่รู้จักงบแก๊ส → ก่อนลงด่านนี้ต้องปรับ `pace()` หรือรัน deploy จากเครื่องเชนตรงเข้า `127.0.0.1:8545` (ยังไม่ได้ลองทั้งสองทาง) |

ค่า 12M / 60 วิ เป็นค่าตั้งต้นจากการคำนวณ ยังไม่ได้ยืนยันด้วยโหลดจริงบน `infrastructure/lab`

```bash
cd ~/TPIX-Coin && git pull
TS=$(date +%Y%m%d-%H%M%S)
sudo mkdir -p /etc/nginx/backup-$TS
sudo cp /etc/nginx/njs/tpix-rpc.js /etc/nginx/conf.d/05-tpix-njs.conf /etc/nginx/backup-$TS/

# 1) โซนก่อน — ไฟล์ js เก่ายังไม่ใช้โซนนี้ จึงไม่มีอะไรเปลี่ยนสำหรับผู้ใช้
sudo cp infrastructure/single-host/nginx-njs.conf /etc/nginx/conf.d/05-tpix-njs.conf
sudo nginx -t && sudo systemctl reload nginx
sudo tail -n 20 /var/log/nginx/error.log        # ต้องไม่มี [emerg] — reload คืน exit 0 แม้ config ถูกปฏิเสธ

# 2) แล้วค่อยตัวด่าน
sudo cp infrastructure/njs/tpix-rpc.js /etc/nginx/njs/
sudo nginx -t && sudo systemctl reload nginx
sudo tail -n 20 /var/log/nginx/error.log

# 3) ตรวจจากเครื่องนอก (ใช้เวลาราว 30 วิ และกินงบแก๊สของ IP ที่รัน 1 นาที)
bash infrastructure/scripts/verify-rpc-gate.sh https://rpc.tpix.online
```

ถอยกลับ: `sudo cp /etc/nginx/backup-$TS/tpix-rpc.js /etc/nginx/njs/ && sudo nginx -t && sudo systemctl reload nginx`
(โซน `rpc_gas_budget` ปล่อยไว้ได้ ไฟล์ js เก่าไม่แตะมัน)

ยังไม่ได้ยืนยันบน njs 0.8.2 ของเครื่องจริง: `incr()` รับค่าลบ (ใช้คืนงบของใบที่ไม่ผ่าน — ถ้าไม่รับ ด่านจะเข้มขึ้นเฉย ๆ ไม่พัง)
และการเพิ่มโซนใหม่ด้วย `reload` (ถ้าไม่ขึ้นให้ `restart` ตามกับดักแถวที่ 2)

---

## ขั้น 0 — ตรวจธง polygon-edge (5 วินาที)

ธงที่ไม่มีอยู่จริง = validator ไม่บูต = **เชนหยุดทั้งวง**

```bash
sudo docker run --rm 0xpolygon/polygon-edge:0.9.0 server --help \
  | grep -E 'max-enqueued|max-slots|block-gas-target|price-limit'
```

ยืนยันแล้วบน 0.9.0: มีครบทั้ง 4 ตัว (`--max-enqueued` default 128, `--max-slots` default 4096)

---

## ขั้น 1 — ด่าน njs ที่ nginx

```bash
cd ~/TPIX-Coin && git pull
TS=$(date +%Y%m%d-%H%M%S)
sudo mkdir -p /etc/nginx/njs /etc/nginx/backup-$TS
sudo cp /etc/nginx/sites-available/tpix-rpc.conf /etc/nginx/backup-$TS/
sudo cp /etc/nginx/conf.d/10-tpix-http.conf     /etc/nginx/backup-$TS/

sudo cp infrastructure/njs/tpix-rpc.js /etc/nginx/njs/
sudo cp infrastructure/single-host/nginx-njs.conf /etc/nginx/conf.d/05-tpix-njs.conf
sudo cp infrastructure/single-host/nginx-rpc.conf /etc/nginx/sites-available/tpix-rpc.conf

sudo nginx -t && sudo systemctl restart nginx     # restart ไม่ใช่ reload
sudo tail -20 /var/log/nginx/error.log            # ต้องไม่มี [emerg] / js exception
```

ตรวจ:
```bash
bash infrastructure/scripts/verify-rpc-gate.sh https://rpc.tpix.online
```
ต้องได้ **ผ่าน 17 · ไม่ผ่าน 0** ถ้าไม่ผ่าน → คืนไฟล์จาก `/etc/nginx/backup-$TS/` แล้ว restart

> `real_ip_header CF-Connecting-IP` อยู่ใน `00-cloudflare-realip.conf` ตั้งแต่ 6 ส.ค. แล้ว
> ไม่ต้องตั้งซ้ำ — และเพราะมันเปิดอยู่ `$remote_addr` ในล็อกจึงเป็น IP ผู้ใช้จริง

---

## ขั้น 2 — ปิดทางยิงตรงเข้า origin

ก่อนทำ **ตรวจว่าทุกโดเมนบนเครื่องนี้อยู่หลัง Cloudflare จริง** ไม่งั้นล็อกแล้วเว็บนั้นดับ:
```bash
getent hosts rpc.tpix.online explorer.tpix.online     # ต้องเป็น IP ของ Cloudflare
ls /etc/letsencrypt/live/ 2>/dev/null                 # ถ้ามี ต้องคิดเรื่อง ACME ก่อนล็อกพอร์ต 80
```

```bash
sudo bash infrastructure/scripts/allow-cloudflare-only.sh            # ดูแผนก่อน
sudo bash infrastructure/scripts/allow-cloudflare-only.sh --apply    # ลงมือ (SSH 22 ไม่ถูกแตะ)
```

ตรวจจาก **เครื่องนอก** (สำคัญ — ตรวจจากบนเครื่องเองไม่พิสูจน์อะไร):
```bash
curl -sk -m 12 -o /dev/null -w '%{http_code}\n' -X POST https://123.253.62.252 \
     -H 'Host: rpc.tpix.online' -H 'User-Agent: Mozilla/5.0' \
     -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}'
# ต้องได้ 000 (ต่อไม่ติด) ไม่ใช่ 200

curl -s -m 12 https://rpc.tpix.online/health -H 'User-Agent: Mozilla/5.0'   # ต้องยัง 200
```

ถ้าเว็บดับ: `sudo ufw allow 443/tcp` กลับทันที แล้วค่อยหาสาเหตุ

---

## ขั้น 3 — fail2ban

```bash
sudo cp infrastructure/fail2ban/filter.d/tpix-rpc.conf /etc/fail2ban/filter.d/
sudo cp infrastructure/fail2ban/jail.d/tpix-rpc.conf   /etc/fail2ban/jail.d/

# กันแบนตัวเอง: IP สาธารณะของเครื่องนี้วนกลับผ่าน CF ตอนรัน verify
sudo sed -i 's|^ignoreip = 127.0.0.1/8 ::1|ignoreip = 127.0.0.1/8 ::1 123.253.62.252|' \
     /etc/fail2ban/jail.d/tpix-rpc.conf

sudo fail2ban-regex /var/log/nginx/tpix-rpc.access.log \
     /etc/fail2ban/filter.d/tpix-rpc.conf | grep -E "Failregex|Lines:"   # matched ต้อง > 0

sudo fail2ban-client reload tpix-rpc
sudo fail2ban-client status tpix-rpc     # ต้องเห็น "File list:" ไม่ใช่ "Journal matches:"
```

พิสูจน์ว่า action แบนได้จริงโดยไม่แตะ IP ของใคร:
```bash
sudo fail2ban-client set tpix-rpc banip 203.0.113.99
sudo iptables -L f2b-tpix-rpc -n | head -4        # ต้องเห็นบรรทัด REJECT
sudo fail2ban-client set tpix-rpc unbanip 203.0.113.99
```

---

## ขั้น 4 — จำกัด txpool ที่ตัวเชน (rolling ห้าม down ทั้งวง)

```bash
sudo cp /opt/tpix/docker-compose.yml /opt/tpix/docker-compose.yml.bak-$(date +%Y%m%d-%H%M%S)
sudo cp infrastructure/single-host/docker-compose.yml /opt/tpix/docker-compose.yml
sudo bash infrastructure/single-host/apply-rolling.sh
```

`apply-rolling.sh` เปลี่ยนทีละตัวและรอ healthcheck + รอเชนเดินก่อนแตะตัวถัดไป
**ห้าม `docker compose down`** เชนจะหยุดทั้งวง

ตรวจว่าธงติดจริง:
```bash
ps -ef | grep -o "server --data-dir.*log-level INFO" | head -1
sudo docker logs tpix-validator-1 --since 5m 2>&1 | grep -i "unknown\|panic"   # ต้องว่าง
```

> watchdog อาจมองว่าเชนสะดุดระหว่าง rolling แล้วสั่ง restart ซ้ำ — ไม่เป็นไร เชนกลับมาเอง
> (เกิดขึ้นจริงตอนติดตั้ง เห็นใน `/var/log/tpix-watchdog.log` เป็น `RESTART OK`)

---

## ขั้น 5 — watchdog เฝ้าดิสก์ + สแปม

⚠️ ตรวจก่อนว่า cron เรียกไฟล์ไหน **อย่าเดา**:
```bash
sudo cat /etc/cron.d/tpix-chain-watchdog
# ปัจจุบัน: * * * * * root /usr/local/sbin/tpix-chain-watchdog     ← ไม่มี .sh และอยู่ sbin
```

```bash
sudo cp /usr/local/sbin/tpix-chain-watchdog /usr/local/sbin/tpix-chain-watchdog.bak-$(date +%Y%m%d-%H%M%S)
sudo cp infrastructure/scripts/chain-watchdog.sh /usr/local/sbin/tpix-chain-watchdog
sudo chmod +x /usr/local/sbin/tpix-chain-watchdog
grep -c "check_disk\|check_flood" /usr/local/sbin/tpix-chain-watchdog   # ต้องได้ 4
sudo /usr/local/sbin/tpix-chain-watchdog && sudo tail -5 /var/log/tpix-watchdog.log
```

ปรับเพดานที่ `/etc/tpix-watchdog.env`:
```bash
TPIX_DISK_PATH=/opt/tpix
TPIX_DISK_WARN_PCT=75
TPIX_DISK_CRIT_PCT=88
TPIX_MEMPOOL_WARN=1000
TPIX_BLOCK_FULL_PCT=80
```

---

## ภาพหลังติดตั้งครบ

| ชั้น | กันอะไร | สถานะ |
|---|---|---|
| ufw เปิดเฉพาะ Cloudflare | บังคับให้ทุกคนผ่าน CF จริง (WAF/DDoS/rate limit ของ CF จึงมีผล) | ✅ |
| `limit_req` 30 r/s + `limit_conn` 10 | เพดานหยาบต่อ IP จริง | ✅ (มีอยู่เดิม) |
| njs deny-list | `admin_*` `debug_*` `txpool_*` `eth_sign` ฯลฯ | ✅ |
| njs allow-list | เมธอดที่ไม่รู้จัก = ปฏิเสธ | ✅ |
| **njs โควตาเขียน 10 tx / 10 วิ / IP** | **แกนของงานนี้** นับรายธุรกรรม batch 20 = 20 หน่วย | ✅ |
| `--max-enqueued 16` | 1 address จองได้ 16 ช่อง (เดิม 128) | ✅ |
| `--block-gas-target 10M` | ครึ่งเดียวของอัตราถมดิสก์สูงสุด | ✅ |
| fail2ban | ปฏิเสธ 10 ครั้ง/60 วิ → แบน 1 ชม. เพิ่มเท่าตัวถ้าซ้ำ | ✅ (ก่อนหน้านี้ **ไม่เคยถูกติดตั้งเลย** มีแต่ jail sshd) |
| watchdog | ดิสก์ 75/88% · mempool ค้าง · บล็อกเต็ม | ✅ |

**คนยิงถล่มต้องมี ~240 IP จริงที่ผ่าน Cloudflare** ถึงจะได้ปริมาณเท่าที่ IP เดียวเคยทำได้

---

## ยังไม่ได้แก้

- โหนด RPC สาธารณะยังชี้เข้า validator ที่ `--seal` และถือคีย์ — ควรมีโหนดที่ไม่ seal แยก
- validator 4 ตัวอยู่เครื่องเดียว ทน BFT ได้แค่ 1 ตัวพัง
- คีย์ validator เก็บแบบไม่เข้ารหัส (`--insecure`)
- `$origin_ok` token gate ยัง `default 1` (ต้องตั้ง Transform Rule ที่ Cloudflare ก่อน)
