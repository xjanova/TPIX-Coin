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
#   1. เข้าคิวบำรุงรักษา (flock) กัน watchdog ทำงานทับ
#   2. ตรวจว่าเชนยังผลิตบล็อกอยู่ และ validator ครบ
#   3. หยุด validator เพียง "ตัวเดียว" — quorum 3/4 ยังอยู่ เชนไม่หยุด
#      แล้ว "รอจนหยุดสนิทจริง" ก่อนแตะไฟล์
#   4. tar ข้อมูล + เข้ารหัสด้วย gpg (symmetric)
#   5. เปิด validator กลับ แล้วรอจน healthy + บล็อกเดินต่อ
#   6. ส่งไฟล์ออกนอกเครื่อง แล้วลบไฟล์เก่าตามอายุที่กำหนด
#
# ถ้าสคริปต์ตายกลางทาง trap จะเปิด validator กลับให้เสมอ + ทำลายไฟล์ดิบทิ้ง
#
# Usage (as root):
#   sudo TPIX_BACKUP_PASS='...' bash backup-chain.sh
#   sudo TPIX_BACKUP_PASS='...' TPIX_BACKUP_UPLOAD='rclone copy {file} remote:tpix-backup' bash backup-chain.sh
#
# ตั้ง cron (ของจริงอยู่ที่ /etc/cron.d/tpix-chain-backup):
#   17 19 * * * root set -a; . /etc/tpix-backup.env; . /etc/tpix-watchdog.env; set +a; \
#               /usr/local/sbin/tpix-backup-chain >> /var/log/tpix-backup.log 2>&1
#   ต้อง source ทั้งสองไฟล์ — ไฟล์แรกให้รหัสถอดไฟล์ ไฟล์หลังให้ปลายทางคาดแดง
#
# Developed by Xman Studio
# ============================================================

set -euo pipefail

# ไฟล์ทุกอย่างที่สคริปต์นี้สร้างต้องเป็น 600 ตั้งแต่วินาทีแรก ไม่ใช่ chmod ทีหลัง
# เพราะถ้าตายระหว่างทาง ไฟล์ดิบที่มีคีย์ validator จะค้างด้วยสิทธิ์ 644
# (เกิดจริง 2026-09-03: tpix-chain-20260903-191701.tar.gz ค้าง 574M สิทธิ์ 644)
umask 077

CHAIN_DIR="${TPIX_CHAIN_DIR:-/opt/tpix/chain}"
BACKUP_DIR="${TPIX_BACKUP_DIR:-/var/backups/tpix}"
VALIDATOR="${TPIX_BACKUP_VALIDATOR:-tpix-validator-4}"
VALIDATOR_DATA="${TPIX_BACKUP_VALIDATOR_DATA:-$CHAIN_DIR/data/validator-4}"
RPC="${TPIX_RPC_URL:-http://127.0.0.1:8545}"
KEEP_DAYS="${TPIX_BACKUP_KEEP_DAYS:-14}"
# คำสั่งส่งไฟล์ออกนอกเครื่อง — ใช้ {file} เป็นตัวแทนพาธไฟล์
UPLOAD_CMD="${TPIX_BACKUP_UPLOAD:-}"

# ── ล็อกบอก watchdog ว่ากำลังสำรองข้อมูลอยู่ ──────────────────────────────────
# สคริปต์นี้หยุด validator 1 ตัวชั่วคราว ซึ่ง chain-watchdog.sh จะเห็นแล้วสั่ง
# restart ทั้งวงทับ = ข้อมูลถูกคัดลอกกลางคันจนไฟล์สำรองเสีย และเชนสะดุดฟรี ๆ
# ต้องเป็น path เดียวกับ BACKUP_LOCK ใน chain-watchdog.sh
BACKUP_LOCK="${TPIX_BACKUP_LOCK:-/run/tpix-backup.lock}"

# ── คิวบำรุงรักษา (flock) — ชั้นที่กันได้จริง ─────────────────────────────────
# ⚠️ ล็อกไฟล์ข้างบนเป็นแค่ "ธง" ที่อ่านด้วย test -f แล้วค่อยเขียน = ไม่ atomic
# 2026-09-03 cron สองตัวยิงพร้อมกันที่ 19:17:00 พอดี (สำรอง `17 19 * * *` กับ
# watchdog `* * * * *`) watchdog อ่านธงก่อนที่สคริปต์นี้จะเขียนเสร็จ → ไม่เห็นธง
# → เห็น validator-4 หาย → สั่ง `compose up -d` ทับตอน tar กำลังอ่านอยู่ →
# LevelDB ของตัวที่เพิ่งฟื้น compact ลบ .ldb ทิ้ง → `File removed before we read it`
# → สำรองล้มเหลว วันนั้นไม่มีไฟล์ และเหลือไฟล์ดิบ 574M สิทธิ์ 644 ค้างไว้
# flock ตัดปัญหาชนิดนี้ทั้งชั้น เพราะ "ขอคิว" กับ "ได้คิว" เป็นก้าวเดียวกัน
MAINT_LOCK="${TPIX_MAINT_LOCK:-/run/tpix-chain-maint.lock}"
MAINT_LOCK_WAIT="${TPIX_MAINT_LOCK_WAIT:-90}"

