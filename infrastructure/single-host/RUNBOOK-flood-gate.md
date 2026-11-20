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
| ลง `tpix-rpc.js` รุ่นงบแก๊สก่อนโซน `rpc_gas_budget` | **ธุรกรรมทุกใบได้ 429** (`gas rate limit exceeded`) เพราะด่าน fail-closed เมื่อโซนหาย การอ่านยังผ่าน และ `nginx -t` ผ่านฉลุย (ยืนยันบน lab) | ลง `05-tpix-njs.conf` + reload ให้โซนเกิดก่อน แล้วค่อยลง `tpix-rpc.js` (ขั้น 1b) · ถ้าพลาดไปแล้ว ลง conf + reload ตามหลังก็หาย |
| แก้กุญแจของโซน `limit_req_zone` / `limit_conn_zone` ที่มีอยู่แล้ว `reload` | nginx ปฏิเสธ config ใหม่ทั้งก้อน (`[emerg] limit_req "rpc_per_ip" uses the "$rpc_client_net" key while previously it used the "$binary_remote_addr" key`) `nginx -t` ผ่าน `reload` คืนค่าสำเร็จ ตัวเก่าวิ่งต่อเงียบ ๆ (ยืนยันบน lab ขั้น 7g) | ประกาศโซน **ชื่อใหม่** แล้วให้ vhost ชี้ไปใช้ (ขั้น 1c) — ใช้ `reload` ได้ |
| ตัด `(?s)` ออกจาก `map $binary_remote_addr $rpc_client_net` | `.` ไม่จับไบต์ `0x0a` → IPv6 ที่มีไบต์นั้น (เช่น `2001:db8:a0a::1`) หลุดไป `default` = กลับไปนับต่อที่อยู่เต็มเงียบ ๆ ไม่มี error | ห้ามตัด — lab ขั้น 7f มีที่อยู่แบบนี้คุมอยู่ |
| jail ของ fail2ban แบนที่ชั้นไฟร์วอลล์ (`iptables-multiport`, `nftables`, `ufw` …) บนเครื่องที่อยู่หลัง Cloudflare | `fail2ban-client status` ขึ้นว่าแบนแล้ว กฎ iptables มีจริง แต่**คำขอของคนนั้นยังได้ 200** — แพ็กเก็ตทุกใบมีต้นทางเป็น IP ของ Cloudflare กฎที่ระบุ IP ผู้ใช้ไม่ตรงกับแพ็กเก็ตใดเลย (ตัวนับแพ็กเก็ตของกฎเป็น 0) ทั้ง IPv4 และ IPv6 (เห็นบน `lab/rpc-ban-lab.sh` ขั้น 2) | แบนที่ชั้นที่เห็น IP ผู้ใช้จริง: action `nginx-tpix-banned` เขียน `tpix-banned.map` ให้ `geo $banned_ip` (ขั้น 3) · พิสูจน์ด้วยการยิงจริงจากที่อยู่ที่ถูกแบน อย่าดูแค่ status |
| ลง vhost ที่ใช้ `log_format tpixban` ก่อน `tpix-rpc.js` ที่มี `banKey` | `nginx -t` ผ่าน ด่านทำงานปกติ แต่ช่องแรกของ access log เป็น `-` → fail2ban ไม่แมตช์สักบรรทัด = ไม่แบนใครเลย และ error log ก็ไม่ฟ้อง (เห็นบน lab ขั้น 6b) | ลำดับ conf → js → vhost (ขั้น 3) แล้ว `tail -n 3` access log ดูช่องแรกทุกครั้ง |
| เห็น `[crit] ngx_slab_alloc() failed: no memory in js shared zone` ใน error log | ไม่ใช่ด่านพัง — โซนเต็ม nginx ลงบรรทัดนี้ทุกครั้งที่จองไม่ได้ แล้ว njs เขี่ยกุญแจเก่าสุดออก (`evict`) และนับต่อ (ยืนยันบน lab: 20,000 กุญแจในโซน 64k ไม่มี error) | ปล่อยได้ ถ้าขึ้นถี่จน log โตค่อยขยายโซน (ต้อง `restart` เพราะเปลี่ยนขนาดโซนเดิม — ยังไม่ได้ลอง) |

---

## ขั้น 1b — งบแก๊สต่อ IP (เพิ่ม 2026-11-13 · ผ่าน lab 2026-11-20 · **ยังไม่ได้ลงเครื่องจริง**)

โควตาเดิมนับจำนวนใบ (10 ใบ / 10 วิ / IP) — ธุรกรรม 21,000 gas กับ 10,000,000 gas กิน 1 หน่วยเท่ากัน
IP เดียวที่ส่งใบละ 5M gas วินาทีละใบจึงทำให้ทุกบล็อกเต็มได้ (เชนรับ 5M gas/วินาที)
ด่านใหม่อ่าน gas limit จากธุรกรรมที่เซ็นแล้ว และให้ IP ละ **12M gas / 60 วิ** (4% ของความจุเชน)
("IP" ของผู้ใช้ IPv6 = /64 ที่ที่อยู่นั้นอยู่ ไม่ใช่ที่อยู่เต็ม — ขั้น 1c)

| สิ่งที่ผู้ใช้จะเห็นต่างจากเดิม | |
|---|---|
| ธุรกรรมที่ขอแก๊สเกิน 10M | 400 `transaction gas limit above block gas limit` (เดิมโหนดเป็นคนปฏิเสธ) |
| ใช้แก๊สรวมเกิน 12M ใน 1 นาทีจาก IP เดียว | 429 `gas rate limit exceeded` — ลองใหม่ได้เมื่อขึ้นนาทีใหม่ |
| สคริปต์ deploy สัญญาหลายตัวติดกัน (`contracts/scripts/deploy-*.js`) | ได้ราว 12M gas ต่อนาที เกินแล้วเจอ 429 — hardhat ลองใหม่จำกัดครั้ง จึง **อาจล้มกลางทาง** `pace()` ในสคริปต์ยังพักตามโควตาจำนวนใบอย่างเดียว ยังไม่รู้จักงบแก๊ส → ก่อนลงด่านนี้ต้องปรับ `pace()` หรือรัน deploy จากเครื่องเชนตรงเข้า `127.0.0.1:8545` (ยังไม่ได้ลองทั้งสองทาง) |

ค่า 12M / 60 วิ เป็นค่าตั้งต้นจากการคำนวณ ยังไม่ได้ยืนยันด้วยโหลดจริงบน `infrastructure/lab`

