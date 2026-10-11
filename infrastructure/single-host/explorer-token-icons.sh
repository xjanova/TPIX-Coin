#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
#  explorer-token-icons.sh — ให้ explorer.tpix.online แสดงโลโก้เหรียญ
# ═══════════════════════════════════════════════════════════════════════════
#
# ดึง Token List สาธารณะของ tpix.online (มาตรฐาน Uniswap Token List — มีเฉพาะเหรียญที่
# แอดมินอนุมัติแล้ว) แล้วส่งโลโก้เข้า Blockscout ผ่าน /api/v2/import/token-info
# ที่รันอยู่บนเครื่องเดียวกัน (127.0.0.1:4000)
#
# ทำไมเป็นแบบ "ดึง" ไม่ใช่ให้เว็บ "ส่ง": คีย์ API_SENSITIVE_ENDPOINTS_KEY ไม่ต้องออกจากเครื่องนี้เลย
# เว็บแค่เผยแพร่รายการสาธารณะ ส่วนเครื่องนี้อ่านคีย์จาก /opt/tpix/.env เอง
#
# ส่งเฉพาะตัวที่โลโก้เปลี่ยน · ใช้ชื่อ/สัญลักษณ์ที่ explorer มีอยู่แล้ว (endpoint บังคับส่ง
# tokenName/tokenSymbol — ส่งค่าเดิมกลับไปจึงไม่เปลี่ยนชื่อเหรียญ) · เหรียญที่ explorer
# ยังไม่ index จะข้ามไปก่อน รอบถัดไปค่อยลองใหม่
#
# ติดตั้ง (root):
#   install -m 700 explorer-token-icons.sh /opt/tpix/bin/explorer-token-icons.sh
#   echo '*/5 * * * * root /opt/tpix/bin/explorer-token-icons.sh >> /var/log/tpix-explorer-icons.log 2>&1' > /etc/cron.d/tpix-explorer-icons
#
# Developed by Xman Studio

set -euo pipefail

LIST_URL="${LIST_URL:-https://tpix.online/tokenlist.json}"
BS_API="${BS_API:-http://127.0.0.1:4000}"
ENV_FILE="${ENV_FILE:-/opt/tpix/.env}"
CHAIN_ID=4289

log() { echo "$(date -u +%FT%TZ) $*"; }

KEY="$(set -a; . "$ENV_FILE"; printf %s "${BS_SENSITIVE_KEY:-}")"
if [ -z "$KEY" ]; then log "BS_SENSITIVE_KEY ไม่มีใน $ENV_FILE — ข้าม"; exit 1; fi

list="$(curl -fsS --max-time 20 -A 'tpix-explorer-icons/1.0' "$LIST_URL")" || { log "ดึง $LIST_URL ไม่ได้"; exit 0; }

jq -e '.tokens | type == "array"' >/dev/null <<<"$list" || { log "รูปแบบ token list ไม่ถูกต้อง"; exit 0; }

changed=0
while IFS= read -r t; do
    addr="$(jq -r '.address' <<<"$t")"
    logo="$(jq -r '.logoURI' <<<"$t")"
    [[ "$addr" =~ ^0x[0-9a-fA-F]{40}$ ]] || continue
    [[ "$logo" =~ ^https://[^[:space:]\"\'\<\>]{4,500}$ ]] || continue

    cur="$(curl -fsS --max-time 10 "$BS_API/api/v2/tokens/$addr" 2>/dev/null)" || continue   # ยังไม่ index
    [ "$(jq -r '.icon_url // ""' <<<"$cur")" = "$logo" ] && continue

    name="$(jq -r '.name // ""' <<<"$cur")"
    sym="$(jq -r '.symbol // ""' <<<"$cur")"
    if [ -z "$name" ] || [ -z "$sym" ]; then log "$addr ยังไม่มีชื่อ/สัญลักษณ์ใน explorer — ข้าม"; continue; fi

    # คีย์ส่งทาง stdin ไม่อยู่ใน argv (ไม่โผล่ใน ps)
    code="$(jq -n --arg k "$KEY" --arg i "$logo" --arg a "$addr" --arg n "$name" --arg s "$sym" --arg c "$CHAIN_ID" \
        '{api_key:$k, iconUrl:$i, tokenAddress:$a, chainId:$c, tokenName:$n, tokenSymbol:$s}' \
        | curl -s -o /dev/null -w '%{http_code}' --max-time 15 -X POST "$BS_API/api/v2/import/token-info" \
            -H 'content-type: application/json' --data-binary @-)"
    log "$sym $addr โลโก้ → $logo (HTTP $code)"
    [ "$code" = "200" ] && changed=$((changed + 1))
done < <(jq -c --argjson c "$CHAIN_ID" '.tokens[] | select(.chainId == $c and ((.logoURI // "") | startswith("https://")))' <<<"$list")

[ "$changed" -gt 0 ] && log "อัปเดตโลโก้ $changed เหรียญ"
exit 0
