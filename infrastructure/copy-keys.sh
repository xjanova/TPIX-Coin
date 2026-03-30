#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# TPIX Chain — Copy Validator Keys to Docker Volumes
# Run after setup-chain.sh and before docker-compose up
#
# This creates temporary containers to copy key data into
# the named Docker volumes used by docker-compose.yml
# ─────────────────────────────────────────────────────────────

set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[TPIX]${NC} $1"; }

DATA_DIR="./data"

if [[ ! -d "${DATA_DIR}/validator-1" ]]; then
    echo "Error: Validator data not found. Run ./setup-chain.sh first."
    exit 1
fi

# Ensure volumes exist (docker-compose creates them)
log "Creating Docker volumes if not exist..."
for i in 1 2 3 4; do
    docker volume create "infrastructure_validator${i}-data" 2>/dev/null || true
done

# Copy keys to volumes
for i in 1 2 3 4; do
    DIR="${DATA_DIR}/validator-${i}"
    VOL="infrastructure_validator${i}-data"

    if [[ ! -d "${DIR}" ]]; then
        echo "Warning: ${DIR} not found, skipping..."
        continue
    fi

    log "Copying validator-${i} keys to volume ${VOL}..."

    # Use a temp container to copy files into the volume
    docker run --rm \
        -v "${VOL}:/data" \
        -v "$(pwd)/${DIR}:/source:ro" \
        alpine sh -c "cp -r /source/* /data/ 2>/dev/null; ls -la /data/"

    echo ""
done

log "All validator keys copied to Docker volumes"
echo ""
echo -e "${CYAN}Next: docker-compose up -d${NC}"
