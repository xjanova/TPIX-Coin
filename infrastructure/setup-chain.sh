#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# TPIX Chain — Full Genesis Setup Script
# Generates 4 validator keys, builds genesis.json with IBFT2,
# pre-mines 7B TPIX, and configures bootnodes.
#
# Requirements: polygon-edge binary in PATH
# Usage:        ./setup-chain.sh [--validators 4] [--clean]
# Developed by Xman Studio
# ─────────────────────────────────────────────────────────────

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────
NUM_VALIDATORS="${1:-4}"
DATA_DIR="./data"
GENESIS_OUT="./genesis.json"
CHAIN_ID=4289
BLOCK_TIME=2
EPOCH_LENGTH=100000
MAX_SLOTS=4096
BLOCK_GAS_TARGET=20000000  # 0x1312D00
PREMINE_FILE="./premine-accounts.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[TPIX]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# ─── Pre-flight Checks ───────────────────────────────────────
if ! command -v polygon-edge &> /dev/null; then
    err "polygon-edge not found in PATH"
    echo "Install: https://github.com/0xPolygon/polygon-edge/releases"
    exit 1
fi

PE_VERSION=$(polygon-edge version 2>/dev/null || echo "unknown")
log "polygon-edge version: ${PE_VERSION}"
log "Setting up TPIX Chain with ${NUM_VALIDATORS} validators"
echo ""

# ─── Clean previous data (optional) ──────────────────────────
if [[ "${2:-}" == "--clean" ]] || [[ "${1:-}" == "--clean" ]]; then
    warn "Cleaning previous data..."
    rm -rf "${DATA_DIR}"
    rm -f "${GENESIS_OUT}"
fi

# ─── Step 1: Generate Validator Keys ─────────────────────────
log "Step 1/4 — Generating ${NUM_VALIDATORS} validator keys..."
echo ""

VALIDATOR_DIRS=()
VALIDATOR_ADDRS=()
BOOTNODE_URLS=()

for i in $(seq 1 "${NUM_VALIDATORS}"); do
    DIR="${DATA_DIR}/validator-${i}"

    if [[ -d "${DIR}/consensus" ]]; then
        warn "Validator ${i} keys already exist, skipping..."
    else
        mkdir -p "${DIR}"
        polygon-edge secrets init --data-dir "${DIR}" --json 2>/dev/null | tee "${DIR}/secrets.json"
    fi

    VALIDATOR_DIRS+=("${DIR}")

    # Extract address and node ID from secrets
    if [[ -f "${DIR}/secrets.json" ]]; then
        ADDR=$(cat "${DIR}/secrets.json" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['address'])" 2>/dev/null || echo "")
        NODE_ID=$(cat "${DIR}/secrets.json" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['node_id'])" 2>/dev/null || echo "")
    else
        # Try extracting from existing key files
        ADDR=$(polygon-edge secrets output --data-dir "${DIR}" 2>/dev/null | grep "Public key (address)" | awk '{print $NF}' || echo "")
        NODE_ID=$(polygon-edge secrets output --data-dir "${DIR}" 2>/dev/null | grep "Node ID" | awk '{print $NF}' || echo "")
    fi

    if [[ -z "${ADDR}" ]]; then
        err "Failed to get address for validator ${i}"
        exit 1
    fi

    VALIDATOR_ADDRS+=("${ADDR}")

    # Build bootnode URL (for docker internal network)
    # Port: 10001 for all validators (each in own container)
    if [[ -n "${NODE_ID}" ]]; then
        BOOTNODE_URLS+=("/ip4/tpix-validator-${i}/tcp/10001/p2p/${NODE_ID}")
    fi

    echo -e "  ${CYAN}Validator ${i}:${NC}"
    echo -e "    Address:  ${ADDR}"
    echo -e "    Node ID:  ${NODE_ID:-unknown}"
    echo -e "    Data Dir: ${DIR}"
    echo ""
done

log "Generated ${#VALIDATOR_ADDRS[@]} validator keys"
echo ""

# ─── Step 2: Generate Genesis ─────────────────────────────────
log "Step 2/4 — Generating genesis.json with IBFT2 consensus..."

# Build premine args (7 Billion TPIX total, 18 decimals)
# Using Polygon Edge format: --premine address:amount
PREMINE_ARGS=""

# Team & Advisors — 20% (1.4B TPIX)
PREMINE_ARGS+=" --premine 0x0000000000000000000000000000000000001001:1400000000000000000000000000"
# Development — 10% (700M TPIX)
PREMINE_ARGS+=" --premine 0x0000000000000000000000000000000000001002:700000000000000000000000000"
# Liquidity Pool — 30% (2.1B TPIX)
PREMINE_ARGS+=" --premine 0x0000000000000000000000000000000000001003:2100000000000000000000000000"
# Staking Rewards — 20% (1.4B TPIX)
PREMINE_ARGS+=" --premine 0x0000000000000000000000000000000000001004:1400000000000000000000000000"
# Ecosystem Fund — 10% (700M TPIX)
PREMINE_ARGS+=" --premine 0x0000000000000000000000000000000000001005:700000000000000000000000000"
# Public Sale (ICO) — 10% (700M TPIX)
PREMINE_ARGS+=" --premine 0x0000000000000000000000000000000000001006:700000000000000000000000000"

