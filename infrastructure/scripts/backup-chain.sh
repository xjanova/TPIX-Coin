#!/bin/bash
# ============================================================
# Backup ข้อมูลเชน TPIX ออกนอกเครื่อง
#
# ทำไมต้องมี: ตอนนี้ validator ทั้ง 4 ตัวอยู่เครื่องเดียว ดิสก์เดียว และ
# ไม่มีการสำรอง block data เลย — ดิสก์พังหรือถูกลบเมื่อไร ธุรกรรมทุกใบ
# ตั้งแต่ regenesis หายถาวร รวมถึงเหรียญที่จ่ายให้ลูกค้าที่ซื้อไปแล้ว
# กู้จาก genesis ได้แค่ยอดตั้งต้น 10 กระเป๋าเท่านั้น
#
# วิธีทำงาน (ปลอดภัยกับเชนที่กำลังวิ่ง):
#   1. ตรวจว่าเชนยังผลิตบล็อกอยู่ และ validator ครบ
#   2. หยุด validator เพียง "ตัวเดียว" — quorum 3/4 ยังอยู่ เชนไม่หยุด
#   3. tar ข้อมูล + เข้ารหัสด้วย gpg (symmetric)
#   4. เปิด validator กลับ แล้วรอจน healthy + บล็อกเดินต่อ
#   5. ส่งไฟล์ออกนอกเครื่อง แล้วลบไฟล์เก่าตามอายุที่กำหนด
#
# ถ้าสคริปต์ตายกลางทาง trap จะเปิด validator กลับให้เสมอ
#
# Usage (as root):
#   sudo TPIX_BACKUP_PASS='...' bash backup-chain.sh
#   sudo TPIX_BACKUP_PASS='...' TPIX_BACKUP_UPLOAD='rclone copy {file} remote:tpix-backup' bash backup-chain.sh
#
# ตั้ง cron ให้รันทุกวันตี 3:
#   0 3 * * * TPIX_BACKUP_PASS=... bash /opt/tpix/scripts/backup-chain.sh >> /var/log/tpix-backup.log 2>&1
#
# Developed by Xman Studio
# ============================================================

set -euo pipefail

CHAIN_DIR="${TPIX_CHAIN_DIR:-/opt/tpix/chain}"
BACKUP_DIR="${TPIX_BACKUP_DIR:-/var/backups/tpix}"
VALIDATOR="${TPIX_BACKUP_VALIDATOR:-tpix-validator-4}"
VALIDATOR_DATA="${TPIX_BACKUP_VALIDATOR_DATA:-$CHAIN_DIR/data/validator-4}"
RPC="${TPIX_RPC_URL:-http://127.0.0.1:8545}"
KEEP_DAYS="${TPIX_BACKUP_KEEP_DAYS:-14}"
# คำสั่งส่งไฟล์ออกนอกเครื่อง — ใช้ {file} เป็นตัวแทนพาธไฟล์
UPLOAD_CMD="${TPIX_BACKUP_UPLOAD:-}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $(date '+%F %T') $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $(date '+%F %T') $*"; }
err()  { echo -e "${RED}[✗]${NC} $(date '+%F %T') $*" >&2; }

[[ $EUID -eq 0 ]] || { err "ต้องรันด้วย root (sudo)"; exit 1; }
[[ -n "${TPIX_BACKUP_PASS:-}" ]] || { err "ต้องตั้ง TPIX_BACKUP_PASS (รหัสถอดไฟล์สำรอง) — ห้ามเก็บไว้ในสคริปต์"; exit 1; }
[[ -d "$VALIDATOR_DATA" ]] || { err "ไม่พบโฟลเดอร์ข้อมูล $VALIDATOR_DATA"; exit 1; }

command -v gpg >/dev/null || { err "ไม่มี gpg — ติดตั้งก่อน: apt-get install -y gnupg"; exit 1; }
command -v docker >/dev/null || { err "ไม่มี docker"; exit 1; }

block_number() {
    curl -s -m 5 -X POST -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$RPC" 2>/dev/null | grep -o '"result":"0x[0-9a-fA-F]*"' | cut -d'"' -f4 || echo ""
}

hex_to_dec() { [[ -n "$1" ]] && printf '%d' "$1" 2>/dev/null || echo 0; }

start_validator() {
    if ! docker ps --format '{{.Names}}' | grep -qx "$VALIDATOR"; then
        log "เปิด $VALIDATOR กลับ"
        docker start "$VALIDATOR" >/dev/null 2>&1 || err "เปิด $VALIDATOR ไม่สำเร็จ — ต้องเข้าไปดูด้วยมือทันที"
    fi
}
trap start_validator EXIT

# ── 1. ตรวจสุขภาพเชนก่อนแตะอะไร ────────────────────────────────────────────
BEFORE_HEX="$(block_number)"
BEFORE="$(hex_to_dec "$BEFORE_HEX")"
[[ "$BEFORE" -gt 0 ]] || { err "อ่านความสูงบล็อกจาก $RPC ไม่ได้ — ยกเลิก ไม่แตะเชนตอนที่ยังไม่รู้สถานะ"; exit 1; }

RUNNING="$(docker ps --format '{{.Names}}' | grep -c '^tpix-validator-' || true)"
[[ "$RUNNING" -ge 4 ]] || { err "validator ทำงานอยู่ $RUNNING ตัว (ต้องครบ 4 ก่อนถึงจะหยุดได้ 1) — ยกเลิก"; exit 1; }

