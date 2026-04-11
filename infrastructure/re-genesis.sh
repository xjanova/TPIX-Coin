#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# TPIX Chain — Re-Genesis Script
# Stops running chain, generates new 4-validator genesis,
# copies keys, and restarts with correct allocation.
#
# WARNING: This DESTROYS all existing chain data and history!
#
# Requirements: polygon-edge, docker, docker-compose, jq
# Usage:        ./re-genesis.sh
# Developed by Xman Studio
# ─────────────────────────────────────────────────────────────

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
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
echo ""
read -p "Type 'YES' to continue: " CONFIRM
if [[ "${CONFIRM}" != "YES" ]]; then
    err "Aborted."
    exit 1
fi

# ─── Pre-flight Checks ───────────────────────────────────────
log "Pre-flight checks..."

for cmd in polygon-edge jq docker; do
    if ! command -v "${cmd}" &> /dev/null; then
        err "${cmd} not found in PATH"
        exit 1
    fi
done
log "All dependencies found."

# ─── Step 1: Stop All Containers ─────────────────────────────
log "Step 1/7 — Stopping all containers..."

docker stop tpix-chain-node 2>/dev/null || true
docker rm tpix-chain-node 2>/dev/null || true
docker-compose down 2>/dev/null || true
docker stop blockscout-frontend blockscout-backend blockscout-db 2>/dev/null || true

log "All containers stopped."

# ─── Step 2: Backup Old Data ─────────────────────────────────
log "Step 2/7 — Backing up old data..."

BACKUP_DIR="./backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP_DIR}"
cp ./genesis.json "${BACKUP_DIR}/genesis.json.bak" 2>/dev/null || true
log "Backup saved: ${BACKUP_DIR}/"

# ─── Step 3: Clean Old Volumes ────────────────────────────────
log "Step 3/7 — Removing old Docker volumes..."

for i in 1 2 3 4; do
    docker volume rm "infrastructure_validator${i}-data" 2>/dev/null || true
done
docker volume ls -q | grep -i tpix | while read -r vol; do
    docker volume rm "${vol}" 2>/dev/null || true
done

log "Old volumes cleaned."

# ─── Step 4: Generate New Validator Keys ──────────────────────
log "Step 4/7 — Generating 4 new validator keys..."

DATA_DIR="./data"
rm -rf "${DATA_DIR}"
mkdir -p "${DATA_DIR}"

NUM_VALIDATORS=4

declare -a VALIDATOR_ADDRS
declare -a NODE_IDS

for i in $(seq 1 ${NUM_VALIDATORS}); do
    DIR="${DATA_DIR}/validator-${i}"
    mkdir -p "${DIR}"

    # Generate keys
    polygon-edge secrets init --data-dir "${DIR}" --insecure --json > "${DIR}/secrets.json" 2>&1

    # Extract info from secrets output
    SECRETS_OUT=$(polygon-edge secrets output --data-dir "${DIR}" 2>/dev/null)

    ADDR=$(echo "${SECRETS_OUT}" | grep "Public key (address)" | awk '{print $NF}')
    NODE_ID=$(echo "${SECRETS_OUT}" | grep "Node ID" | awk '{print $NF}')

    if [[ -z "${ADDR}" ]]; then
        err "Failed to extract address for validator ${i}"
        err "Secrets output:"
        echo "${SECRETS_OUT}"
        exit 1
    fi

    if [[ -z "${NODE_ID}" ]]; then
        err "Failed to extract Node ID for validator ${i}"
        exit 1
    fi

    VALIDATOR_ADDRS[$i]="${ADDR}"
    NODE_IDS[$i]="${NODE_ID}"

    log "Validator ${i}: ${ADDR} | Node: ${NODE_ID:0:20}..."
done

echo ""

# ─── Step 5: Generate Genesis ─────────────────────────────────
log "Step 5/7 — Generating genesis.json..."

rm -f ./genesis.json