# Also premine small amounts to validators for gas (0 gas chain, but good practice)
for addr in "${VALIDATOR_ADDRS[@]}"; do
    PREMINE_ARGS+=" --premine ${addr}:1000000000000000000000"  # 1000 TPIX each
done

# Build bootnode args
BOOTNODE_ARGS=""
for bn in "${BOOTNODE_URLS[@]}"; do
    BOOTNODE_ARGS+=" --bootnode ${bn}"
done

# Generate genesis
polygon-edge genesis \
    --consensus ibft \
    --ibft-validators-prefix-path "${DATA_DIR}/validator-" \
    --chain-id "${CHAIN_ID}" \
    --block-gas-limit "${BLOCK_GAS_TARGET}" \
    --epoch-size "${EPOCH_LENGTH}" \
    --block-time "${BLOCK_TIME}s" \
    --max-validator-count 21 \
    --min-validator-count 1 \
    --price-limit 0 \
    ${BOOTNODE_ARGS} \
    ${PREMINE_ARGS} \
    --dir "${GENESIS_OUT}"

log "Genesis created: ${GENESIS_OUT}"
echo ""

# ─── Step 3: Display Summary ─────────────────────────────────
log "Step 3/4 — Chain Configuration Summary"
echo ""
echo -e "  ${CYAN}Chain:${NC}         TPIX Chain"
echo -e "  ${CYAN}Chain ID:${NC}      ${CHAIN_ID}"
echo -e "  ${CYAN}Consensus:${NC}     IBFT 2.0 (PoA)"
echo -e "  ${CYAN}Block Time:${NC}    ${BLOCK_TIME}s"
echo -e "  ${CYAN}Epoch Length:${NC}  ${EPOCH_LENGTH} blocks"
echo -e "  ${CYAN}Gas Price:${NC}     0 (free transactions)"
echo -e "  ${CYAN}Gas Limit:${NC}     ${BLOCK_GAS_TARGET}"
echo -e "  ${CYAN}Total Supply:${NC}  7,000,000,000 TPIX"
echo ""
echo -e "  ${CYAN}Validators:${NC}"
for i in $(seq 0 $((${#VALIDATOR_ADDRS[@]} - 1))); do
    echo -e "    ${GREEN}[$((i+1))]${NC} ${VALIDATOR_ADDRS[$i]}"
done
echo ""
echo -e "  ${CYAN}Bootnodes:${NC}"
for bn in "${BOOTNODE_URLS[@]}"; do
    echo -e "    ${bn}"
done
echo ""

# IBFT fault tolerance
F=$(( (${#VALIDATOR_ADDRS[@]} - 1) / 3 ))
echo -e "  ${CYAN}IBFT Fault Tolerance:${NC} ${F} node(s) can fail"
echo -e "  ${CYAN}Min for Consensus:${NC}    $((${#VALIDATOR_ADDRS[@]} - F)) of ${#VALIDATOR_ADDRS[@]} validators"
echo ""

# ─── Step 4: Save Bootnode Config ─────────────────────────────
log "Step 4/4 — Saving configuration files..."

# Save validator addresses
cat > "${DATA_DIR}/validators.json" << EOF
{
    "chainId": ${CHAIN_ID},
    "validators": [
$(for i in $(seq 0 $((${#VALIDATOR_ADDRS[@]} - 1))); do
    COMMA=""
    if [[ $i -lt $((${#VALIDATOR_ADDRS[@]} - 1)) ]]; then COMMA=","; fi
    echo "        { \"id\": $((i+1)), \"address\": \"${VALIDATOR_ADDRS[$i]}\" }${COMMA}"
done)
    ],
    "bootnodes": [
$(for i in $(seq 0 $((${#BOOTNODE_URLS[@]} - 1))); do
    COMMA=""
    if [[ $i -lt $((${#BOOTNODE_URLS[@]} - 1)) ]]; then COMMA=","; fi
    echo "        \"${BOOTNODE_URLS[$i]}\"${COMMA}"
done)
    ]
}
EOF

log "Validator config saved: ${DATA_DIR}/validators.json"
echo ""

# ─── Done ─────────────────────────────────────────────────────
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  TPIX Chain genesis setup complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo "Next steps:"
echo "  1. Copy validator data to each node:"
echo "     scp -r data/validator-1/ server1:/data/"
echo "     scp -r data/validator-2/ server2:/data/"
echo ""
echo "  2. Start the chain:"
echo "     docker-compose up -d"
echo ""
echo "  3. Verify chain is producing blocks:"
echo "     curl -s http://localhost:8545 -X POST \\"
echo "       -H 'Content-Type: application/json' \\"
echo "       -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
echo ""
echo "  4. Check validators:"
echo "     curl -s http://localhost:8545 -X POST \\"
echo "       -H 'Content-Type: application/json' \\"
echo "       -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"latest\",false],\"id\":1}'"
echo ""