ลำดับข้างล่างเดินครบแล้วบน lab (`infrastructure/lab/rpc-gate-lab.sh` — nginx 1.24.0 + njs 0.8.2 ของ Ubuntu 24.04
กับ upstream ปลอม รันใน CI ทุกครั้งที่ไฟล์ด่านเปลี่ยน) ทั้งทางถูก ทางผิดลำดับ และทาง `restart`

```bash
cd ~/TPIX-Coin && git pull

# 0) อ่านอย่างเดียว — เครื่องต้องตรงกับที่ lab ทดสอบ ข้อไหนไม่ตรงให้หยุดก่อน
dpkg-query -W nginx libnginx-mod-http-js       # lab: nginx 1.24.0-2ubuntu7.x · libnginx-mod-http-js 0.8.2-1ubuntu1
BASE=38eb23b587a50ae810f17f67ad237882b80cd5c6   # main ก่อนมีงบแก๊ส = "ของเดิม" ที่ lab ใช้
diff <(git show $BASE:infrastructure/njs/tpix-rpc.js) /etc/nginx/njs/tpix-rpc.js && echo "js บนเครื่องตรงกับ repo"
diff <(git show $BASE:infrastructure/single-host/nginx-njs.conf) /etc/nginx/conf.d/05-tpix-njs.conf && echo "conf บนเครื่องตรงกับ repo"

TS=$(date +%Y%m%d-%H%M%S)
sudo mkdir -p /etc/nginx/backup-$TS
sudo cp /etc/nginx/njs/tpix-rpc.js /etc/nginx/conf.d/05-tpix-njs.conf /etc/nginx/backup-$TS/

# 1) โซนก่อน — ไฟล์ js เก่ายังไม่ใช้โซนนี้ จึงไม่มีอะไรเปลี่ยนสำหรับผู้ใช้ (reload ไม่ล้างโควตาที่นับอยู่)
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

ยืนยันบน lab แล้ว (2026-11-20, njs 0.8.2):

- `incr()` รับค่าลบ — ใบที่โดน 429 ไม่กินงบ ใบเล็กที่ตามมายังผ่าน และใช้ได้ครบ 12M พอดี
- เพิ่มโซนใหม่ด้วย `reload` ได้ ไม่ต้อง `restart` · ตัวนับของ `rpc_write_budget` ไม่หายข้ามรอบ reload (`restart` ล้างทุก IP)
- ลงผิดลำดับ (js ก่อนโซน): ธุรกรรมทุกใบ 429 การอ่านยังผ่าน `nginx -t` ไม่ฟ้อง — ลง conf + reload ตามหลังแล้วหาย
- `verify-rpc-gate.sh`: ผ่าน 18/0 กับด่านใหม่ · ฟ้อง "ส่ง 3 ใบไม่โดนตัดเลย" กับ js เดิม · ฟ้อง "โดนตัดตั้งแต่ใบแรก" กับการลงผิดลำดับ
- ธุรกรรม ~100KB ถอดแก๊สได้ถูก · งบเริ่มใหม่เมื่อขึ้นนาทีใหม่ · โซนเต็มแล้ว evict ไม่ใช่ 500

ที่ lab พิสูจน์ไม่ได้ ต้องดูตอนลงจริง: ไฟล์อื่นใน `/etc/nginx/conf.d` ของเครื่อง (`10-tpix-http.conf`, `99-tpix-debug.conf`),
Cloudflare ที่อยู่ข้างหน้า, โหนดจริงเป็น upstream และรุ่น njs ของเครื่อง (ข้อ 0 ข้างบนเช็กให้)

---

## ขั้น 1c — "ต่อ IP" ของ IPv6 คือต่อ /64 (เพิ่ม 2026-11-20 · ผ่าน lab · **ยังไม่ได้ลงเครื่องจริง**)

`rpc.tpix.online` มี AAAA ที่ Cloudflare จึงรับผู้ใช้ IPv6 และ `CF-Connecting-IP` เป็น IPv6 ได้
ผู้ใช้ IPv6 หนึ่งราย (สายบ้าน, VPS, มือถือ) ถือทั้ง /64 = 2^64 ที่อยู่ และเปลี่ยนที่อยู่ต้นทางได้เองทุกคำขอ
ทุกชั้นที่นับ "ต่อ IP" ด้วยที่อยู่เต็ม (/128) จึงให้ถังใหม่ทุกครั้งที่เปลี่ยนที่อยู่:

| ชั้น | กุญแจเดิม | ผลกับ /64 เดียว | กุญแจใหม่ |
|---|---|---|---|
| njs โควตาเขียน 10 tx / 10 วิ | `CF-Connecting-IP` ทั้งตัว | 10 ใบต่อที่อยู่ ไม่จำกัดจำนวนที่อยู่ (เห็นบน lab ขั้น 1 กับด่านเดิม) | `addressKey()` ใน `tpix-rpc.js` — IPv6 ตัดที่ /64 |
| njs งบแก๊ส 12M / 60 วิ (ขั้น 1b) | เหมือนกัน | 12M ต่อที่อยู่ — ราว 25 ที่อยู่ถึงความจุเชน | เหมือนกัน |
| `limit_req` 30 r/s + `limit_conn` 10 | `$binary_remote_addr` (16 ไบต์) | 30 r/s ต่อที่อยู่ (เห็นบน lab ขั้น 7e) | `$rpc_client_net` (map ใน `05-tpix-njs.conf`) — โซนชื่อใหม่ `rpc_per_net` / `rpc_conn_per_net` |
| fail2ban | `<HOST>` = ที่อยู่เต็ม | นับ 10 ครั้ง/60 วิ ต่อที่อยู่ — หมุนที่อยู่แล้วไม่ถึงเกณฑ์แบน (เห็นบน `lab/rpc-ban-lab.sh` ขั้น 3) | ช่องแรกของ log = `banKey()` — IPv6 เป็นที่อยู่เครือข่ายของ /64 (ขั้น 3 · PR แยก) |

กุญแจใหม่ทั้งสองชั้นใช้กติกาเดียวกัน: IPv4 ต่อที่อยู่เหมือนเดิม · IPv6 ต่อ /64 · `::ffff:a.b.c.d` ใช้ถังของ `a.b.c.d`
(ถ้าไม่แยกกรณีนี้ IPv4 ที่ถูกห่อเป็น IPv6 ทุกตัวจะกองรวมใน `::/64` ถังเดียว = ผู้ใช้จริงล็อกกันเอง)

| สิ่งที่ผู้ใช้จะเห็นต่างจากเดิม | |
|---|---|
| ผู้ใช้ IPv4 | ไม่มีอะไรเปลี่ยน |
| ผู้ใช้ IPv6 หลายเครื่องหลังเราเตอร์เดียว (/64 เดียว) | ใช้โควตาร่วมกัน: 10 tx / 10 วิ, 12M gas / นาที, 30 r/s, 10 connection — เท่ากับบ้านที่ใช้ IPv4 ตัวเดียวหลัง NAT วันนี้ |
| ตอนลง | ตัวนับของผู้ใช้ IPv6 เริ่มใหม่หนึ่งครั้ง (กุญแจเปลี่ยนรูป) |

ต้องลง **ขั้น 1b ก่อนหรือพร้อมกัน** — `tpix-rpc.js` กับ `nginx-njs.conf` ของ branch นี้มีงบแก๊สของขั้น 1b อยู่ด้วย
ลำดับข้างล่างคือขั้น 1b + 1c รวมกัน และเดินครบแล้วบน lab (ขั้น 7): ของเดิม → conf ใหม่ → js ใหม่ → vhost ใหม่

```bash
cd ~/TPIX-Coin && git pull

