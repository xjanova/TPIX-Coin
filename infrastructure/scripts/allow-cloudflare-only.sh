#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  ปิดทางยิงตรงเข้า origin — เปิด 80/443 ให้เฉพาะช่วง IP ของ Cloudflare
#
#  ทำไมต้องมี (พิสูจน์แล้ว 2026-08-27):
#    curl -k https://123.253.62.252 -H 'Host: rpc.tpix.online' \
#         -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}'
#    → 200 พร้อมเลขบล็อกจริง
#
#    แปลว่า WAF · bot rule · DDoS protection · rate limit ของ Cloudflare
#    เป็นของ "สมัครใจ" ทั้งหมด ใครรู้ IP origin ก็ข้ามได้หมด
#    และโน้ตสมองระบุว่า IP origin หลุดใน repo history ไปแล้ว
#
#  และมันเป็น "เงื่อนไขก่อน" ของด่านอื่นทั้งหมด:
#    real_ip_header CF-Connecting-IP เชื่อได้ก็ต่อเมื่อไม่มีใครยิงตรงมาได้
#    ถ้ายังยิงตรงได้ → ปลอม header → หลบโควตาเขียนของ njs ได้ทั้งดุ้น
#
#  ใช้งาน:
#    bash allow-cloudflare-only.sh                 # ดูอย่างเดียว ไม่แตะอะไร (ค่าเริ่มต้น)
#    bash allow-cloudflare-only.sh --apply         # ลงมือจริง
#    bash allow-cloudflare-only.sh --print-nginx   # พิมพ์บรรทัด set_real_ip_from
#    ADMIN_IP=1.2.3.4 bash allow-cloudflare-only.sh --apply   # เปิดให้ IP ตัวเองด้วย
#
#  Developed by Xman Studio.
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

MODE="${1:---dry-run}"
CF_V4_URL="https://www.cloudflare.com/ips-v4"
CF_V6_URL="https://www.cloudflare.com/ips-v6"

# ชุดสำรอง ใช้เมื่อดึงจากเน็ตไม่ได้ — ต้องตรงกับที่ใส่ใน nginx-http-tpix.conf
# และ fail2ban/jail.d/tpix-rpc.conf (ทั้งสามที่ต้องเป็นชุดเดียวกันเสมอ)
FALLBACK_V4="173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22
141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20
197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
104.24.0.0/14 172.64.0.0/13 131.0.72.0/22"
FALLBACK_V6="2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32
2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32"

log() { printf '%s\n' "$*"; }
die() { printf '❌ %s\n' "$*" >&2; exit 1; }

fetch_ranges() {
    local url="$1" fallback="$2" out
    if out=$(curl -fsS --max-time 10 "$url" 2>/dev/null) && [ -n "$out" ]; then
        printf '%s\n' "$out"
    else
        log "⚠️  ดึง $url ไม่ได้ — ใช้ชุดสำรองในสคริปต์แทน" >&2
        printf '%s\n' "$fallback" | tr ' ' '\n'
    fi
}

V4=$(fetch_ranges "$CF_V4_URL" "$FALLBACK_V4" | grep -E '^[0-9]' || true)
V6=$(fetch_ranges "$CF_V6_URL" "$FALLBACK_V6" | grep -E '^[0-9a-fA-F]*:' || true)

[ -n "$V4" ] || die "ไม่ได้ช่วง IPv4 ของ Cloudflare เลยสักช่วง — หยุดไว้ก่อน ดีกว่าเปิดผิด"

if [ "$MODE" = "--print-nginx" ]; then
    # เอาไปวางแทนบล็อก set_real_ip_from ใน nginx-http-tpix.conf
    printf 'set_real_ip_from %s;\n' $V4 $V6
    printf 'real_ip_header CF-Connecting-IP;\nreal_ip_recursive on;\n'
    exit 0
fi

command -v ufw >/dev/null 2>&1 || die "ไม่มี ufw บนเครื่องนี้"