log "เชนปกติ บล็อกล่าสุด $BEFORE · validator ครบ $RUNNING ตัว"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

STAMP="$(date '+%Y%m%d-%H%M%S')"
ARCHIVE="$BACKUP_DIR/tpix-chain-$STAMP.tar.gz"
ENCRYPTED="$ARCHIVE.gpg"

# ── 2. หยุด validator ตัวเดียว (quorum 3/4 ยังอยู่) ────────────────────────
log "หยุด $VALIDATOR ชั่วคราวเพื่อคัดลอกข้อมูลให้สอดคล้องกัน"
docker stop "$VALIDATOR" >/dev/null

# ── 3. บีบอัด + เข้ารหัส ───────────────────────────────────────────────────
# genesis ต้องอยู่ในไฟล์เดียวกับ block data — ถ้ามีแต่ block data ก็กู้เชนไม่ได้
# (ต่อไฟล์เข้า .tar.gz ทีหลังไม่ได้ จึงต้องใส่ให้ครบตั้งแต่ตอนสร้าง)
TAR_ARGS=(-C "$(dirname "$VALIDATOR_DATA")" "$(basename "$VALIDATOR_DATA")")
if [[ -f "$CHAIN_DIR/genesis.json" ]]; then
    TAR_ARGS+=(-C "$CHAIN_DIR" genesis.json)
else
    warn "ไม่พบ $CHAIN_DIR/genesis.json — ไฟล์สำรองจะไม่มี genesis ต้องเก็บแยกเอง"
fi

log "กำลังบีบอัดข้อมูลจาก $VALIDATOR_DATA"
tar -czf "$ARCHIVE" "${TAR_ARGS[@]}" || { err "บีบอัดไม่สำเร็จ"; exit 1; }

log "กำลังเข้ารหัสไฟล์สำรอง"
gpg --batch --yes --symmetric --cipher-algo AES256 \
    --passphrase "$TPIX_BACKUP_PASS" \
    --output "$ENCRYPTED" "$ARCHIVE" || { err "เข้ารหัสไม่สำเร็จ"; exit 1; }

shred -u "$ARCHIVE" 2>/dev/null || rm -f "$ARCHIVE"
chmod 600 "$ENCRYPTED"

# ── 4. เปิด validator กลับ แล้วรอจนเชนเดินต่อจริง ──────────────────────────
start_validator
trap - EXIT

log "รอให้ $VALIDATOR ตามบล็อกทัน"
# ใช้ตัวแปรธงแทน `[[ ]] && err` ท้ายลูป เพราะ set -e จะฆ่าสคริปต์ทันที
# ที่เงื่อนไขเป็นเท็จในรอบแรก (ซึ่งเป็นเรื่องปกติ ไม่ใช่ความผิดพลาด)
CHAIN_RESUMED=0
for _ in $(seq 1 30); do
    sleep 2
    AFTER="$(hex_to_dec "$(block_number)")"
    if [[ "$AFTER" -gt "$BEFORE" ]]; then
        log "เชนเดินต่อปกติ บล็อก $BEFORE → $AFTER"
        CHAIN_RESUMED=1
        break
    fi
done

if [[ "$CHAIN_RESUMED" -eq 0 ]]; then
    err "เชนไม่เดินต่อภายใน 60 วินาทีหลังเปิด $VALIDATOR กลับ — ต้องเข้าไปตรวจด้วยมือทันที"
    exit 1
fi

# ── 5. ตรวจว่าไฟล์สำรองใช้ได้จริง (ไม่ใช่แค่มีไฟล์) ───────────────────────
log "ตรวจสอบไฟล์สำรองว่าถอดรหัสและอ่านได้"
if ! gpg --batch --yes --quiet --decrypt --passphrase "$TPIX_BACKUP_PASS" "$ENCRYPTED" 2>/dev/null | tar -tzf - >/dev/null 2>&1; then
    err "ไฟล์สำรองเสียหรือถอดรหัสไม่ได้ — ถือว่าล้มเหลว"
    exit 1
fi

SIZE="$(du -h "$ENCRYPTED" | cut -f1)"
log "ไฟล์สำรองพร้อม: $ENCRYPTED ($SIZE)"

# ── 6. ส่งออกนอกเครื่อง ────────────────────────────────────────────────────
# สำรองไว้ในเครื่องเดียวกันไม่นับว่าสำรอง — ดิสก์พังก็หายพร้อมกัน
if [[ -n "$UPLOAD_CMD" ]]; then
    log "ส่งไฟล์ออกนอกเครื่อง"
    CMD="${UPLOAD_CMD//\{file\}/$ENCRYPTED}"
    if eval "$CMD"; then
        log "ส่งสำเร็จ"
    else
        err "ส่งไฟล์ออกนอกเครื่องไม่สำเร็จ — ไฟล์ยังอยู่ที่ $ENCRYPTED"
        exit 1
    fi
else
    warn "ยังไม่ได้ตั้ง TPIX_BACKUP_UPLOAD — ไฟล์อยู่แค่ในเครื่องนี้"
    warn "ดิสก์พังเมื่อไรก็หายพร้อมกัน กรุณาตั้งคำสั่งส่งออกนอกเครื่องด้วย"
fi

# ── 7. ลบไฟล์เก่า ─────────────────────────────────────────────────────────
find "$BACKUP_DIR" -name 'tpix-chain-*.tar.gz.gpg' -mtime "+$KEEP_DAYS" -print -delete 2>/dev/null | \
    while read -r old; do log "ลบไฟล์เก่า $old"; done

log "เสร็จสิ้น"