# 0) อ่านอย่างเดียว — ทำข้อ 0 ของขั้น 1b ให้ครบก่อน แล้วเพิ่มสามข้อนี้ ข้อไหนไม่ตรงให้หยุดก่อน
sudo grep -RnE 'limit_(req|conn)(_zone)?[[:space:]]' /etc/nginx/     # โซนเดิมประกาศที่ไฟล์ไหน vhost ไหนเรียกใช้บ้าง
sudo grep -Rn 'rpc_per_net\|rpc_conn_per_net\|rpc_client_net' /etc/nginx/ ; echo "ต้องว่าง (ชื่อยังไม่ถูกใช้)"
BASE=38eb23b587a50ae810f17f67ad237882b80cd5c6
diff <(git show $BASE:infrastructure/single-host/nginx-rpc.conf) /etc/nginx/sites-available/tpix-rpc.conf && echo "vhost บนเครื่องตรงกับ repo"

TS=$(date +%Y%m%d-%H%M%S)
sudo mkdir -p /etc/nginx/backup-$TS
sudo cp /etc/nginx/njs/tpix-rpc.js /etc/nginx/conf.d/05-tpix-njs.conf /etc/nginx/sites-available/tpix-rpc.conf /etc/nginx/backup-$TS/

# 1) conf ก่อน — โซน rpc_gas_budget, map $rpc_client_net, โซน rpc_per_net / rpc_conn_per_net เกิด
#    ยังไม่มีอะไรเปลี่ยนสำหรับผู้ใช้ (js เดิมกับ vhost เดิมไม่ได้เรียกของใหม่)
sudo cp infrastructure/single-host/nginx-njs.conf /etc/nginx/conf.d/05-tpix-njs.conf
sudo nginx -t && sudo systemctl reload nginx
sudo tail -n 20 /var/log/nginx/error.log        # ต้องไม่มี [emerg]

# 2) ตัวด่าน — งบแก๊ส + กุญแจ /64 ของ njs
sudo cp infrastructure/njs/tpix-rpc.js /etc/nginx/njs/
sudo nginx -t && sudo systemctl reload nginx
sudo tail -n 20 /var/log/nginx/error.log

# 3) vhost — limit_req / limit_conn ย้ายไปโซนที่นับ IPv6 ต่อ /64
#    ถ้าข้อ 0 บอกว่า vhost บนเครื่องไม่ตรงกับ repo: อย่าทับทั้งไฟล์ แก้เฉพาะสองบรรทัด
#      limit_req  zone=rpc_per_ip ...   →  zone=rpc_per_net
#      limit_conn rpc_conn_per_ip 10;   →  rpc_conn_per_net 10;
sudo cp infrastructure/single-host/nginx-rpc.conf /etc/nginx/sites-available/tpix-rpc.conf
sudo nginx -t && sudo systemctl reload nginx
sudo tail -n 20 /var/log/nginx/error.log

