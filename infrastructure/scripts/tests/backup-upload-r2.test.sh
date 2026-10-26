#!/bin/bash
# Offline regression tests: no credentials, network, Docker or real backups.
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/backup-upload-r2.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/bin" "$WORK/remote"
cat > "$WORK/bin/rclone" <<'MOCK'
#!/bin/bash
set -euo pipefail
[[ -z "${RCLONE_CONFIG_R2_ACL:-}" ]] || { echo 'R2 must omit S3 ACL headers' >&2; exit 1; }
case "$1" in
 copyto)
   [[ "${MODE:-}" != upload_fail ]] || exit 1
   target="$REMOTE_DIR/${3##*/}"
   if [[ -f "$target" ]]; then
     [[ "$(stat -c %s "$2")" == "$(stat -c %s "$target")" ]] || exit 1
   else cp "$2" "$target"; fi ;;
 cat)
   target="$REMOTE_DIR/${2##*/}"
   if [[ "${MODE:-}" == read_fail ]]; then cat "$target"; exit 1; fi
   if [[ "${MODE:-}" == bad_manifest && "$target" == *.sha256 ]]; then
     printf wrong
   else cat "$target"; fi ;;
 *) echo "Unexpected/destructive operation: $1" >&2; exit 99 ;;
esac
MOCK
chmod +x "$WORK/bin/rclone"
export PATH="$WORK/bin:$PATH" REMOTE_DIR="$WORK/remote"
export TPIX_R2_ACCOUNT_ID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export TPIX_R2_ACCESS_KEY_ID=test TPIX_R2_SECRET_ACCESS_KEY=test TPIX_R2_RETRIES=1
FILE="$WORK/tpix-chain-test.tar.gz.gpg"
reset_case() { rm -f "$WORK/remote/"* "$FILE.r2-verified"; printf abcdef > "$FILE"; unset MODE; }
expect_failure() {
    if bash "$SCRIPT" "$FILE" > "$WORK/log" 2>&1; then
        cat "$WORK/log"; echo 'Expected failure' >&2; exit 1
    fi
    [[ -f "$FILE" && ! -f "$FILE.r2-verified" ]]
}
reset_case
bash "$SCRIPT" "$FILE" > "$WORK/log"
[[ -f "$FILE.r2-verified" && -f "$REMOTE_DIR/$(basename "$FILE").sha256" ]]
bash "$SCRIPT" "$FILE" > "$WORK/log" # same locked object is reusable
echo 'PASS: full read-back, manifest and idempotent retry'
reset_case
printf ghijkl > "$REMOTE_DIR/$(basename "$FILE")"
expect_failure
[[ "$(cat "$REMOTE_DIR/$(basename "$FILE")")" == ghijkl ]]
echo 'PASS: same-size corruption rejected, never overwritten'
reset_case
printf conflict > "$REMOTE_DIR/$(basename "$FILE")"
expect_failure
echo 'PASS: different-size collision rejected'
reset_case; export MODE=read_fail; expect_failure
echo 'PASS: incomplete read-back fails even when digest bytes match'
reset_case; export MODE=bad_manifest; expect_failure
echo 'PASS: corrupt manifest rejected'
reset_case; export MODE=upload_fail; expect_failure
echo 'PASS: failed upload preserves local archive'
