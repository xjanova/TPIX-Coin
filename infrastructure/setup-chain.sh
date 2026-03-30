#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# TPIX Chain — Full Genesis Setup Script
# Generates 4 validator keys, builds genesis.json with IBFT2,
# pre-mines 7B TPIX, and configures bootnodes.
#
# Requirements: polygon-edge binary in PATH, jq
# Usage:        ./setup-chain.sh [--clean]
# CI Usage:     ./setup-chain.sh  (auto-detects CI environment)
# Developed by Xman Studio
# ─────────────────────────────────────────────────────────────

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────
NUM_VALIDATORS=4
DATA_DIR="./data"
GENESIS_OUT="./genesis.json"
CHAIN_ID=4289
BLOCK_TIME=2
EPOCH_LENGTH=100000
BLOCK_GAS_TARGET=20000000  # 0x1312D00

# Colors (disable in CI for clean logs)
if [[ -n "${CI:-}" ]]; then
    RED=''; GREEN=''; CYAN=''; YELLOW=''; NC=''
else
    RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
fi

log()  { echo -e "${GREEN}[TPIX]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# ─── Pre-flight Checks ───────────────────────────────────────
if ! command -v polygon-edge &> /dev/null; then
    err "polygon-edge not found in PATH"
    echo "Install: https://github.com/0xPolygon/polygon-edge/releases"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    err "jq not found. Install: apt-get install jq"
    exit 1
fi

PE_VERSION=$(polygon-edge version 2>&1 | head -1 || echo "unknown")
log "polygon-edge: ${PE_VERSION}"
log "Setting up TPIX Chain with ${NUM_VALIDATORS} validators"
echo ""

# ─── Clean previous data ─────────────────────────────────────
if [[ "${1:-}" == "--clean" ]]; then
    warn "Cleaning previous data..."
    rm -rf "${DATA_DIR}"
    rm -f "${GENESIS_OUT}"
fi

# ─── Step 1: Generate Validator Keys ─────────────────────────
log "Step 1/4 — Generating ${NUM_VALIDATORS} validator keys..."
echo ""

VALIDATOR_ADDRS=()
BOOTNODE_URLS=()

for i in $(seq 1 "${NUM_VALIDATORS}"); do
    DIR="${DATA_DIR}/validator-${i}"

    if [[ -d "${DIR}/consensus" ]]; then
        warn "Validator ${i} keys already exist, skipping generation..."
    else
        mkdir -p "${DIR}"
        polygon-edge secrets init --data-dir "${DIR}" --insecure --json > "${DIR}/secrets.json" 2>&1
    fi

    # Extract address and node ID using jq
    if [[ -f "${DIR}/secrets.json" ]]; then
        ADDR=$(jq -r '.[0].address // empty' "${DIR}/secrets.json" 2>/dev/null || echo "")
        NODE_ID=$(jq -r '.[0].node_id // empty' "${DIR}/secrets.json" 2>/dev/null || echo "")
    fi

    # Fallback: try polygon-edge secrets output
    if [[ -z "${ADDR:-}" ]]; then
        ADDR=$(polygon-edge secrets output --data-dir "${DIR}" 2>/dev/null | grep -i "address" | awk '{print $NF}' || echo "")
        NODE_ID=$(polygon-edge secrets output --data-dir "${DIR}" 2>/dev/null | grep -i "node id" | awk '{print $NF}' || echo "")
    fi

    if [[ -z "${ADDR:-}" ]]; then
        err "Failed to extract address for validator ${i}"
        err "Contents of ${DIR}:"
        ls -la "${DIR}/" 2>/dev/null || true
        cat "${DIR}/secrets.json" 2>/dev/null || true
        exit 1
    fi

    VALIDATOR_ADDRS+=("${ADDR}")

    # Bootnode multiaddr (docker internal network)
    if [[ -n "${NODE_ID:-}" ]]; then
        BOOTNODE_URLS+=("/ip4/tpix-validator-${i}/tcp/10001/p2p/${NODE_ID}")
    fi

    log "Validator ${i}: ${ADDR} (node: ${NODE_ID:-unknown})"
done

echo ""
log "Generated ${#VALIDATOR_ADDRS[@]} validator keys"
echo ""

# ─── Step 2: Generate Genesis ─────────────────────────────────
log "Step 2/4 — Generating genesis.json with IBFT2 consensus..."

# Build premine args (7 Billion TPIX total, 18 decimals)
PREMINE_ARGS=""
PREMINE_ARGS+=" --premine 0x0000000000000000000000000000000000001001:1400000000000000000000000000"
PREMINE_ARGS+=" --premine 0x0000000000000000000000000000000000001002:700000000000000000000000000"
PREMINE_ARGS+=" --premine 0x0000000000000000000000000000000000001003:2100000000000000000000000000"
PREMINE_ARGS+=" --premine 0x0000000000000000000000000000000000001004:1400000000000000000000000000"
PREMINE_ARGS+=" --premine 0x0000000000000000000000000000000000001005:700000000000000000000000000"
PREMINE_ARGS+=" --premine 0x0000000000000000000000000000000000001006:700000000000000000000000000"

# Premine 1000 TPIX to each validator
for addr in "${VALIDATOR_ADDRS[@]}"; do
    PREMINE_ARGS+=" --premine ${addr}:1000000000000000000000"
done

# Build bootnode args
BOOTNODE_ARGS=""
for bn in "${BOOTNODE_URLS[@]}"; do
    BOOTNODE_ARGS+=" --bootnode ${bn}"
done

# Generate genesis
# Flags verified against polygon-edge v1.3.x source:
#   --validators-prefix (not --ibft-validators-prefix-path)
#   --price-limit is a server flag, not genesis — omit here
polygon-edge genesis \
    --consensus ibft \
    --validators-prefix "${DATA_DIR}/validator-" \
    --chain-id "${CHAIN_ID}" \
    --name "tpix-chain" \
    --block-gas-limit "${BLOCK_GAS_TARGET}" \
    --epoch-size "${EPOCH_LENGTH}" \
    --block-time "${BLOCK_TIME}s" \
    --max-validator-count 21 \
    --min-validator-count 1 \
    ${BOOTNODE_ARGS} \
    ${PREMINE_ARGS} \
    --dir "${GENESIS_OUT}"

log "Genesis created: ${GENESIS_OUT}"
echo ""

# ─── Step 3: Display Summary ─────────────────────────────────
log "Step 3/4 — Chain Configuration Summary"
echo ""
echo "  Chain:          TPIX Chain"
echo "  Chain ID:       ${CHAIN_ID}"
echo "  Consensus:      IBFT 2.0 (PoA)"
echo "  Block Time:     ${BLOCK_TIME}s"
echo "  Epoch Length:   ${EPOCH_LENGTH} blocks"
echo "  Gas Price:      0 (free transactions)"
echo "  Total Supply:   7,000,000,000 TPIX"
echo ""
echo "  Validators:"
for i in $(seq 0 $((${#VALIDATOR_ADDRS[@]} - 1))); do
    echo "    [$((i+1))] ${VALIDATOR_ADDRS[$i]}"
done
echo ""
if [[ ${#BOOTNODE_URLS[@]} -gt 0 ]]; then
    echo "  Bootnodes:"
    for bn in "${BOOTNODE_URLS[@]}"; do
        echo "    ${bn}"
    done
    echo ""
fi

F=$(( (${#VALIDATOR_ADDRS[@]} - 1) / 3 ))
echo "  IBFT Fault Tolerance: ${F} node(s) can fail"
echo "  Min for Consensus:    $((${#VALIDATOR_ADDRS[@]} - F)) of ${#VALIDATOR_ADDRS[@]} validators"
echo ""

# ─── Step 4: Save Config Files ────────────────────────────────
log "Step 4/4 — Saving configuration files..."

# Save validators.json (public info only — no private keys)
jq -n \
    --argjson chainId "${CHAIN_ID}" \
    --argjson blockTime "${BLOCK_TIME}" \
    --argjson epochLength "${EPOCH_LENGTH}" \
    '{ chainId: $chainId, blockTime: $blockTime, epochLength: $epochLength, validators: [], bootnodes: [] }' > "${DATA_DIR}/validators.json"

# Add validators
for i in $(seq 0 $((${#VALIDATOR_ADDRS[@]} - 1))); do
    jq --arg addr "${VALIDATOR_ADDRS[$i]}" --argjson id "$((i+1))" \
        '.validators += [{ id: $id, address: $addr }]' \
        "${DATA_DIR}/validators.json" > "${DATA_DIR}/validators.tmp" && mv "${DATA_DIR}/validators.tmp" "${DATA_DIR}/validators.json"
done

# Add bootnodes
for bn in "${BOOTNODE_URLS[@]}"; do
    jq --arg bn "${bn}" '.bootnodes += [$bn]' \
        "${DATA_DIR}/validators.json" > "${DATA_DIR}/validators.tmp" && mv "${DATA_DIR}/validators.tmp" "${DATA_DIR}/validators.json"
done

log "Validator config saved: ${DATA_DIR}/validators.json"

# Verify genesis.json is valid JSON
if jq empty "${GENESIS_OUT}" 2>/dev/null; then
    log "Genesis JSON validated OK"
else
    err "Genesis JSON is invalid!"
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "  TPIX Chain genesis setup complete!"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Copy validator keys:  ./copy-keys.sh"
echo "  2. Start chain:          docker-compose up -d"
echo "  3. Verify blocks:        curl -s localhost:8545 -X POST \\"
echo "       -H 'Content-Type: application/json' \\"
echo "       -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
echo ""
