#!/bin/bash
# TPIX Daily Security Report — Apache log analyzer + fail2ban summary
# Cron entry (run at 00:05 every day):
#   5 0 * * * /home/admin/TPIX-Coin/infrastructure/monitoring/daily-security-report.sh
#
# Sends ntfy.sh summary to NTFY_TOPIC from /etc/tpix-watchdog.env

set -euo pipefail

ENV_FILE=/etc/tpix-watchdog.env
[[ -r "$ENV_FILE" ]] && source "$ENV_FILE"

NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
NTFY_TOPIC="${NTFY_TOPIC:-tpix-alerts-CHANGE-ME}"

YESTERDAY=$(date -d "yesterday" +%d/%b/%Y)
TODAY=$(date +%Y-%m-%d)
APACHE_LOG="${APACHE_LOG:-/var/log/httpd/access_log}"
[[ -r "$APACHE_LOG" ]] || APACHE_LOG=/var/log/apache2/access.log
[[ -r "$APACHE_LOG" ]] || { echo "No readable Apache log"; exit 1; }

# ─ Aggregate yesterday's stats
TOTAL_REQ=$(grep "$YESTERDAY" "$APACHE_LOG" 2>/dev/null | wc -l)
BLOCKED_403=$(grep "$YESTERDAY" "$APACHE_LOG" 2>/dev/null | awk '{print $9}' | grep -c "^403" || echo 0)
RATE_LIMITED=$(grep "$YESTERDAY" "$APACHE_LOG" 2>/dev/null | awk '{print $9}' | grep -c "^429" || echo 0)
ERRORS_5XX=$(grep "$YESTERDAY" "$APACHE_LOG" 2>/dev/null | awk '{print $9}' | grep -cE "^5[0-9][0-9]" || echo 0)

# Top 5 abuser IPs (got 403/429)
TOP_IPS=$(grep "$YESTERDAY" "$APACHE_LOG" 2>/dev/null \
    | awk '$9=="403" || $9=="429" { print $1 }' \
    | sort | uniq -c | sort -rn | head -5)

# Top 5 RPC POST source IPs
TOP_RPC_IPS=$(grep "$YESTERDAY" "$APACHE_LOG" 2>/dev/null \
    | grep "rpc.tpix.online" \
    | awk '{ print $1 }' \
    | sort | uniq -c | sort -rn | head -5)

# fail2ban status
F2B=""
if command -v fail2ban-client >/dev/null 2>&1; then
    F2B=$(sudo fail2ban-client status 2>/dev/null \
        | grep "Banned IP" \
        | head -10)
    BANNED_TODAY=$(sudo fail2ban-client status apache-overflows 2>/dev/null \
        | grep "Total banned" | awk '{print $NF}' || echo "?")
fi

# Disk + load
DISK=$(df -h / | tail -1 | awk '{print $5 " of " $2}')
LOAD=$(uptime | awk -F'load average: ' '{print $2}')

# Blockchain — latest block + connected peers
BLOCK_HEX=$(curl -s -m 5 -X POST -H 'Content-Type: application/json' \
    -H 'User-Agent: daily-report/1.0' \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    "${RPC_URL:-https://rpc.tpix.online}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('result',''))" 2>/dev/null || echo "")
BLOCK=$([[ -n "$BLOCK_HEX" ]] && echo $((16#${BLOCK_HEX:2})) || echo "?")

# Build report
REPORT=$(cat <<EOF
TPIX Daily Report — $TODAY (covering $YESTERDAY)

📊 HTTP traffic (yesterday)
  Total: $TOTAL_REQ requests
  403 blocked: $BLOCKED_403
  429 rate-limited: $RATE_LIMITED
  5xx errors: $ERRORS_5XX

🚫 Top abusive IPs (403/429)
$(echo "$TOP_IPS" | sed 's/^/  /')

🌐 Top RPC source IPs
$(echo "$TOP_RPC_IPS" | sed 's/^/  /')

🛡️ fail2ban
  Total bans (apache-overflows): $BANNED_TODAY
$(echo "$F2B" | sed 's/^/  /')

💻 System health
  Disk: $DISK
  Load: $LOAD
  Block height: $BLOCK
EOF
)

echo "$REPORT"

# Send to ntfy
curl -s -m 10 \
    -H "Title: TPIX Daily Report — $TODAY" \
    -H "Priority: low" \
    -H "Tags: chart_with_upwards_trend,tpix" \
    -d "$REPORT" \
    "$NTFY_SERVER/$NTFY_TOPIC" > /dev/null

# Also save to disk for archival
LOG_DIR="${LOG_DIR:-/var/log/tpix-reports}"
mkdir -p "$LOG_DIR"
echo "$REPORT" > "$LOG_DIR/$TODAY.txt"

exit 0