# ── ปลายทางคาดแดงหลังบ้าน tpix.online (ตัวเดียวกับที่ chain-watchdog.sh ใช้) ──
# ว่าง = ไม่ส่ง แต่ทำงานต่อได้ปกติ · ค่าอยู่ใน /etc/tpix-watchdog.env
ALERT_URL="${TPIX_ALERT_URL:-}"
ALERT_TOKEN="${TPIX_ALERT_TOKEN:-}"
NODE_NAME="${TPIX_NODE_NAME:-$(hostname)}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $(date '+%F %T') $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $(date '+%F %T') $*"; }
err()  { echo -e "${RED}[✗]${NC} $(date '+%F %T') $*" >&2; }

# ── แจ้งเตือนขึ้นคาดแดงหลังบ้าน (POST /api/infra/alert) ──────────────────────
# ทำไมต้องมี: ก่อนหน้านี้ความล้มเหลวลงแค่ /var/log/tpix-backup.log ของวันที่
# 3 ก.ย. จึงไม่มีใครรู้ 4 วัน — ยอมหยุด validator ทุกคืนแล้วไม่ได้ไฟล์กลับมา
# `backup_failed` ไม่อยู่ใน SystemAlert::AUTO_RESOLVE_KEYS โดยตั้งใจ:
# heartbeat ของเชนบอกไม่ได้ว่าการสำรองกลับมาดีแล้ว ต้องให้คนกดรับทราบเอง
alert() {
    local key="$1" sev="$2" msg="$3"
    [[ -n "$ALERT_URL" && -n "$ALERT_TOKEN" ]] || return 0
    msg=${msg//\\/\\\\}; msg=${msg//\"/\\\"}
    curl -fsS -m 10 -A "tpix-backup/1.0 (${NODE_NAME})" \
        -H "Authorization: Bearer ${ALERT_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"node\":\"${NODE_NAME}\",\"key\":\"${key}\",\"severity\":\"${sev}\",\"message\":\"${msg}\"}" \
        "${ALERT_URL}/alert" -o /dev/null 2>/dev/null || true
}

# ตายพร้อมส่งเสียง — ใช้แทน `err ...; exit 1` ทุกจุดที่เป็นความล้มเหลวจริง
fail() {
    err "$1"
    alert "backup_failed" "critical" "สำรองข้อมูลเชนล้มเหลว: $1"
    exit 1
}

[[ $EUID -eq 0 ]] || { err "ต้องรันด้วย root (sudo)"; exit 1; }
[[ -n "${TPIX_BACKUP_PASS:-}" ]] || { err "ต้องตั้ง TPIX_BACKUP_PASS (รหัสถอดไฟล์สำรอง) — ห้ามเก็บไว้ในสคริปต์"; exit 1; }
[[ -d "$VALIDATOR_DATA" ]] || { err "ไม่พบโฟลเดอร์ข้อมูล $VALIDATOR_DATA"; exit 1; }

command -v gpg >/dev/null || { err "ไม่มี gpg — ติดตั้งก่อน: apt-get install -y gnupg"; exit 1; }
command -v docker >/dev/null || { err "ไม่มี docker"; exit 1; }

# ── เข้าคิวบำรุงรักษาก่อนทำอะไรทั้งสิ้น ──────────────────────────────────────
# รันตัวเองซ้ำใต้ flock (ไม่ใช้ exec เพราะยังอยากได้รหัสจบกลับมาแจ้งเตือน)
# -E 75 = แยก "จับคิวไม่ได้" ออกจาก "งานข้างในล้มเหลว" ให้ชัด
# เครื่องไหนไม่มี flock ก็ทำงานต่อแบบเดิม ดีกว่าไม่สำรองเลย (ธง BACKUP_LOCK
# ยังกันอีกชั้น) — security/robustness control ที่ fail-closed ในงาน cron
# = งานไม่เคยรันแล้วไม่มีใครรู้ ซึ่งแย่กว่าปัญหาที่มันกัน
if command -v flock >/dev/null 2>&1 && [[ -z "${TPIX_BACKUP_FLOCKED:-}" ]]; then
    export TPIX_BACKUP_FLOCKED=1
    set +e
    flock -w "$MAINT_LOCK_WAIT" -E 75 "$MAINT_LOCK" "$0" "$@"
    FLOCK_RC=$?
    set -e
    if [[ "$FLOCK_RC" -eq 75 ]]; then
        err "รอคิวบำรุงรักษาเกิน ${MAINT_LOCK_WAIT}s (มีงานอื่นถือคิวอยู่) — ข้ามรอบนี้"
        alert "backup_failed" "critical" \
            "สำรองข้อมูลเชนไม่ได้เริ่ม: รอคิวบำรุงรักษาเกิน ${MAINT_LOCK_WAIT}s"
    fi
    exit "$FLOCK_RC"
fi

block_number() {
    curl -s -m 5 -X POST -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$RPC" 2>/dev/null | grep -o '"result":"0x[0-9a-fA-F]*"' | cut -d'"' -f4 || echo ""
}

hex_to_dec() { [[ -n "$1" ]] && printf '%d' "$1" 2>/dev/null || echo 0; }
container_running()    { [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == "true" ]]; }
container_started_at() { docker inspect -f '{{.State.StartedAt}}' "$1" 2>/dev/null || echo "?"; }

