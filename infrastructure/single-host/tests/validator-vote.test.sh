#!/bin/bash
# ============================================================
# เทสต์ validator-vote.sh ด้วย docker/curl ปลอม — ไม่แตะเชนจริง
#
#   bash infrastructure/single-host/tests/validator-vote.test.sh
#
# docker ปลอมจำลองพฤติกรรม polygon-edge ที่สคริปต์พึ่ง:
#   ibft snapshot --json · ibft propose (ครบเสียงเกินครึ่ง = เปลี่ยนชุด) ·
#   ibft candidates --json · peers list --json · inspect (รัน/ไม่รัน)
# ============================================================

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../validator-vote.sh"
PASS=0; FAIL=0

V1=0x00affa6379fbd969cbe5906cdeee793960a500da
V2=0xfe0dd72399145f54b5882ea3620f106bafdd5ad5
V3=0xa7d8ea159a59c82effcef88ccd92cf47048b2fde
V4=0xdeff2d109b52ddc574f6edc374e7e081e4198e20
B1=0x8f5c6db7b7f32fb48d9f3b1e86eec5b3821ada3ca35e110aa258c1aa2e55c3fc11f7fd1b48027240667e9c8e806c18d5
NEW=0x1111111111111111111111111111111111111111
NEW_BLS=0x$(printf 'ab%.0s' $(seq 1 48))
NEW_NODE=16Uiu2HAmSmFLK2z9HhZifQ3xaZmbZkZbT3hcEodRvVdX9tNnB8xv

setup() {
    T="$(mktemp -d)"
    mkdir -p "$T/bin"
    cat > "$T/snapshot.py" <<'PY'
import json, sys
path, op, addr, bls = sys.argv[1], sys.argv[2], sys.argv[3], (sys.argv[4] if len(sys.argv) > 4 else "")
snap = json.load(open(path))
if op == "add":
    snap["validators"].append({"Address": addr, "BLSPublicKey": bls})
else:
    snap["validators"] = [v for v in snap["validators"] if v["Address"].lower() != addr]
json.dump(snap, open(path, "w"))
PY
    python3 - "$T/snapshot.json" <<PY
import json, sys
json.dump({"number": 100, "votes": [], "validators": [
  {"Address": "$V1", "BLSPublicKey": "$B1"},
  {"Address": "$V2", "BLSPublicKey": "0x$(printf '22%.0s' $(seq 1 48))"},
  {"Address": "$V3", "BLSPublicKey": "0x$(printf '33%.0s' $(seq 1 48))"},
  {"Address": "$V4", "BLSPublicKey": "0x$(printf '44%.0s' $(seq 1 48))"}]}, open(sys.argv[1], "w"))
PY
    echo '{"peers":[]}' > "$T/peers.json"
    printf 'tpix-validator-1\ntpix-validator-2\ntpix-validator-3\ntpix-validator-4\n' > "$T/running"
    echo 1000 > "$T/block"
    : > "$T/votes.log"

    cat > "$T/bin/docker" <<SH
#!/bin/bash
T="$T"
if [ "\$1" = inspect ]; then grep -qx "\$4" "\$T/running" && echo true || echo false; exit 0; fi
[ "\$1" = exec ] || exit 9
c="\$2"; shift 3   # exec <c> polygon-edge
grep -qx "\$c" "\$T/running" || exit 1
case "\$1 \$2" in
  "ibft snapshot") cat "\$T/snapshot.json" ;;
  "ibft candidates") echo '{"candidates":[]}' ;;
  "peers list") if [ -f "\$T/peers-\$c.json" ]; then cat "\$T/peers-\$c.json"; else cat "\$T/peers.json"; fi ;;
  "ibft propose")
    addr=""; vote=""; bls=""
    while [ \$# -gt 0 ]; do case "\$1" in --addr) addr="\$2"; shift 2;; --vote) vote="\$2"; shift 2;; --bls) bls="\$2"; shift 2;; *) shift;; esac; done
    [ -f "\$T/fail-propose" ] && exit 1
    echo "\$c \$vote \$addr \$bls" >> "\$T/votes.log"
    n=\$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["validators"]))' "\$T/snapshot.json")
    got=\$(grep -c " \$vote \$addr" "\$T/votes.log")
    if [ "\$got" -eq \$(( n / 2 + 1 )) ] && [ ! -f "\$T/never-apply" ]; then
      [ "\$vote" = auth ] && python3 "\$T/snapshot.py" "\$T/snapshot.json" add "\$addr" "\$bls"
      [ "\$vote" = drop ] && python3 "\$T/snapshot.py" "\$T/snapshot.json" drop "\$addr"
    fi ;;
  *) exit 7 ;;
esac
SH
    cat > "$T/bin/curl" <<SH
#!/bin/bash
b=\$(cat "$T/block")
[ -f "$T/stuck" ] || echo \$((b + 3)) > "$T/block"
printf '{"jsonrpc":"2.0","id":1,"result":"0x%x"}' "\$b"
SH
    chmod +x "$T/bin/docker" "$T/bin/curl"
    export DOCKER_BIN="$T/bin/docker" CURL_BIN="$T/bin/curl" TPIX_PROGRESS_WAIT=0 TPIX_VOTE_WAIT=3
}

teardown() { rm -rf "$T"; }

run() { OUT="$(bash "$SCRIPT" "$@" 2>&1)"; CODE=$?; }

check() { # check <name> <condition…>
    local name="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); echo "ok   - $name"; else FAIL=$((FAIL + 1)); echo "FAIL - $name"; echo "$OUT" | sed 's/^/       /'; fi
}
has()  { printf '%s' "$OUT" | grep -qF -- "$1"; }
code() { [ "$CODE" -eq "$1" ]; }
votes() { grep -c . "$T/votes.log"; }

