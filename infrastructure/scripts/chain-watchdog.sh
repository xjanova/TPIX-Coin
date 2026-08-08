#!/bin/bash
# ============================================================
# TPIX Chain Watchdog — 4-validator IBFT cluster
#
# ตรวจสอบและ restart chain อัตโนมัติ — รันทุก 1 นาทีผ่าน cron
#
# Install:
#   sudo bash infrastructure/scripts/install-watchdog.sh
#
# Manual run:
#   sudo bash infrastructure/scripts/chain-watchdog.sh
#
# Config — set ใน /etc/tpix-watchdog.env:
#   TPIX_INFRA_DIR=/home/admin/tpix-infrastructure (default)
#   HC_PING_URL=https://hc-ping.com/<uuid>          (optional — dead-man-switch)
#   NTFY_TOPIC=https://ntfy.sh/tpix-alerts-xxx      (optional — push on critical)
#   TPIX_ALERT_URL=https://tpix.online/api/infra    (optional — คาดแดงหลังบ้าน tpix.online)
#   TPIX_ALERT_TOKEN=<token>                        (คู่กับ TPIX_ALERT_URL — ค่าเดียวกับ
#                                                    TPIX_INFRA_ALERT_TOKEN ใน .env ฝั่งเว็บ)
#   TPIX_NODE_NAME=chain-1                          (ชื่อ node ที่โชว์ในหลังบ้าน; default hostname
#                                                    — ตอนขยายหลายเครื่อง ตั้งไม่ให้ซ้ำกัน)
#
# Developed by Xman Studio
# ============================================================

set -uo pipefail

# ─── Load config ───
ENV_FILE="${TPIX_WATCHDOG_ENV:-/etc/tpix-watchdog.env}"
if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    set -a; . "$ENV_FILE"; set +a
fi

# ─── Defaults ───
INFRA_DIR="${TPIX_INFRA_DIR:-$HOME/tpix-infrastructure}"
RPC_URL="${TPIX_RPC_URL:-http://127.0.0.1:8545}"
LOG_FILE="${TPIX_WATCHDOG_LOG:-/var/log/tpix-watchdog.log}"
MAX_RESTART_PER_HOUR="${TPIX_MAX_RESTART_PER_HOUR:-3}"
RESTART_COUNTER_FILE="${TPIX_RESTART_COUNTER_FILE:-/tmp/tpix-restart-counter}"
BLOCK_PROGRESS_WAIT="${TPIX_BLOCK_PROGRESS_WAIT:-10}"  # วินาที — ห่างกันระหว่าง 2 sample
MEM_WARN_PCT="${TPIX_MEM_WARN_PCT:-85}"
VALIDATORS=(tpix-validator-1 tpix-validator-2 tpix-validator-3 tpix-validator-4)

# Optional integrations (empty = skip)
HC_PING_URL="${HC_PING_URL:-}"
NTFY_TOPIC="${NTFY_TOPIC:-}"

# หลังบ้าน tpix.online — heartbeat + คาดแดง (empty = skip)
ALERT_URL="${TPIX_ALERT_URL:-}"
ALERT_TOKEN="${TPIX_ALERT_TOKEN:-}"
NODE_NAME="${TPIX_NODE_NAME:-$(hostname)}"
LAST_BLOCK_DEC=0

# ─── Logging — เขียน log file ในตัว, print to terminal เฉพาะตอน interactive ───
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
log() {
    local msg="[$(timestamp)] $1"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    # ถ้า stderr เป็น terminal (manual run) — print ด้วย; cron ไม่ print
    [ -t 2 ] && echo "$msg" >&2
}

# ─── Dead-man-switch + alert helpers (no-op if URL not set) ───
hc_ping() {
    [ -n "$HC_PING_URL" ] || return 0
    local suffix="${1:-}"
    curl -fsS -m 10 --retry 2 "${HC_PING_URL}${suffix}" -o /dev/null 2>/dev/null || true
}

