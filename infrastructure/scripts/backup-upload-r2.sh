#!/bin/bash
# ============================================================
# ส่งไฟล์สำรองเชนขึ้น Cloudflare R2
#
# ใช้เป็นปลายทางของ backup-chain.sh:
#   TPIX_BACKUP_UPLOAD='/usr/local/sbin/tpix-backup-upload-r2 {file}'
#
# ทำไมต้องมีสคริปต์แยก ไม่ยัด rclone ยาว ๆ ลง TPIX_BACKUP_UPLOAD ตรง ๆ:
#   1. ต้อง "ยืนยันว่าไบต์ถึงปลายทางจริง" ไม่ใช่แค่ rclone คืน 0
#      — rclone copy คืน 0 ได้แม้ไฟล์ปลายทางขนาดไม่ตรง ในบางเคส retry ครึ่งทาง
#   2. ต้อง retry เอง เพราะไฟล์ 650MB ข้ามทวีป เน็ตสะดุดกลางทางเป็นเรื่องปกติ
#   3. ต้องลบของเก่าฝั่ง R2 ให้ตรงกับ KEEP_DAYS ฝั่งเครื่อง ไม่งั้นจ่ายค่าเก็บเพิ่มไปเรื่อย ๆ
#
# ค่าที่ต้องตั้งใน /etc/tpix-backup.env (600 root — ห้าม commit):
#   TPIX_R2_ACCOUNT_ID          รหัสบัญชี Cloudflare (ขึ้นต้น endpoint)
#   TPIX_R2_ACCESS_KEY_ID       จาก R2 API token
#   TPIX_R2_SECRET_ACCESS_KEY   จาก R2 API token
#   TPIX_R2_BUCKET              ชื่อ bucket (ตั้งต้น tpix-chain-backup)
#   TPIX_BACKUP_KEEP_DAYS       ใช้ค่าเดียวกับฝั่งเครื่อง (ตั้งต้น 14)
#
# ⚠️ คีย์ R2 ตัวนี้ควรเป็น token ที่มีสิทธิ์ "Object Read & Write เฉพาะ bucket นี้"
#    ไม่ใช่ token ระดับบัญชี — เครื่องเชนถูกยึดเมื่อไรจะได้ไม่ลามไปถังอื่น
#
# Developed by Xman Studio
# ============================================================

set -euo pipefail
umask 077

FILE="${1:-}"
BUCKET="${TPIX_R2_BUCKET:-tpix-chain-backup}"
KEEP_DAYS="${TPIX_BACKUP_KEEP_DAYS:-14}"
RETRIES="${TPIX_R2_RETRIES:-3}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[R2]${NC} $(date '+%F %T') $*"; }
warn() { echo -e "${YELLOW}[R2]${NC} $(date '+%F %T') $*"; }
err()  { echo -e "${RED}[R2]${NC} $(date '+%F %T') $*" >&2; }

[[ -n "$FILE" ]]  || { err "ต้องส่งพาธไฟล์มาเป็นอาร์กิวเมนต์แรก"; exit 2; }
[[ -f "$FILE" ]]  || { err "ไม่พบไฟล์ $FILE"; exit 2; }
command -v rclone >/dev/null || { err "ไม่มี rclone — ติดตั้งก่อน: apt-get install -y rclone"; exit 2; }

for v in TPIX_R2_ACCOUNT_ID TPIX_R2_ACCESS_KEY_ID TPIX_R2_SECRET_ACCESS_KEY; do
    [[ -n "${!v:-}" ]] || { err "ยังไม่ได้ตั้ง $v ใน /etc/tpix-backup.env"; exit 2; }
done

# ── ตั้งค่า rclone ผ่าน env ไม่ต้องมีไฟล์ config ────────────────────────────
# ข้อดี: ไม่มีคีย์นอนอยู่ในไฟล์ config อีกที่หนึ่งให้ต้องคอยดูแลสิทธิ์
export RCLONE_CONFIG_R2_TYPE=s3
export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ACCESS_KEY_ID="$TPIX_R2_ACCESS_KEY_ID"
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$TPIX_R2_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_R2_ENDPOINT="https://${TPIX_R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
# R2 ไม่รองรับ checksum แบบ AWS — ไม่ปิดตัวนี้ rclone จะเตือนรัว ๆ ทุกรอบ
export RCLONE_S3_NO_CHECK_BUCKET=true
export RCLONE_CONFIG_R2_ACL=private

NAME="$(basename "$FILE")"
LOCAL_SIZE="$(stat -c %s "$FILE")"

# ── อัปโหลด + retry ────────────────────────────────────────────────────────
UPLOADED=0
for attempt in $(seq 1 "$RETRIES"); do
    log "อัปโหลด $NAME ($(numfmt --to=iec "$LOCAL_SIZE")) ครั้งที่ $attempt/$RETRIES"
    if rclone copyto "$FILE" "R2:${BUCKET}/${NAME}" \
        --s3-chunk-size 32M --transfers 1 --retries 1 --low-level-retries 5 \
        --stats-one-line --stats 30s 2>&1; then
        UPLOADED=1
        break
    fi
    warn "ครั้งที่ $attempt ไม่สำเร็จ"
    sleep $(( attempt * 10 ))
done
[[ "$UPLOADED" -eq 1 ]] || { err "อัปโหลดไม่สำเร็จครบ $RETRIES ครั้ง"; exit 1; }

# ── ยืนยันว่าไบต์ถึงปลายทางจริง ไม่ใช่แค่คำสั่งคืน 0 ────────────────────────
# ถามขนาดจาก R2 กลับมาเทียบ — สำรองข้อมูลที่ "อัปโหลดสำเร็จ" แต่ไฟล์ปลายทาง
# ไม่ครบ คือสิ่งที่แย่กว่าไม่มีสำรองเลย เพราะทำให้เข้าใจผิดว่ามีของ
REMOTE_SIZE="$(rclone size "R2:${BUCKET}/${NAME}" --json 2>/dev/null | grep -o '"bytes":[0-9]*' | cut -d: -f2 || echo 0)"
if [[ "$REMOTE_SIZE" != "$LOCAL_SIZE" ]]; then
    err "ขนาดปลายทางไม่ตรง: บนเครื่อง $LOCAL_SIZE ไบต์ · บน R2 $REMOTE_SIZE ไบต์ — ถือว่าล้มเหลว"
    exit 1
fi
log "ยืนยันแล้ว: R2:${BUCKET}/${NAME} = $REMOTE_SIZE ไบต์ ตรงกับต้นทาง"

# ── ลบของเก่าฝั่ง R2 ให้ตรงกับนโยบายฝั่งเครื่อง ────────────────────────────
# ใช้ min-age เพื่อไม่ให้เผลอลบไฟล์ที่เพิ่งอัปไป และจับเฉพาะชื่อของเราเอง
log "ลบไฟล์เก่าเกิน ${KEEP_DAYS} วันบน R2"
rclone delete "R2:${BUCKET}" --min-age "${KEEP_DAYS}d" \
    --include 'tpix-chain-*.tar.gz.gpg' --rmdirs 2>&1 || warn "ลบของเก่าไม่สำเร็จ (ไม่ถือว่าการสำรองล้มเหลว)"

REMAIN="$(rclone lsf "R2:${BUCKET}" --include 'tpix-chain-*.tar.gz.gpg' 2>/dev/null | wc -l)"
log "เสร็จ — ตอนนี้บน R2 มีไฟล์สำรอง $REMAIN ใบ"
