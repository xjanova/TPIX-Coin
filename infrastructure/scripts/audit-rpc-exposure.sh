#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  audit-rpc-exposure.sh — สำรวจว่าอะไรเปิดอยู่จริงบนเซิร์ฟเวอร์ (อ่านเท่านั้น)
# ══════════════════════════════════════════════════════════════════════════════
#
#  เขียนขึ้นเพราะ repo กับของจริงบนเซิร์ฟเวอร์ไม่ตรงกันหลายจุด:
#    · โน้ต "xman4289 server stack + DirectAdmin/Cloudflare setup" บอกว่าเครื่อง
#      DirectAdmin ใช้ Apache ไม่มี nginx บน host เลย
#    · แต่ `docker-compose.yml` มี service `rpc-lb` (nginx:alpine) map port 80:80
#    · ยังไม่ยืนยันว่า container นั้นรันอยู่จริง หรือ RPC อยู่คนละเครื่อง
#  ⇒ ต้องรู้สถานะจริงก่อน ไม่ควรแก้ไฟร์วอลล์บนสมมติฐาน
#
#  สคริปต์นี้ **ไม่เปลี่ยนอะไรเลย** รันได้ปลอดภัยบน production
#
#  ใช้:  sudo bash audit-rpc-exposure.sh            # รายงานบนจอ
#        sudo bash audit-rpc-exposure.sh > rpt.txt  # เก็บไฟล์มาให้ดู
# ══════════════════════════════════════════════════════════════════════════════
set -uo pipefail

hr()  { printf '─%.0s' {1..74}; echo; }
sec() { echo; hr; echo "▸ $*"; hr; }

echo "TPIX RPC exposure audit — $(date -u +%Y-%m-%dT%H:%M:%SZ) UTC"
echo "host: $(hostname)  ·  kernel: $(uname -r)  ·  arch: $(uname -m)"

sec "1. พอร์ตที่เปิดฟังอยู่ (สนใจ 80/443/8545/8546-8548/10000/10001)"
if command -v ss >/dev/null; then
  ss -tlnp 2>/dev/null | awk 'NR==1 || /:(80|443|8545|8546|8547|8548|10000|10001)\s/'
else
  netstat -tlnp 2>/dev/null | grep -E ':(80|443|8545|8546|8547|8548|10000|10001)\s'
fi
echo
echo "  ⚠️ ตีความ: อะไรที่ผูก 0.0.0.0 หรือ * = เข้าถึงได้จากเน็ต"
echo "     ถ้าเห็น 0.0.0.0:10000 → gRPC admin เปิดอยู่ = SECURITY-AUDIT ข้อ I1"
echo "     ถ้าเห็น 0.0.0.0:8545  → JSON-RPC ตรงถึง validator ข้าม nginx ได้"

sec "2. container ที่รันอยู่ + port mapping จริง"
if command -v docker >/dev/null; then
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null
  echo
  echo "  มี rpc-lb (nginx) รันอยู่ไหม:"
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'rpc-lb'; then
    echo "    ✅ มี — nginx-rpc.conf มีผลจริง คุ้มที่จะแก้"
    echo "    ทดสอบ config ก่อน reload:"
    echo "      docker exec tpix-rpc-lb nginx -t"
    echo "      docker exec tpix-rpc-lb nginx -s reload"
  else
    echo "    ❌ ไม่มี — nginx-rpc.conf อาจไม่ได้ถูกใช้เลย"
    echo "       ตรวจว่า RPC ปลายทางจริงคืออะไร: Apache vhost / Cloudflare Tunnel /"
    echo "       เครื่องอื่น — ก่อนเสียเวลาแก้ไฟล์ nginx"
  fi
else
  echo "  ไม่มี docker บนเครื่องนี้ → RPC อาจอยู่คนละเครื่อง"
fi

