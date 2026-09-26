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

# ── ด่านดิสก์ ────────────────────────────────────────────────────────────────
# เดิม watchdog ไม่เคยตรวจดิสก์เลยสักบรรทัด ซึ่งเป็นช่องที่แย่ที่สุดของเชนค่าแก๊ส 0:
# เขียน state ฟรี → deploy สัญญา 24KB ≈ 4.9M gas → ~4 GB/วัน
# หรือ SSTORE slot ใหม่ (20k gas) → ~5-10 GB/วัน เทียบกับ data เชนเก่าทั้งชีวิต 9.8 GB
# พอดิสก์เต็ม validator จะ crash แล้ว watchdog จะ restart วนไม่จบโดยไม่มีใครรู้สาเหตุ
DISK_PATH="${TPIX_DISK_PATH:-/opt/tpix}"
DISK_WARN_PCT="${TPIX_DISK_WARN_PCT:-75}"
DISK_CRIT_PCT="${TPIX_DISK_CRIT_PCT:-88}"

# ── ด่านสแปม ────────────────────────────────────────────────────────────────
# บล็อกเต็มติดกัน = สัญญาณยิงถล่มที่ชัดที่สุด เพราะทราฟฟิกจริงตอนนี้ทำให้
# pending เป็น 0 อยู่ตลอด (ยืนยันจาก prod 2026-08-27)
# ไม่ restart เพราะ restart ไม่ได้แก้สแปม แค่ทำให้เชนสะดุดซ้ำ — หน้าที่คือส่งเสียง
MEMPOOL_WARN="${TPIX_MEMPOOL_WARN:-1000}"      # pending+queued ที่ถือว่าผิดปกติ
BLOCK_FULL_PCT="${TPIX_BLOCK_FULL_PCT:-80}"    # gasUsed/gasLimit ที่ถือว่าเต็ม

# ── ล็อกกันชนกับงานสำรองข้อมูล ────────────────────────────────────────────────
# ต้องเป็น path เดียวกับที่ backup-chain.sh สร้าง ไม่งั้นทั้งสองตัวจะไม่เห็นกัน
BACKUP_LOCK="${TPIX_BACKUP_LOCK:-/run/tpix-backup.lock}"
BACKUP_LOCK_MAX_AGE="${TPIX_BACKUP_LOCK_MAX_AGE:-1800}"   # 30 นาที
# คิวบำรุงรักษาร่วมกับ backup-chain.sh — ต้องเป็น path เดียวกันทั้งสองสคริปต์
MAINT_LOCK="${TPIX_MAINT_LOCK:-/run/tpix-chain-maint.lock}"
VALIDATORS=(tpix-validator-1 tpix-validator-2 tpix-validator-3 tpix-validator-4)

# ── ด่าน validator แยกเชน / ตามไม่ทัน ─────────────────────────────────────────
# 2026-09-26 VM ดับกะทันหัน validator-1/2/4 เสียบล็อกท้ายที่ยังไม่ลงดิสก์ แล้วออกบล็อกใหม่
# ทับความสูงเดิม ส่วน validator-3 ยังถือชุดเก่า → แยกเชนค้างที่ 2126541 ถาวร ทั้งที่
# container ยัง healthy และเห็น peer ครบ · watchdog เดิมดูแค่ 8545 จึงเห็นแค่ "บล็อกไม่เดิน"
# แล้ว restart ทั้งวง 3 รอบจนหมดโควตา — fork ไม่หายด้วย restart ต้อง resync มือ
# ด่านนี้จึงแจ้งเตือนอย่างเดียว ไม่ restart และไม่ resync เอง: การซ่อมต้องหยุด validator
# 2 ตัว (เชนหยุดระหว่างนั้น) และต้องเลือกตัวต้นแบบให้ถูก ซึ่งควรเป็นคนตัดสิน
# RPC ของ validator แต่ละตัว — ลำดับต้องตรงกับ VALIDATORS (ชื่อผิดตัว = คนไป resync ผิดตัว)
read -r -a VALIDATOR_RPCS <<< "${TPIX_VALIDATOR_RPCS:-http://127.0.0.1:8545 http://127.0.0.1:8546 http://127.0.0.1:8547 http://127.0.0.1:8548}"
LAG_MAX_BLOCKS="${TPIX_LAG_MAX_BLOCKS:-30}"        # ตามหลังเชนหลักเกินนี้ = ผิดปกติ (~1 นาที)
LAG_CONFIRM_RUNS="${TPIX_LAG_CONFIRM_RUNS:-2}"     # ต้องเห็นติดกันกี่รอบถึงแจ้ง
# จำผลรอบก่อนไว้นับ "ติดกัน" — อยู่ใน /run ที่ root เขียนได้คนเดียว ไม่ใช่ /tmp ที่ใครก็วางไฟล์ดักได้
DIVERGENCE_STATE="${TPIX_DIVERGENCE_STATE:-/run/tpix-watchdog-divergence}"
DIVERGENCE_STATE_MAX_AGE="${TPIX_DIVERGENCE_STATE_MAX_AGE:-180}"   # วินาที — เก่ากว่านี้ไม่นับว่าติดกัน
# รอบแรกไม่มีบล็อกใหม่ ดูต่ออีกเท่านี้ก่อนตัดสินว่าเชนหยุด (0 = ตัดสินทันทีแบบเดิม)
BLOCK_PROGRESS_RECHECK="${TPIX_BLOCK_PROGRESS_RECHECK:-20}"

