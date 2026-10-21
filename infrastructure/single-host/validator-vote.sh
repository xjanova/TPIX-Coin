#!/bin/bash
# ============================================================
# validator-vote.sh — โหวตเพิ่ม/ถอด validator ของเชน TPIX (polygon-edge 0.9, IBFT PoA, bls)
#
# รันบนเครื่องเชน (123.253.62.252) ที่ validator ทั้งหมดเป็นคอนเทนเนอร์อยู่ในเครื่องเดียว
# ช่อง gRPC (สั่งโหวตได้) เปิดเฉพาะ 127.0.0.1 ในคอนเทนเนอร์ — เว็บสั่งเองไม่ได้โดยตั้งใจ
#
# Usage (as root):
#   sudo bash validator-vote.sh auth --addr 0x… --bls 0x… [--node-id 16Uiu2…] [--yes]
#   sudo bash validator-vote.sh drop --addr 0x… [--yes]
#   sudo bash validator-vote.sh status
#
#   ค่าเริ่มต้นคือ "ซ้อม" — ตรวจทุกอย่างแล้วพิมพ์สิ่งที่จะทำ ไม่ส่งอะไร
#   ใส่ --yes ถึงจะโหวตจริง
#
# ยืนยันธงกับเครื่องจริงแล้ว (2026-10-22, `polygon-edge ibft propose --help`):
#   --addr · --bls (ต้องมีตอน auth เพราะ genesis เป็น validator_type: bls) · --vote auth|drop
#   ค่าเริ่มต้นของ --grpc-address คือ 127.0.0.1:9632 ซึ่งผิด → ต้องระบุ 127.0.0.1:10000 เสมอ
#
# กติกา polygon-edge ที่สคริปต์นี้อิง:
#   - ผ่านเมื่อได้เสียง > ครึ่งของชุดปัจจุบัน — แต่ละ validator ใส่เสียงของตัวเองลงบล็อก
#     ตอนที่ได้คิวเสนอบล็อก (ไม่กี่วินาที) แล้วผลมีทันทีที่ครบ
#   - คะแนนที่ยังไม่ครบถูกล้างทุก epoch (100,000 บล็อก ≈ 55 ชม.)
#   - ปิดบล็อกต้องเห็นพ้อง ceil(2N/3) — เพิ่มตัวที่ดับเข้าไป = เสียตัวสำรองทันที
#     จึงบังคับให้โหนดใหม่ "เป็นเพียร์" กับ validator ในเครื่องนี้ก่อน (--node-id)
#
# ตัวแปรสำหรับเทสต์/เครื่องอื่น:
#   TPIX_VALIDATORS="tpix-validator-1 tpix-validator-2 …"  TPIX_GRPC=127.0.0.1:10000
#   TPIX_PEER_HUBS="tpix-bootnode" (โหนดในเครื่องที่ไม่ใช่ validator แต่โหนดภายนอกต่อผ่านได้)
#   TPIX_RPC_URL=http://127.0.0.1:8545  DOCKER_BIN=docker  CURL_BIN=curl
#   TPIX_VOTE_WAIT=90 (วินาทีที่รอผลหลังโหวต)  TPIX_PROGRESS_WAIT=6
#
# Developed by Xman Studio
# ============================================================

set -uo pipefail

read -r -a VALIDATORS <<< "${TPIX_VALIDATORS:-tpix-validator-1 tpix-validator-2 tpix-validator-3 tpix-validator-4}"
GRPC="${TPIX_GRPC:-127.0.0.1:10000}"
RPC="${TPIX_RPC_URL:-http://127.0.0.1:8545}"
read -r -a PEER_HUBS <<< "${TPIX_PEER_HUBS-tpix-bootnode}"
DOCKER="${DOCKER_BIN:-docker}"
CURL="${CURL_BIN:-curl}"
VOTE_WAIT="${TPIX_VOTE_WAIT:-90}"
PROGRESS_WAIT="${TPIX_PROGRESS_WAIT:-6}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
die()  { err "$*"; exit 1; }