# 4) ตรวจจากเครื่องนอก
bash infrastructure/scripts/verify-rpc-gate.sh https://rpc.tpix.online
```

ถอยกลับ: คืน `tpix-rpc.conf` และ/หรือ `tpix-rpc.js` จาก `/etc/nginx/backup-$TS/` แล้ว `nginx -t && systemctl reload nginx`
(`05-tpix-njs.conf` ใหม่ปล่อยไว้ได้ — โซนกับ map ที่ไม่มีใครเรียกไม่มีผลอะไร)

⛔ **อย่า** แก้บรรทัด `limit_req_zone $binary_remote_addr zone=rpc_per_ip` ใน `10-tpix-http.conf` ให้ใช้กุญแจใหม่ — ดูตารางกับดัก
โซนเดิมสองตัวปล่อยไว้ได้ (ไม่มีใครเรียกแล้ว เปลืองหน่วยความจำ 20 MB) จะลบก็ต่อเมื่อมี `restart` รอบหน้า

ยืนยันบน lab แล้ว (2026-11-20, nginx 1.24.0 + njs 0.8.2):

- ด่าน njs: สองที่อยู่ใน /64 เดียวใช้โควตาจำนวนใบและงบแก๊สร่วมกัน · /64 ที่ติดกันมีของตัวเอง · รูปย่อ/รูปเต็ม/ตัวใหญ่ของที่อยู่เดียวกันตกถังเดียวกัน
  · `::ffff:a.b.c.d` ใช้ถังของ `a.b.c.d` · header ที่ไม่ใช่ที่อยู่ไม่ทำให้ด่านพัง
- ด่านเดิม (ก่อนขั้น 1b): ที่อยู่ที่สองใน /64 เดียวกันได้ถังใหม่จริง — ช่องนี้เคยอ่านจากโค้ดอย่างเดียว ตอนนี้เห็นบน nginx จริงแล้ว
- ชั้นหยาบ: `limit_req` ที่ใช้ `$rpc_client_net` นับต่อ /64 รวมที่อยู่ที่มีไบต์ `0x00` `0x0a` `0xff` · IPv4 ยังนับต่อที่อยู่ · `::ffff:` ไม่กองรวมกัน
- ลำดับ conf → js → vhost ใช้ `reload` ได้ทุกข้อ · vhost ขึ้นก่อน conf: `nginx -t` ไม่ผ่านและบอกชื่อโซน (พลาดแบบนี้ไม่เงียบ)
- แก้กุญแจของโซนเดิมแล้ว `reload`: ถูกปฏิเสธ ตัวเก่าวิ่งต่อ (ตารางกับดัก)

ที่ lab พิสูจน์ไม่ได้ / ยังไม่ได้ลอง:

- `limit_conn` กับกุญแจใหม่ — ใช้ตัวแปรเดียวกับ `limit_req` แต่ lab ไม่ได้เปิด connection พร้อมกันให้เห็นว่านับร่วมจริง
- 30 r/s burst 60 ของจริงกับ /64 — lab พิสูจน์ "กุญแจ" ด้วยโซน 1 คำขอ/นาที ไม่ได้ยิงแข่งกับอัตราจริง
- `10-tpix-http.conf` ของเครื่อง (โซนเดิมประกาศที่นั่น — lab ใช้ไฟล์จำลองสองบรรทัด) และ vhost บนเครื่องที่อาจไม่ตรงกับ repo (ข้อ 0 เช็กให้)
- `CF-Connecting-IP` ที่ Cloudflare ส่งมาจริงสำหรับผู้ใช้ IPv6 — lab ใส่ header เอง

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

## ขั้น 3 — fail2ban (เขียนใหม่ 2026-11-20 · ผ่าน lab · **ยังไม่ได้ลงเครื่องจริง**)

jail `tpix-rpc` ที่ติดตั้งเมื่อ 2026-08-28 แบนด้วย `iptables-multiport` — อ่านจาก repo แล้วมันแบนไม่ถึงคำขอที่ผ่าน Cloudflare:

| ทางแบน | เทียบกับอะไร | คำขอที่มาทาง Cloudflare — IPv4 | IPv6 |
|---|---|---|---|
| iptables / ip6tables (`iptables-multiport` ของ jail เดิม) | ต้นทางของแพ็กเก็ต = IP ของ Cloudflare เสมอ (ขั้น 2 เปิด 80/443 ให้เฉพาะช่วงนั้น) | **ไม่มีผล** — กฎที่ระบุ IP ผู้ใช้ไม่ตรงกับแพ็กเก็ตใด | **ไม่มีผล** เหตุผลเดียวกัน |
| nginx `geo $banned_ip` + `if ($banned_ip) { return 403; }` ใน vhost | `$remote_addr` หลัง `real_ip` = IP ผู้ใช้จริง | มีผล แต่**ไม่มีอะไรเขียน `tpix-banned.map`** (มีผลเฉพาะบรรทัดที่คนใส่มือ) | เหมือนกัน · รับ CIDR จึงแบนทั้ง /64 ได้ |
| รายการ IP ที่ Cloudflare (`cloudflare-tpix` + `cf-ban-ip`) | IP ผู้ใช้ที่ขอบ Cloudflare | มีผลถ้ามี jail เรียก — **jail `tpix-rpc` ไม่เคยเรียก** (`install-cf-autoban.sh` ผูกให้เฉพาะ jail apache ของเครื่องเก่า และ `decommission-old-chain.sh` ลบ action นี้ทิ้ง) | เหมือนกัน · `cf-ban-ip` ส่งที่อยู่เดี่ยว ไม่ได้ส่ง /64 |

และ jail นับ "ถูกปฏิเสธ 10 ครั้ง/60 วิ" ต่อช่องแรกของ log ซึ่งเป็นที่อยู่เต็ม — ผู้ใช้ IPv6 ที่หมุนที่อยู่ใน /64 เดียวจึงไม่ถึงเกณฑ์เลย

สองข้อนี้เห็นบน lab แล้ว (`infrastructure/lab/rpc-ban-lab.sh` ขั้น 2-3: nginx + fail2ban + iptables ตัวจริง, jail/filter/vhost ชุดที่ commit `38eb23b`)
**แต่ยังไม่ได้ดูบนเครื่องจริง** — ข้อ 0 ข้างล่างคือคำสั่งอ่านอย่างเดียวที่ยืนยันได้

### ของใหม่

| ชิ้น | ทำอะไร |
|---|---|
| `fail2ban/action.d/nginx-tpix-banned.conf` | action ใหม่ของ jail — เรียก `tpix-nginx-ban add/remove/flush` |
| `scripts/tpix-nginx-ban.py` → `/usr/local/sbin/tpix-nginx-ban` | เขียน/ลบบรรทัดใน `tpix-banned.map` (IPv4 = ที่อยู่ · IPv6 = /64) → `nginx -t` → reload · `nginx -t` ไม่ผ่านคืนไฟล์เดิม · รับเฉพาะที่อยู่ IP ที่ถอดได้ · reload ไม่เกิน 1 ครั้ง/5 วิ · ไม่แตะบรรทัดที่คนใส่มือ |
| `banKey()` ใน `tpix-rpc.js` + `log_format tpixban` ใน `05-tpix-njs.conf` | ช่องแรกของ log = หน่วยที่แบน: IPv6 เป็นที่อยู่เครือข่ายของ /64 (`2001:db8:0:1::`) → fail2ban นับรวมทั้ง /64 · ที่อยู่เต็มยังอยู่ในช่อง `cf=` |
| vhost (`nginx-rpc.conf`) | `access_log` ใช้ `tpixban` · คำขอจากที่อยู่ที่ถูกแบนอยู่แล้วแยกไป `tpix-rpc.banned.log` ที่ fail2ban ไม่ได้อ่าน |

| สิ่งที่ผู้ใช้จะเห็นต่างจากเดิม | |
|---|---|
| **การแบนมีผลจริงเป็นครั้งแรก** | ใครถูกปฏิเสธ (403/405/413/429) 10 ครั้งใน 60 วิ ใช้ RPC ไม่ได้ 1 ชม. (ถูกแบนซ้ำแล้วนานขึ้นเรื่อย ๆ สูงสุด 24 ชม.) — ได้ 403 ทุกคำขอ รวมการอ่าน เกณฑ์นี้ตั้งไว้ตั้งแต่ ส.ค. แต่ไม่เคยมีผลกับใคร จึง**ยังไม่เคยเห็นว่าผู้ใช้จริงโดนกี่ราย** — ข้อ 0 ข. นับจาก log ย้อนหลังได้ก่อนตัดสินใจ |
| ผู้ใช้หลายคนหลังที่อยู่เดียว (NAT / CGNAT ของมือถือ, IPv6 /64 เดียว, Cloudflare Workers) | ถูกแบนพร้อมกันเมื่อคนใดคนหนึ่งถึงเกณฑ์ — หน่วยเดียวกับโควตาของด่าน |
| หลังถูกแบน | คำขอระหว่างถูกแบนไม่ถูกนับ พอหมดเวลาใช้ได้ทันที ไม่โดนแบนต่อเองเพราะเปิดหน้าเว็บค้างไว้ |
| ความล่าช้า | การแบน/เลิกแบนมีผลหลัง nginx reload — ช้าสุดราว 5 วิ |

### 0) อ่านอย่างเดียว — ต้องรันบน `tpixserver` (ยังไม่ได้รัน รอเจ้าของสั่ง)

ไม่มีคำสั่งไหนแก้ไฟล์ของระบบ reload หรือแบนใคร (`git fetch` เขียนเฉพาะใน `.git` ของ clone และรันก็ต่อเมื่อยังไม่มี commit `38eb23b`)

```bash
cd ~/TPIX-Coin && { git cat-file -e 38eb23b || git fetch origin; }    # ต้องมี commit นี้ไว้ให้ git show ข้างล่าง — ไม่แตะไฟล์ทำงาน

