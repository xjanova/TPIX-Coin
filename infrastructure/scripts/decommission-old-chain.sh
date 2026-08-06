#!/bin/bash
# ==============================================================================
#  ถอนเชนเก่าออกจากเว็บเซิร์ฟเวอร์เก่า — เฉพาะส่วนที่ต้องใช้ sudo
# ==============================================================================
#
#  ใช้กับเครื่อง 123.253.62.251 (server-123-253-62-251) เท่านั้น
#  เครื่องนี้เป็น **เว็บเซิร์ฟเวอร์ DirectAdmin ที่มี ~45 เว็บอยู่**
#  (tpix.online, thaiprompt, netwix, naruay999, n8n, atmos ฯลฯ)
#  สคริปต์นี้จึงลบเฉพาะของเชนล้วน ๆ และมีด่านกันลบผิดเครื่องอยู่ข้างล่าง
#
#  ส่วนที่ไม่ต้อง sudo ทำไปแล้วเมื่อ 6 ส.ค. 2026:
#    - ถอน container 7 ตัว (validator ×4 + blockscout ×3)
#    - ลบ block data 9.8 GB + repo clone + โฟลเดอร์สำรอง (คืนพื้นที่รวม 22 GB)
#    - ลบ docker volume ของ blockscout, network, image ของเชน
#    - ลบ cron watchdog ฝั่ง admin + /home/admin/chain-watchdog.sh
#    - ลบไฟล์พร็อกซีใน domains/{rpc,explorer}.tpix.online/public_html
#
#  วิธีรัน:
#    sudo bash decommission-old-chain.sh          # ลบของเชน (ไม่แตะ Cloudflare autoban)
#    sudo bash decommission-old-chain.sh --all    # ลบเครื่องมือ Cloudflare autoban ด้วย
#
# ==============================================================================

set -uo pipefail

EXPECT_HOST="server-123-253-62-251"
WITH_CF_AUTOBAN=0
[ "${1:-}" = "--all" ] && WITH_CF_AUTOBAN=1

# ─── ด่านกันลบผิดเครื่อง ──────────────────────────────────────────────────────
if [ "$(hostname)" != "$EXPECT_HOST" ]; then
    echo "หยุด: สคริปต์นี้สำหรับเครื่อง '$EXPECT_HOST' เท่านั้น"
    echo "      เครื่องนี้คือ '$(hostname)' — ถ้ารันต่อจะลบของผิดเครื่อง"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "หยุด: ต้องรันด้วย sudo"
    exit 1
fi

# ─── ด่านกันรันซ้ำตอนเชนยังอยู่ ───────────────────────────────────────────────
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^tpix-validator'; then
    echo "หยุด: ยังมี container tpix-validator อยู่ — ถอน container ให้เสร็จก่อน"
    echo "      (สคริปต์นี้ลบเฉพาะ cron/script/log ระดับ root)"
    exit 1
fi

echo "=============================================================="
echo " ถอนเชนเก่าออกจาก $(hostname) — ส่วน root"
echo "=============================================================="

rm_if() {
    if [ -e "$1" ]; then
        rm -rf -- "$1" && echo "  ลบแล้ว  $1"
    else
        echo "  ไม่มีอยู่ $1"
    fi
}

echo
echo "[1/5] cron ของเชน"
rm_if /etc/cron.d/tpix-chain-watchdog
rm_if /etc/cron.d/tpix-monitoring

echo
echo "[2/5] สคริปต์ watchdog / รายงาน"
rm_if /usr/local/sbin/tpix-chain-watchdog
rm_if /usr/local/sbin/tpix-daily-report

echo
echo "[3/5] config + logrotate"
rm_if /etc/tpix-watchdog.env
rm_if /etc/tpix-watchdog.env.bak.20260515
rm_if /etc/logrotate.d/tpix-watchdog

echo
echo "[4/5] log ของเชน"
for f in /var/log/tpix-watchdog.log /var/log/tpix-watchdog.err /var/log/tpix-watchdog.log.*; do
    rm_if "$f"
done

echo
echo "[5/5] fail2ban action ที่ไม่มี jail ไหนเรียกใช้แล้ว"
rm_if /etc/fail2ban/action.d/cloudflare-tpix.conf

if [ "$WITH_CF_AUTOBAN" -eq 1 ]; then
    echo
    echo "[เสริม] เครื่องมือ Cloudflare auto-ban (เคยใช้กัน abuse ที่ rpc.tpix.online)"
    rm_if /etc/cron.d/tpix-cf-autoban-prune
    rm_if /usr/local/sbin/cf-ban-ip
    rm_if /var/log/cf-ban.log
else
    echo
    echo "[เสริม] ข้ามเครื่องมือ Cloudflare auto-ban — ใส่ --all ถ้าจะลบด้วย"
    echo "        (/etc/cron.d/tpix-cf-autoban-prune · /usr/local/sbin/cf-ban-ip)"
fi

# ══════════════════════════════════════════════════════════════════════════════
#  ⚠ สิ่งที่ **ห้ามลบ** ถึงชื่อจะขึ้นต้นด้วย tpix
# ══════════════════════════════════════════════════════════════════════════════
#
#    /etc/fail2ban/jail.d/tpix-apache.conf
#
#  ชื่อหลอก — ข้างในเปิด jail apache-auth / apache-noscript / apache-overflows
#  อ่าน /var/log/httpd/access_log ซึ่งเป็น log รวมของ **ทุกเว็บบนเครื่องนี้**
#  ลบทิ้ง = เว็บทั้ง 45 ตัวเสียเกราะกัน brute-force และ exploit scan
#
# ══════════════════════════════════════════════════════════════════════════════

echo
echo "=============================================================="
echo " ตรวจผล"
echo "=============================================================="
echo "cron ของเชนที่เหลือ :"
ls /etc/cron.d/ 2>/dev/null | grep -i tpix || echo "  (ไม่เหลือแล้ว)"
echo "สคริปต์ที่เหลือ     :"
ls /usr/local/sbin/ 2>/dev/null | grep -i -E "tpix|cf-ban" || echo "  (ไม่เหลือแล้ว)"
echo "jail ที่ต้องยังอยู่  :"
ls /etc/fail2ban/jail.d/tpix-apache.conf 2>/dev/null && echo "  ✓ ยังอยู่ ถูกต้อง" || echo "  ✗ หายไป — เว็บทั้งเครื่องเสียเกราะ ต้องกู้คืน"
echo
echo "เว็บยังปกติไหม (ต้องได้ 200) :"
for d in tpix.online main.thaiprompt.online netwix.online naruay999.com; do
    printf '  %-28s %s\n' "$d" "$(curl -sk -m 10 -o /dev/null -w '%{http_code}' -H "Host: $d" https://127.0.0.1/ 2>/dev/null)"
done
echo
echo "เสร็จแล้ว"
