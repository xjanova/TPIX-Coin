#!/bin/sh
# download Blockscout images built by github.com/xjanova/tpix-blockscout-build, verify sha256, docker load
#
# tpix-blockscout-build is private since 2026-11-21: its release links answer 404 without a login.
# Set GITHUB_TOKEN (fine-grained, Contents: read on that repo) and the files come through the API.
#   sudo GITHUB_TOKEN=... /opt/tpix-bs/fetch-images.sh <asset-file-name> ...
set -e
TAG=${TAG:-images-2026-11-07}
REPO=xjanova/tpix-blockscout-build
BASE=https://github.com/$REPO/releases/download/$TAG
DIR=/opt/tpix-bs/images; mkdir -p $DIR; cd $DIR

if [ -n "$GITHUB_TOKEN" ]; then
  # asset name -> API address, from the release's JSON (jq, else python3)
  curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
    -o release.json "https://api.github.com/repos/$REPO/releases/tags/$TAG"
  if command -v jq >/dev/null 2>&1; then
    asset_url() { jq -r --arg n "$1" '.assets[] | select(.name == $n) | .url' release.json; }
  else
    asset_url() { python3 -c 'import json,sys; print(next((a["url"] for a in json.load(open("release.json"))["assets"] if a["name"] == sys.argv[1]), ""))' "$1"; }
  fi
  # The API answers with a redirect to a signed file-host link; curl drops the Authorization header
  # when it follows a redirect to another host, so the token stays with api.github.com.
  get() {
    url=$(asset_url "$1")
    [ -n "$url" ] || { echo "no asset $1 in $REPO release $TAG" >&2; exit 1; }
    curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/octet-stream" -o "$1" "$url"
  }
else
  get() { curl -fsSL -o "$1" "$BASE/$1"; }
fi

for f in "$@"; do
  echo "=== $f start $(date -u +%FT%TZ)"
  get $f.sha256
  get $f
  sha256sum -c $f.sha256
  gunzip -c $f | docker load
  rm -f $f
  echo "=== $f done $(date -u +%FT%TZ)"
done
rm -f release.json
echo ALL_DONE