ntfy_push() {
    [ -n "$NTFY_TOPIC" ] || return 0
    local title="$1"; shift
    local body="$*"
    curl -fsS -m 10 \
        -H "Title: $title" \
        -H "Priority: high" \
        -H "Tags: warning,tpix" \
        -d "$body" \
        "$NTFY_TOPIC" -o /dev/null 2>/dev/null || true
}

# ─── หลังบ้าน tpix.online — heartbeat + คาดแดง (no-op if URL/token not set) ───
# สำคัญ: ต้องส่ง User-Agent (-A) เสมอ — Cloudflare WAF บล็อก request ไม่มี UA เป็น 403
# ทุกตัวเป็น best-effort (|| true) — ระบบแจ้งเตือนล่มต้องไม่ทำให้ watchdog ล่มตาม
backend_post() {
    [ -n "$ALERT_URL" ] && [ -n "$ALERT_TOKEN" ] || return 0
    curl -fsS -m 10 -A "tpix-watchdog/1.0 (${NODE_NAME})" \
        -H "Authorization: Bearer ${ALERT_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$2" "${ALERT_URL}$1" -o /dev/null 2>/dev/null || true
}

# heartbeat = "ทุก check ผ่าน" — ฝั่งหลังบ้านใช้ auto-resolve เหตุร้ายของ node นี้
# และใช้จับกรณีทั้งเครื่องดับ: heartbeat ขาดเกิน 3 นาที → ฝั่งเว็บขึ้นคาดแดงเอง
backend_heartbeat() {
    backend_post "/heartbeat" "{\"node\":\"${NODE_NAME}\",\"block\":${1:-0}}"
}

