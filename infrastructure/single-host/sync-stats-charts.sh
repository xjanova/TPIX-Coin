#!/bin/bash
# ============================================================
# ดึง charts.json ของบริการ stats ออกจาก image มาแก้สัญลักษณ์เหรียญ แล้ววางไว้ให้ bind-mount
#
# ทำไมต้องมีสคริปต์นี้
#   charts.json ฝัง "native_coin_symbol": "ETH" ไว้ในตัว image และไม่มี env
#   ให้ override ค่านี้เลย ผลคือหน้า /stats เขียนว่า "Transactions fees (24h) 0 ETH"
#   และ "Number of ETH transfers" ทั้งที่เชนนี้ใช้ TPIX — ผู้ใช้อ่านแล้วสับสนว่า
#   explorer ดูเชนผิดตัวหรือเปล่า
#
#   ไฟล์ต้นฉบับ 17KB/393 บรรทัด แต่คำว่า ETH โผล่จุดเดียว จึงไม่เก็บสำเนาไว้ใน repo
#   (จะ drift กับ upstream ทุกครั้งที่อัป image) — ดึงสดจาก image ที่ใช้อยู่จริงแล้ว
#   แก้บรรทัดเดียวแทน
#
# ต้องรันใหม่ทุกครั้งที่เปลี่ยน digest ของ ghcr.io/blockscout/stats ใน compose
#
# Usage (as root):
#   sudo bash sync-stats-charts.sh          # แล้วค่อย docker compose up -d blockscout-stats
#
# Developed by Xman Studio
# ============================================================

set -euo pipefail

SYMBOL="${TPIX_COIN_SYMBOL:-TPIX}"
OUT_DIR="${1:-/opt/tpix/blockscout}"
OUT="$OUT_DIR/stats-charts.json"
SRC_IN_IMAGE="/app/config/blockscout_instance/charts.json"
CONTAINER="blockscout-stats"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo -e "${GREEN}[+]${NC} $*"; }
err() { echo -e "${RED}[✗]${NC} $*" >&2; }

[[ $EUID -eq 0 ]] || { err "ต้องรันด้วย root (sudo)"; exit 1; }

docker inspect "$CONTAINER" >/dev/null 2>&1 || {
    err "ไม่พบคอนเทนเนอร์ $CONTAINER — สร้างมันขึ้นมาก่อน (docker compose up -d $CONTAINER)"
    exit 1
}

mkdir -p "$OUT_DIR"

# อ่านจาก image ผ่าน `docker cp` ไม่ใช่ `exec cat` — ถ้ารอบก่อนหน้า mount ทับไว้แล้ว
# exec จะอ่านได้ไฟล์ที่แก้แล้ว (แก้ซ้ำก็ยังถูก แต่จะไม่ได้ของใหม่ตอนอัปเวอร์ชัน)
IMAGE=$(docker inspect "$CONTAINER" --format '{{.Config.Image}}')
TMP_C=$(docker create "$IMAGE")
trap 'docker rm -f "$TMP_C" >/dev/null 2>&1 || true' EXIT
docker cp "$TMP_C:$SRC_IN_IMAGE" "$OUT.raw"
log "ดึง charts.json จาก image มาแล้ว ($(wc -c < "$OUT.raw") ไบต์)"

grep -q '"native_coin_symbol"' "$OUT.raw" || {
    err "ไม่พบคีย์ native_coin_symbol — โครงสร้างไฟล์เปลี่ยนไปแล้ว ต้องอ่าน charts.json ก่อนแก้สคริปต์นี้"
    exit 1
}

sed -E "s/(\"native_coin_symbol\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"/\1\"$SYMBOL\"/" "$OUT.raw" > "$OUT"

python3 -c "import json,sys; json.load(open('$OUT'))" 2>/dev/null || {
    err "ผลลัพธ์ไม่ใช่ JSON ที่ถูกต้อง — ยกเลิก ไม่เขียนทับของเดิม"
    exit 1
}

ACTUAL=$(python3 -c "import json; print(json.load(open('$OUT'))['template_values']['native_coin_symbol'])")
[[ "$ACTUAL" == "$SYMBOL" ]] || { err "แก้ไม่ติด: ยังเป็น '$ACTUAL'"; exit 1; }

rm -f "$OUT.raw"
chmod 0644 "$OUT"
log "เขียน $OUT แล้ว (native_coin_symbol = $ACTUAL)"
echo
echo "ขั้นต่อไป: cd /opt/tpix && sudo docker compose up -d --no-deps blockscout-stats"