# Build the full command as an array to avoid word-splitting issues
CMD=(polygon-edge genesis
    --consensus ibft
    --ibft-validators-prefix-path "${DATA_DIR}/validator-"
    --ibft-validator-type bls
    --chain-id 4289
    --name "tpix-chain"
    --block-gas-limit 20000000
    --epoch-size 100000
    --block-time "2s"
    --bootnode "/ip4/tpix-validator-1/tcp/10001/p2p/${NODE_IDS[1]}"
    --bootnode "/ip4/tpix-validator-2/tcp/10001/p2p/${NODE_IDS[2]}"
    --bootnode "/ip4/tpix-validator-3/tcp/10001/p2p/${NODE_IDS[3]}"
    --bootnode "/ip4/tpix-validator-4/tcp/10001/p2p/${NODE_IDS[4]}"
    --premine "0x2112b98e3ec5A252b7b2A8f02d498B64a2186A7f:1400000000000000000000000000"
    --premine "0xD2eAB07809921fcB36c7AB72D7B5D8D2C12A67d7:1710000000000000000000000000"
    --premine "0xf46131C82819d7621163F482b3fe88a228A7807c:700000000000000000000000000"
    --premine "0x3F8EB4046F5C79fd0D67C7547B5830cB2Cfb401A:700000000000000000000000000"
    --premine "0x3da3776e0AB0F442c181aa031f47FA83696859AF:1050000000000000000000000000"
    --premine "0xA945d1bE9c1DDeaE75BBb9B39981D1CE6Ed7d9d5:1400000000000000000000000000"
    --premine "${VALIDATOR_ADDRS[1]}:10000000000000000000000000"
    --premine "${VALIDATOR_ADDRS[2]}:10000000000000000000000000"
    --premine "${VALIDATOR_ADDRS[3]}:10000000000000000000000000"
    --premine "${VALIDATOR_ADDRS[4]}:10000000000000000000000000"
    --dir ./genesis.json
)

# Print command for debugging
log "Running: ${CMD[*]}"
echo ""

# Execute
"${CMD[@]}"

# Validate
if jq empty ./genesis.json 2>/dev/null; then
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

    log "Validator ${i} keys → ${VOL}"
done

echo ""

# ─── Step 7: Start Chain ──────────────────────────────────────
log "Step 7/7 — Starting TPIX Chain with 4 validators..."

docker-compose up -d

log "Waiting 15s for chain to produce blocks..."
sleep 15

# Verify
BLOCK_NUM=$(curl -s -X POST http://localhost:8545 \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    | jq -r '.result // "error"' 2>/dev/null || echo "error")

if [[ "${BLOCK_NUM}" != "error" && "${BLOCK_NUM}" != "null" ]]; then
    BLOCK_DEC=$(printf "%d" "${BLOCK_NUM}" 2>/dev/null || echo "?")
    log "Chain is running! Current block: ${BLOCK_DEC}"
else
    warn "Chain not responding yet. Check: docker-compose logs -f validator-1"
fi

echo ""

# ─── Restart Blockscout ───────────────────────────────────────
log "Restarting Blockscout (re-index from genesis)..."

docker start blockscout-db 2>/dev/null || true
sleep 3
docker exec blockscout-db psql -U blockscout -d blockscout -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" 2>/dev/null || true
sleep 2
docker start blockscout-backend 2>/dev/null || true
sleep 5
docker start blockscout-frontend 2>/dev/null || true

log "Blockscout restarted."
echo ""

# ─── Summary ──────────────────────────────────────────────────
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   RE-GENESIS COMPLETE                                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Chain ID:    4289"
echo "  Consensus:   IBFT 2.0 (4 validators, BLS)"
echo "  Block Time:  2s"
echo "  Gas Price:   0 (free)"
echo ""
echo "  Validators:"
for i in 1 2 3 4; do
    echo "    [${i}] ${VALIDATOR_ADDRS[$i]} (10M TPIX)"
done
echo ""
echo "  Allocation Pools (BIP-44 HD Wallet):"
echo "    #0 Main Wallet (rewards):   0x0B263D083969946fA2bB44Af2debA69D3d3d0220"
echo "    #1 Master Node Rewards:     0x2112b98e3ec5A252b7b2A8f02d498B64a2186A7f  (1,400M)"
echo "    #2 Ecosystem Development:   0xD2eAB07809921fcB36c7AB72D7B5D8D2C12A67d7  (1,710M)"
echo "    #3 Team & Advisors:         0xf46131C82819d7621163F482b3fe88a228A7807c  (700M)"
echo "    #4 Token Sale:              0x3F8EB4046F5C79fd0D67C7547B5830cB2Cfb401A  (700M)"
echo "    #5 Liquidity & Market:      0x3da3776e0AB0F442c181aa031f47FA83696859AF  (1,050M)"
echo "    #6 Community & Rewards:     0xA945d1bE9c1DDeaE75BBb9B39981D1CE6Ed7d9d5  (1,400M)"
echo ""
echo "  Total Supply: 7,000,000,000 TPIX"
echo "  Backup: ${BACKUP_DIR}/"
echo ""
