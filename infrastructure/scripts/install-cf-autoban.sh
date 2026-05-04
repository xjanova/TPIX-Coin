#!/bin/bash
# Install Cloudflare auto-ban: fail2ban → CF API → IP list → WAF rule
#
# Pre-requisites:
#   You need a Cloudflare API token with these permissions:
#     - Account: Account Filter Lists: Edit (Read)
#     - Account: Workers Scripts: Read (just so token can list account)
#     - Zone: Firewall Services: Edit (for tpix.online)
#   Generate at: https://dash.cloudflare.com/profile/api-tokens
#
# Usage:
#   sudo CF_API_TOKEN=... bash install-cf-autoban.sh
#
# What it does:
#   1. Auto-discover CF account ID from token
#   2. Create IP list "tpix-auto-banned" via API (idempotent — reuses if exists)
#   3. Create WAF custom rule that blocks IPs in the list (idempotent)
#   4. Save CF_API_TOKEN, CF_ACCOUNT_ID, CF_LIST_ID, CF_ZONE_ID to /etc/tpix-watchdog.env
#   5. Install /usr/local/sbin/cf-ban-ip
#   6. Install fail2ban action.d/cloudflare-tpix.conf
#   7. Update jail.d/tpix-rpc.conf to use the new action (in addition to iptables)
#   8. Reload fail2ban
#   9. Add daily cron to prune bans older than 30 days

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }

if [[ $EUID -ne 0 ]]; then err "Run as root"; exit 1; fi
if [[ -z "${CF_API_TOKEN:-}" ]]; then
    err "CF_API_TOKEN env var required. Generate at https://dash.cloudflare.com/profile/api-tokens"
    err "Required perms: Account/Account Filter Lists:Edit + Zone/Firewall Services:Edit (tpix.online)"
    exit 1
fi

ZONE_NAME="${ZONE_NAME:-tpix.online}"
LIST_NAME="${LIST_NAME:-tpix_auto_banned}"

cf() {
    curl -s -m 10 -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" "$@"
}

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")"/../.. && pwd)"

# ─── 1. Discover account ID
log "[1/9] Discovering Cloudflare account..."
if [[ -n "${CF_ACCOUNT_ID:-}" ]]; then
    log "  Using preset CF_ACCOUNT_ID: $CF_ACCOUNT_ID"
    ACCOUNT_ID="$CF_ACCOUNT_ID"
