#!/bin/bash
# Install TPIX monitoring (chain-watchdog + daily-security-report)
# Run as root on the RPC server:
#   cd ~/TPIX-Coin && git pull
#   sudo bash infrastructure/monitoring/install-monitoring.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then
   echo "Run as root (sudo)"
   exit 1
fi

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")"/../.. && pwd)"
log "Repo: $REPO_DIR"

# ─── 1. Pick or generate ntfy topic
ENV_FILE=/etc/tpix-watchdog.env
if [[ -r "$ENV_FILE" ]] && grep -q "^NTFY_TOPIC=" "$ENV_FILE"; then
    log "Existing $ENV_FILE found — keeping current NTFY_TOPIC"
else
    TOPIC="tpix-alerts-$(openssl rand -hex 8)"
    cat > "$ENV_FILE" <<EOF
# TPIX watchdog env — auto-generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
RPC_URL=https://rpc.tpix.online
NTFY_TOPIC=$TOPIC
NTFY_SERVER=https://ntfy.sh
MAX_BLOCK_LAG_SECONDS=120
MIN_PEER_COUNT=2
STATE_DIR=/var/lib/tpix-watchdog
COOLDOWN_SECONDS=900
APACHE_LOG=/var/log/httpd/access_log
LOG_DIR=/var/log/tpix-reports
EOF
    chmod 600 "$ENV_FILE"
    log "Created $ENV_FILE with topic: $TOPIC"
    echo
    echo "📲 Subscribe on your phone:"
    echo "    1. Install ntfy from App Store / Play Store"
    echo "    2. Add subscription → server: ntfy.sh, topic: $TOPIC"
    echo "    3. (Or open in browser: https://ntfy.sh/$TOPIC)"
    echo
fi

# ─── 2. State + log dirs
mkdir -p /var/lib/tpix-watchdog /var/log/tpix-reports
chmod 750 /var/lib/tpix-watchdog /var/log/tpix-reports

# ─── 3. Install scripts
install -m 0750 -o root -g root "$REPO_DIR/infrastructure/monitoring/chain-watchdog.sh"        /usr/local/sbin/tpix-chain-watchdog
install -m 0750 -o root -g root "$REPO_DIR/infrastructure/monitoring/daily-security-report.sh" /usr/local/sbin/tpix-daily-report
log "Installed:"
log "  /usr/local/sbin/tpix-chain-watchdog"
log "  /usr/local/sbin/tpix-daily-report"

# ─── 4. Cron entries (idempotent)
CRONFILE=/etc/cron.d/tpix-monitoring
cat > "$CRONFILE" <<'EOF'
# TPIX monitoring — installed by install-monitoring.sh
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Run watchdog every minute
*/1 * * * * root /usr/local/sbin/tpix-chain-watchdog 2>>/var/log/tpix-watchdog.err

# Daily report at 00:05
5 0 * * * root /usr/local/sbin/tpix-daily-report 2>>/var/log/tpix-watchdog.err
EOF
chmod 644 "$CRONFILE"
log "Installed cron at $CRONFILE"

# ─── 5. Test ntfy reachability (sends a startup notification)
if [[ -r "$ENV_FILE" ]]; then
    source "$ENV_FILE"
    curl -s -m 5 \
        -H "Title: ✅ TPIX monitoring installed" \
        -H "Priority: default" \
        -H "Tags: white_check_mark,tpix" \
        -d "Watchdog active. You should see daily reports at 00:05 + alerts on incidents." \
        "$NTFY_SERVER/$NTFY_TOPIC" > /dev/null && log "Sent test notification to ntfy"
fi

# ─── 6. Run watchdog once now to seed state
/usr/local/sbin/tpix-chain-watchdog || warn "First run had issues (state may be empty — normal on first boot)"

echo
log "════════════════════════════════════════════════════"
log "  ✅ TPIX monitoring installed!"
log "════════════════════════════════════════════════════"
echo
echo "Verify cron is loaded:"
echo "  sudo systemctl reload cron && sudo grep CRON /var/log/syslog | tail"
echo
echo "Watch logs:"
echo "  sudo tail -f /var/log/tpix-watchdog.err"
echo
echo "Force a daily report now:"
echo "  sudo /usr/local/sbin/tpix-daily-report"
echo
echo "View today's saved report:"
echo "  cat /var/log/tpix-reports/$(date +%Y-%m-%d).txt"
echo