sec "3. compose ไฟล์ไหนที่ใช้งานจริง"
for d in /home/admin/tpix-infrastructure /opt/tpix-node "$HOME/TPIX-Coin/infrastructure"; do
  [[ -d "$d" ]] || continue
  echo "  $d:"
  ls -la "$d"/*.yml 2>/dev/null | awk '{print "    " $NF "  (" $5 " bytes, " $6" "$7" "$8 ")"}'
done
echo
echo "  หมายเหตุ: /home/admin/tpix-infrastructure คือชุดที่เชนเดินอยู่จริง (OLD compose)"
echo "            ไม่ใช่ชุดใน repo — ห้ามสับสน"

sec "4. genesis ที่ใช้งานจริง — validator set ว่างหรือไม่"
for g in /home/admin/tpix-infrastructure/genesis.json /opt/tpix-node/genesis.json; do
  [[ -f "$g" ]] || continue
  LEN=$(python3 -c "
import json
try:
    print(len(json.load(open('$g'))['genesis']['extraData']))
except Exception as e:
    print('อ่านไม่ได้:', e)
" 2>/dev/null)
  printf "  %-52s extraData ยาว %s\n" "$g" "$LEN"
  case "$LEN" in
    82)  echo "      🔴 validator set ว่าง — เชนจะค้างบล็อก 0" ;;
    ''|*[!0-9]*) echo "      ⚠️ ตรวจไม่ได้" ;;
    *)   [[ "$LEN" -gt 600 ]] && echo "      ✅ มี validator ครบ (ตัวที่ใช้งานได้)" \
                              || echo "      ⚠️ ความยาวผิดปกติ ตรวจด้วย genesis-verify.py" ;;
  esac
done

sec "5. สิทธิ์ไฟล์คีย์ validator (SECURITY-AUDIT ข้อ I2)"
found=0
for d in /home/admin/tpix-infrastructure/data /opt/tpix-node/data; do
  [[ -d "$d" ]] || continue
  found=1
  find "$d" -name "*.key" -o -name "validator*" -type f 2>/dev/null | head -12 | while read -r f; do
    printf "  %s  %s\n" "$(stat -c '%a %U:%G' "$f" 2>/dev/null)" "$f"
  done
done
[[ "$found" -eq 0 ]] && echo "  ไม่พบ data dir ที่คาดไว้"
echo
echo "  ที่ต้องการ: ไฟล์คีย์ = 600, ไดเรกทอรี consensus = 700"
echo "  ถ้าเห็น 644 หรือ 755 → ใครอ่านไฟล์ได้ก็ปลอมเป็น validator ตัวนั้นได้"

sec "6. ไฟร์วอลล์ปัจจุบัน"
if command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
  echo "  firewalld: active"
  firewall-cmd --list-all 2>/dev/null | sed 's/^/    /'
else
  echo "  iptables INPUT:"
  iptables -L INPUT -n --line-numbers 2>/dev/null | head -25 | sed 's/^/    /'
fi

sec "7. fail2ban — jail จับ 429 ได้จริงหรือไม่ (ข้อ N3)"
if command -v fail2ban-client >/dev/null; then
  fail2ban-client status 2>/dev/null | sed 's/^/  /'
  echo
  for f in /etc/fail2ban/filter.d/tpix-rpc.conf /etc/fail2ban/jail.d/tpix-rpc.conf; do
    if [[ -f "$f" ]]; then
      echo "  $f:"
      grep -nE "failregex|logpath|maxretry|findtime|bantime" "$f" 2>/dev/null | sed 's/^/    /'
    fi
  done
  echo
  echo "  ⚠️ ถ้า failregex จับ ' 429 ' แต่ nginx เดิมแปลง 429→403 อยู่"
  echo "     jail นี้จะไม่เคยแบนใครเลย — นับจำนวนใน access log เทียบกันได้:"
  echo "       docker logs tpix-rpc-lb 2>&1 | grep -c ' 429 '"
  echo "       docker logs tpix-rpc-lb 2>&1 | grep -c ' 403 '"
else
  echo "  ไม่มี fail2ban ติดตั้ง"
fi

sec "8. ทดสอบจากภายนอกด้วยตัวเอง (คำสั่งให้ก๊อปไปรัน — สคริปต์ไม่รันให้)"
cat <<'EOF'
  # gRPC admin ต้องต่อไม่ได้จากเน็ต
  nc -zv <public-ip> 10000        ← ต้อง "refused/timeout"

  # JSON-RPC ตรงต้องต่อไม่ได้ (ต้องผ่าน rpc.tpix.online เท่านั้น)
  nc -zv <public-ip> 8545         ← ต้อง "refused/timeout"

  # libp2p ต้องต่อได้จาก IP เพื่อนเท่านั้น
  nc -zv <public-ip> 10001        ← ต่อได้จากโหนดเพื่อน, ไม่ได้จากที่อื่น

  # deny-list ใหม่ทำงานไหม (ต้องได้ 403)
  curl -s -o /dev/null -w '%{http_code}\n' -X POST https://rpc.tpix.online \
    -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"admin_addPeer","params":[]}'

  # ช่องโหว่ N1 เดิม (ยัดสตริงใน params) — ต้องได้ 403 ด้วย
  curl -s -o /dev/null -w '%{http_code}\n' -X POST https://rpc.tpix.online \
    -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"admin_addPeer","params":["\"method\":\"eth_call\""]}'

  # เมธอดปกติต้องยังได้ 200
  curl -s -X POST https://rpc.tpix.online -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}'
EOF

echo
hr
echo "จบรายงาน — ส่งไฟล์นี้กลับมาให้ดูได้ ไม่มีข้อมูลลับ (ไม่ได้ cat ไฟล์คีย์ แสดงแค่สิทธิ์)"
hr