else
    ACCOUNT_ID=$(cf "https://api.cloudflare.com/client/v4/accounts?per_page=1" \
        | python3 -c "
import sys,json
try:
    d = json.load(sys.stdin)
    r = d.get('result') or []
    if r:
        print(r[0]['id'])
    else:
        print('')
except Exception:
    print('')
")
    if [[ -z "$ACCOUNT_ID" ]]; then
        err "Token cannot list accounts — set CF_ACCOUNT_ID env var manually"
        err "  Find your account ID at https://dash.cloudflare.com (URL pattern: /<ACCOUNT_ID>/...)"
        err "  Then re-run: sudo CF_API_TOKEN=... CF_ACCOUNT_ID=... bash $0"
        exit 1
    fi
    log "  Discovered account: $ACCOUNT_ID"
fi

# Zone ID for tpix.online
ZONE_ID=$(cf "https://api.cloudflare.com/client/v4/zones?name=$ZONE_NAME" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['result'][0]['id'])")
log "  Zone $ZONE_NAME: $ZONE_ID"

# ─── 2. Create or find IP list
log "[2/9] Creating IP list '$LIST_NAME'..."
LISTS_RESP=$(cf "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/rules/lists")
LIST_ID=$(echo "$LISTS_RESP" | python3 -c "
import sys,json
d = json.load(sys.stdin)
for l in d.get('result', []):
    if l['name'] == '$LIST_NAME':
        print(l['id']); break
")

if [[ -z "$LIST_ID" ]]; then
    LIST_ID=$(cf -X POST "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/rules/lists" \
        --data "{\"name\":\"$LIST_NAME\",\"kind\":\"ip\",\"description\":\"TPIX fail2ban auto-banned IPs (managed by /usr/local/sbin/cf-ban-ip)\"}" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['id'])")
    log "  Created list: $LIST_ID"
else
    log "  Existing list found: $LIST_ID"
fi

# ─── 3. Create or update WAF rule
log "[3/9] Ensuring WAF rule references list..."
RULES=$(cf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/phases/http_request_firewall_custom/entrypoint")
RULESET_ID=$(echo "$RULES" | python3 -c "
import sys,json
try:
    print(json.load(sys.stdin)['result']['id'])
except Exception:
    pass
")

EXPR="(ip.src in \$$LIST_NAME)"

if [[ -z "$RULESET_ID" ]]; then
    # Create entrypoint ruleset with our rule
    cf -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/phases/http_request_firewall_custom/entrypoint" \
        --data "{\"rules\":[{\"action\":\"block\",\"expression\":\"$EXPR\",\"description\":\"Auto-ban from fail2ban\",\"enabled\":true}]}" \
        > /dev/null
    log "  Created entrypoint with auto-ban rule"
else
    # Check if rule exists
    HAS_RULE=$(echo "$RULES" | python3 -c "
import sys,json
d = json.load(sys.stdin)
rules = d.get('result',{}).get('rules', []) or []
for r in rules:
    if 'tpix_auto_banned' in r.get('expression', ''):
        print('yes'); break
")
    if [[ "$HAS_RULE" != "yes" ]]; then
        # Append rule
        cf -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/$RULESET_ID/rules" \
            --data "{\"action\":\"block\",\"expression\":\"$EXPR\",\"description\":\"Auto-ban from fail2ban\",\"enabled\":true}" \
            > /dev/null
        log "  Added auto-ban rule to ruleset"
    else
        log "  Auto-ban rule already exists"
    fi
fi

# ─── 4. Save env
ENV_FILE=/etc/tpix-watchdog.env
log "[4/9] Saving credentials to $ENV_FILE..."
# Remove any existing CF_* lines, then append fresh
sed -i '/^CF_API_TOKEN=/d; /^CF_ACCOUNT_ID=/d; /^CF_LIST_ID=/d; /^CF_ZONE_ID=/d' "$ENV_FILE" 2>/dev/null || true
cat >> "$ENV_FILE" <<EOF
# Cloudflare auto-ban — added $(date -u +%Y-%m-%dT%H:%M:%SZ)
CF_API_TOKEN=$CF_API_TOKEN
CF_ACCOUNT_ID=$ACCOUNT_ID
CF_LIST_ID=$LIST_ID
CF_ZONE_ID=$ZONE_ID
EOF
chmod 600 "$ENV_FILE"

# ─── 5. Install cf-ban-ip
log "[5/9] Installing /usr/local/sbin/cf-ban-ip..."
install -m 0750 -o root -g root "$REPO_DIR/infrastructure/scripts/cf-ban-ip.sh" /usr/local/sbin/cf-ban-ip

# ─── 6. Install fail2ban action
log "[6/9] Installing fail2ban action..."
install -m 0644 -o root -g root "$REPO_DIR/infrastructure/fail2ban/action.d/cloudflare-tpix.conf" /etc/fail2ban/action.d/

# ─── 7. Update jail to use action (idempotent)
log "[7/9] Updating fail2ban jail to push to Cloudflare..."
JAIL=/etc/fail2ban/jail.d/tpix-rpc.conf
if [[ -f "$JAIL" ]] && ! grep -q "cloudflare-tpix" "$JAIL"; then
    # Append cloudflare action to existing action lines (or add new banaction)
    cat >> "$JAIL" <<'EOF'

# ── Cloudflare auto-ban (added by install-cf-autoban.sh)
[apache-overflows]
action = iptables-multiport[name=apache-overflows, port="http,https", protocol=tcp]
         cloudflare-tpix[name=apache-overflows]

[apache-noscript]
action = iptables-multiport[name=apache-noscript, port="http,https", protocol=tcp]
         cloudflare-tpix[name=apache-noscript]

[apache-auth]
action = iptables-multiport[name=apache-auth, port="http,https", protocol=tcp]
         cloudflare-tpix[name=apache-auth]
EOF
    log "  Appended Cloudflare actions to jail"
fi

# ─── 8. Reload fail2ban
log "[8/9] Reloading fail2ban..."
fail2ban-client reload 2>&1 | tail -5 || systemctl restart fail2ban

# ─── 9. Daily prune cron
log "[9/9] Adding daily prune cron..."
PRUNE_CRON=/etc/cron.d/tpix-cf-autoban-prune
cat > "$PRUNE_CRON" <<'EOF'
# Prune CF auto-bans older than 30 days, run 03:30 daily
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
30 3 * * * root /usr/local/sbin/cf-ban-ip prune 30 >>/var/log/cf-ban.log 2>&1
EOF
chmod 644 "$PRUNE_CRON"

# ─── Smoke test: list (should be empty initially or just show seed entries)
log "Sanity check — current banned IPs in CF list:"
/usr/local/sbin/cf-ban-ip list 2>&1 | head -10 || warn "list failed (check perms)"

# ─── Done
echo
log "════════════════════════════════════════════════════════════"
log "  ✅ Cloudflare auto-ban installed!"
log "════════════════════════════════════════════════════════════"
echo
echo "Manual ops:"
echo "  Ban an IP now:"
echo "    sudo /usr/local/sbin/cf-ban-ip add 1.2.3.4 'manual ban'"
echo "  Unban:"
echo "    sudo /usr/local/sbin/cf-ban-ip remove 1.2.3.4"
echo "  See current bans:"
echo "    sudo /usr/local/sbin/cf-ban-ip list"
echo "  Force prune now (older than 30d):"
echo "    sudo /usr/local/sbin/cf-ban-ip prune 30"
echo
echo "Watch log:"
echo "    sudo tail -f /var/log/cf-ban.log"
echo
echo "From now on: any IP that fail2ban catches → blocked at Cloudflare edge"
echo "(in addition to iptables on this server)."
echo