# Optional integrations (empty = skip)
HC_PING_URL="${HC_PING_URL:-}"
NTFY_TOPIC="${NTFY_TOPIC:-}"

# หลังบ้าน tpix.online — heartbeat + คาดแดง (empty = skip)
ALERT_URL="${TPIX_ALERT_URL:-}"
ALERT_TOKEN="${TPIX_ALERT_TOKEN:-}"
NODE_NAME="${TPIX_NODE_NAME:-$(hostname)}"
LAST_BLOCK_DEC=0
FORKED_VALIDATORS=()   # hash ไม่ตรงเสียงข้างมาก — ตัดออกจากการวัดความคืบหน้าของเชน
ACTIVE_ALERT_KEYS=()   # เหตุแบบแจ้งเตือนอย่างเดียวที่ยังเห็นอยู่รอบนี้ — ส่งไปกับ heartbeat

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
# active_keys = เหตุแบบแจ้งเตือนอย่างเดียวที่ยังไม่จบ (validator แยกเชน/ตามไม่ทัน): รอบนั้น
# เชนหลักยังเดิน heartbeat จึงยังยิง ถ้าไม่บอก หลังบ้านจะปิดเหตุทันทีหลังยกแล้วยกใหม่ทุกนาที
# (คาดแดงแทบไม่โผล่ แต่กระดิ่งแอดมินเด้งทุกนาที) · หลังบ้านรุ่นที่ไม่รู้จัก field นี้ก็แค่ข้ามไป
backend_heartbeat() {
    local keys="" extra="" k
    for k in "${ACTIVE_ALERT_KEYS[@]}"; do keys+="${keys:+,}\"${k}\""; done
    [ -n "$keys" ] && extra=",\"active_keys\":[${keys}]"
    backend_post "/heartbeat" "{\"node\":\"${NODE_NAME}\",\"block\":${1:-0}${extra}}"
}