# กัน backup สองตัวทับกัน (cron ซ้อนตอนรอบก่อนยังไม่จบ) — ตรวจ "ก่อน" ติด trap
# เพราะถ้าติด trap ก่อนแล้วเจอล็อกของคนอื่น เราจะไปลบล็อกที่ไม่ใช่ของเรา
if [[ -f "$BACKUP_LOCK" ]]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$BACKUP_LOCK" 2>/dev/null || echo 0) ))
    if [[ "$LOCK_AGE" -lt 1800 ]]; then
        err "มีงานสำรองข้อมูลทำงานอยู่แล้ว (ล็อกอายุ ${LOCK_AGE}s) — ยกเลิกรอบนี้"
        exit 1
    fi
    warn "ล็อกค้างมา ${LOCK_AGE}s ถือว่าเป็นของรอบที่ตายไปแล้ว — ทำต่อ"
fi

# ── trap เดียวคุมทั้งสคริปต์ ─────────────────────────────────────────────────
# ⚠️ ห้ามสลับ trap กลางทาง — โค้ดรุ่นก่อนทำแบบนั้นแล้วเคยลืมลบล็อก จน watchdog
#    ข้ามการตรวจ 30 นาทีทุกคืนโดยไม่มีใครรู้ (เจอจริง 2026-08-28)
#    ใช้ธง VALIDATOR_STOPPED_BY_US ตัดสินแทนว่าจะเปิด validator กลับไหม
VALIDATOR_STOPPED_BY_US=0
ARCHIVE=""
cleanup() {
    # ไฟล์ดิบมี validator.key / validator-bls.key / libp2p.key อยู่ข้างใน
    # ตายตรงไหนก็ตามห้ามทิ้งไว้เด็ดขาด
    if [[ -n "$ARCHIVE" && -f "$ARCHIVE" ]]; then
        warn "ทำลายไฟล์ดิบที่ยังไม่ได้เข้ารหัสทิ้ง: $ARCHIVE"
        shred -u "$ARCHIVE" 2>/dev/null || rm -f "$ARCHIVE"
    fi
    if [[ "$VALIDATOR_STOPPED_BY_US" -eq 1 ]] && ! docker ps --format '{{.Names}}' | grep -qx "$VALIDATOR"; then
        log "เปิด $VALIDATOR กลับ"
        docker start "$VALIDATOR" >/dev/null 2>&1 || alert "backup_failed" "critical" \
            "เปิด $VALIDATOR กลับไม่สำเร็จหลังสำรองข้อมูล — เชนเหลือ 3/4 ต้องเข้าไปดูด้วยมือทันที"
    fi
    rm -f "$BACKUP_LOCK"
}
trap cleanup EXIT

date +%s > "$BACKUP_LOCK"

# ── 1. ตรวจสุขภาพเชนก่อนแตะอะไร ────────────────────────────────────────────
BEFORE_HEX="$(block_number)"
BEFORE="$(hex_to_dec "$BEFORE_HEX")"
[[ "$BEFORE" -gt 0 ]] || fail "อ่านความสูงบล็อกจาก $RPC ไม่ได้ — ยกเลิก ไม่แตะเชนตอนที่ยังไม่รู้สถานะ"

