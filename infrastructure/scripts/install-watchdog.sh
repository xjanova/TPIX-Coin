#!/bin/bash
# ============================================================
# TPIX Chain Watchdog — Installer
#
# วาง watchdog ที่ /usr/local/sbin/, ตั้ง cron ทุก 1 นาที, ทำ log rotation
#
# Usage:
#   sudo bash infrastructure/scripts/install-watchdog.sh
#
# Idempotent — ปลอดภัยรันซ้ำได้
#
# Developed by Xman Studio
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }

if [[ $EUID -ne 0 ]]; then
    err "Must run as root (uses /usr/local/sbin/ + /etc/cron.d/)"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")"/../.. && pwd)"
SRC="$REPO_DIR/infrastructure/scripts/chain-watchdog.sh"
DST="/usr/local/sbin/tpix-chain-watchdog"
ENV_FILE="/etc/tpix-watchdog.env"
CRON_FILE="/etc/cron.d/tpix-chain-watchdog"
LOG_FILE="/var/log/tpix-watchdog.log"
LOGROTATE_FILE="/etc/logrotate.d/tpix-watchdog"

if [ ! -f "$SRC" ]; then
    err "Source not found: $SRC"
    exit 1
fi

# ─── 1. Copy script ───
log "Installing watchdog → $DST"
install -m 0755 "$SRC" "$DST"

# ─── 2. Env file (preserve existing values if present) ───
if [ ! -f "$ENV_FILE" ]; then
    log "Creating env template → $ENV_FILE"
    cat > "$ENV_FILE" <<'EOF'
# TPIX Chain Watchdog — config
# (any unset value uses script defaults)

# Path to infrastructure dir (where docker-compose.yml lives)
TPIX_INFRA_DIR=/home/admin/tpix-infrastructure

# RPC endpoint (validator-1 exposes 8545 by default)
TPIX_RPC_URL=http://127.0.0.1:8545

# Restart loop guard
TPIX_MAX_RESTART_PER_HOUR=3

# Memory warning threshold (per validator)
TPIX_MEM_WARN_PCT=85

# Dead-man-switch — register at https://healthchecks.io (free)
# Tell it "expect ping every 1 min, grace 2 min" → email/SMS/webhook on miss
# HC_PING_URL=https://hc-ping.com/<your-uuid>

# Push notifications on critical events (already used for CF auto-ban)
# NTFY_TOPIC=https://ntfy.sh/tpix-alerts-xxx
EOF
    chmod 0644 "$ENV_FILE"
else
    log "Env file exists: $ENV_FILE (preserved)"
fi

# ─── 3. Log file + perms ───
touch "$LOG_FILE"
chmod 0644 "$LOG_FILE"

# ─── 4. Cron — every 1 minute ───
log "Installing cron → $CRON_FILE"
cat > "$CRON_FILE" <<EOF
# TPIX Chain Watchdog — runs every minute
# Script writes its own log to $LOG_FILE (ดู log()
# function ใน chain-watchdog.sh) — cron ไม่ต้อง redirect
# Managed by infrastructure/scripts/install-watchdog.sh — do not edit manually
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

* * * * * root $DST
EOF
chmod 0644 "$CRON_FILE"

# ─── 5. Logrotate (keep 7 days) ───
log "Installing logrotate → $LOGROTATE_FILE"
cat > "$LOGROTATE_FILE" <<EOF
$LOG_FILE {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
chmod 0644 "$LOGROTATE_FILE"

# ─── 6. Restart cron daemon to pick up file ───
if systemctl is-active --quiet cron 2>/dev/null; then
    systemctl restart cron
    log "cron service restarted"
elif systemctl is-active --quiet crond 2>/dev/null; then
    systemctl restart crond
    log "crond service restarted"
else
    warn "Neither cron nor crond is active — please verify cron is installed"
fi

# ─── 7. Smoke test ───
log "Running first watchdog check (smoke test)..."
if "$DST"; then
    log "Smoke test passed — chain is healthy"
else
    warn "Smoke test returned non-zero. Check $LOG_FILE"
fi

echo
echo "══════════════════════════════════════════════════════════"
echo " ✅ TPIX Chain Watchdog installed"
echo "══════════════════════════════════════════════════════════"
echo
echo " Script:    $DST"
echo " Env:       $ENV_FILE"
echo " Cron:      $CRON_FILE       (every 1 min)"
echo " Log:       $LOG_FILE"
echo " Logrotate: $LOGROTATE_FILE  (7 days)"
echo
echo " Next steps:"
echo "   1. Sign up free at https://healthchecks.io"
echo "   2. Add a check (period: 1 min, grace: 2 min, name: 'TPIX chain')"
echo "   3. Copy ping URL → set HC_PING_URL in $ENV_FILE"
echo "   4. Optional: set NTFY_TOPIC for push notifications on critical events"
echo
echo " Manual test:   sudo $DST"
echo " Live tail:     tail -f $LOG_FILE"
echo " Disable:       sudo rm $CRON_FILE && sudo systemctl restart cron"
echo
