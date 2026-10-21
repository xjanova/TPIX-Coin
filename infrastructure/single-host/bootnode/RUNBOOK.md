# รันบุ๊ก: เปิด bootnode สาธารณะ + รายงาน peer ให้ uptime oracle

> เครื่อง: `tpixserver` 123.253.62.252 · เข้าด้วย ssh profile **`tpix-chain-new`** (ผู้ใช้ `tpixadmin` + sudo)
> **ทุกคำสั่งในไฟล์นี้เจ้าของเป็นคนรันเอง / อนุมัติทีละขั้น** — ไม่มีอะไรรันอัตโนมัติจาก repo
> เหตุผลการออกแบบทั้งหมด (ทำไมพอร์ต 30301, ทำไมแยก compose, ความเสี่ยง gossip) อยู่ที่
> [`docs/MASTERNODE_PUBLIC_BOOTNODE.md`](../../../docs/MASTERNODE_PUBLIC_BOOTNODE.md)

## ทำไมต้องมี

1. แอปมาสเตอร์โหนดซิงก์เชนไม่ได้เลย — พอร์ต libp2p ของ validator ไม่ได้เปิดออกเน็ต (ตั้งใจ)
   แอปจึงตกไปโหมดเฝ้าดูเชนทุกเครื่อง
2. uptime oracle บน tpix.online นับว่าโหนด "รันจริง" ก็ต่อเมื่อ **bootnode ตัวนี้เห็น peer ID ของโหนดต่ออยู่**
   ไม่มี bootnode = ไม่มีใครพิสูจน์ได้ = ห้ามเรียก `setUptimeOracle`

## ไฟล์ในโฟลเดอร์นี้

| ไฟล์ | ไปอยู่ที่ |
|---|---|
| `docker-compose.yml` | `/opt/tpix-bootnode/docker-compose.yml` |
| `tpix-p2p-firewall` | `/usr/local/sbin/tpix-p2p-firewall` (0755) |
| `tpix-p2p-firewall.service` | `/etc/systemd/system/tpix-p2p-firewall.service` |
| `tpix-node-peers` | `/usr/local/sbin/tpix-node-peers` (0755) |
| `tpix-node-peers.cron` | `/etc/cron.d/tpix-node-peers` (0644) |
| `tpix-node-peers.test.js` | ไม่ติดตั้ง — `node --test infrastructure/single-host/bootnode/tpix-node-peers.test.js` |

**ต่างจากข้อเสนอเดิมจุดเดียว:** `--max-inbound-peers 150` (เดิม 48) เพราะทุกโหนดที่จะได้รางวัล
ต้องต่อ bootnode นี้ค้างไว้ · เกิน ~150 โหนดให้เพิ่ม bootnode ตัวที่สอง (ข้อเสนอ §4.6)

---

## ขั้น 0 — แนะนำทำก่อน: ผูก gRPC แอดมินของ validator ไว้ใน container

แตะ validator → **ต้องถือ maintenance lock** · ทำตามข้อเสนอ §4.4 + §5 "Phase 0" ทุกบรรทัด
(ปิดทางที่ container บนเครือข่าย `tpix_tpix` จะสั่ง `ibft propose` ได้ ก่อนเอา container ที่หันออกเน็ตเข้ามาในเครือข่ายเดียวกัน)

## ขั้น 1 — ตรวจก่อนเริ่ม (อ่านอย่างเดียว)

```bash
date -u                                        # ต้องไม่อยู่ช่วง 18:45–20:00 UTC (backup 19:17 UTC = 02:17 ไทย)
for p in 8545 8546 8547 8548; do curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"net_peerCount","params":[]}' http://127.0.0.1:$p; echo; done   # 0x3 ทุกตัว
ss -ltn | grep -E ':(30301|8549)\b' || echo "30301/8549 ว่าง"
sudo docker network inspect tpix_tpix -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}'   # 172.18.0.0/16
df -h /opt                                      # เหลือ ≥ 5 GB
cd ~/TPIX-Coin && git fetch && git checkout <บรานช์/แท็กที่ merge แล้ว> && git log --oneline -1
```

## ขั้น 2 — กุญแจและ peer ID ของ bootnode

```bash
sudo install -d -m 700 /opt/tpix-bootnode /opt/tpix-bootnode/data
sudo docker run --rm -v /opt/tpix-bootnode/data:/data 0xpolygon/polygon-edge:0.9.0 secrets init --data-dir /data --insecure
sudo docker run --rm -v /opt/tpix-bootnode/data:/data 0xpolygon/polygon-edge:0.9.0 secrets output --data-dir /data --node-id
```

**ตรวจ:** ได้ `16Uiu2HAm…` ตัวเดียว → จด `/ip4/123.253.62.252/tcp/30301/p2p/<ID นั้น>`
`sudo ls /opt/tpix-bootnode/data` เห็นแค่ `consensus libp2p` · **ห้ามคัดลอกกุญแจจาก validator/backup มาใส่**

## ขั้น 3 — compose stage 1 (P2P อยู่แค่ loopback)

