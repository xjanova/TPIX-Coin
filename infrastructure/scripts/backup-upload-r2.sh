#!/bin/bash
# Upload encrypted backups to private R2 and verify a full read-back.
# Credentials come from the root-only backup environment, never argv.
# Remote retention belongs to R2 lifecycle + bucket locks. This script NEVER
# deletes remote objects and does not use TPIX_BACKUP_KEEP_DAYS.
set -euo pipefail
umask 077

FILE="${1:-}"
BUCKET="${TPIX_R2_BUCKET:-tpix-chain-backup}"
RETRIES="${TPIX_R2_RETRIES:-3}"
BW_LIMIT="${TPIX_R2_BWLIMIT:-10M}"
log() { printf '[R2] %s %s\n' "$(date -Is)" "$*"; }
fail() { log "$*" >&2; exit 1; }
[[ -n "$FILE" && -f "$FILE" && ! -L "$FILE" ]] || fail 'Expected a regular backup file'
[[ "$RETRIES" =~ ^[1-9][0-9]*$ && "$RETRIES" -le 10 ]] || fail 'Invalid retry count'
for cmd in rclone sha256sum stat mktemp cmp flock install; do
    command -v "$cmd" >/dev/null || fail "Missing command: $cmd"
done
for var in TPIX_R2_ACCOUNT_ID TPIX_R2_ACCESS_KEY_ID TPIX_R2_SECRET_ACCESS_KEY; do
    [[ -n "${!var:-}" ]] || fail "Missing configuration: $var"
done
[[ "$TPIX_R2_ACCOUNT_ID" =~ ^[a-fA-F0-9]{32}$ ]] || fail 'Invalid R2 account ID'
[[ "$BUCKET" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ]] || fail 'Invalid bucket name'
NAME="$(basename "$FILE")"
[[ "$NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || fail 'Unsafe object name'
REMOTE="R2:${BUCKET}/${NAME}"

export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ACCESS_KEY_ID="$TPIX_R2_ACCESS_KEY_ID"
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$TPIX_R2_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_R2_ENDPOINT="https://${TPIX_R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
# R2 rejects the S3 x-amz-acl header. An empty ACL omits that header;
# privacy is enforced by the bucket's disabled public access.
export RCLONE_CONFIG_R2_ACL='' RCLONE_S3_NO_CHECK_BUCKET=true

# Serialize manual retry and cron for this archive without a maintenance lock.
exec 8>"${FILE}.r2-upload.lock"
flock -n 8 || fail 'This archive is already uploading'
TMP_DIR="$(mktemp -d)"
trap 'rm -f "$TMP_DIR/manifest" "$TMP_DIR/remote-manifest" "$TMP_DIR/receipt"; rmdir "$TMP_DIR"' EXIT
LOCAL_SIZE="$(stat -c %s "$FILE")"
LOCAL_HASH="$(sha256sum "$FILE" | cut -d ' ' -f 1)"
printf '%s  %s\n' "$LOCAL_HASH" "$NAME" > "$TMP_DIR/manifest"
COMMON=(--bwlimit "$BW_LIMIT" --contimeout 20s --timeout 120s --retries 1 --low-level-retries 5)

upload() {
    local source="$1" destination="$2" attempt
    for ((attempt=1; attempt<=RETRIES; attempt++)); do
        # Same-size objects are verified below, never overwritten.
        # --immutable refuses different-size collisions.
        # Old rclone follows R2's versionId with a versioned HEAD, which R2
        # rejects (501). Skip that post-PUT HEAD; full read-back below verifies
        # the content instead. Pre-upload collision checks remain enabled.
        if rclone copyto "$source" "$destination" --immutable --size-only --s3-no-head \
            --s3-chunk-size 32M --transfers 1 --stats-one-line --stats 30s "${COMMON[@]}"; then
            return 0
        fi
        if (( attempt < RETRIES )); then sleep "$((attempt * 10))"; fi
    done
    return 1
}

log "Uploading $NAME ($LOCAL_SIZE bytes)"
upload "$FILE" "$REMOTE" || fail 'Archive upload failed; local copy retained'
log 'Reading back the entire remote object for SHA-256 verification'
REMOTE_HASH="$(rclone cat "$REMOTE" "${COMMON[@]}" | sha256sum | cut -d ' ' -f 1)" \
    || fail 'Remote read-back failed; local copy retained'
[[ "$REMOTE_HASH" == "$LOCAL_HASH" ]] || fail 'Remote SHA-256 mismatch; local copy retained'
[[ "$(sha256sum "$FILE" | cut -d ' ' -f 1)" == "$LOCAL_HASH" ]] \
    || fail 'Local archive changed during upload; no verification receipt written'

upload "$TMP_DIR/manifest" "${REMOTE}.sha256" || fail 'Manifest upload failed'
rclone cat "${REMOTE}.sha256" "${COMMON[@]}" > "$TMP_DIR/remote-manifest" || fail 'Manifest read-back failed'
cmp -s "$TMP_DIR/manifest" "$TMP_DIR/remote-manifest" || fail 'Remote manifest mismatch'
printf 'sha256=%s\nbytes=%s\nremote=%s\nverified_at=%s\n' \
    "$LOCAL_HASH" "$LOCAL_SIZE" "$REMOTE" "$(date -u +%FT%TZ)" > "$TMP_DIR/receipt"
install -m 600 "$TMP_DIR/receipt" "${FILE}.r2-verified"
log "Verified archive + manifest: $REMOTE (SHA-256 $LOCAL_HASH)"
log 'No remote pruning performed; configure retention in R2 separately'
