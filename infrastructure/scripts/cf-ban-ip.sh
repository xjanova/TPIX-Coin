#!/bin/bash
# cf-ban-ip — add or remove an IP from the Cloudflare auto-ban list
# Used by fail2ban action + manual ops.
#
# Usage:
#   cf-ban-ip add <ip> [comment]
#   cf-ban-ip remove <ip>
#   cf-ban-ip list                       # show current bans
#   cf-ban-ip prune <days>               # remove bans older than N days
#
# Reads /etc/tpix-watchdog.env for CF_API_TOKEN, CF_ACCOUNT_ID, CF_LIST_ID

set -euo pipefail

ENV_FILE=/etc/tpix-watchdog.env
[[ -r "$ENV_FILE" ]] && source "$ENV_FILE"

: "${CF_API_TOKEN:?CF_API_TOKEN not set in $ENV_FILE}"
: "${CF_ACCOUNT_ID:?CF_ACCOUNT_ID not set}"
: "${CF_LIST_ID:?CF_LIST_ID not set}"

API="https://api.cloudflare.com/client/v4"
LOG=/var/log/cf-ban.log

log() { echo "$(date -u +%FT%TZ) $*" | tee -a "$LOG" >&2; }

cf() {
    curl -s -m 10 \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        "$@"
}

cmd="${1:-}"
shift || true

case "$cmd" in
    add)
        IP="${1:?IP required}"
        COMMENT="${2:-fail2ban auto-ban}"

        # Cloudflare lists API requires items as array
        RESP=$(cf -X POST "$API/accounts/$CF_ACCOUNT_ID/rules/lists/$CF_LIST_ID/items" \
            --data "[{\"ip\":\"$IP\",\"comment\":\"$COMMENT\"}]")

        if echo "$RESP" | grep -qE '"success":\s*true'; then
            log "BANNED $IP via CF list ($COMMENT)"
        else
            log "FAIL ban $IP — response: $(echo "$RESP" | head -c 300)"
            exit 1
        fi
        ;;

    remove)
        IP="${1:?IP required}"

        # Find item ID for this IP
        ITEM_ID=$(cf -X GET "$API/accounts/$CF_ACCOUNT_ID/rules/lists/$CF_LIST_ID/items?per_page=10000" \
            | python3 -c "
import sys,json
d = json.load(sys.stdin)
for it in d.get('result', []):
    if it.get('ip') == '$IP' or it.get('ip') == '$IP/32':
        print(it.get('id', '')); break
")

        if [[ -z "$ITEM_ID" ]]; then
            log "SKIP unban $IP — not in CF list"
            exit 0
        fi

        RESP=$(cf -X DELETE "$API/accounts/$CF_ACCOUNT_ID/rules/lists/$CF_LIST_ID/items" \
            --data "{\"items\":[{\"id\":\"$ITEM_ID\"}]}")

        if echo "$RESP" | grep -qE '"success":\s*true'; then
            log "UNBANNED $IP from CF list"
        else
            log "FAIL unban $IP — $(echo "$RESP" | head -c 300)"
            exit 1
        fi
        ;;

    list)
        cf -X GET "$API/accounts/$CF_ACCOUNT_ID/rules/lists/$CF_LIST_ID/items?per_page=200" \
            | python3 -c "
import sys,json,datetime
d = json.load(sys.stdin)
items = d.get('result', [])
print(f'{len(items)} banned IPs:')
print(f'{\"IP\":40} {\"banned at\":25} comment')
print('-' * 100)
for it in items:
    ts = it.get('created_on', '')[:19]
    ip = it.get('ip', '?')
    cm = it.get('comment', '')
    print(f'{ip:40} {ts:25} {cm[:60]}')
"
        ;;

    prune)
        DAYS="${1:-30}"
        cutoff=$(date -u -d "$DAYS days ago" +%s)
        log "Pruning IPs banned more than $DAYS days ago…"

        # Fetch and filter
        ids=$(cf -X GET "$API/accounts/$CF_ACCOUNT_ID/rules/lists/$CF_LIST_ID/items?per_page=10000" \
            | python3 -c "
import sys,json,datetime
d = json.load(sys.stdin)
cutoff = $cutoff
ids = []
for it in d.get('result', []):
    try:
        ts = datetime.datetime.fromisoformat(it['created_on'].replace('Z','+00:00')).timestamp()
        if ts < cutoff:
            ids.append(it['id'])
    except Exception:
        pass
print(','.join(ids))
")

        if [[ -z "$ids" ]]; then
            log "Nothing to prune"
            exit 0
        fi

        # Build payload
        items=$(echo "$ids" | tr ',' '\n' | awk 'NF{print "{\"id\":\"" $1 "\"}"}' | paste -sd,)
        RESP=$(cf -X DELETE "$API/accounts/$CF_ACCOUNT_ID/rules/lists/$CF_LIST_ID/items" \
            --data "{\"items\":[$items]}")

        if echo "$RESP" | grep -qE '"success":\s*true'; then
            count=$(echo "$ids" | tr ',' '\n' | wc -l)
            log "Pruned $count old bans"
        else
            log "FAIL prune — $(echo "$RESP" | head -c 300)"
            exit 1
        fi
        ;;

    *)
        echo "Usage: $0 {add <ip> [comment] | remove <ip> | list | prune <days>}" >&2
        exit 1
        ;;
esac