```bash
sudo cp ~/TPIX-Coin/infrastructure/single-host/bootnode/docker-compose.yml /opt/tpix-bootnode/docker-compose.yml
cd /opt/tpix-bootnode && sudo docker compose config -q && echo "compose OK"
sudo docker compose config | grep -E 'host_ip|published'     # 127.0.0.1 ทั้งสองพอร์ต
```

## ขั้น 4 — เริ่ม แล้วให้ sync จาก validator (เฝ้าเชนไปด้วย)

```bash
cd /opt/tpix-bootnode && sudo docker compose up -d
sudo docker logs --tail 20 tpix-bootnode | grep -E 'LibP2P server running|error'
```

ตรวจทุกไม่กี่นาทีจนห่างหัวเชน ≤ 2 บล็อก:

```bash
bn() { curl -s -X POST -H 'Content-Type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' http://127.0.0.1:$1 | grep -o '0x[0-9a-f]*'; }
echo "validator=$((16#$(bn 8545 | cut -c3-))) bootnode=$((16#$(bn 8549 | cut -c3-)))"
sudo docker exec tpix-validator-1 polygon-edge peers list --grpc-address 127.0.0.1:10000 | grep 'Number of peers'   # 4
sudo docker stats --no-stream tpix-bootnode tpix-validator-1 tpix-validator-2 tpix-validator-3 tpix-validator-4
tail -5 /var/log/tpix-watchdog.log                          # ไม่มี "RESTARTING chain"
```

block time ของ validator แย่ลง / watchdog เจอ stall → `sudo docker stop tpix-bootnode` แล้วค่อยลองใหม่ด้วย `cpus: 1.0`

## ขั้น 5 — ไฟร์วอลล์ (ก่อนเปิดสาธารณะ)

```bash
cd ~/TPIX-Coin/infrastructure/single-host/bootnode
sudo install -m 0755 tpix-p2p-firewall /usr/local/sbin/tpix-p2p-firewall
sudo install -m 0644 tpix-p2p-firewall.service /etc/systemd/system/tpix-p2p-firewall.service
sudo systemctl daemon-reload && sudo systemctl enable --now tpix-p2p-firewall
```

**ตรวจ:**

```bash
sudo /usr/local/sbin/tpix-p2p-firewall status | grep -c 'tpix-p2p-'      # 4
sudo docker exec tpix-bootnode sh -c 'wget -q -O /dev/null -T 8 https://binaries.soliditylang.org/linux-amd64/list.json && echo "https egress OK"'
sudo docker exec tpix-bootnode sh -c 'nc -z -w 3 1.1.1.1 853 && echo "LEAK: egress open" || echo "non-web egress blocked"'
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4000/api/v2/stats   # explorer ยัง 200
```

## ขั้น 6 — เปิดสาธารณะ (stage 2)

```bash
sudo sed -i 's|- "127.0.0.1:30301:30301/tcp"|- "0.0.0.0:30301:30301/tcp"|' /opt/tpix-bootnode/docker-compose.yml
grep -n '30301:30301' /opt/tpix-bootnode/docker-compose.yml     # บรรทัด "- " เป็น 0.0.0.0 แล้ว
cd /opt/tpix-bootnode && sudo docker compose up -d                # สร้างใหม่แค่ tpix-bootnode ข้อมูลอยู่ครบ
sudo docker exec tpix-bootnode polygon-edge status --grpc-address 127.0.0.1:10000 | grep 'Libp2p Address'
#   → /ip4/123.253.62.252/tcp/30301/p2p/<BOOTNODE_PEER_ID>
```

**ตรวจจากนอกเครื่อง (PowerShell บน PC เจ้าของ):**

```powershell
Test-NetConnection 123.253.62.252 -Port 30301 | Select TcpTestSucceeded   # True
Test-NetConnection 123.253.62.252 -Port 10001 | Select TcpTestSucceeded   # False (validator ยังปิด)
Test-NetConnection 123.253.62.252 -Port 8549  | Select TcpTestSucceeded   # False (RPC อยู่ใน loopback)
```

## ขั้น 7 — รายงาน peer ให้ tpix.online (uptime oracle)

ต้องได้ token ก่อน: สุ่ม ≥ 32 ตัว ใส่ `.env` ของเว็บเป็น `TPIX_NODE_PEERS_TOKEN` (ขั้นตอนฝั่งเว็บ:
`ThaiXTrade/docs/MASTERNODE_UPTIME_ORACLE.md`) แล้วใส่ค่าเดียวกันที่นี่

```bash
cd ~/TPIX-Coin/infrastructure/single-host/bootnode
sudo install -m 0755 tpix-node-peers /usr/local/sbin/tpix-node-peers
sudo install -m 0600 /dev/null /etc/tpix-node-peers.env
sudoedit /etc/tpix-node-peers.env       # TPIX_NODE_PEERS_TOKEN=<token เดียวกับเว็บ>
sudo /usr/local/sbin/tpix-node-peers; echo "exit=$?"
sudo tail -5 /var/log/tpix-node-peers.log 2>/dev/null || echo "ไม่มี log = ส่งสำเร็จ"
sudo install -m 0644 tpix-node-peers.cron /etc/cron.d/tpix-node-peers
```

