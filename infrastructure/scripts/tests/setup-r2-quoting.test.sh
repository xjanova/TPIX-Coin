#!/bin/bash
# Exercise the real setter without running interactive setup or loading secrets.
set -euo pipefail
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/setup-r2-backup.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ENV_FILE="$WORK/config"
touch "$ENV_FILE"
source <(sed -n '/^set_kv() {/,/^}/p' "$SCRIPT")
EXPECTED='/usr/local/sbin/tpix-backup-upload-r2 {file}'
set_kv TPIX_BACKUP_UPLOAD "$EXPECTED"
source "$ENV_FILE"
[[ "$TPIX_BACKUP_UPLOAD" == "$EXPECTED" ]]
# Replacement must preserve quoting, ampersands and sed delimiters too.
EXPECTED='spaces & pipes | backslash \ and $literal'
set_kv TPIX_BACKUP_UPLOAD "$EXPECTED"
source "$ENV_FILE"
[[ "$TPIX_BACKUP_UPLOAD" == "$EXPECTED" ]]
[[ $(grep -c '^TPIX_BACKUP_UPLOAD=' "$ENV_FILE") -eq 1 ]]
echo 'PASS: new and replaced environment values safely source with spaces/metacharacters'