# ── dry-run: ตรวจครบ ไม่ส่งอะไร ───────────────────────────────────────────
setup
echo "{\"peers\":[\"$NEW_NODE\"]}" > "$T/peers.json"
run auth --addr "$NEW" --bls "$NEW_BLS" --node-id "$NEW_NODE"
check "dry-run exits 0" code 0
check "dry-run prints the real propose command" has "polygon-edge ibft propose --addr $NEW --vote auth --bls $NEW_BLS --grpc-address 127.0.0.1:10000"
check "dry-run sends no vote" [ "$(votes)" -eq 0 ]
check "dry-run warns that 5 validators tolerate no more than 4" has "ไม่ได้ทำให้ทนขึ้น"
check "dry-run says peering is ok" has "เป็นเพียร์กับ validator ในเครื่องนี้ 4 ตัว"
teardown

# ── --yes: โหวตทุกตัว แล้วรอจนเห็นในชุด ────────────────────────────────────
setup
echo "{\"peers\":[\"$NEW_NODE\"]}" > "$T/peers.json"
run auth --addr "$NEW" --bls "$NEW_BLS" --node-id "$NEW_NODE" --yes
check "auth --yes succeeds" code 0
check "auth votes from all 4 validators" [ "$(votes)" -eq 4 ]
check "auth confirms the new set" has "เพิ่ม $NEW เข้าชุดแล้ว"
run auth --addr "$NEW" --bls "$NEW_BLS" --yes
check "voting in a member again is a no-op" has "อยู่ในชุดแล้ว"
teardown

# ── ด่านความปลอดภัย ─────────────────────────────────────────────────────────
setup
run auth --addr "$NEW" --bls "$NEW_BLS" --node-id "$NEW_NODE" --yes
check "refuses a node that is not a peer" code 1
check "explains the peer refusal" has "ไม่ได้ต่อกับ validator หรือ bootnode"
check "no vote sent without peering" [ "$(votes)" -eq 0 ]

run auth --addr "$NEW" --yes
check "auth without --bls is refused" has "--bls ต้องเป็น"

run auth --addr "$NEW" --bls "$B1" --yes
check "refuses a BLS key that already seals" has "BLS key นี้เป็นของ validator"

run auth --addr 0x123 --bls "$NEW_BLS"
check "refuses a malformed address" has "--addr ต้องเป็น"

touch "$T/stuck"
echo "{\"peers\":[\"$NEW_NODE\"]}" > "$T/peers.json"
run auth --addr "$NEW" --bls "$NEW_BLS" --node-id "$NEW_NODE" --yes
check "refuses to change the set while the chain is stuck" has "เชนไม่เดิน"
check "no vote while stuck" [ "$(votes)" -eq 0 ]
rm -f "$T/stuck"

printf 'tpix-validator-1\ntpix-validator-2\n' > "$T/running"
run auth --addr "$NEW" --bls "$NEW_BLS" --node-id "$NEW_NODE" --yes
check "refuses when fewer local validators run than votes needed" has "ไม่ถึง 3 เสียง"
teardown

# ── ต่อได้แค่ผ่าน bootnode สาธารณะ: เตือนแต่ไปต่อ ──────────────────────────
setup
echo tpix-bootnode >> "$T/running"
echo "{\"peers\":[\"$NEW_NODE\"]}" > "$T/peers-tpix-bootnode.json"
run auth --addr "$NEW" --bls "$NEW_BLS" --node-id "$NEW_NODE"
check "a node reachable only through the bootnode passes the dry-run" code 0
check "it is reported as the normal external path" has "ต่ออยู่กับ tpix-bootnode (ทางปกติของโหนดภายนอก"
check "and is warned that the bootnode is its only path" has "bootnode เป็นทางเดียวของ validator ตัวนี้"
TPIX_PEER_HUBS="" run auth --addr "$NEW" --bls "$NEW_BLS" --node-id "$NEW_NODE"
check "without a hub the same node is refused" code 1
teardown

# ── โหวตไม่ครบ / ไม่เข้าชุด ───────────────────────────────────────────────
setup
echo "{\"peers\":[\"$NEW_NODE\"]}" > "$T/peers.json"
touch "$T/never-apply"
run auth --addr "$NEW" --bls "$NEW_BLS" --node-id "$NEW_NODE" --yes
check "reports when the vote never lands" has "ยังไม่เห็น $NEW ในชุด"
check "that is a failure exit" code 1
rm -f "$T/never-apply"; : > "$T/votes.log"
touch "$T/fail-propose"
run auth --addr "$NEW" --bls "$NEW_BLS" --node-id "$NEW_NODE" --yes
check "reports when propose fails everywhere" has "ได้ 0 เสียง ไม่ถึง 3"
teardown

# ── drop ─────────────────────────────────────────────────────────────────
setup
run drop --addr "$V4"
check "drop refuses to shrink below 4 validators" has "ต่ำกว่า 4"
run drop --addr "$V4" --allow-small-set --yes
check "drop with --allow-small-set works" has "ถอด $V4 ออกจากชุดแล้ว"
check "drop needs no BLS" bash -c "! grep -q ' 0x[0-9a-f]\{96\}' '$T/votes.log'"
run drop --addr "$NEW"
check "dropping a non-member is a no-op" has "ไม่อยู่ในชุดอยู่แล้ว"
teardown

# ── status ───────────────────────────────────────────────────────────────
setup
run status
check "status lists the set and the vote threshold" has "โหวตต้องได้ 3 เสียง"
check "status shows each container's candidates" has "tpix-validator-4 candidates:"
teardown

echo
echo "ผ่าน $PASS · ล้ม $FAIL"
[ "$FAIL" -eq 0 ]
