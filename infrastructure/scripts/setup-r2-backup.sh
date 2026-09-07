#!/bin/bash
# ============================================================
# ตั้งค่าคีย์ Cloudflare R2 ให้งานสำรองข้อมูลเชนส่งไฟล์ออกนอกเครื่อง
#
#   sudo bash setup-r2-backup.sh
#
# ถามค่า 3 ตัวแบบไม่โชว์บนจอ → ทดสอบอัปโหลดจริง → ถ้าผ่านค่อยเขียนลง
# /etc/tpix-backup.env แล้วเปิดใช้ TPIX_BACKUP_UPLOAD ให้อัตโนมัติ
#
# ทำไมต้อง "ทดสอบก่อนเปิดใช้": ถ้าเขียนคีย์ผิดแล้วเปิดใช้เลย จะไม่รู้จนกระทั่ง
# ตี 2 คืนนั้น แล้วงานสำรองจะล้มทั้งรอบ (สคริปต์ถือว่าส่งไม่ออก = ล้มเหลว)
#
# ค่าที่ต้องเตรียม — จาก Cloudflare dashboard → R2 → Manage API tokens:
#   1. Account ID            (มุมขวาของหน้า R2 Overview)
#   2. Access Key ID         (ได้ตอนสร้าง token)
#   3. Secret Access Key     (โชว์ครั้งเดียวตอนสร้าง token)
#
# ⚠️ ตอนสร้าง token ให้เลือก Object Read & Write และจำกัดเฉพาะ bucket
#    tpix-chain-backup เท่านั้น อย่าใช้ token ระดับบัญชี — เครื่องเชนถูกยึด
#    เมื่อไรจะได้ไม่ลามไปถังอื่นของบ้าน
#
# Developed by Xman Studio
# ============================================================

set -euo pipefail
umask 077

ENV_FILE="${TPIX_BACKUP_ENV:-/etc/tpix-backup.env}"
BUCKET="${TPIX_R2_BUCKET:-tpix-chain-backup}"
UPLOADER="/usr/local/sbin/tpix-backup-upload-r2"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]]     || die "ต้องรันด้วย sudo"
[[ -f "$ENV_FILE" ]]  || die "ไม่พบ $ENV_FILE"
[[ -x "$UPLOADER" ]]  || die "ไม่พบ $UPLOADER — ติดตั้ง backup-upload-r2.sh ก่อน"
command -v rclone >/dev/null || die "ไม่มี rclone — apt-get install -y rclone"

echo
echo "ตั้งค่า R2 สำหรับสำรองข้อมูลเชน TPIX (bucket: $BUCKET)"
echo "พิมพ์แล้วจะไม่แสดงบนจอ — วางแล้วกด Enter ได้เลย"
echo

read -rsp "  1/3 Account ID           : " ACCOUNT_ID; echo
read -rsp "  2/3 Access Key ID        : " ACCESS_KEY; echo
read -rsp "  3/3 Secret Access Key    : " SECRET_KEY; echo
echo

[[ -n "$ACCOUNT_ID" && -n "$ACCESS_KEY" && -n "$SECRET_KEY" ]] || die "มีช่องที่เว้นว่าง — ยกเลิก"

# ── ทดสอบด้วยไฟล์เล็กก่อน ไม่เอาไฟล์ 650MB มาลองผิดลองถูก ──────────────────
TMP="$(mktemp -t tpix-r2-test.XXXXXX)"
trap 'rm -f "$TMP"' EXIT
echo "ทดสอบการเชื่อมต่อ R2 จาก $(hostname) เมื่อ $(date -Is)" > "$TMP"

echo "กำลังทดสอบอัปโหลด…"
if ! TPIX_R2_ACCOUNT_ID="$ACCOUNT_ID" \
     TPIX_R2_ACCESS_KEY_ID="$ACCESS_KEY" \
     TPIX_R2_SECRET_ACCESS_KEY="$SECRET_KEY" \
     TPIX_R2_BUCKET="$BUCKET" \
     TPIX_BACKUP_KEEP_DAYS=36500 \
     "$UPLOADER" "$TMP"; then
    die "ทดสอบไม่ผ่าน — ยังไม่เขียนอะไรลง $ENV_FILE เลย ตรวจคีย์/ชื่อ bucket แล้วลองใหม่"
fi

# เก็บกวาดไฟล์ทดสอบออกจาก bucket
export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare \
       RCLONE_CONFIG_R2_ACCESS_KEY_ID="$ACCESS_KEY" \
       RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$SECRET_KEY" \
       RCLONE_CONFIG_R2_ENDPOINT="https://${ACCOUNT_ID}.r2.cloudflarestorage.com"
rclone deletefile "R2:${BUCKET}/$(basename "$TMP")" 2>/dev/null || true
ok "เชื่อมต่อ R2 ได้ อัปโหลดและตรวจขนาดผ่าน"

# ── เขียนลงไฟล์ env (สำรองของเดิมไว้ก่อนเสมอ) ──────────────────────────────
cp -a "$ENV_FILE" "${ENV_FILE}.bak-$(date +%Y%m%d-%H%M%S)"

set_kv() {   # ตั้งค่า key=value แบบไม่ซ้ำบรรทัด
    local k="$1" v="$2"
    if grep -qE "^#?${k}=" "$ENV_FILE"; then
        # ใช้ตัวคั่นที่ไม่ปรากฏในคีย์ R2 (ฐาน 64 ไม่มี |)
        sed -i -E "s|^#?${k}=.*|${k}=${v}|" "$ENV_FILE"
    else
        echo "${k}=${v}" >> "$ENV_FILE"
    fi
}

set_kv TPIX_R2_ACCOUNT_ID        "$ACCOUNT_ID"
set_kv TPIX_R2_ACCESS_KEY_ID     "$ACCESS_KEY"
set_kv TPIX_R2_SECRET_ACCESS_KEY "$SECRET_KEY"
set_kv TPIX_R2_BUCKET            "$BUCKET"
set_kv TPIX_BACKUP_UPLOAD        "${UPLOADER} {file}"

chmod 600 "$ENV_FILE"; chown root:root "$ENV_FILE"

ok "เขียน $ENV_FILE แล้ว (600 root) — ของเดิมสำรองไว้เป็น .bak-*"
echo
echo "ตรวจว่าเปิดใช้ครบ (ไม่โชว์ค่าลับ):"
grep -oE '^TPIX_[A-Z_]+=' "$ENV_FILE" | sed 's/^/    /'
echo
ok "เสร็จ — คืนนี้ 02:17 น. งานสำรองจะส่งไฟล์ขึ้น R2 เอง"
echo "  อยากลองเดี๋ยวนี้เลย (หยุด validator-4 ~90 วิ + อัปไฟล์ ~650MB):"
echo "    sudo bash -c 'set -a; . /etc/tpix-backup.env; . /etc/tpix-watchdog.env; set +a; tpix-backup-chain'"