usage() {
    sed -n '9,17p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

lower() { tr '[:upper:]' '[:lower:]'; }

edge() { # edge <container> <args…>
    local c="$1"; shift
    "$DOCKER" exec "$c" polygon-edge "$@" --grpc-address "$GRPC"
}

running() {
    [ "$("$DOCKER" inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]
}

# ── ชุด validator ปัจจุบัน (จาก validator ตัวแรกที่ตอบ) ──────────────────────
SNAP_JSON=""
load_snapshot() {
    local c
    for c in "${VALIDATORS[@]}"; do
        running "$c" || continue
        SNAP_JSON="$(edge "$c" ibft snapshot --json 2>/dev/null)" && [ -n "$SNAP_JSON" ] && return 0
    done
    return 1
}

# ที่อยู่ในชุด ตัวพิมพ์เล็ก บรรทัดละตัว
set_addresses() {
    printf '%s' "$SNAP_JSON" | python3 -c 'import json,sys
for v in json.load(sys.stdin).get("validators", []): print(v["Address"].lower())'
}

set_bls_keys() {
    printf '%s' "$SNAP_JSON" | python3 -c 'import json,sys
for v in json.load(sys.stdin).get("validators", []): print((v.get("BLSPublicKey") or "").lower())'
}

votes_needed() { echo $(( $1 / 2 + 1 )); }
quorum()       { if [ "$1" -lt 4 ]; then echo "$1"; else echo $(( (2 * $1 + 2) / 3 )); fi; }
tolerance()    { echo $(( $1 - $(quorum "$1") )); }

block_number() {
    "$CURL" -s -m 5 -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "$RPC" \
        | python3 -c 'import json,sys; print(int(json.load(sys.stdin)["result"],16))' 2>/dev/null
}

# เชนต้องเดินอยู่ — เปลี่ยนชุดตอนเชนค้างไม่มีผล (คะแนนเข้าบล็อกไม่ได้) และเสี่ยงสับสน
require_progress() {
    local a b
    a="$(block_number)" || true
    [ -n "$a" ] || die "อ่านเลขบล็อกจาก $RPC ไม่ได้ — ตรวจเชนก่อน"
    sleep "$PROGRESS_WAIT"
    b="$(block_number)" || true
    [ -n "$b" ] && [ "$b" -gt "$a" ] || die "เชนไม่เดิน (บล็อก $a → ${b:-?} ใน ${PROGRESS_WAIT} วิ) — ซ่อมเชนก่อน ห้ามเปลี่ยนชุด validator ตอนนี้"
    log "เชนเดินอยู่: บล็อก $a → $b"
}

# โหนดใหม่ต้องต่อกับเครือข่ายของ validator ในเครื่องนี้ — ไม่งั้นโหวตเข้าแล้วมันเซ็นอะไรไม่ได้เลย
# peer_count_of <node_id> <container…>
peer_count_of() {
    local node_id="$1" c n=0
    shift
    for c in "$@"; do
        running "$c" || continue
        if edge "$c" peers list --json 2>/dev/null | python3 -c 'import json,sys
sys.exit(0 if sys.argv[1] in json.load(sys.stdin).get("peers", []) else 1)' "$node_id"; then
            n=$((n + 1))
        fi
    done
    echo "$n"
}

cmd_status() {
    load_snapshot || die "อ่าน ibft snapshot จาก validator ในเครื่องไม่ได้"
    local addrs n
    addrs="$(set_addresses)"
    n="$(printf '%s\n' "$addrs" | grep -c .)"
    log "ชุด validator ตอนนี้ ($n ตัว · ต้องเห็นพ้อง $(quorum "$n") · ทนดับได้ $(tolerance "$n") · โหวตต้องได้ $(votes_needed "$n") เสียง):"
    printf '%s\n' "$addrs" | sed 's/^/    /'
    local c
    for c in "${VALIDATORS[@]}"; do
        if ! running "$c"; then warn "$c ไม่ได้รัน"; continue; fi
        echo "  $c candidates: $(edge "$c" ibft candidates --json 2>/dev/null | tr -d '\n')"
    done
}

wait_for() { # wait_for in|out <addr>
    local want="$1" addr="$2" waited=0
    while [ "$waited" -lt "$VOTE_WAIT" ]; do
        if load_snapshot; then
            if set_addresses | grep -qx "$addr"; then
                [ "$want" = "in" ] && return 0
            else
                [ "$want" = "out" ] && return 0
            fi
        fi
        sleep 3; waited=$((waited + 3))
    done
    return 1
}

cmd_vote() {
    local vote="$1"; shift
    local addr="" bls="" node_id="" yes=0 allow_small=0 skip_peer=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --addr) addr="$(printf '%s' "${2:-}" | lower)"; shift 2 ;;
            --bls) bls="$(printf '%s' "${2:-}" | lower)"; shift 2 ;;
            --node-id) node_id="${2:-}"; shift 2 ;;
            --yes) yes=1; shift ;;
            --allow-small-set) allow_small=1; shift ;;
            --skip-peer-check) skip_peer=1; shift ;;
            *) err "ไม่รู้จัก: $1"; usage ;;
        esac
    done

    [[ "$addr" =~ ^0x[0-9a-f]{40}$ ]] || die "--addr ต้องเป็น 0x + 40 hex"
    if [ "$vote" = "auth" ]; then
        [[ "$bls" =~ ^0x[0-9a-f]{96}$ ]] || die "--bls ต้องเป็น 0x + 96 hex (BLS public key 48 ไบต์) — เชนนี้เป็น validator_type: bls"
    fi
    if [ -n "$node_id" ] && ! [[ "$node_id" =~ ^16Uiu2HA[1-9A-HJ-NP-Za-km-z]{40,60}$ ]]; then
        die "--node-id ไม่ใช่ libp2p peer ID (ขึ้นต้น 16Uiu2HA)"
    fi

    local c up=0
    for c in "${VALIDATORS[@]}"; do running "$c" && up=$((up + 1)); done
    [ "$up" -gt 0 ] || die "ไม่มี validator ไหนในเครื่องนี้รันอยู่"

    load_snapshot || die "อ่าน ibft snapshot ไม่ได้"
    local addrs n after
    addrs="$(set_addresses)"
    n="$(printf '%s\n' "$addrs" | grep -c .)"

    if [ "$vote" = "auth" ]; then
        if printf '%s\n' "$addrs" | grep -qx "$addr"; then log "$addr อยู่ในชุดแล้ว — ไม่ต้องโหวต"; exit 0; fi
        if set_bls_keys | grep -qx "$bls"; then die "BLS key นี้เป็นของ validator ที่อยู่ในชุดแล้ว — ห้ามใช้ซ้ำ"; fi
        after=$((n + 1))
    else
        if ! printf '%s\n' "$addrs" | grep -qx "$addr"; then log "$addr ไม่อยู่ในชุดอยู่แล้ว — ไม่ต้องโหวต"; exit 0; fi
        after=$((n - 1))
        if [ "$after" -lt 4 ] && [ "$allow_small" -ne 1 ]; then
            die "ถอดแล้วเหลือ $after ตัว (ต่ำกว่า 4 = ต้องอยู่ครบทุกตัว ดับตัวเดียวเชนหยุด) — ถ้าตั้งใจจริงใส่ --allow-small-set"
        fi
    fi

    local need
    need="$(votes_needed "$n")"
    log "ชุดตอนนี้ $n ตัว → หลังโหวต $after ตัว · ต้องได้ $need เสียง · validator ในเครื่องนี้รันอยู่ $up ตัว"
    log "หลังโหวต: ต้องเห็นพ้อง $(quorum "$after") · ทนดับได้ $(tolerance "$after") (ตอนนี้ $(tolerance "$n"))"
    [ "$up" -ge "$need" ] || die "validator ในเครื่องนี้รันอยู่ $up ตัว ไม่ถึง $need เสียง — โหวตไม่ผ่านแน่นอน"
    if [ "$vote" = "auth" ] && [ "$(tolerance "$after")" -le "$(tolerance "$n")" ]; then
        warn "เพิ่มเป็น $after ตัวไม่ได้ทำให้ทนขึ้น — ถ้าตัวใหม่ดับ ตัวเดิมต้องอยู่ครบ (แนะนำเพิ่มทีละ 2 ตัว)"
    fi

    require_progress

    if [ "$vote" = "auth" ]; then
        if [ -n "$node_id" ]; then
            local peers hub_peers=0
            peers="$(peer_count_of "$node_id" "${VALIDATORS[@]}")"
            [ "${#PEER_HUBS[@]}" -gt 0 ] && hub_peers="$(peer_count_of "$node_id" "${PEER_HUBS[@]}")"
            if [ "$peers" -gt 0 ]; then
                log "โหนดใหม่เป็นเพียร์กับ validator ในเครื่องนี้ $peers ตัว"
            elif [ "$hub_peers" -gt 0 ]; then
                # validator หลักอยู่หลัง docker bridge — โหนดภายนอกอาจต่อได้แค่ผ่าน bootnode สาธารณะ
                # ข้อความ IBFT เดินผ่าน gossip ได้ แต่ยืนยันไม่ได้จนกว่าจะเห็นมันเซ็นบล็อกจริง
                warn "โหนดใหม่ต่ออยู่กับ ${PEER_HUBS[*]} แต่ยังไม่เป็นเพียร์ตรงกับ validator — หลังโหวตต้องเห็น 'เซ็น %' ขึ้นใน 5 นาที ไม่งั้นถอดออก"
            else
                [ "$skip_peer" -eq 1 ] || die "โหนด $node_id ไม่ได้ต่อกับ validator หรือ bootnode ในเครื่องนี้ — โหวตเข้าแล้วจะเซ็นอะไรไม่ได้ (ตรวจไฟร์วอลล์/genesis ของโหนดนั้น)"
                warn "--skip-peer-check: ข้ามการตรวจเพียร์ตามที่สั่ง"
            fi
        else
            warn "ไม่ได้ใส่ --node-id — ตรวจไม่ได้ว่าโหนดใหม่ต่อกับเครือข่ายแล้ว ยืนยันกับผู้สมัครว่าซิงก์ถึงบล็อกล่าสุดก่อน"
        fi
    fi

    local args=(ibft propose --addr "$addr" --vote "$vote")
    [ "$vote" = "auth" ] && args+=(--bls "$bls")

    if [ "$yes" -ne 1 ]; then
        log "ซ้อมเท่านั้น — จะรันบน validator ทุกตัวในเครื่อง:"
        for c in "${VALIDATORS[@]}"; do echo "    $DOCKER exec $c polygon-edge ${args[*]} --grpc-address $GRPC"; done
        log "ผลตรวจผ่าน · เติม --yes เพื่อโหวตจริง"
        exit 0
    fi

    local ok=0
    for c in "${VALIDATORS[@]}"; do
        if ! running "$c"; then warn "$c ไม่ได้รัน — ข้าม"; continue; fi
        if edge "$c" "${args[@]}" >/dev/null 2>&1; then
            ok=$((ok + 1)); log "$c โหวต $vote แล้ว"
        else
            warn "$c โหวตไม่สำเร็จ"
        fi
    done
    [ "$ok" -ge "$need" ] || die "ได้ $ok เสียง ไม่ถึง $need — ตรวจด้วย: sudo bash $0 status"

    log "ได้ $ok/$need เสียง — รอให้เสียงเข้าบล็อก (สูงสุด ${VOTE_WAIT} วิ)…"
    if [ "$vote" = "auth" ]; then
        wait_for in "$addr" || die "ยังไม่เห็น $addr ในชุดหลัง ${VOTE_WAIT} วิ — ตรวจด้วย status (เสียงยังค้างอยู่ใน candidates จนครบหรือจนขึ้น epoch ใหม่)"
        log "เพิ่ม $addr เข้าชุดแล้ว ✓ — ดูการปิดบล็อกรายตัวที่ /admin/validators (ตัวเฝ้าดูอ่านทุกนาที)"
    else
        wait_for out "$addr" || die "ยังเห็น $addr ในชุดหลัง ${VOTE_WAIT} วิ — ตรวจด้วย status"
        log "ถอด $addr ออกจากชุดแล้ว ✓"
    fi
}

[ $# -ge 1 ] || usage
command -v python3 >/dev/null || die "ต้องมี python3"
case "$1" in
    auth|drop) cmd_vote "$@" ;;
    status) cmd_status ;;
    -h|--help|help) usage ;;
    *) err "ไม่รู้จักคำสั่ง: $1"; usage ;;
esac
