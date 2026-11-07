#!/bin/sh
# download Blockscout images built by github.com/xjanova/tpix-blockscout-build, verify sha256, docker load
set -e
TAG=${TAG:-images-2026-11-07}
BASE=https://github.com/xjanova/tpix-blockscout-build/releases/download/$TAG
DIR=/opt/tpix-bs/images; mkdir -p $DIR; cd $DIR
for f in "$@"; do
  echo "=== $f start $(date -u +%FT%TZ)"
  curl -fsSL -o $f.sha256 $BASE/$f.sha256
  curl -fsSL -o $f $BASE/$f
  sha256sum -c $f.sha256
  gunzip -c $f | docker load
  rm -f $f
  echo "=== $f done $(date -u +%FT%TZ)"
done
echo ALL_DONE