# ยิงเหตุเข้าคาดแดง — key ซ้ำฝั่งหลังบ้านจะรวมเป็นรายการเดียว (นับ occurrences)
backend_alert() {
    local key="$1" sev="$2" msg="$3"
    msg=${msg//\\/\\\\}; msg=${msg//\"/\\\"}
    backend_post "/alert" "{\"node\":\"${NODE_NAME}\",\"key\":\"${key}\",\"severity\":\"${sev}\",\"message\":\"${msg}\"}"
}

# ─── Compose file auto-detect ───
detect_compose_file() {
    # ดู container ที่รันอยู่ว่าเริ่มจากไฟล์ไหน
    if [ -f "$INFRA_DIR/docker-compose-4v.yml" ] && docker ps --filter "name=tpix-validator-1" --format '{{.Names}}' | grep -q .; then
        # ถ้าตอนนี้ตัวไหนเป็น active ก็ใช้ตัวนั้น — โดยดูจาก label หรือ default ไป 4v ถ้ามี
        local active_file
        active_file=$(docker inspect tpix-validator-1 --format '{{ index .Config.Labels "com.docker.compose.project.config_files" }}' 2>/dev/null || echo "")
        if echo "$active_file" | grep -q "docker-compose-4v.yml"; then
            echo "$INFRA_DIR/docker-compose-4v.yml"
            return
        fi
    fi
    # default fallback: docker-compose.yml (OLD) > docker-compose-4v.yml
    if [ -f "$INFRA_DIR/docker-compose.yml" ]; then
        echo "$INFRA_DIR/docker-compose.yml"
    elif [ -f "$INFRA_DIR/docker-compose-4v.yml" ]; then
        echo "$INFRA_DIR/docker-compose-4v.yml"
    else
        echo ""
    fi
}

# ─── Restart counter (กัน restart loop) ───
check_restart_limit() {
    local now count last_modified diff
    now=$(date +%s)

    if [ -f "$RESTART_COUNTER_FILE" ]; then
        last_modified=$(stat -c %Y "$RESTART_COUNTER_FILE" 2>/dev/null || echo 0)
        diff=$((now - last_modified))
        if [ $diff -gt 3600 ]; then
            echo "0" > "$RESTART_COUNTER_FILE"
        fi
        count=$(cat "$RESTART_COUNTER_FILE" 2>/dev/null || echo 0)
        if [ "$count" -ge "$MAX_RESTART_PER_HOUR" ]; then
            log "CRITICAL: Restarted $count times in last hour. Manual intervention required."
            ntfy_push "TPIX chain CRITICAL" "Watchdog blocked: ${count} restarts in last hour. Check infrastructure manually."
            backend_alert "chain_restart_blocked" "critical" "Watchdog restart ${count} ครั้งใน 1 ชม.แล้วยังไม่หาย — หยุด auto-restart รอคนเข้าไปดู"
            return 1
        fi
    else
        echo "0" > "$RESTART_COUNTER_FILE"
    fi
    return 0
}

increment_restart_counter() {
    local count
    count=$(cat "$RESTART_COUNTER_FILE" 2>/dev/null || echo 0)
    echo $((count + 1)) > "$RESTART_COUNTER_FILE"
}

# ─── Check 1: All 4 validators running? ───
check_containers() {
    local missing=()
    for v in "${VALIDATORS[@]}"; do
        local status
        status=$(docker inspect -f '{{.State.Status}}' "$v" 2>/dev/null || echo "not_found")
        if [ "$status" != "running" ]; then
            missing+=("$v($status)")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        log "ERROR: Validators not running: ${missing[*]}"
        return 1
    fi
    return 0
}

# ─── Check 2: RPC responding + return block number (hex) ───
check_rpc() {
    local response result
    response=$(curl -s --max-time 10 "$RPC_URL" \
        -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null)
    [ -z "$response" ] && return 1
    result=$(echo "$response" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
    [ -z "$result" ] && return 1
    echo "$result"
}

hex_to_dec() {
    local hex="$1"
    [ -z "$hex" ] && { echo 0; return; }
    printf "%d" "$hex" 2>/dev/null || echo 0
}

# ─── Check 3: Blocks progressing? ───
# return 0 if progressing, 1 if stalled
check_block_progress() {
    local block1 block2 dec1 dec2 diff
    block1=$(check_rpc) || return 1

    sleep "$BLOCK_PROGRESS_WAIT"

    block2=$(check_rpc) || return 1
    dec1=$(hex_to_dec "$block1")
    dec2=$(hex_to_dec "$block2")
    diff=$((dec2 - dec1))
    LAST_BLOCK_DEC=$dec2

    if [ "$diff" -le 0 ]; then
        log "ERROR: Blocks not progressing — $dec1 → $dec2 (diff=$diff in ${BLOCK_PROGRESS_WAIT}s)"
        return 1
    fi
    log "OK: Block $dec1 → $dec2 (+$diff in ${BLOCK_PROGRESS_WAIT}s; ~$((diff * 60 / BLOCK_PROGRESS_WAIT)) blocks/min)"
    return 0
}

# ─── Check 4: Memory usage across all validators ───
check_memory() {
    local pct_int worst=0 worst_name="" v pct
    for v in "${VALIDATORS[@]}"; do
        pct=$(docker stats "$v" --no-stream --format "{{.MemPerc}}" 2>/dev/null | tr -d '%' || echo "0")
        pct_int=$(echo "$pct" | cut -d'.' -f1)
        pct_int=${pct_int:-0}
        if [ "$pct_int" -gt "$worst" ]; then
            worst=$pct_int
            worst_name=$v
        fi
    done
    if [ "$worst" -gt "$MEM_WARN_PCT" ]; then
        log "WARNING: $worst_name memory at ${worst}% (threshold $MEM_WARN_PCT%)"
        return 1
    fi
    return 0
}

# ─── Restart all validators ───
restart_chain() {
    local reason="$1" compose_file
    log "RESTARTING chain — reason: $reason"
    backend_alert "chain_stalled" "critical" "เชนสะดุด (${reason}) — watchdog กำลัง restart validator ทั้งวง"

    check_restart_limit || return 1
    increment_restart_counter

    compose_file=$(detect_compose_file)
    if [ -z "$compose_file" ]; then
        log "ERROR: No docker-compose file found in $INFRA_DIR"
        return 1
    fi
    log "Using compose: $compose_file"

    # ถ้า container ไม่ขึ้น → `up -d` (recreate)
    # ถ้า container ขึ้นแต่ stuck → `restart` (เร็วกว่า)
    local missing_any=0
    for v in "${VALIDATORS[@]}"; do
        docker inspect -f '{{.State.Status}}' "$v" 2>/dev/null | grep -q "running" || missing_any=1
    done

    cd "$(dirname "$compose_file")" || return 1

    if [ "$missing_any" -eq 1 ]; then
        log "Some validators missing — running 'compose up -d'..."
        docker compose -f "$(basename "$compose_file")" up -d 2>&1 | tail -5 | while read -r l; do log "  $l"; done
    else
        log "All validators running — restarting them..."
        docker restart "${VALIDATORS[@]}" 2>&1 | tail -5 | while read -r l; do log "  $l"; done
    fi

    log "Waiting 20s for IBFT consensus to resume..."
    sleep 20

    local block_after dec_after
    block_after=$(check_rpc)
    if [ -z "$block_after" ]; then
        log "RESTART FAILED: RPC still not responding"
        ntfy_push "TPIX chain DOWN" "Watchdog restart failed: RPC unreachable after restart. Reason was: $reason"
        backend_alert "chain_down" "critical" "Restart แล้ว RPC ยังไม่ตอบ — เชนล่ม ต้องมีคนเข้าไปดูด่วน (สาเหตุแรก: ${reason})"
        return 1
    fi

    dec_after=$(hex_to_dec "$block_after")
    log "RESTART OK: RPC responding, block $dec_after"
    ntfy_push "TPIX chain restarted" "Watchdog recovered chain. Reason: $reason. Now at block $dec_after."
    # warning ค้างไว้ให้แอดมินกดรับทราบ — ส่วน chain_stalled (critical) จะถูก
    # auto-resolve ด้วย heartbeat รอบถัดไปเมื่อทุก check กลับมาผ่าน
    backend_alert "chain_restarted" "warning" "Watchdog กู้เชนสำเร็จ (สาเหตุ: ${reason}) — ตอนนี้อยู่บล็อก ${dec_after}"
    return 0
}

# ─── Main ───
main() {
    if [ ! -d "$INFRA_DIR" ]; then
        log "ERROR: Infrastructure dir not found: $INFRA_DIR"
        hc_ping "/fail"
        exit 1
    fi

    # Check 1: containers
    if ! check_containers; then
        restart_chain "containers not all running"
        # ping after attempted recovery — success if restart_chain returned 0
        [ $? -eq 0 ] && hc_ping || hc_ping "/fail"
        exit 0
    fi

    # Check 2: RPC
    if ! check_rpc > /dev/null 2>&1; then
        log "ERROR: RPC not responding"
        restart_chain "RPC not responding"
        [ $? -eq 0 ] && hc_ping || hc_ping "/fail"
        exit 0
    fi

    # Check 3: block progress (สำคัญที่สุด)
    if ! check_block_progress; then
        restart_chain "blocks not progressing"
        [ $? -eq 0 ] && hc_ping || hc_ping "/fail"
        exit 0
    fi

    # Check 4: memory (warning only — restart ถ้าสูงเกิน)
    if ! check_memory; then
        restart_chain "memory pressure"
        [ $? -eq 0 ] && hc_ping || hc_ping "/fail"
        exit 0
    fi

    # All checks passed — heartbeat (healthchecks.io + หลังบ้าน tpix.online)
    hc_ping
    backend_heartbeat "$LAST_BLOCK_DEC"
}

main "$@"