**ตรวจ:** ไม่มีบรรทัด `report failed` ใน log · ฝั่งเว็บ `masternode_peer_reports` มีแถว `source = tpix-bootnode`
เพิ่ม `reports` ทีละ 1 ทุกนาที (≈ 5 ต่อช่อง 5 นาที)

script นี้อ่านอย่างเดียว (docker inspect + peers list) ไม่ restart อะไร ไม่ต้องถือ maintenance lock
bootnode ไม่รัน/ถามไม่ได้ = **ไม่ส่งอะไรเลย** → เว็บถือว่าข้อมูลขาด แล้วไม่ลด uptime ของใครในชั่วโมงนั้น

## ขั้น 8 — บอกแอปผ่านเว็บ (ไม่ต้องปล่อยแอปใหม่)

ใน `.env` ของเว็บ: `MASTERNODE_PUBLIC_BOOTNODES=/ip4/123.253.62.252/tcp/30301/p2p/<BOOTNODE_PEER_ID>`
แล้ว `php artisan config:cache` · แอปรุ่นที่มี heartbeat อ่านค่านี้จาก `/api/v1/masternode/config` ทุก 30 นาที
และใช้ตอนกดเริ่มโหนดครั้งถัดไป

**ตรวจ:** log ของแอปขึ้น `ต่อ bootnode ได้ 1 ตัว — เริ่มโหนดจริง` แล้วบล็อกขยับ ·
บนเครื่องเชน `curl … net_peerCount @127.0.0.1:8549` ≥ 5

## ขั้น 9 — กันไฟล์บนเครื่องเพี้ยนจาก repo

เพิ่มหนึ่งบรรทัดใน `single-host/README.md` และ `CHAIN_HOST`: มี bootnode สาธารณะ ไม่ใช่ validator
สวิตช์ฉุกเฉินคือ `docker stop tpix-bootnode` · cron `tpix-node-peers` ส่งรายชื่อ peer ให้เว็บ

---

## ถอยกลับ

| ระดับ | คำสั่ง | ผล |
|---|---|---|
| **สวิตช์ฉุกเฉิน** (วินาที, validator ไม่กระทบ) | `sudo docker stop tpix-bootnode` | peer ชุมชนหลุดหมด แอปกลับโหมดเฝ้าดู · uptime oracle เห็นรายงานขาด → ไม่ลดใคร · คืน: `sudo docker start tpix-bootnode` |
| หยุดรายงาน peer | `sudo rm /etc/cron.d/tpix-node-peers` | เว็บเห็นรายงานขาด → ไม่ลดใคร (ไม่ใช่ทุกคนได้ 0) |
| ปิดสาธารณะ | แก้พอร์ตกลับ `127.0.0.1:30301:30301/tcp` แล้ว `cd /opt/tpix-bootnode && sudo docker compose up -d` | สร้างใหม่แค่ bootnode |
| ถอดกฎไฟร์วอลล์ | `sudo systemctl disable --now tpix-p2p-firewall` | ExecStop ลบทุกกฎ `tpix-p2p-*` |
| ถอด container | `cd /opt/tpix-bootnode && sudo docker compose down` | validator เห็นเพียร์ 4 → 3 · เครือข่าย `tpix_tpix` ไม่ถูกลบ |
| ลบข้อมูล | `sudo rm -rf /opt/tpix-bootnode` | **ลบถาวร** — มีแค่กุญแจทิ้งได้กับสำเนาเชน · เจ้าของยืนยันก่อนเสมอ |
| ขั้น 0 | คืน `/opt/tpix/docker-compose.yml.bak-<ts>` แล้ว `sudo flock -w 900 /run/tpix-chain-maint.lock bash infrastructure/single-host/apply-rolling.sh` | — |

⚠️ ถ้าเจ้าของเรียก `setUptimeOracle` ไปแล้ว การหยุด bootnode **นาน** ทำให้ไม่มีใครพิสูจน์ได้ว่ารันอยู่
(รอบที่รายงานขาดระบบไม่ลดใคร แต่ก็ไม่ยกใครขึ้นด้วย — โหนดใหม่จะค้างที่ 0) ถ้าต้องปิดนานให้ `setUptimeOracle(0x0)` ก่อน

## เฝ้าดูประจำ

| อะไร | คำสั่ง |
|---|---|
| เพียร์ | `curl … net_peerCount @127.0.0.1:8549` |
| ห่าง validator | `bn 8545` เทียบ `bn 8549` |
| การเชื่อมต่อขาเข้า | `sudo docker exec tpix-bootnode netstat -tn \| grep -c ':30301 .*ESTABLISHED'` |
| ตัวนับกฎไฟร์วอลล์ | `sudo /usr/local/sbin/tpix-p2p-firewall status` |
| CPU / RAM / เน็ต | `sudo docker stats --no-stream tpix-bootnode` |
| รายงาน peer | `sudo tail /var/log/tpix-node-peers.log` (ว่าง = ปกติ) |
