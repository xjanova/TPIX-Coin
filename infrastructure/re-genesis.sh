#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# TPIX Chain — Re-Genesis Script
# Stops running chain, generates new 4-validator genesis,
# copies keys, and restarts with correct allocation.
#
# WARNING: This DESTROYS all existing chain data and history!
#
# Requirements: polygon-edge (v0.9.0), docker, docker-compose, jq
# Usage:        ./re-genesis.sh
# Developed by Xman Studio
# ─────────────────────────────────────────────────────────────

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[TPIX]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   TPIX Chain — Re-Genesis (4 Validators, 7B TPIX)       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
warn "This will DESTROY all existing chain data and block history!"
warn "Make sure you have backed up any important data."
echo ""
read -p "Type 'YES' to continue: " CONFIRM
if [[ "${CONFIRM}" != "YES" ]]; then
    err "Aborted."
    exit 1
fi

# ─── Pre-flight Checks ───────────────────────────────────────
log "Pre-flight checks..."

if ! command -v polygon-edge &> /dev/null; then
    err "polygon-edge not found. Installing..."
    # Try to find it or provide instructions
    if [[ -f /usr/local/bin/polygon-edge ]]; then
        log "Found at /usr/local/bin/polygon-edge"
    else
        err "Install polygon-edge v0.9.0:"
        err "  wget https://github.com/0xPolygon/polygon-edge/releases/download/v0.9.0/polygon-edge_0.9.0_linux_amd64.tar.gz"
        err "  tar xzf polygon-edge_0.9.0_linux_amd64.tar.gz"
        err "  sudo mv polygon-edge /usr/local/bin/"
        exit 1
    fi
fi

if ! command -v jq &> /dev/null; then
    err "jq not found. Install: sudo apt-get install -y jq"
    exit 1
fi

PE_VERSION=$(polygon-edge version 2>&1 | head -1 || echo "unknown")
log "polygon-edge: ${PE_VERSION}"

# ─── Step 1: Stop All Containers ─────────────────────────────
log "Step 1/7 — Stopping all TPIX containers..."

# Stop current single-node setup
docker stop tpix-chain-node 2>/dev/null || true
docker rm tpix-chain-node 2>/dev/null || true

# Stop docker-compose services (if any)
docker-compose down 2>/dev/null || true

# Stop blockscout (preserve it — just stop temporarily)
docker stop blockscout-frontend blockscout-backend blockscout-db 2>/dev/null || true

log "All containers stopped."
echo ""

# ─── Step 2: Backup Old Data ─────────────────────────────────
log "Step 2/7 — Backing up old validator key..."

BACKUP_DIR="./backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP_DIR}"

# Backup the old validator key from the running container's volume
OLD_VOL=$(docker volume ls -q | grep -E "validator.*data|tpix.*data" | head -1 || echo "")
if [[ -n "${OLD_VOL}" ]]; then
    docker run --rm -v "${OLD_VOL}:/data" -v "$(pwd)/${BACKUP_DIR}:/backup" \
        alpine sh -c "cp -r /data/ /backup/old-validator/ 2>/dev/null" || true
    log "Old validator data backed up to ${BACKUP_DIR}/"
else
    warn "No old volume found to backup."
fi

echo ""

# ─── Step 3: Clean Old Volumes ────────────────────────────────
log "Step 3/7 — Removing old Docker volumes..."

docker volume rm infrastructure_validator1-data 2>/dev/null || true
docker volume rm infrastructure_validator2-data 2>/dev/null || true
docker volume rm infrastructure_validator3-data 2>/dev/null || true
docker volume rm infrastructure_validator4-data 2>/dev/null || true

# Also remove any other tpix data volumes
docker volume ls -q | grep -i tpix | while read -r vol; do
    docker volume rm "${vol}" 2>/dev/null || true
done

log "Old volumes cleaned."
echo ""

# ─── Step 4: Generate New Validator Keys ──────────────────────
log "Step 4/7 — Generating 4 new validator keys..."

DATA_DIR="./data"
rm -rf "${DATA_DIR}"
mkdir -p "${DATA_DIR}"

NUM_VALIDATORS=4
CHAIN_ID=4289
BLOCK_TIME=2
EPOCH_LENGTH=100000
BLOCK_GAS_TARGET=20000000