# ก. fail2ban: jail ทำงานไหม action อะไร ไฟล์ตรงกับ repo ไหม
dpkg-query -W fail2ban nginx libnginx-mod-http-js python3
sudo fail2ban-client status
sudo fail2ban-client status tpix-rpc            # ต้องเห็น "File list:" · ดู Total banned / Banned IP list
sudo fail2ban-client get tpix-rpc actions       # คาดว่า iptables-multiport
grep -vE '^[[:space:]]*(#|$)' /etc/fail2ban/jail.d/tpix-rpc.conf
diff <(git show 38eb23b:infrastructure/fail2ban/jail.d/tpix-rpc.conf) /etc/fail2ban/jail.d/tpix-rpc.conf   # คาดว่าต่างแค่บรรทัด ignoreip
ls -l /etc/fail2ban/jail.d/ /etc/fail2ban/action.d/ | grep -iE 'tpix|cloudflare|nginx'
systemctl cat fail2ban | grep -nE 'Protect|ReadOnly|ReadWrite|Private|User=|Capabilit'   # มี = unit ถูกจำกัดสิทธิ์ สคริปต์ใหม่อาจเขียน /etc/nginx ไม่ได้

# ข. jail เคย "แบน" ไปกี่ครั้ง ใครบ้าง — คือคนที่จะโดนจริงเมื่อการแบนมีผล
sudo zgrep -h '\[tpix-rpc\] Ban ' /var/log/fail2ban.log* | wc -l
sudo zgrep -h '\[tpix-rpc\] Ban ' /var/log/fail2ban.log* | awk '{print $NF}' | sort | uniq -c | sort -rn | head -n 20

# ค. ไฟร์วอลล์: กฎของ jail มีไหม เคยมีแพ็กเก็ตตรงกับกฎไหม (คอลัมน์ pkts)
sudo iptables -S | grep -n 'f2b'
sudo iptables  -nvxL f2b-tpix-rpc 2>/dev/null
sudo ip6tables -nvxL f2b-tpix-rpc 2>/dev/null
sudo nft list ruleset 2>/dev/null | grep -n -A12 'f2b' | head -n 60      # เผื่อเครื่องใช้ banaction nftables
sudo ufw status numbered | head -n 40                                     # 80/443 ต้องเปิดเฉพาะ Cloudflare (+ admin)