# ยิงเหตุเข้าคาดแดง — key ซ้ำฝั่งหลังบ้านจะรวมเป็นรายการเดียว (นับ occurrences)
backend_alert() {
    local key="$1" sev="$2" msg="$3"
    # หลังบ้านรับ message ไม่เกิน 1000 ตัวอักษร เกินแล้วตอบ 422 = เหตุหายเงียบ
    # ตัดแบบนับตัวอักษร ไม่ใช่ไบต์ — cron ไม่มี locale ถ้าตัดกลางอักษรไทย JSON จะเสียทั้งก้อน
    msg=$( { LC_ALL=C.UTF-8; printf '%s' "${msg:0:1000}"; } 2>/dev/null )
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

# ─── อ่านหัวเชน / hash จาก validator ทีละตัว ───
# timeout สั้นกว่า check_rpc เพราะยิงหลายตัวต่อรอบ — ตัวที่แขวนต้องไม่ลากทั้งรอบจนเกินนาที
# กรองรูปแบบก่อนใช้เสมอ: ค่าพวกนี้ไหลเข้า $(( )) ซึ่ง bash ตีความเป็นนิพจน์ได้
rpc_head() {
    local hex
    hex=$(curl -s -m 3 -X POST "$1" -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null \
        | grep -o '"result":"0x[0-9a-fA-F]\{1,15\}"' | cut -d'"' -f4)
    [ -n "$hex" ] || return 1
    printf '%d' "$hex"
}

rpc_block_hash() {
    local hash
    hash=$(curl -s -m 3 -X POST "$1" -H 'Content-Type: application/json' \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$(printf '0x%x' "$2")\",false],\"id\":1}" 2>/dev/null \
        | grep -o '"hash":"0x[0-9a-fA-F]\{64\}"' | head -1 | cut -d'"' -f4)
    [ -n "$hash" ] || return 1
    printf '%s' "$hash"
}

is_forked() {
    local f
    for f in "${FORKED_VALIDATORS[@]}"; do [ "$f" = "$1" ] && return 0; done
    return 1
}

validator_data_dir() {
    local dir
    dir=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$1" 2>/dev/null)
    printf '%s' "${dir:-<โฟลเดอร์ /data ของ $1>}"
}

# ขั้นตอนเดียวกับที่ซ่อมจริง 2026-09-26 (เชนหยุด 114 วิ แล้วเดินต่อเองเมื่อครบ 4 ตัว) — ใส่ไว้ใน
# ข้อความแจ้งเตือนเลย คนที่เปิดคาดแดงกลางดึกจะได้ไม่ต้องไปค้นว่าต้องทำอะไร
# ต้นแบบต้องหยุดด้วย เพราะ LevelDB ที่คัดลอกขณะเปิดอยู่ไม่สอดคล้องกันเอง
resync_hint() {
    local bad="$1" donor="$2" bd dd
    bd=$(validator_data_dir "$bad"); dd=$(validator_data_dir "$donor")
    printf '%s' "ถือ flock $MAINT_LOCK ตลอดงาน (กัน watchdog/backup ชน) → docker stop $bad $donor (เชนหยุดระหว่างนี้) → ย้าย $bd/blockchain กับ $bd/trie ไปเก็บ → cp -a blockchain, trie, consensus/metadata, consensus/snapshots จาก $dd ไปไว้ใน $bd (คีย์ validator และ libp2p ของ $bad ห้ามทับ) → docker start $donor แล้วค่อย $bad"
}

# ─── Check 3: validator ทุกตัวอยู่เชนเดียวกันและตามทันไหม ───
# เทียบสองชั้น:
#   1. hash ที่ความสูงต่ำสุดที่ทุกตัวมี — IBFT ไม่มี reorg บล็อกความสูงเดียวกันต้องเป็นก้อนเดียวกัน
#      ไม่ตรง = แยกเชน แจ้งทันที (ตัวที่ fork ค้างถาวร รอยืนยันไปก็ไม่หาย)
#   2. ตามหลังเชนหลักเกิน LAG_MAX_BLOCKS หรืออ่านหัวเชนไม่ได้ ติดกัน LAG_CONFIRM_RUNS รอบ
#      — รอบเดียวอาจแค่กำลังไล่ตามหลังถูกหยุดไปสำรองข้อมูล
# แจ้งเตือนอย่างเดียว คืน 0 เสมอ · ผลที่ส่งต่อ: FORKED_VALIDATORS (ตัดออกจากการวัดความคืบหน้า)
# และ ACTIVE_ALERT_KEYS (บอก heartbeat ว่าเหตุไหนยังไม่จบ)
check_validator_divergence() {
    local -A heads=() hashes=() votes=() prev_streak=() prev_lag=() lag=() streak=()
    local n=${#VALIDATORS[@]} quorum i v h name s l names
    local readable=() min_head="" canon="" best="" best_n=0 tie=0 split=0
    local now prev_ts=0 fresh=0 donor="" first_lag="" summary="" groups=""
    local forked_msg="" lag_msg="" lag_sev="warning"

    # IBFT n ตัวทนพังได้ f=(n-1)/3 ต้องมีเสียง n-f — 4 ตัว = 3
    quorum=$(( n - (n - 1) / 3 ))
    FORKED_VALIDATORS=()

    # 1) หัวเชนของทุกตัว
    for i in "${!VALIDATORS[@]}"; do
        v=${VALIDATORS[$i]}
        if h=$(rpc_head "${VALIDATOR_RPCS[$i]:-}"); then
            heads[$v]=$h
            readable+=("$i")
            if [ -z "$min_head" ] || [ "$h" -lt "$min_head" ]; then min_head=$h; fi
        fi
        summary+="${summary:+ }${v#tpix-}=${heads[$v]:-?}"
    done

    # 2) hash ที่ความสูงร่วม → หาเสียงข้างมาก
    for i in "${readable[@]}"; do
        v=${VALIDATORS[$i]}
        h=$(rpc_block_hash "${VALIDATOR_RPCS[$i]}" "$min_head") || continue
        hashes[$v]=$h
        votes[$h]=$(( ${votes[$h]:-0} + 1 ))
    done
    for h in "${!votes[@]}"; do
        if [ "${votes[$h]}" -gt "$best_n" ]; then best=$h; best_n=${votes[$h]}; tie=0
        elif [ "${votes[$h]}" -eq "$best_n" ]; then tie=1; fi
    done
    if [ "${#votes[@]}" -gt 1 ]; then
        # ชี้ตัวผิดได้ก็ต่อเมื่อฝั่งใหญ่ครบองค์ประชุม — ฝั่งนั้นเท่านั้นที่ทำบล็อกต่อได้
        # ไม่ครบ (เช่น 2 ต่อ 2) ห้ามเดา: ชี้ผิดตัวแล้วคนไปทับข้อมูลตัวที่ถูก = เสียเชนจริง
        if [ "$tie" -eq 0 ] && [ "$best_n" -ge "$quorum" ]; then
            for i in "${readable[@]}"; do
                v=${VALIDATORS[$i]}
                if [ -n "${hashes[$v]:-}" ] && [ "${hashes[$v]}" != "$best" ]; then
                    FORKED_VALIDATORS+=("$v")
                fi
            done
        else
            split=1
        fi
    fi

    # 3) หัวเชนหลัก = สูงสุดของตัวที่ไม่ได้แยกเชน (ตัวที่ fork อาจค้างอยู่ "ข้างหน้า" ได้ ถ้าตัวอื่น
    #    เสียบล็อกท้ายไปแบบ 2026-09-26 — ห้ามใช้เป็นหลักวัด ไม่งั้นตัวปกติจะดูเหมือนตามไม่ทัน)
    for i in "${readable[@]}"; do
        v=${VALIDATORS[$i]}
        is_forked "$v" && continue
        if [ -z "$canon" ] || [ "${heads[$v]}" -gt "$canon" ]; then canon=${heads[$v]}; fi
    done

    # 4) ตามไม่ทัน — นับรอบติดกันจากผลรอบก่อน
    now=$(date +%s)
    if [ -r "$DIVERGENCE_STATE" ]; then
        while read -r name s l; do
            # ค่าจากไฟล์ไหลเข้า $(( )) — รับเฉพาะตัวเลข กันไฟล์เสีย/ถูกแก้แล้วกลายเป็นคำสั่ง
            [[ "$s" =~ ^[0-9]+$ ]] || continue
            if [ "$name" = "ts" ]; then prev_ts=$s; continue; fi
            prev_streak[$name]=$s
            [[ "$l" =~ ^[0-9]+$ ]] && prev_lag[$name]=$l
        done < "$DIVERGENCE_STATE"
    fi
    [ $(( now - prev_ts )) -le "$DIVERGENCE_STATE_MAX_AGE" ] && fresh=1

    for i in "${!VALIDATORS[@]}"; do
        v=${VALIDATORS[$i]}
        streak[$v]=0
        is_forked "$v" && continue      # รายงานเป็น "แยกเชน" แล้ว ไม่นับซ้ำเป็นตามไม่ทัน
        if [ -n "${heads[$v]:-}" ] && [ -n "$canon" ]; then
            lag[$v]=$(( canon - ${heads[$v]} ))
            [ "${lag[$v]}" -gt "$LAG_MAX_BLOCKS" ] || continue
            l="$v หัว ${heads[$v]} ห่างเชนหลัก ${lag[$v]} บล็อก"
        else
            # อ่านหัวเชนไม่ได้ = ยืนยันไม่ได้ว่ายังตามทัน นับเหมือนตามไม่ทัน
            l="$v ไม่ตอบ RPC ${VALIDATOR_RPCS[$i]:-?}"
        fi
        s=0
        [ "$fresh" -eq 1 ] && s=${prev_streak[$v]:-0}
        streak[$v]=$(( s + 1 ))
        if [ "${streak[$v]}" -lt "$LAG_CONFIRM_RUNS" ]; then
            log "WARNING: $l (รอบที่ ${streak[$v]}/${LAG_CONFIRM_RUNS} — ยังไม่แจ้ง)"
            continue
        fi
        # ห่างน้อยลงจากรอบก่อน = กำลังไล่ตาม (เตือน) · ค้าง/ห่างขึ้น/อ่านไม่ได้ = ต้องมีคนดู (วิกฤต)
        if [ -z "${lag[$v]:-}" ]; then
            l+=" ${streak[$v]} รอบติด"
            lag_sev="critical"
        elif [ "$fresh" -eq 1 ] && [ -n "${prev_lag[$v]:-}" ] && [ "${lag[$v]}" -lt "${prev_lag[$v]}" ]; then
            l+=" ${streak[$v]} รอบติด แต่กำลังไล่ตาม (รอบก่อนห่าง ${prev_lag[$v]})"
        else
            l+=" ${streak[$v]} รอบติด และไม่ไล่ตาม${prev_lag[$v]:+ (รอบก่อนห่าง ${prev_lag[$v]})}"
            lag_sev="critical"
        fi
        lag_msg+="${lag_msg:+ · }$l"
        [ -n "$first_lag" ] || first_lag=$v
    done

    {
        echo "ts $now"
        for v in "${VALIDATORS[@]}"; do echo "$v ${streak[$v]:-0} ${lag[$v]:--}"; done
    } 2>/dev/null > "${DIVERGENCE_STATE}.tmp" && mv -f "${DIVERGENCE_STATE}.tmp" "$DIVERGENCE_STATE" 2>/dev/null \
        || log "WARNING: เขียน $DIVERGENCE_STATE ไม่ได้ — นับรอบติดกันของ validator ที่ตามไม่ทันไม่ได้"

    # ต้นแบบสำหรับ resync = ตัวท้ายสุดที่อยู่เชนหลักและตามทัน (ตรงกับที่ใช้ซ่อมจริง: validator-4)
    for (( i = n - 1; i >= 0; i-- )); do
        v=${VALIDATORS[$i]}
        if [ -n "${lag[$v]:-}" ] && [ "${lag[$v]}" -le "$LAG_MAX_BLOCKS" ]; then donor=$v; break; fi
    done
    donor=${donor:-<validator ที่ตามทัน>}

    # 5) ประกอบข้อความ — เรื่องสำคัญไว้หน้า คาดแดงโชว์บรรทัดเดียวแล้วตัดท้าย
    if [ "$split" -eq 1 ]; then
        for h in "${!votes[@]}"; do
            names=""
            for i in "${readable[@]}"; do
                v=${VALIDATORS[$i]}
                [ "${hashes[$v]:-}" = "$h" ] && names+="${names:+,}$v"
            done
            groups+="${groups:+ / }$names = $h"
        done
        forked_msg="validator แยกเชนและไม่มีฝั่งไหนครบ $quorum ตัว — hash บล็อก #$min_head: $groups · หัวเชน $summary · ชี้ไม่ได้ว่าฝั่งไหนเป็นเชนหลัก ห้าม restart/ห้ามย้ายข้อมูลจนกว่าจะเทียบ hash บล็อก #$min_head กับ explorer"
    elif [ "${#FORKED_VALIDATORS[@]}" -gt 0 ]; then
        names=""
        for i in "${readable[@]}"; do
            v=${VALIDATORS[$i]}
            [ "${hashes[$v]:-}" = "$best" ] && names+="${names:+,}$v"
        done
        for v in "${FORKED_VALIDATORS[@]}"; do
            forked_msg+="${forked_msg:+ · }$v แยกเชน (fork) — บล็อก #$min_head ของตัวนี้คือ ${hashes[$v]} แต่ของ $names คือ $best · หัวเชน $v=${heads[$v]} เชนหลัก=$canon"
        done
        forked_msg+=" · restart ไม่หาย (fork ติดไปด้วย) watchdog จึงไม่ restart ให้ · วิธี resync: $(resync_hint "${FORKED_VALIDATORS[0]}" "$donor")"
    fi
    if [ -n "$lag_msg" ]; then
        lag_msg+=" · เชนหลัก=${canon:-?} · ยังไม่พบ hash ขัดกับเชนหลัก · watchdog ไม่ restart ให้ · ดู docker logs --tail 100 $first_lag ก่อน: ไม่เจอ 'unable to verify block' ให้ลอง docker restart $first_lag ตัวเดียว (ห้าม restart ทั้งวง) · เจอ = แยกเชน ต้อง resync: $(resync_hint "$first_lag" "$donor")"
    fi

    if [ "${#hashes[@]}" -lt 2 ]; then
        log "WARNING: เทียบ hash ข้าม validator ไม่ได้รอบนี้ (ได้ ${#hashes[@]} ตัว) — หัวเชน $summary"
    elif [ -z "$forked_msg" ] && [ -z "$lag_msg" ]; then
        log "OK: validator ${#hashes[@]}/$n ตัว hash@$min_head ตรงกัน — หัวเชน $summary"
    fi
    if [ -n "$forked_msg" ]; then
        log "CRITICAL: $forked_msg"
        backend_alert "validator_forked" "critical" "$forked_msg"
        ACTIVE_ALERT_KEYS+=(validator_forked)
    fi
    if [ -n "$lag_msg" ]; then
        log "${lag_sev^^}: $lag_msg"
        backend_alert "validator_lagging" "$lag_sev" "$lag_msg"
        ACTIVE_ALERT_KEYS+=(validator_lagging)
    fi
    return 0
}

# หัวเชนหลัก = หัวสูงสุดของ validator ที่อ่านได้และไม่ได้แยกเชน
# ไม่ผูกกับ 8545 ตัวเดียวแล้ว: ถ้า validator-1 เองเป็นตัวที่ค้าง การวัดจาก 8545 จะเห็น
# "ไม่ขยับ" ทุกรอบแล้ว restart ทั้งวงจนหมดโควตา ทั้งที่อีก 3 ตัวยังทำบล็อกอยู่
chain_head() {
    local i h best=""
    for i in "${!VALIDATORS[@]}"; do
        is_forked "${VALIDATORS[$i]}" && continue
        h=$(rpc_head "${VALIDATOR_RPCS[$i]:-}") || continue
        if [ -z "$best" ] || [ "$h" -gt "$best" ]; then best=$h; fi
    done
    [ -n "$best" ] || return 1
    echo "$best"
}

# ─── Check 4: Blocks progressing? ───
# return 0 if progressing, 1 if stalled
check_block_progress() {
    local dec1 dec2 diff waited=$BLOCK_PROGRESS_WAIT
    dec1=$(chain_head) || return 1

    sleep "$BLOCK_PROGRESS_WAIT"

    dec2=$(chain_head) || return 1

    # 10 วิไม่มีบล็อกใหม่ยังไม่แปลว่าเชนหยุด: มี validator ตัวหนึ่งไม่เสนอบล็อก (แยกเชน/ค้าง)
    # เมื่อไหร่ ทุกครั้งที่ถึงคิวมัน IBFT ต้องรอหมดรอบ ~12 วิ แล้วค่อยออกบล็อกรอบถัดไป = ช่องว่าง
    # ~15 วิ · 2026-09-26 เชน 3/4 ยังเดิน ~10 บล็อก/นาที แต่หน้าต่าง 10 วิตกช่องนี้ทุก ~3 นาที
    # → restart ทั้งวงฟรีจนโควตาหมด · ดูต่ออีกช่วงก่อนตัดสิน (เชนหยุดจริงยังโดน restart แค่ช้าลง)
    if [ "$dec2" -le "$dec1" ] && [ "$BLOCK_PROGRESS_RECHECK" -gt 0 ]; then
        log "WARNING: ${BLOCK_PROGRESS_WAIT}s ไม่มีบล็อกใหม่ (ค้างที่ $dec2) — ดูต่ออีก ${BLOCK_PROGRESS_RECHECK}s ก่อนตัดสิน"
        sleep "$BLOCK_PROGRESS_RECHECK"
        dec2=$(chain_head) || return 1
        waited=$((waited + BLOCK_PROGRESS_RECHECK))
    fi

    diff=$((dec2 - dec1))
    LAST_BLOCK_DEC=$dec2

    if [ "$diff" -le 0 ]; then
        log "ERROR: Blocks not progressing — $dec1 → $dec2 (diff=$diff in ${waited}s)"
        return 1
    fi
    log "OK: Block $dec1 → $dec2 (+$diff in ${waited}s; ~$((diff * 60 / waited)) blocks/min)"
    return 0
}

# ─── Check 5: Memory usage across all validators ───
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

# ─── ดิสก์ ───
# คืน 1 เมื่อถึงขั้นวิกฤต · ระดับเตือนแค่ log + แจ้งหลังบ้าน ไม่ทำให้ล้ม
check_disk() {
    local pct
    pct=$(df -P "$DISK_PATH" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    if [ -z "$pct" ]; then
        log "WARNING: อ่านพื้นที่ดิสก์ของ $DISK_PATH ไม่ได้"
        return 0
    fi

    if [ "$pct" -ge "$DISK_CRIT_PCT" ]; then
        log "CRITICAL: ดิสก์ $DISK_PATH ใช้ไป ${pct}% (เพดานวิกฤต ${DISK_CRIT_PCT}%)"
        backend_alert "disk_critical" "critical" \
            "ดิสก์เชนเหลือน้อยมาก ใช้ไป ${pct}% — เต็มเมื่อไหร่ validator ตายทั้งวง"
        return 1
    fi

    if [ "$pct" -ge "$DISK_WARN_PCT" ]; then
        log "WARNING: ดิสก์ $DISK_PATH ใช้ไป ${pct}% (เพดานเตือน ${DISK_WARN_PCT}%)"
        backend_alert "disk_warning" "warning" \
            "ดิสก์เชนใช้ไป ${pct}% — ถ้าโตเร็วผิดปกติให้ดูว่ามีใครยิง state ถล่มอยู่ไหม"
    fi

    return 0
}

# ─── สแปม / ยิงถล่ม ───
# แจ้งเตือนอย่างเดียว ไม่ restart — restart ไม่ได้ไล่คนยิงออกไป
check_flood() {
    local pool pending queued total blk gas_used gas_limit pct

    # txpool_status ผูก 127.0.0.1 ไว้ ไม่ได้เปิดออกเน็ต (ด่าน njs ปิดไว้ฝั่ง nginx)
    pool=$(curl -s -m 5 -X POST "$RPC_URL" -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"txpool_status","params":[],"id":1}' 2>/dev/null)

    pending=$(printf '%s' "$pool" | grep -o '"pending":[^,}]*' | head -1 | cut -d: -f2 | tr -d '" ')
    queued=$(printf '%s' "$pool"  | grep -o '"queued":[^,}]*'  | head -1 | cut -d: -f2 | tr -d '" ')

    if [ -n "$pending" ] && [ -n "$queued" ]; then
        total=$(( $(printf '%d' "$pending" 2>/dev/null || echo 0) + $(printf '%d' "$queued" 2>/dev/null || echo 0) ))
        if [ "$total" -ge "$MEMPOOL_WARN" ]; then
            log "WARNING: mempool ค้าง $total ใบ (เพดาน $MEMPOOL_WARN)"
            backend_alert "mempool_flood" "warning" \
                "mempool ค้าง $total ใบ — ปกติเป็น 0 ให้ดูว่ามีใครยิงถล่มอยู่ไหม"
        fi
    fi

    # บล็อกล่าสุดเต็มแค่ไหน — เชนนี้ทราฟฟิกจริงยังใกล้ 0 บล็อกเต็มจึงผิดปกติแน่นอน
    blk=$(curl -s -m 5 -X POST "$RPC_URL" -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}' 2>/dev/null)

    gas_used=$(printf '%s' "$blk"  | grep -o '"gasUsed":"[^"]*"'  | head -1 | cut -d'"' -f4)
    gas_limit=$(printf '%s' "$blk" | grep -o '"gasLimit":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -n "$gas_used" ] && [ -n "$gas_limit" ]; then
        gas_used=$(printf '%d' "$gas_used" 2>/dev/null || echo 0)
        gas_limit=$(printf '%d' "$gas_limit" 2>/dev/null || echo 0)
        if [ "$gas_limit" -gt 0 ]; then
            pct=$(( gas_used * 100 / gas_limit ))
            if [ "$pct" -ge "$BLOCK_FULL_PCT" ]; then
                log "WARNING: บล็อกล่าสุดใช้แก๊สไป ${pct}% ของเพดาน"
                backend_alert "block_saturated" "warning" \
                    "บล็อกล่าสุดเต็ม ${pct}% — เชนนี้ปกติแทบว่าง ให้ตรวจว่ามีใครยิงถล่มไหม"
            fi
        fi
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

    # ── เข้าคิวบำรุงรักษาร่วมกับ backup-chain.sh ────────────────────────────
    #
    # ทำไมธง BACKUP_LOCK ข้างล่างอย่างเดียวไม่พอ: มันเป็น test-then-act ที่ไม่
    # atomic — 2026-09-03 cron ทั้งสองยิงพร้อมกันที่ 19:17:00 พอดี รอบนั้นอ่านธง
    # ก่อนที่ backup จะเขียนเสร็จ จึงไม่เห็นอะไร แล้วสั่ง `compose up -d` ทับตอน
    # tar กำลังอ่าน LevelDB อยู่ → ไฟล์สำรองของวันนั้นเสียทั้งชุด
    #
    # flock ปิดช่องนั้นเพราะ "ขอคิว" กับ "ได้คิว" เป็นก้าวเดียวกัน
    # -n = ไม่รอ ข้ามรอบนี้ไปเลย (อีกนาทีเดียวก็มาใหม่ ไม่ต้องต่อคิว)
    # -E 75 = แยก "จับคิวไม่ได้" ออกจาก "ตัวเองล้มเหลว"
    # ไม่มี flock บนเครื่อง = ทำงานต่อแบบเดิม ธง BACKUP_LOCK ยังกันอีกชั้น
    if command -v flock >/dev/null 2>&1 && [ -z "${TPIX_WATCHDOG_FLOCKED:-}" ]; then
        export TPIX_WATCHDOG_FLOCKED=1
        flock -n -E 75 "$MAINT_LOCK" "$0" "$@"
        local rc=$?
        if [ "$rc" -eq 75 ]; then
            log "SKIP: มีงานบำรุงรักษาถือคิวอยู่ (flock $MAINT_LOCK) — ข้ามรอบนี้"
            hc_ping
            exit 0
        fi
        exit "$rc"
    fi

    # ── ยอมให้งานสำรองข้อมูลหยุด validator ได้ 1 ตัวโดยไม่โดน restart ทับ ──────
    #
    # backup-chain.sh หยุด tpix-validator-4 ชั่วคราวเพื่อคัดลอกข้อมูลให้สอดคล้องกัน
    # (IBFT 4 ตัวทนพังได้ 1 เชนจึงเดินต่อ) แต่ check_containers เห็นแล้วจะสั่ง
    # restart ทั้งวง = ข้อมูลถูกคัดลอกกลางคันจนไฟล์สำรองเสีย และเชนสะดุดฟรี ๆ
    #
    # ชั้นนี้ยังอยู่เป็น defense-in-depth: กันกรณี flock ใช้ไม่ได้ และเป็นตัวจับ
    # "backup ตายกลางทางจนลบล็อกไม่ทัน" ซึ่ง flock บอกไม่ได้ (ล็อกหลุดตอนโปรเซสตาย)
    # ล็อกมีอายุ ถ้า backup ตายกลางทางจนลบล็อกไม่ทัน watchdog จะกลับมาทำงานเองใน
    # 30 นาที ไม่ใช่เงียบไปตลอดกาล
    if [ -f "$BACKUP_LOCK" ]; then
        local lock_age
        lock_age=$(( $(date +%s) - $(stat -c %Y "$BACKUP_LOCK" 2>/dev/null || echo 0) ))
        if [ "$lock_age" -lt "$BACKUP_LOCK_MAX_AGE" ]; then
            log "SKIP: งานสำรองข้อมูลกำลังทำงาน (ล็อกอายุ ${lock_age}s) — ไม่ตรวจ/ไม่ restart รอบนี้"
            hc_ping
            exit 0
        fi
        log "WARNING: ล็อกสำรองข้อมูลค้างมา ${lock_age}s เกินเพดาน ${BACKUP_LOCK_MAX_AGE}s — ตรวจตามปกติ"
        backend_alert "backup_lock_stale" "warning" \
            "ล็อกสำรองข้อมูลค้างเกิน ${BACKUP_LOCK_MAX_AGE}s — งานสำรองอาจตายกลางทาง ไปดูที่ $BACKUP_LOCK"
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

    # Check 3: validator แยกเชน/ตามไม่ทัน — แจ้งเตือนอย่างเดียว ไม่ restart ไม่ resync และไม่แตะ
    # โควตา restart · ต้องมาก่อนวัดบล็อก เพราะตัวที่แยกเชนถูกตัดออกจากการวัดความคืบหน้า
    check_validator_divergence || true

    # Check 4: block progress (สำคัญที่สุด)
    if ! check_block_progress; then
        restart_chain "blocks not progressing"
        [ $? -eq 0 ] && hc_ping || hc_ping "/fail"
        exit 0
    fi

    # Check 5: memory (warning only — restart ถ้าสูงเกิน)
    if ! check_memory; then
        restart_chain "memory pressure"
        [ $? -eq 0 ] && hc_ping || hc_ping "/fail"
        exit 0
    fi

    # Check 6: ดิสก์ — ไม่ restart เพราะ restart ไม่ได้คืนพื้นที่ แต่ต้องส่งเสียง
    # ข้อนี้สำคัญกว่าที่เห็น: เชนค่าแก๊ส 0 ถูกถมดิสก์ได้ฟรี และเมื่อเต็มแล้ว
    # อาการจะออกมาเป็น "validator ตาย → watchdog restart → ตายอีก" วนไม่จบ
    check_disk || true

    # Check 7: สแปม / ยิงถล่ม — แจ้งเตือนอย่างเดียวเช่นกัน
    check_flood || true

    # All checks passed — heartbeat (healthchecks.io + หลังบ้าน tpix.online)
    hc_ping
    backend_heartbeat "$LAST_BLOCK_DEC"
}

main "$@"
