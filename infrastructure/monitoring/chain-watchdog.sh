#!/bin/bash
# TPIX Chain Watchdog — runs every minute via cron
# Detects: block lag, RPC unreachable, validator down
# Alerts via ntfy.sh (free, self-hosted-able, no signup needed)
#
# Setup:
#   1. Pick a unique ntfy topic name (random string — anyone with the name can read alerts):
#        TPIX_NTFY_TOPIC="tpix-alerts-$(openssl rand -hex 8)"
#   2. Subscribe on phone: install ntfy app → add topic → done
#   3. Add cron entry:
#        */1 * * * * /home/admin/TPIX-Coin/infrastructure/monitoring/chain-watchdog.sh
#   4. Optionally use private ntfy server (self-hosted Docker):
#        docker run -d -p 8082:80 binwiederhier/ntfy serve
#
# Tunable thresholds via env file at /etc/tpix-watchdog.env:
#   RPC_URL=https://rpc.tpix.online
#   NTFY_TOPIC=tpix-alerts-...
#   NTFY_SERVER=https://ntfy.sh
#   MAX_BLOCK_LAG_SECONDS=120        # alert if no new block in N seconds
#   MIN_PEER_COUNT=2                 # alert if connected peers < N
#   STATE_DIR=/var/lib/tpix-watchdog
#   COOLDOWN_SECONDS=900             # don't re-alert same condition for 15min

set -euo pipefail

# ──── Load env or use defaults
ENV_FILE=/etc/tpix-watchdog.env
[[ -r "$ENV_FILE" ]] && source "$ENV_FILE"

RPC_URL="${RPC_URL:-https://rpc.tpix.online}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
NTFY_TOPIC="${NTFY_TOPIC:-tpix-alerts-CHANGE-ME}"
MAX_BLOCK_LAG_SECONDS="${MAX_BLOCK_LAG_SECONDS:-120}"
MIN_PEER_COUNT="${MIN_PEER_COUNT:-2}"
STATE_DIR="${STATE_DIR:-/var/lib/tpix-watchdog}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-900}"

mkdir -p "$STATE_DIR"

NOW=$(date +%s)

# ──── helpers
notify() {
    local title="$1"
    local body="$2"
    local priority="${3:-default}"  # default | high | urgent
    local tag_key="$4"

    # Cooldown — don't spam same alert
    local cooldown_file="$STATE_DIR/last_${tag_key}.ts"
    if [[ -f "$cooldown_file" ]]; then
        local last=$(cat "$cooldown_file")
        if (( NOW - last < COOLDOWN_SECONDS )); then
            return 0
        fi
    fi
    echo "$NOW" > "$cooldown_file"

    curl -s -m 5 \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -H "Tags: warning,tpix" \
        -d "$body" \
        "$NTFY_SERVER/$NTFY_TOPIC" > /dev/null || true
}

clear_alert() {
    rm -f "$STATE_DIR/last_$1.ts"
}

rpc_call() {
    local method="$1"
    local params="${2:-[]}"
    curl -s -m 5 -X POST -H 'Content-Type: application/json' \
         -H 'User-Agent: tpix-watchdog/1.0' \
         --data "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
         "$RPC_URL" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null
}

# ──── 1. RPC reachable?
RESPONSE=$(rpc_call "eth_blockNumber" || echo "")
if [[ -z "$RESPONSE" ]]; then
    notify "🚨 TPIX RPC down" "rpc.tpix.online not responding (eth_blockNumber timeout)" "urgent" "rpc_down"
    exit 0
else
    clear_alert "rpc_down"
fi

# ──── 2. Block height advancing?
LATEST_BLOCK=$((16#${RESPONSE:2}))
LAST_FILE="$STATE_DIR/last_block.txt"
LAST_TS_FILE="$STATE_DIR/last_block_ts.txt"

if [[ -f "$LAST_FILE" && -f "$LAST_TS_FILE" ]]; then
    LAST_BLOCK=$(cat "$LAST_FILE")
    LAST_TS=$(cat "$LAST_TS_FILE")
    if (( LATEST_BLOCK > LAST_BLOCK )); then
        echo "$LATEST_BLOCK" > "$LAST_FILE"
        echo "$NOW" > "$LAST_TS_FILE"
        clear_alert "block_stuck"
    elif (( NOW - LAST_TS > MAX_BLOCK_LAG_SECONDS )); then
        local lag=$((NOW - LAST_TS))
        notify "⚠️ TPIX block stuck" "Block #$LATEST_BLOCK has not advanced in ${lag}s (threshold ${MAX_BLOCK_LAG_SECONDS}s)" "high" "block_stuck"
    fi
else
    echo "$LATEST_BLOCK" > "$LAST_FILE"
    echo "$NOW" > "$LAST_TS_FILE"
fi

# ──── 3. Peer count (if net_peerCount exposed — geth/erigon allow it)
PEER_RESP=$(rpc_call "net_peerCount" || echo "")
if [[ -n "$PEER_RESP" && "$PEER_RESP" != "" ]]; then
    PEER_COUNT=$((16#${PEER_RESP:2}))
    if (( PEER_COUNT < MIN_PEER_COUNT )); then
        notify "⚠️ TPIX low peers" "Connected peers: $PEER_COUNT (threshold $MIN_PEER_COUNT)" "high" "low_peers"
    else
        clear_alert "low_peers"
    fi
fi

# ──── 4. SSL cert expiry (warn 30d before)
CERT_EXPIRY=$(echo | timeout 5 openssl s_client -servername rpc.tpix.online -connect rpc.tpix.online:443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")
if [[ -n "$CERT_EXPIRY" ]]; then
    EXPIRY_TS=$(date -d "$CERT_EXPIRY" +%s 2>/dev/null || echo 0)
    DAYS_LEFT=$(( (EXPIRY_TS - NOW) / 86400 ))
    if (( DAYS_LEFT < 30 && DAYS_LEFT > 0 )); then
        notify "🔐 SSL cert expiring" "rpc.tpix.online cert expires in $DAYS_LEFT days ($CERT_EXPIRY)" "default" "ssl_expiry"
    elif (( DAYS_LEFT <= 0 )); then
        notify "🚨 SSL cert EXPIRED" "rpc.tpix.online cert expired on $CERT_EXPIRY" "urgent" "ssl_expired"
    else
        clear_alert "ssl_expiry"
        clear_alert "ssl_expired"
    fi
fi

# ──── 5. Disk space — warn at 85%, urgent at 95%
DISK_USED=$(df / | tail -1 | awk '{ print $5 }' | tr -d '%')
if (( DISK_USED >= 95 )); then
    notify "🚨 TPIX server disk almost full" "/ is ${DISK_USED}% used — chain may halt!" "urgent" "disk_critical"
elif (( DISK_USED >= 85 )); then
    notify "⚠️ TPIX server disk warning" "/ is ${DISK_USED}% used" "high" "disk_warning"
else
    clear_alert "disk_critical"
    clear_alert "disk_warning"
fi

# ──── 6. fail2ban status — alert if jail dead
if command -v fail2ban-client >/dev/null; then
    if ! systemctl is-active --quiet fail2ban 2>/dev/null; then
        notify "⚠️ fail2ban down" "fail2ban service is not running on RPC server" "high" "fail2ban_down"
    else
        clear_alert "fail2ban_down"
    fi
fi

exit 0