RUNNING="$(docker ps --format '{{.Names}}' | grep -c '^tpix-validator-' || true)"
[[ "$RUNNING" -ge 4 ]] || fail "validator ทำงานอยู่ $RUNNING ตัว (ต้องครบ 4 ก่อนถึงจะหยุดได้ 1) — ยกเลิก"

log "เชนปกติ บล็อกล่าสุด $BEFORE · validator ครบ $RUNNING ตัว"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# ── ซากไฟล์ดิบจากรอบที่เคยตาย ────────────────────────────────────────────────
# ไม่ลบให้เอง เพราะเป็นข้อมูลเชนจริง + คีย์ validator ควรให้คนตัดสินใจ
# แต่ต้องรู้ว่ามีอยู่ ไม่ใช่นอนเงียบอยู่ในโฟลเดอร์เป็นเดือน
STRAY="$(find "$BACKUP_DIR" -maxdepth 1 -name 'tpix-chain-*.tar.gz' -type f 2>/dev/null | head -5)"
if [[ -n "$STRAY" ]]; then
    warn "พบไฟล์สำรองที่ยังไม่ได้เข้ารหัสค้างอยู่ (ซากจากรอบที่ล้มเหลว) — มีคีย์ validator ข้างใน:"
    echo "$STRAY" | while read -r f; do warn "  $f"; done
    alert "backup_plaintext_left" "warning" \
        "มีไฟล์สำรองที่ยังไม่ได้เข้ารหัสค้างใน $BACKUP_DIR (มีคีย์ validator ข้างใน) — ตรวจแล้วลบด้วย shred -u"
fi

STAMP="$(date '+%Y%m%d-%H%M%S')"
ARCHIVE="$BACKUP_DIR/tpix-chain-$STAMP.tar.gz"
ENCRYPTED="$ARCHIVE.gpg"

# ── 2. หยุด validator ตัวเดียว (quorum 3/4 ยังอยู่) ────────────────────────
log "หยุด $VALIDATOR ชั่วคราวเพื่อคัดลอกข้อมูลให้สอดคล้องกัน"
VALIDATOR_STOPPED_BY_US=1
docker stop "$VALIDATOR" >/dev/null

# รอจนหยุดสนิทจริงก่อนแตะไฟล์ — `docker stop` คืนค่าแล้วไม่ได้แปลว่า state
# เป็น false ทันที และห้าม tar ข้อมูล LevelDB ที่ยังมีคนเขียนอยู่เด็ดขาด
STOPPED=0
for _ in $(seq 1 30); do
    if ! container_running "$VALIDATOR"; then STOPPED=1; break; fi
    sleep 1
done
[[ "$STOPPED" -eq 1 ]] || fail "$VALIDATOR ยังไม่หยุดภายใน 30 วินาที — ยกเลิก ไม่คัดลอกข้อมูลที่ยังมีคนเขียนอยู่"
STOPPED_MARK="$(container_started_at "$VALIDATOR")"

# ── 3. บีบอัด + เข้ารหัส ───────────────────────────────────────────────────
# genesis ต้องอยู่ในไฟล์เดียวกับ block data — ถ้ามีแต่ block data ก็กู้เชนไม่ได้
# (ต่อไฟล์เข้า .tar.gz ทีหลังไม่ได้ จึงต้องใส่ให้ครบตั้งแต่ตอนสร้าง)
TAR_ARGS=(-C "$(dirname "$VALIDATOR_DATA")" "$(basename "$VALIDATOR_DATA")")
if [[ -f "$CHAIN_DIR/genesis.json" ]]; then
    TAR_ARGS+=(-C "$CHAIN_DIR" genesis.json)
else
    warn "ไม่พบ $CHAIN_DIR/genesis.json — ไฟล์สำรองจะไม่มี genesis ต้องเก็บแยกเอง"
    alert "backup_no_genesis" "warning" \
        "ไฟล์สำรองรอบนี้ไม่มี genesis.json ($CHAIN_DIR/genesis.json หาย) — มีแต่ block data กู้เชนไม่ได้"
fi

log "กำลังบีบอัดข้อมูลจาก $VALIDATOR_DATA"
tar -czf "$ARCHIVE" "${TAR_ARGS[@]}" || fail "บีบอัดไม่สำเร็จ (ดูบรรทัดของ tar ข้างบนประกอบ)"