log "══ ช่วง IP ที่จะอนุญาต ══"
log "IPv4: $(printf '%s\n' "$V4" | wc -l) ช่วง"
log "IPv6: $(printf '%s\n' "$V6" | wc -l) ช่วง"
log ""

# ── กันล็อกตัวเองออกจากเครื่อง ────────────────────────────────────────────────
# ถ้า SSH ไม่ได้ถูกอนุญาตไว้ แล้วเราไปลบกฎ 80/443 ทิ้ง อาจกลายเป็นว่าเข้าไม่ได้อีก
# ตรวจก่อนเสมอ — ข้อนี้สำคัญกว่าความสวยงามของสคริปต์
if ! ufw status | grep -qE '^22(/tcp)?[[:space:]]+ALLOW'; then
    die "ufw ยังไม่อนุญาตพอร์ต 22 — เปิดก่อน (ufw allow 22/tcp) ไม่งั้นเสี่ยงล็อกตัวเองออก"
fi

# ต้องมี :- เพราะ sudo ทิ้ง SSH_CLIENT ทิ้ง แล้ว set -u จะทำให้สคริปต์ตายทันที
CURRENT_SSH="${SSH_CLIENT:-}"; CURRENT_SSH="${CURRENT_SSH%% *}"
if [ -n "${ADMIN_IP:-}" ]; then
    KEEP_IP="$ADMIN_IP"
elif [ -n "$CURRENT_SSH" ]; then
    KEEP_IP="$CURRENT_SSH"
else
    KEEP_IP=""
fi
[ -n "$KEEP_IP" ] && log "จะเปิด 80/443 ให้ IP ผู้ดูแลด้วย: $KEEP_IP"

emit_rules() {
    log "ufw --force delete allow 80/tcp   # ถ้ามี"
    log "ufw --force delete allow 443/tcp  # ถ้ามี"
    [ -n "$KEEP_IP" ] && log "ufw allow from $KEEP_IP to any port 80,443 proto tcp comment 'admin'"
    for cidr in $V4 $V6; do
        log "ufw allow from $cidr to any port 80,443 proto tcp comment 'cloudflare'"
    done
}

if [ "$MODE" != "--apply" ]; then
    log "── โหมดดูอย่างเดียว จะไม่แตะไฟร์วอลล์ ── (ใส่ --apply เพื่อลงมือจริง)"
    log ""
    emit_rules
    log ""
    log "หลัง --apply แล้วต้องได้ผลนี้:"
    log "  curl -sk -m 8 -o /dev/null -w '%{http_code}\\n' -X POST https://<origin-ip>/ \\"
    log "       -H 'Host: rpc.tpix.online' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_chainId\",\"id\":1}'"
    log "  → ต้อง timeout หรือ connection refused (ไม่ใช่ 200)"
    log "  curl ผ่าน https://rpc.tpix.online → ต้องยังได้ 200"
    exit 0
fi

[ "$(id -u)" -eq 0 ] || die "ต้องรันด้วย sudo"

log "── ลงมือจริง ──"
ufw --force delete allow 80/tcp  >/dev/null 2>&1 || true
ufw --force delete allow 443/tcp >/dev/null 2>&1 || true

if [ -n "$KEEP_IP" ]; then
    ufw allow from "$KEEP_IP" to any port 80,443 proto tcp comment 'admin' >/dev/null
fi

for cidr in $V4 $V6; do
    ufw allow from "$cidr" to any port 80,443 proto tcp comment 'cloudflare' >/dev/null
done

log "✓ ใส่กฎครบแล้ว"
log ""
ufw status numbered | head -40
log ""
log "⚠️  ตรวจของจริงทันที อย่าเชื่อว่ากฎเข้าแล้วจะทำงาน:"
log "   1. จากเครื่องนอก: ยิงตรง IP origin ต้องไม่ได้ 200"
log "   2. https://rpc.tpix.online/health ต้องยังได้ 200"
log "   3. ถ้าข้อ 2 พัง: ufw --force delete จำนวนกฎที่เพิ่ง add แล้ว ufw allow 443/tcp กลับ"
