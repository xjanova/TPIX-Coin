#!/bin/bash
# TPIX RPC Server Hardening — DirectAdmin / Apache edition
# For Ubuntu 22.04 server with DirectAdmin web panel + Apache backend
#
# Run on server (requires sudo password once):
#   cd ~/TPIX-Coin
#   git pull
#   sudo bash infrastructure/scripts/harden-rpc-directadmin.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }

if [[ $EUID -ne 0 ]]; then
   err "Run as root (sudo)"
   exit 1
fi

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")"/../.. && pwd)"
log "Repo: $REPO_DIR"

# ──── 1. Install fail2ban + UFW + mod_evasive
log "[1/5] Installing fail2ban + ufw + libapache2-mod-evasive..."
apt-get update -qq
apt-get install -y fail2ban ufw libapache2-mod-evasive >/dev/null 2>&1 || \
    apt-get install -y fail2ban ufw apache2-utils >/dev/null

# DirectAdmin uses CustomBuild — Apache is /etc/httpd not /etc/apache2 typically
# Check which layout
if [[ -d /etc/httpd ]]; then
    APACHE_CONF_D=/etc/httpd/conf/extra
    APACHE_LOG=/var/log/httpd/access_log
    APACHE_SVC=httpd
elif [[ -d /etc/apache2 ]]; then
    APACHE_CONF_D=/etc/apache2/conf-available
    APACHE_LOG=/var/log/apache2/access.log
    APACHE_SVC=apache2
else
    err "No Apache config dir found"
    exit 1
fi
log "  Apache layout: $APACHE_CONF_D (service: $APACHE_SVC)"

# ──── 2. Install rpc-hardening.conf for rpc.tpix.online vhost
log "[2/5] Installing Apache rpc-hardening.conf..."
SRC="$REPO_DIR/infrastructure/apache/rpc-hardening.conf"
mkdir -p /etc/httpd/conf.d 2>/dev/null || true

# DirectAdmin per-domain CUSTOM token — preferred path
DA_CUST="/usr/local/directadmin/data/users/admin/domains/rpc.tpix.online.cust_httpd"
if [[ -d "$(dirname "$DA_CUST")" ]]; then
    cp "$SRC" "$DA_CUST"
    log "  Installed via DirectAdmin custom: $DA_CUST"
    log "  Rebuilding vhost configs..."
    cd /usr/local/directadmin/custombuild 2>/dev/null && ./build rewrite_confs >/dev/null 2>&1 || true
else
    # Fallback: drop into Apache extra/conf.d
    cp "$SRC" "$APACHE_CONF_D/tpix-rpc-hardening.conf"
    log "  Installed: $APACHE_CONF_D/tpix-rpc-hardening.conf"
fi

# ──── 3. Apache test + reload
log "[3/5] Testing Apache config..."
if command -v apachectl >/dev/null; then
    if apachectl -t 2>&1 | grep -qE "Syntax OK|^$"; then
        log "  ✓ Apache config OK"
        systemctl reload "$APACHE_SVC"
        log "  ✓ Apache reloaded"
    else
        err "Apache config FAILED — please check"
        apachectl -t
        exit 1
    fi
fi

# ──── 4. fail2ban for Apache
log "[4/5] Installing fail2ban Apache filter..."
cat > /etc/fail2ban/jail.d/tpix-apache.conf <<EOF
[apache-auth]
enabled = true
port    = http,https
logpath = $APACHE_LOG
maxretry = 5
bantime  = 3600

[apache-noscript]
enabled = true
port    = http,https
logpath = $APACHE_LOG
maxretry = 5
bantime  = 3600

[apache-overflows]
enabled = true
port    = http,https
logpath = $APACHE_LOG
maxretry = 2
bantime  = 7200
EOF

systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban
sleep 1
fail2ban-client status 2>/dev/null | head -5

# ──── 5. UFW firewall
log "[5/5] Configuring UFW..."
ufw --force default deny incoming >/dev/null
ufw --force default allow outgoing >/dev/null
ufw allow 22/tcp comment 'SSH' >/dev/null
ufw allow 80/tcp comment 'HTTP' >/dev/null
ufw allow 443/tcp comment 'HTTPS' >/dev/null
# DirectAdmin panel
ufw allow 2222/tcp comment 'DirectAdmin' >/dev/null
# Mail
ufw allow 25,143,587,993,995/tcp comment 'Mail' >/dev/null
ufw --force enable >/dev/null
log "  ✓ UFW enabled"
ufw status verbose | head -25

# ──── Done
echo
log "════════════════════════════════════════════════════════════"
log "  ✅ Phase 2 RPC hardening (DirectAdmin/Apache) complete!"
log "════════════════════════════════════════════════════════════"
echo
echo "Next steps:"
echo "  • Smoke test:"
echo "      curl -s -X POST -H 'Content-Type: application/json' \\"
echo "           --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' \\"
echo "           https://rpc.tpix.online"
echo "  • Watch fail2ban (live):"
echo "      sudo tail -f /var/log/fail2ban.log"
echo "  • Watch Apache 403/429:"
echo "      sudo tail -f $APACHE_LOG | grep -E ' (403|429) '"
echo