# ── ยืนยันว่าไม่มีใครแอบเปิด validator ระหว่าง tar ────────────────────────────
# ถ้ามี = ที่เพิ่ง tar มาคือ snapshot ของ LevelDB ที่กำลังถูกเขียน = ใช้กู้ไม่ได้
# ด่านนี้จับได้แม้ tar คืนค่า 0 มา และแม้ flock พังหรือถูกปิดไว้
if container_running "$VALIDATOR" || [[ "$(container_started_at "$VALIDATOR")" != "$STOPPED_MARK" ]]; then
    fail "$VALIDATOR ถูกเปิดกลับระหว่างคัดลอกข้อมูล — ไฟล์รอบนี้ใช้กู้ไม่ได้ ทิ้งทั้งชุด (ตรวจว่า watchdog แย่งคิวหรือมีคนสั่งด้วยมือ)"
fi

log "กำลังเข้ารหัสไฟล์สำรอง"
gpg --batch --yes --symmetric --cipher-algo AES256 \
    --passphrase "$TPIX_BACKUP_PASS" \
    --output "$ENCRYPTED" "$ARCHIVE" || fail "เข้ารหัสไม่สำเร็จ"

shred -u "$ARCHIVE" 2>/dev/null || rm -f "$ARCHIVE"
ARCHIVE=""          # ทำลายแล้ว — อย่าให้ trap ไปตามหาอีก
chmod 600 "$ENCRYPTED"

# ── 4. เปิด validator กลับ แล้วรอจนเชนเดินต่อจริง ──────────────────────────
if ! docker ps --format '{{.Names}}' | grep -qx "$VALIDATOR"; then
    log "เปิด $VALIDATOR กลับ"
    docker start "$VALIDATOR" >/dev/null 2>&1 || fail "เปิด $VALIDATOR กลับไม่สำเร็จ — ต้องเข้าไปดูด้วยมือทันที"
fi
VALIDATOR_STOPPED_BY_US=0

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
    fail "เชนไม่เดินต่อภายใน 60 วินาทีหลังเปิด $VALIDATOR กลับ — ต้องเข้าไปตรวจด้วยมือทันที"
fi

# ── 5. ตรวจว่าไฟล์สำรองใช้ได้จริง (ไม่ใช่แค่มีไฟล์) ───────────────────────
log "ตรวจสอบไฟล์สำรองว่าถอดรหัสและอ่านได้"
if ! gpg --batch --yes --quiet --decrypt --passphrase "$TPIX_BACKUP_PASS" "$ENCRYPTED" 2>/dev/null | tar -tzf - >/dev/null 2>&1; then
    fail "ไฟล์สำรองเสียหรือถอดรหัสไม่ได้ — ถือว่าล้มเหลว"
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
        fail "ส่งไฟล์ออกนอกเครื่องไม่สำเร็จ — ไฟล์ยังอยู่ที่ $ENCRYPTED"
    fi
else
    warn "ยังไม่ได้ตั้ง TPIX_BACKUP_UPLOAD — ไฟล์อยู่แค่ในเครื่องนี้"
    warn "ดิสก์พังเมื่อไรก็หายพร้อมกัน กรุณาตั้งคำสั่งส่งออกนอกเครื่องด้วย"
    # ขึ้นคาดแดงเป็น warning — SystemAlert::raise รวมเป็นแถวเดียวแล้วนับ occurrences
    # จึงไม่รกหลังบ้าน แต่ทำให้ "ยอมหยุด validator ทุกคืนแล้วไฟล์ไม่เคยออกนอกเครื่อง"
    # เป็นสิ่งที่มองเห็นได้ ไม่ใช่บรรทัดที่ซ่อนอยู่ท้าย log
    alert "backup_not_offsite" "warning" \
        "ไฟล์สำรองเชนยังอยู่ในเครื่องเดียวกับเชน (ยังไม่ตั้ง TPIX_BACKUP_UPLOAD) — ดิสก์พังคือหายพร้อมกันทั้งคู่"
fi

# ── 7. ลบไฟล์เก่า ─────────────────────────────────────────────────────────
# จับเฉพาะ .gpg โดยตั้งใจ — ไฟล์ดิบไม่ควรมีอยู่เลย ถ้ามีต้องให้คนไปดูว่าเกิดอะไร
# (แจ้งไว้แล้วด้วย backup_plaintext_left ตอนต้น) ไม่ใช่ปล่อยให้หายเงียบตามอายุ
find "$BACKUP_DIR" -maxdepth 1 -name 'tpix-chain-*.tar.gz.gpg' -mtime "+$KEEP_DAYS" -print -delete 2>/dev/null | \
    while read -r old; do log "ลบไฟล์เก่า $old"; done

log "เสร็จสิ้น"