VALIDATOR_ADDRS=()
BOOTNODE_URLS=()

for i in $(seq 1 ${NUM_VALIDATORS}); do
    DIR="${DATA_DIR}/validator-${i}"
    mkdir -p "${DIR}"

    polygon-edge secrets init --data-dir "${DIR}" --insecure --json > "${DIR}/secrets.json" 2>&1

    # Extract address and node ID
    ADDR=""
    NODE_ID=""

    if [[ -f "${DIR}/secrets.json" ]]; then
        ADDR=$(jq -r '.[0].address // empty' "${DIR}/secrets.json" 2>/dev/null || echo "")
        NODE_ID=$(jq -r '.[0].node_id // empty' "${DIR}/secrets.json" 2>/dev/null || echo "")
    fi

    # Fallback
    if [[ -z "${ADDR}" ]]; then
        ADDR=$(polygon-edge secrets output --data-dir "${DIR}" 2>/dev/null | grep -i "address" | awk '{print $NF}' || echo "")
        NODE_ID=$(polygon-edge secrets output --data-dir "${DIR}" 2>/dev/null | grep -i "node id" | awk '{print $NF}' || echo "")
    fi

    if [[ -z "${ADDR}" ]]; then
        err "Failed to extract address for validator ${i}"
        exit 1
    fi

    VALIDATOR_ADDRS+=("${ADDR}")
    if [[ -n "${NODE_ID}" ]]; then
        BOOTNODE_URLS+=("/ip4/tpix-validator-${i}/tcp/10001/p2p/${NODE_ID}")
    fi

    log "Validator ${i}: ${ADDR}"
done

echo ""

# ─── Step 5: Generate Genesis ─────────────────────────────────
log "Step 5/7 — Generating genesis.json with whitepaper allocation..."

# Allocation addresses (BIP-44 derived from project HD wallet)
# See WHITEPAPER.md Section 6 for full details
PREMINE_ARGS=""
# Pool 1: Master Node Rewards (20%) — 1,400,000,000 TPIX
PREMINE_ARGS+=" --premine 0x2112b98e3ec5A252b7b2A8f02d498B64a2186A7f:1400000000000000000000000000"
# Pool 2: Ecosystem Development (24.43%) — 1,710,000,000 TPIX (originally 1,750M minus 40M for validator stakes)
PREMINE_ARGS+=" --premine 0xD2eAB07809921fcB36c7AB72D7B5D8D2C12A67d7:1710000000000000000000000000"
# Pool 3: Team & Advisors (10%) — 700,000,000 TPIX
PREMINE_ARGS+=" --premine 0xf46131C82819d7621163F482b3fe88a228A7807c:700000000000000000000000000"
# Pool 4: Token Sale (10%) — 700,000,000 TPIX
PREMINE_ARGS+=" --premine 0x3F8EB4046F5C79fd0D67C7547B5830cB2Cfb401A:700000000000000000000000000"
# Pool 5: Liquidity & Market Making (15%) — 1,050,000,000 TPIX
PREMINE_ARGS+=" --premine 0x3da3776e0AB0F442c181aa031f47FA83696859AF:1050000000000000000000000000"
# Pool 6: Community & Rewards (20%) — 1,400,000,000 TPIX
PREMINE_ARGS+=" --premine 0xA945d1bE9c1DDeaE75BBb9B39981D1CE6Ed7d9d5:1400000000000000000000000000"

# Validator stakes: 10,000,000 TPIX each (Validator tier — highest)
for addr in "${VALIDATOR_ADDRS[@]}"; do
    PREMINE_ARGS+=" --premine ${addr}:10000000000000000000000000"
done

# Bootnode args
BOOTNODE_ARGS=""
for bn in "${BOOTNODE_URLS[@]}"; do
    BOOTNODE_ARGS+=" --bootnode ${bn}"
done

# Generate genesis
# Flags for polygon-edge v0.9.0:
#   --ibft-validators-prefix-path (not --validators-prefix)
#   --block-time accepts duration format (e.g. "2s")
GENESIS_OUT="./genesis.json"
rm -f "${GENESIS_OUT}"

