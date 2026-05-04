#!/bin/bash
# TPIX RPC Server Hardening — one-shot install
# Run as root (sudo): sudo bash harden-rpc.sh
#
# Idempotent: re-running will not break anything; will only update changed configs

set -euo pipefail

# ──── colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }

if [[ $EUID -ne 0 ]]; then
   err "This script must be run as root (use sudo)"
   exit 1
fi

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")"/../.. && pwd)"
log "Repo path: $REPO_DIR"

# ─────────────────────────────────────────────────────────────────
# 1. Install dependencies
# ─────────────────────────────────────────────────────────────────
log "[1/6] Installing fail2ban + ufw (if missing)..."
apt-get update -qq
apt-get install -y fail2ban ufw nginx >/dev/null

# ─────────────────────────────────────────────────────────────────
# 2. Add nginx rate-limit zones to nginx.conf (idempotent)
# ─────────────────────────────────────────────────────────────────
log "[2/6] Configuring nginx rate-limit zones..."
NGINX_CONF=/etc/nginx/nginx.conf
if ! grep -q "zone=rpc_per_ip" "$NGINX_CONF"; then
    # Insert just before the `include /etc/nginx/conf.d/*.conf;` line
    sed -i '/include \/etc\/nginx\/conf.d\/\*\.conf;/i \\n\t# TPIX RPC rate limiting (added by harden-rpc.sh)\n\tlimit_req_zone $binary_remote_addr zone=rpc_per_ip:10m rate=30r/s;\n\tlimit_conn_zone $binary_remote_addr zone=rpc_conn_per_ip:10m;\n' "$NGINX_CONF"
    log "  Added rate-limit zones to $NGINX_CONF"
else
    log "  Rate-limit zones already present, skipping"
fi

# ─────────────────────────────────────────────────────────────────
# 3. Install hardened nginx-rpc.conf
# ─────────────────────────────────────────────────────────────────
log "[3/6] Installing hardened nginx-rpc.conf..."
SOURCE_NGINX="$REPO_DIR/infrastructure/nginx-rpc.conf"
TARGET_NGINX=/etc/nginx/sites-available/rpc.tpix.online
TARGET_LINK=/etc/nginx/sites-enabled/rpc.tpix.online

if [[ ! -f "$SOURCE_NGINX" ]]; then
    err "Source not found: $SOURCE_NGINX"
    err "Did you 'git pull' first?"
    exit 1
fi

# Backup existing
if [[ -f "$TARGET_NGINX" ]]; then
    BAK="${TARGET_NGINX}.bak.$(date +%s)"
    cp "$TARGET_NGINX" "$BAK"
    log "  Backed up existing config → $BAK"
fi

cp "$SOURCE_NGINX" "$TARGET_NGINX"
[[ ! -L "$TARGET_LINK" ]] && ln -sf "$TARGET_NGINX" "$TARGET_LINK"

# Test before reload
if nginx -t 2>&1 | grep -q "syntax is ok"; then
    nginx -t
    systemctl reload nginx
    log "  ✓ nginx reloaded successfully"
else
    err "nginx -t FAILED — restoring backup"
    nginx -t
    if [[ -n "${BAK:-}" && -f "$BAK" ]]; then
        cp "$BAK" "$TARGET_NGINX"
        warn "  Restored backup. Manual investigation required."
    fi
    exit 1
fi

# ─────────────────────────────────────────────────────────────────
# 4. Install fail2ban filter + jail
# ─────────────────────────────────────────────────────────────────
log "[4/6] Installing fail2ban configs..."
cp "$REPO_DIR/infrastructure/fail2ban/filter.d/tpix-rpc.conf"  /etc/fail2ban/filter.d/
cp "$REPO_DIR/infrastructure/fail2ban/jail.d/tpix-rpc.conf"    /etc/fail2ban/jail.d/

systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban
sleep 2
if fail2ban-client status tpix-rpc >/dev/null 2>&1; then
    log "  ✓ fail2ban tpix-rpc jail active"
    fail2ban-client status tpix-rpc | sed 's/^/    /'
else
    warn "  fail2ban tpix-rpc not yet active (might need a few seconds)"
fi

# ─────────────────────────────────────────────────────────────────
# 5. Configure UFW firewall
# ─────────────────────────────────────────────────────────────────
log "[5/6] Configuring UFW firewall..."
ufw --force default deny incoming >/dev/null
ufw --force default allow outgoing >/dev/null
ufw allow 22/tcp comment 'SSH' >/dev/null
ufw allow 80/tcp comment 'HTTP for nginx' >/dev/null
ufw allow 443/tcp comment 'HTTPS' >/dev/null
# TPIX validator P2P ports — open to internal cluster only via Docker network
# (Docker handles its own iptables; UFW won't block Docker bridges)
ufw --force enable >/dev/null
log "  ✓ UFW enabled — only 22/80/443 allowed from public"
ufw status numbered | head -20 | sed 's/^/    /'

# ─────────────────────────────────────────────────────────────────
# 6. Quick verification
# ─────────────────────────────────────────────────────────────────
log "[6/6] Verification..."
echo
echo "── Active nginx config ──"
nginx -T 2>/dev/null | grep -A2 "server_name rpc.tpix.online" | head -10 | sed 's/^/    /'
echo
echo "── fail2ban jails ──"
fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/^/    /'
echo
echo "── UFW status ──"
ufw status verbose 2>/dev/null | head -15 | sed 's/^/    /'
echo

# ─────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────
echo
log "════════════════════════════════════════════════════════════"
log "  ✅ Phase 2 RPC hardening complete!"
log "════════════════════════════════════════════════════════════"
echo
echo "Next:"
echo "  • Run a smoke test:"
echo "      curl -s -X POST -H 'Content-Type: application/json' \\"
echo "           --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' \\"
echo "           https://rpc.tpix.online"
echo "  • Watch fail2ban bans (live):"
echo "      sudo tail -f /var/log/fail2ban.log"
echo "  • Watch nginx access for 403/429:"
echo "      sudo tail -f /var/log/nginx/access.log | grep -E '\" (403|429) '"
echo