# ง. ตัวชี้ขาด: ที่อยู่ที่ถูกแบนล่าสุด ยังมีบรรทัดใน access log หลังเวลาที่ถูกแบนไหม
LAST=$(sudo zgrep -h '\[tpix-rpc\] Ban ' /var/log/fail2ban.log* | sort | tail -n 1); echo "$LAST"
IP=${LAST##* }
sudo grep "^$IP " /var/log/nginx/tpix-rpc.access.log | tail -n 5         # มีบรรทัดหลังเวลาใน $LAST = แบนแล้วยังเข้าได้

# จ. nginx: geo $banned_ip อยู่ไหม include ไฟล์ไหน vhost ใช้ไหม ไฟล์มีอะไร
sudo nginx -T 2>/dev/null | grep -n -B1 -A6 'geo \$banned_ip'
sudo nginx -T 2>/dev/null | grep -nE 'banned_ip|log_format|access_log|real_ip_header' | head -n 40
ls -l /etc/nginx/conf.d/tpix-banned.map && grep -vcE '^[[:space:]]*(#|$)' /etc/nginx/conf.d/tpix-banned.map   # จำนวนบรรทัดที่แบนอยู่
diff <(git show 38eb23b:infrastructure/single-host/nginx-rpc.conf) /etc/nginx/sites-available/tpix-rpc.conf && echo "vhost ตรงกับ repo"
sudo tail -n 3 /var/log/nginx/tpix-rpc.access.log                         # ช่องแรกต้องเป็น IP ผู้ใช้ ไม่ใช่ของ Cloudflare
sudo awk '$1 ~ /:/' /var/log/nginx/tpix-rpc.access.log | wc -l            # มีผู้ใช้ IPv6 จริงกี่บรรทัด
head -n 3 /etc/logrotate.d/nginx                                          # /var/log/nginx/*.log = ครอบ tpix-rpc.banned.log ด้วย
python3 -c 'import ipaddress, fcntl; print("python ok")'
```

หยุดก่อนถ้า: ไม่มี `geo $banned_ip` หรือมัน include ไฟล์อื่น · vhost บนเครื่องไม่ตรงกับ repo · ช่องแรกของ access log เป็น IP ของ Cloudflare
(`real_ip` ไม่ทำงาน — ลง jail นี้แล้วจะแบน edge ของ Cloudflare = ตัดผู้ใช้ทั้งก้อน) · unit ของ fail2ban ถูกจำกัดสิทธิ์เขียน

### 1) ลง — ต่อจากขั้น 1b + 1c (ไฟล์ของ branch นี้มีของสองขั้นนั้นอยู่ด้วย)

เดินครบแล้วบน lab ตามลำดับนี้ (ขั้น 4-5 ของ `rpc-ban-lab.sh`) ยกเว้นคำสั่ง `systemctl` ซึ่ง lab ใช้ HUP / stop-start ของตัวเองแทน

```bash
cd ~/TPIX-Coin && git pull
TS=$(date +%Y%m%d-%H%M%S)
sudo mkdir -p /etc/nginx/backup-$TS /etc/fail2ban/backup-$TS
sudo cp /etc/nginx/njs/tpix-rpc.js /etc/nginx/conf.d/05-tpix-njs.conf /etc/nginx/sites-available/tpix-rpc.conf \
        /etc/nginx/conf.d/tpix-banned.map /etc/nginx/backup-$TS/
sudo cp /etc/fail2ban/jail.d/tpix-rpc.conf /etc/fail2ban/filter.d/tpix-rpc.conf /etc/fail2ban/backup-$TS/

# 1) conf — log_format tpixban + js_set $rpc_ban_key (ยังไม่มีใครเรียก ไม่มีอะไรเปลี่ยน)
sudo cp infrastructure/single-host/nginx-njs.conf /etc/nginx/conf.d/05-tpix-njs.conf
sudo nginx -t && sudo systemctl reload nginx
sudo tail -n 20 /var/log/nginx/error.log        # ต้องไม่มี [emerg]

# 2) js — banKey (ยังไม่มีใครเรียก)
sudo cp infrastructure/njs/tpix-rpc.js /etc/nginx/njs/
sudo nginx -t && sudo systemctl reload nginx
sudo tail -n 20 /var/log/nginx/error.log

# 3) vhost — access_log เปลี่ยนเป็น tpixban + แยก log ของคนที่ถูกแบน
#    ⛔ ต้องหลังข้อ 2 เสมอ (ตารางกับดัก) · ถ้าข้อ 0 บอกว่า vhost บนเครื่องไม่ตรงกับ repo อย่าทับทั้งไฟล์
sudo cp infrastructure/single-host/nginx-rpc.conf /etc/nginx/sites-available/tpix-rpc.conf
sudo nginx -t && sudo systemctl reload nginx
sudo tail -n 20 /var/log/nginx/error.log
sudo tail -n 3 /var/log/nginx/tpix-rpc.access.log   # ช่องแรก: IPv4 = ที่อยู่ · IPv6 = ลงท้าย :: (เช่น 2001:db8:0:1::) · ต้องไม่ใช่ "-"
#    jail เดิมยังอ่าน log นี้ได้ (failregex ไม่เปลี่ยน) — ระหว่างข้อ 3 กับข้อ 4 ไม่มีอะไรแย่ลง

# 4) fail2ban — สคริปต์ + action + filter + jail แล้ว restart (ไม่ใช่ reload)
sudo install -m 0755 -o root -g root infrastructure/scripts/tpix-nginx-ban.py /usr/local/sbin/tpix-nginx-ban
sudo cp infrastructure/fail2ban/action.d/nginx-tpix-banned.conf /etc/fail2ban/action.d/
sudo cp infrastructure/fail2ban/filter.d/tpix-rpc.conf          /etc/fail2ban/filter.d/
sudo cp infrastructure/fail2ban/jail.d/tpix-rpc.conf            /etc/fail2ban/jail.d/
# กันแบนตัวเอง: IP สาธารณะของเครื่องนี้วนกลับผ่าน CF ตอนรัน verify
sudo sed -i 's|^ignoreip = 127.0.0.1/8 ::1|ignoreip = 127.0.0.1/8 ::1 123.253.62.252|' /etc/fail2ban/jail.d/tpix-rpc.conf
sudo fail2ban-regex /var/log/nginx/tpix-rpc.access.log /etc/fail2ban/filter.d/tpix-rpc.conf | grep -E "Failregex|Lines:"
sudo fail2ban-client -t                              # config ของ fail2ban ต้องผ่าน
sudo systemctl restart fail2ban                      # ตอนหยุด action เดิมเก็บกฎ iptables ของตัวเองไป · การแบนที่ยังไม่หมดเวลาถูกเขียนลง tpix-banned.map
sudo fail2ban-client status tpix-rpc                 # "File list:" ไม่ใช่ "Journal matches:"
sudo fail2ban-client get tpix-rpc actions            # nginx-tpix-banned
sudo iptables -S | grep f2b-tpix-rpc ; echo "ต้องว่าง"
grep -c '# tpix-nginx-ban ' /etc/nginx/conf.d/tpix-banned.map   # = จำนวนที่กำลังแบนอยู่
```

### 2) พิสูจน์ด้วยการยิงจริง — อย่าดูแค่ `status`

```bash
# บนเครื่องนอก (เครื่องที่ใช้ทดสอบ): ที่อยู่ของตัวเองตามที่ Cloudflare เห็น
curl -s https://rpc.tpix.online/cdn-cgi/trace -H 'User-Agent: Mozilla/5.0' | grep '^ip='

# บน tpixserver: แบนที่อยู่นั้น
sudo fail2ban-client set tpix-rpc banip <ที่อยู่จากบรรทัด ip=>
grep '# tpix-nginx-ban ' /etc/nginx/conf.d/tpix-banned.map       # IPv4 = ที่อยู่ · IPv6 = /64

# บนเครื่องนอก: รอ 5 วิ
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://rpc.tpix.online/ -H 'User-Agent: Mozilla/5.0' \
     -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'   # ต้องได้ 403

# บน tpixserver: เลิกแบน แล้วเครื่องนอกต้องกลับมาได้ 200
sudo fail2ban-client set tpix-rpc unbanip <ที่อยู่เดิม>
sudo tail -n 3 /var/log/nginx/tpix-rpc.banned.log                # คำขอที่โดน 403 เมื่อครู่อยู่ที่นี่ ไม่อยู่ใน access log
sudo tail -n 20 /var/log/tpix-nginx-ban.log                      # ADD / RELOAD / REMOVE
```

ถอยกลับ: `sudo cp /etc/fail2ban/backup-$TS/* ` กลับที่เดิม (jail → `jail.d/`, filter → `filter.d/`) แล้ว `sudo systemctl restart fail2ban`
(ตอนหยุด action ใหม่ลบบรรทัดของตัวเองออกจาก `tpix-banned.map` ให้) · vhost / js / conf คืนจาก `/etc/nginx/backup-$TS/` ตามลำดับย้อนกลับ vhost → js → conf

### ยืนยันบน lab แล้ว (2026-11-20 · Ubuntu 24.04: nginx 1.24.0 + njs 0.8.2 + fail2ban 1.0.2 + iptables 1.8.10)

- **ของเดิมแบนไม่ติด** (jail + filter + vhost ที่ `38eb23b`, `iptables-multiport` ตัวจริง): fail2ban แบน IPv4 และ IPv6 → กฎ iptables / ip6tables เกิดจริง
  → คำขอของที่อยู่นั้นผ่าน "Cloudflare" ยังได้ 200 ตัวนับแพ็กเก็ตของกฎเป็น 0 · กฎรูปเดียวกันในเชนเดียวกันบล็อกได้เมื่อต้นทางของแพ็กเก็ตตรง (ต่อตรงจาก 127.0.0.2)
- **ของเดิมนับต่อที่อยู่เต็ม**: 12 ที่อยู่ใน /64 เดียวถูกปฏิเสธที่อยู่ละครั้ง — fail2ban เห็นครบ 12 ครั้ง ไม่แบนใคร · ที่อยู่เดียว 12 ครั้งถูกแบน (แล้วก็ยังอ่านได้)
- `geo $banned_ip` เทียบกับที่อยู่ผู้ใช้หลัง `real_ip`: บรรทัดที่คนใส่มือบล็อกได้จริงตั้งแต่ vhost เดิม · บรรทัด IPv4 จับรูป `::ffff:` ของตัวเองด้วย
- ลำดับ conf → js → vhost ใช้ `reload` ได้ทุกข้อ · restart fail2ban: กฎ iptables ของ action เดิมหายหมด การแบนที่ค้างอยู่ 3 รายการถูกเขียนลง `tpix-banned.map`
  แล้วได้ 403 (ที่อยู่ IPv6 เดี่ยวที่ jail เดิมแบนไว้ กลายเป็นทั้ง /64)
- **ของใหม่**: 12 ที่อยู่ใน /64 เดียว → แบนทั้ง /64 (ที่อยู่ที่ยังไม่เคยใช้ก็ 403) · /64 ที่ติดกันไม่โดน · IPv4 ยังนับต่อที่อยู่ · IPv4 สลับกับรูป `::ffff:` ถูกนับรวมกัน
- คำขอ 15 ครั้งของคนที่ถูกแบนอยู่: `Total failed` ไม่ขยับ ไม่มี reload เพิ่ม ลง `tpix-rpc.banned.log` ด้วยที่อยู่เต็ม · อ่านสำเร็จ 25 ครั้งไม่ถูกนับ
  · `fail2ban-regex` จับบรรทัดที่ถูกปฏิเสธครบและไม่จับบรรทัด 200
- เลิกแบน: บรรทัดหาย ใช้ได้ภายในไม่กี่วิ · บรรทัดที่คนใส่มืออยู่ครบตลอด · แบน 20 ที่อยู่ติดกัน = reload 2 ครั้ง (ไม่ใช่ 20)
  · หยุด fail2ban = บรรทัดของมันหายหมดด้วย reload ครั้งเดียว · ของที่ไม่ใช่ที่อยู่ถูกปฏิเสธ ไฟล์ไม่ถูกแตะ · `nginx -t` ผ่านหลังเขียนไฟล์ทุกครั้ง
- ผิดลำดับ: vhost ก่อน conf → `nginx -t` ฟ้อง `unknown log format "tpixban"` · vhost ก่อน js → `nginx -t` ผ่าน ช่องแรกของ log เป็น `-`
  fail2ban แมตช์ 0 บรรทัด และ error log ก็ไม่มีบรรทัดไหนฟ้อง
- `js_set` ที่ยังไม่มีใครเรียก กับ `tpix-rpc.js` เดิมที่ไม่มี `banKey`: ไม่มี error (ขั้น 4 ของ lab นี้ และ `rpc-gate-lab.sh` ขั้น 2)
- ตัวเขียนไฟล์ (`scripts/tests/test_tpix_nginx_ban.py`, คำสั่ง test/reload ปลอม): `nginx -t` ไม่ผ่าน → คืนไฟล์เดิมทั้งตอนแบนและเลิกแบน
  · ไฟล์หาย → error ไม่สร้างไฟล์ใหม่ · สิทธิ์ไฟล์คงเดิม · แบน 20 ครั้งติดกัน = reload 2 ครั้ง

### ที่ lab พิสูจน์ไม่ได้ / ยังไม่ได้ลอง

- สถานะจริงของเครื่อง — ทุกอย่างในตารางบนสุดของขั้นนี้มาจากการอ่าน repo และจาก lab ไม่ได้มาจาก `tpixserver` (ข้อ 0)
- Cloudflare ตัวจริง: lab ให้ 127.0.0.1 เป็น "Cloudflare" และใส่ `CF-Connecting-IP` เอง · ufw ของเครื่อง
- `10-tpix-http.conf` ของเครื่อง — `geo $banned_ip` กับ path ที่มัน include มาจากไฟล์นั้น lab ใช้ไฟล์จำลอง (ข้อ 0 จ. เช็กให้)
- `systemctl reload nginx` / `systemctl restart fail2ban` — lab ส่ง HUP และ stop-start เอง · fail2ban ภายใต้ systemd unit ของเครื่อง (สิทธิ์เขียน `/etc/nginx`, `/run`, `/var/log`)
- `fail2ban-client reload` แทน restart ตอนเปลี่ยน action — ไม่ได้ลอง ใช้ restart
- ต้นทุนของ `js_set $rpc_ban_key`: ทุกคำขอที่ลง access log เรียก njs หนึ่งครั้ง รวมคำขอที่ `limit_req` ตัดก่อนถึงด่าน — ไม่ได้วัดภายใต้โหลด
  (คำขอของคนที่ถูกแบนแล้วไม่เรียก — ไปอีก log ที่ใช้ `$remote_addr`)
- reload nginx ระหว่างมีโหลดจริงและ connection ค้างจาก Cloudflare · การแบนหลายร้อยที่อยู่ในนาทีเดียว (lab: 20 ที่อยู่)
- `bantime.increment` ข้ามรอบ (แบนซ้ำแล้วนานขึ้น) · logrotate ของ `tpix-rpc.banned.log` · รุ่น fail2ban ของเครื่องถ้าไม่ใช่ 1.0.2

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
| `limit_req` 30 r/s + `limit_conn` 10 | เพดานหยาบต่อ IP จริง | ✅ (มีอยู่เดิม) · IPv6 ยังนับต่อที่อยู่เต็ม จนกว่าจะลงขั้น 1c |
| njs deny-list | `admin_*` `debug_*` `txpool_*` `eth_sign` ฯลฯ | ✅ |
| njs allow-list | เมธอดที่ไม่รู้จัก = ปฏิเสธ | ✅ |
| **njs โควตาเขียน 10 tx / 10 วิ / IP** | **แกนของงานนี้** นับรายธุรกรรม batch 20 = 20 หน่วย | ✅ · IPv6 ยังนับต่อที่อยู่เต็ม จนกว่าจะลงขั้น 1c |
| njs งบแก๊ส 12M / 60 วิ / IP | ธุรกรรมใหญ่จาก IP เดียวทำให้ทุกบล็อกเต็ม | ⏳ ขั้น 1b — ผ่าน lab ยังไม่ได้ลง |
| กุญแจ /64 สำหรับ IPv6 (njs + `limit_req`/`limit_conn`) | /64 เดียวหมุนที่อยู่เพื่อเอาถังใหม่ | ⏳ ขั้น 1c — ผ่าน lab ยังไม่ได้ลง |
| `--max-enqueued 16` | 1 address จองได้ 16 ช่อง (เดิม 128) | ✅ |
| `--block-gas-target 10M` | ครึ่งเดียวของอัตราถมดิสก์สูงสุด | ✅ |
| fail2ban | ปฏิเสธ 10 ครั้ง/60 วิ → แบน 1 ชม. เพิ่มเท่าตัวถ้าซ้ำ | ⚠️ jail ติดตั้งแล้ว (2026-08-28) แต่ action เป็น `iptables-multiport` ซึ่งแบนไม่ถึงคำขอที่ผ่าน Cloudflare (อ่านจาก repo + เห็นบน lab · ยังไม่ได้ดูบนเครื่อง — ขั้น 3 ข้อ 0) · ⏳ action ใหม่ + นับ IPv6 ต่อ /64: ผ่าน lab ยังไม่ได้ลง |
| watchdog | ดิสก์ 75/88% · mempool ค้าง · บล็อกเต็ม | ✅ |

**คนยิงถล่มต้องมี ~240 IP จริงที่ผ่าน Cloudflare** ถึงจะได้ปริมาณเท่าที่ IP เดียวเคยทำได้
(ตัวเลขนี้จริงกับ IPv4 เท่านั้น — กับ IPv6 "IP จริง" ต้องแปลว่า /64 ซึ่งยังไม่เป็นอย่างนั้นจนกว่าจะลงขั้น 1c)

---

## ยังไม่ได้แก้

- โหนด RPC สาธารณะยังชี้เข้า validator ที่ `--seal` และถือคีย์ — ควรมีโหนดที่ไม่ seal แยก
- validator 4 ตัวอยู่เครื่องเดียว ทน BFT ได้แค่ 1 ตัวพัง
- คีย์ validator เก็บแบบไม่เข้ารหัส (`--insecure`)
- `$origin_ok` token gate ยัง `default 1` (ต้องตั้ง Transform Rule ที่ Cloudflare ก่อน)
- **IPv6 ที่ใหญ่กว่า /64** — ขั้น 1c ตัดที่ /64 ซึ่งเป็นหน่วยเล็กสุดที่ผู้ให้บริการแจก ผู้ที่ถือ /56 ยังมี 256 ถัง
  และ /48 มี 65,536 ถัง (tunnel broker แจก /48 ฟรี) ยังไม่ได้ตัดกว้างกว่านี้เพราะผู้ให้บริการมือถือแจก /64 ต่อเครื่อง
  จากบล็อกเดียวกัน ตัดที่ /48 = ผู้ใช้จริงหลายหมื่นรายใช้ถังเดียว ทางที่ยังไม่ได้ออกแบบ: ถังชั้นที่สองต่อ /48 ที่งบใหญ่กว่า
  หรือกฎ rate limit ของ Cloudflare ที่นับต่อ prefix
- **fail2ban หลัง Cloudflare** — ขั้น 3 (action `nginx-tpix-banned` + นับ IPv6 ต่อ /64) ผ่าน lab แล้ว ยังไม่ได้ลง และยังไม่ได้ยืนยันบนเครื่องว่า
  การแบนของ jail เดิมไม่มีผลจริง (ขั้น 3 ข้อ 0 — คำสั่งอ่านอย่างเดียว) ที่ยังเหลือหลังลง:
  - **เกณฑ์แบนยังไม่เคยถูกใช้กับผู้ใช้จริง** — 10 ครั้ง/60 วิ → 1 ชม. ตั้งไว้ตอนที่การแบนไม่มีผล หน้าเว็บที่ยิงอ่านพร้อมกันเกิน 30 r/s
    ได้ 429 เป็นชุดและถึงเกณฑ์ได้ในวินาทีเดียว ดูจำนวนจากขั้น 3 ข้อ 0 ข. ก่อน ถ้ามากให้ปรับ `maxretry` / ตัด 429 ของ `limit_req` ออกจาก filter
  - **ถ้า `real_ip` หยุดทำงาน** ช่องแรกของ log กลายเป็น IP ของ Cloudflare แล้ว jail จะแบน edge ของ Cloudflare = ตัดผู้ใช้ทั้งก้อน
    (action เดิมก็เป็นแบบเดียวกัน) กันได้ด้วยการใส่ช่วง IP ของ Cloudflare กลับเข้า `ignoreip` — เมื่อ `real_ip` ทำงาน ที่อยู่ผู้ใช้ไม่อยู่ในช่วงนั้น
    จึงไม่กระทบการแบนปกติ แต่ comment ใน jail ห้ามไว้ (2026-08-28) และจะทำให้คำขอจาก Cloudflare Workers แบนไม่ได้ — ยังไม่ได้เปลี่ยน รอตัดสิน
  - **หมุนข้าม /64** (ผู้ถือ /56, /48) ยังไม่ถึงเกณฑ์ต่อ /64 เหมือนเดิม — ข้อเดียวกับ "IPv6 ที่ใหญ่กว่า /64" ข้างบน
  - **แบนที่ nginx ยังกินแรงเครื่อง** — คำขอของคนที่ถูกแบนยังมาถึง origin (TLS + 403 + หนึ่งบรรทัดใน `tpix-rpc.banned.log`) ถ้าโดนยิงหนักจน log โต
    ทางถัดไปคือแบนที่ขอบ Cloudflare ด้วย: เพิ่ม `cloudflare-tpix` เป็น action ที่สองของ jail — ต้องแก้ `cf-ban-ip.sh` ให้ส่ง IPv6 เป็น /64
    และติดตั้ง token ก่อน (`install-cf-autoban.sh`) ยังไม่ได้ทำ
- `infrastructure/nginx-rpc.conf` (ชั้นนอก ฉบับเก่า) กับ `scripts/harden-rpc.sh` ยังประกาศโซนด้วย `$binary_remote_addr` — ไม่ได้แตะ
  และ `harden-rpc.sh` / `SECURITY_RUNBOOK.md` ข้อ 2.4 ยัง copy แค่ filter กับ jail: jail ฉบับใหม่เรียก action `nginx-tpix-banned`
  ซึ่งสองที่นั้นไม่ได้ติดตั้ง — ใช้ขั้น 3 ของเอกสารนี้แทน (ยังไม่ได้ลองว่า fail2ban ฟ้องอย่างไรเมื่อหา action ไม่เจอ)
