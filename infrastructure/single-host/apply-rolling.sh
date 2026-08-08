#!/bin/bash
# ============================================================
# Rolling apply — recreate validator ทีละตัว รักษา quorum 3/4
#
# ใช้ตอนแก้ docker-compose.yml (env/healthcheck/limits) บนเครื่อง
# ที่เชนกำลังวิ่ง — เชนต้องไม่หยุดผลิตบล็อกระหว่างอัปเดต
#
# ห้ามใช้ `docker compose up -d` เฉยๆ กับการแก้ x-validator anchor:
# มันจะ recreate ทั้ง 4 ตัวพร้อมกัน → เสีย quorum → เชนสะดุด
#
# Usage (as root):
#   sudo bash apply-rolling.sh [compose_dir]     # default /opt/tpix
#
# ก่อนรัน: วางไฟล์ compose ใหม่ทับ $compose_dir/docker-compose.yml แล้ว
# (สคริปต์ตรวจว่ามี backup .bak-* ของวันนี้ก่อน ถ้าไม่มีจะเตือน)
#
# Developed by Xman Studio
# ============================================================

set -euo pipefail

DIR="${1:-/opt/tpix}"
RPC="${TPIX_RPC_URL:-http://127.0.0.1:8545}"
VALIDATORS=(tpix-validator-1 tpix-validator-2 tpix-validator-3 tpix-validator-4)

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }

[[ $EUID -eq 0 ]] || { err "ต้องรันด้วย root (sudo)"; exit 1; }
[[ -f "$DIR/docker-compose.yml" ]] || { err "ไม่พบ $DIR/docker-compose.yml"; exit 1; }

if ! ls "$DIR"/docker-compose.yml.bak-* >/dev/null 2>&1; then
    warn "ไม่พบไฟล์ backup (.bak-*) ใน $DIR — ควร cp เก็บไว้ก่อน apply เผื่อ rollback"
fi

block_hex() {
    curl -s -m 5 -X POST -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$RPC" 2>/dev/null | grep -o '"result":"[^"]*"' | cut -d'"' -f4
}

# รอจนเชนผลิตบล็อกใหม่ (ยืนยันว่า quorum ยังอยู่) — เพดาน ~90 วิ
wait_chain_progress() {
    local b1 b2 i
    b1=$(block_hex)
    for i in $(seq 1 30); do
        sleep 3
        b2=$(block_hex)
        if [[ -n "$b2" && -n "$b1" && "$b2" != "$b1" ]]; then
            log "  เชนเดินอยู่: $b1 → $b2"
            return 0
        fi
        [[ -z "$b1" ]] && b1=$(block_hex)
    done
    return 1
}

# รอ container กลับมา healthy (มี healthcheck ทุกตัวใน compose ใหม่) — เพดาน ~120 วิ
wait_container_healthy() {
    local name="$1" st i
    for i in $(seq 1 40); do
        st=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || echo "missing")
        if [[ "$st" == "healthy" ]]; then return 0; fi
        # compose เก่าไม่มี healthcheck → running ก็พอ (จะเจอเฉพาะรอบ apply แรก)
        if [[ "$st" == "running" ]]; then
            docker inspect -f '{{.State.Health}}' "$name" 2>/dev/null | grep -q '^<nil>$' && return 0
        fi
        sleep 3
    done
    return 1
}

cd "$DIR"

log "ตรวจเชนก่อนเริ่ม..."
if ! wait_chain_progress; then
    err "เชนไม่เดินอยู่แล้วก่อน apply — ห้าม rolling ตอนเชนหยุด"
    err "กู้เชนก่อน (docker restart validator ทั้ง 4 พร้อมกัน) แล้วค่อยรันใหม่"
    exit 1
fi

for v in "${VALIDATORS[@]}"; do
    log "── recreate $v ──"
    # --no-deps สำคัญ: กันไม่ให้ compose ไปแตะ blockscout ที่ depends_on validator-1
    docker compose up -d --no-deps "$v" 2>&1 | tail -2

    if ! wait_container_healthy "$v"; then
        err "$v ไม่กลับมา healthy — หยุดทันที (อีก 3 ตัวยังถือ quorum อยู่)"
        err "ดู log: docker logs --tail 50 $v"
        exit 1
    fi
    log "  $v healthy"

    if ! wait_chain_progress; then
        err "เชนไม่ผลิตบล็อกหลัง recreate $v — หยุดก่อนแตะตัวถัดไป"
        exit 1
    fi
done

B=$(block_hex)
echo
log "✅ rolling apply ครบ 4 validator — เชนเดินต่อเนื่อง อยู่ที่บล็อก $((16#${B:2}))"
log "ตรวจ env ใหม่: docker exec tpix-validator-1 env | grep -E 'GOGC|GOMEM|GOMAX'"