polygon-edge genesis \
    --consensus ibft \
    --ibft-validators-prefix-path "${DATA_DIR}/validator-" \
    --ibft-validator-type bls \
    --chain-id ${CHAIN_ID} \
    --name "tpix-chain" \
    --block-gas-limit ${BLOCK_GAS_TARGET} \
    --epoch-size ${EPOCH_LENGTH} \
    --block-time "${BLOCK_TIME}s" \
    ${BOOTNODE_ARGS} \
    ${PREMINE_ARGS} \
    --dir "${GENESIS_OUT}"

# Validate genesis
if jq empty "${GENESIS_OUT}" 2>/dev/null; then
    log "Genesis JSON validated OK"
else
    err "Genesis JSON is invalid!"
    exit 1
fi

echo ""

# ─── Step 6: Copy Keys to Docker Volumes ─────────────────────
log "Step 6/7 — Copying validator keys to Docker volumes..."

for i in 1 2 3 4; do
    DIR="${DATA_DIR}/validator-${i}"
    VOL="infrastructure_validator${i}-data"

    docker volume create "${VOL}" 2>/dev/null || true

    docker run --rm \
        -v "${VOL}:/data" \
        -v "$(pwd)/${DIR}:/source:ro" \
        alpine sh -c "cp -r /source/* /data/"

    log "Validator ${i} keys → volume ${VOL}"
done

echo ""

# ─── Step 7: Start Chain ──────────────────────────────────────
log "Step 7/7 — Starting TPIX Chain with 4 validators..."

docker-compose up -d

# Wait for chain to start
log "Waiting for chain to produce blocks..."
sleep 10

# Verify chain is running
BLOCK_NUM=$(curl -s -X POST http://localhost:8545 \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    | jq -r '.result // "error"' 2>/dev/null || echo "error")

if [[ "${BLOCK_NUM}" == "error" || "${BLOCK_NUM}" == "null" ]]; then
    warn "Chain not responding yet. Check: docker-compose logs -f validator-1"
else
    BLOCK_DEC=$(printf "%d" "${BLOCK_NUM}" 2>/dev/null || echo "?")
    log "Chain is running! Current block: ${BLOCK_DEC}"
fi

echo ""

# ─── Step 8: Restart Blockscout ───────────────────────────────
log "Restarting Blockscout (re-index from genesis)..."

# Blockscout needs to re-index from scratch for new chain
docker start blockscout-db 2>/dev/null || true
sleep 3

# Clear blockscout DB for fresh re-index
docker exec blockscout-db psql -U blockscout -d blockscout -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" 2>/dev/null || true
sleep 2

docker start blockscout-backend 2>/dev/null || true
sleep 5
docker start blockscout-frontend 2>/dev/null || true

log "Blockscout restarted (will re-index from block 0)."
echo ""

# ─── Summary ──────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   RE-GENESIS COMPLETE                                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Chain ID:    ${CHAIN_ID}"
echo "  Consensus:   IBFT 2.0 (4 validators)"
echo "  Block Time:  ${BLOCK_TIME}s"
echo "  Gas Price:   0 (free)"
echo ""
echo "  Validators:"
for i in $(seq 0 $((${#VALIDATOR_ADDRS[@]} - 1))); do
    echo "    [$((i+1))] ${VALIDATOR_ADDRS[$i]} (10M TPIX)"
done
echo ""
echo "  Allocation Pools:"
echo "    Master Node Rewards:      1,400,000,000 TPIX → 0x2112b9...6A7f"
echo "    Ecosystem Development:    1,710,000,000 TPIX → 0xD2eAB0...67d7"
echo "    Team & Advisors:            700,000,000 TPIX → 0xf46131...807c"
echo "    Token Sale:                 700,000,000 TPIX → 0x3F8EB4...401A"
echo "    Liquidity & Market Making:1,050,000,000 TPIX → 0x3da377...59AF"
echo "    Community & Rewards:      1,400,000,000 TPIX → 0xA945d1...d9d5"
echo ""
echo "  Total Supply: 7,000,000,000 TPIX"
echo ""
echo "  Backup saved: ${BACKUP_DIR}/"
echo ""
echo "  Verify:"
echo "    curl -s localhost:8545 -X POST \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
echo ""
