#!/bin/bash
# Offline regression tests for backup-chain.sh: the maintenance queue (flock) is
# handed back to the watchdog as soon as the chain is no longer touched, and a
# chain that stalls after the validator rejoins is reported instead of being
# called healthy. docker, curl and sleep are mocks — no real chain, no network.
# Needs root (the script refuses otherwise) and flock: CI runs it with sudo.
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/backup-chain.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/chain/data/validator-4" "$WORK/backups" "$WORK/gnupg"
chmod 700 "$WORK/gnupg"
echo '{}' > "$WORK/chain/genesis.json"
echo leveldb > "$WORK/chain/data/validator-4/000001.ldb"

# docker: v4 running/stopped state lives in files under $WORK
cat > "$WORK/bin/docker" <<'MOCK'
#!/bin/bash
S="$MOCK_STATE"
case "$1" in
  ps)    for v in 1 2 3; do echo "tpix-validator-$v"; done
         [[ -f "$S/v4-running" ]] && echo tpix-validator-4; exit 0 ;;
  stop)  rm -f "$S/v4-running"; echo "$2" ;;
  start) touch "$S/v4-running"; date +%s%N > "$S/v4-started"; touch "$S/v4-rejoined"; echo "$2" ;;
  inspect)
    case "$3" in
      *Running*)   [[ -f "$S/v4-running" ]] && echo true || echo false ;;
      *StartedAt*) cat "$S/v4-started" ;;
    esac ;;
  *) echo "unexpected docker $*" >&2; exit 99 ;;
esac
MOCK

# curl: eth_blockNumber advances one block per call — unless MODE=stall and the
# validator has rejoined. Alert POSTs are appended to $MOCK_STATE/alerts.
cat > "$WORK/bin/curl" <<'MOCK'
#!/bin/bash
S="$MOCK_STATE"
args="$*"
if [[ "$args" == *eth_blockNumber* ]]; then
    n=$(cat "$S/head")
    if ! [[ "${MODE:-}" == stall && -f "$S/v4-rejoined" ]]; then n=$((n + 1)); echo "$n" > "$S/head"; fi
    printf '{"jsonrpc":"2.0","id":1,"result":"0x%x"}' "$n"
elif [[ "$args" == */alert* ]]; then
    for a in "$@"; do [[ "$a" == '{"node"'* ]] && echo "$a" >> "$S/alerts"; done
fi
exit 0
MOCK

printf '#!/bin/bash\nexit 0\n' > "$WORK/bin/sleep"

# upload: proves the queue is free while it runs — the watchdog's own probe
cat > "$WORK/bin/fake-upload" <<'MOCK'
#!/bin/bash
[[ -f "$1" ]] || { echo "no file $1" >&2; exit 1; }
[[ ! -f "$TPIX_BACKUP_LOCK" ]] || { echo 'backup flag still set during upload' >&2; exit 1; }
flock -n "$TPIX_MAINT_LOCK" true || { echo 'maintenance queue still held during upload' >&2; exit 1; }
touch "$MOCK_STATE/uploaded"
MOCK
chmod +x "$WORK/bin/"*

export PATH="$WORK/bin:$PATH" GNUPGHOME="$WORK/gnupg"
export TPIX_CHAIN_DIR="$WORK/chain" TPIX_BACKUP_DIR="$WORK/backups"
export TPIX_BACKUP_VALIDATOR_DATA="$WORK/chain/data/validator-4"
export TPIX_BACKUP_LOCK="$WORK/backup.lock" TPIX_MAINT_LOCK="$WORK/maint.lock"
export TPIX_BACKUP_PASS=test-pass TPIX_BACKUP_UPLOAD="fake-upload {file}"
export TPIX_ALERT_URL=http://alerts.invalid/api/infra TPIX_ALERT_TOKEN=t TPIX_NODE_NAME=chain-test
export TPIX_MAINT_LOCK_WAIT=1 TPIX_BACKUP_RESUME_WAIT=20

reset_case() {
    export MOCK_STATE="$WORK/state-$1"
    rm -rf "$MOCK_STATE" "$WORK/backups/"*
    mkdir -p "$MOCK_STATE"
    echo 1000 > "$MOCK_STATE/head"; touch "$MOCK_STATE/v4-running" "$MOCK_STATE/alerts"
    echo 0 > "$MOCK_STATE/v4-started"
    unset MODE
}

# 1. healthy night: upload runs with the queue free, no alerts
reset_case healthy
bash "$SCRIPT" > "$WORK/log" 2>&1 || { cat "$WORK/log"; echo 'healthy run failed' >&2; exit 1; }
[[ -f "$MOCK_STATE/uploaded" && -f "$MOCK_STATE/v4-running" ]]
[[ ! -s "$MOCK_STATE/alerts" ]] || { cat "$MOCK_STATE/alerts"; echo 'unexpected alert' >&2; exit 1; }
[[ ! -f "$TPIX_BACKUP_LOCK" ]]
grep -q 'เชนเดินต่อปกติ' "$WORK/log"

# 2. chain stalls after the validator rejoins (2026-11-01): reported, queue
#    handed back, and the good backup is still shipped offsite
reset_case stall
export MODE=stall
bash "$SCRIPT" > "$WORK/log" 2>&1 || { cat "$WORK/log"; echo 'stall run should still ship the backup' >&2; exit 1; }
[[ -f "$MOCK_STATE/uploaded" ]]
grep -q '"key":"chain_stalled","severity":"critical"' "$MOCK_STATE/alerts"
if grep -q 'เชนเดินต่อปกติ' "$WORK/log"; then echo 'stalled chain reported as healthy' >&2; exit 1; fi
flock -n "$TPIX_MAINT_LOCK" true

# 3. queue held by someone else: skip with exit 75 and raise backup_failed,
#    without stopping the validator
reset_case busy
flock "$TPIX_MAINT_LOCK" /bin/sleep 5 &
HOLDER=$!
for _ in $(seq 1 50); do flock -n "$TPIX_MAINT_LOCK" true 2>/dev/null || break; /bin/sleep 0.1; done
set +e; bash "$SCRIPT" > "$WORK/log" 2>&1; rc=$?; set -e
kill "$HOLDER" 2>/dev/null || true; wait "$HOLDER" 2>/dev/null || true
[[ "$rc" -eq 75 ]] || { cat "$WORK/log"; echo "expected exit 75, got $rc" >&2; exit 1; }
grep -q '"key":"backup_failed"' "$MOCK_STATE/alerts"
[[ -f "$MOCK_STATE/v4-running" && ! -f "$MOCK_STATE/uploaded" ]]

echo 'backup-chain lock tests passed'
