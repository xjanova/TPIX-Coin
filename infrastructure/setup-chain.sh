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
        BOOTNODE_URLS+=("/dns4/tpix-validator-${i}/tcp/10001/p2p/${NODE_ID}")
    fi

    log "Validator ${i}: ${ADDR} (node: ${NODE_ID:-unknown})"
done

echo ""
log "Generated ${#VALIDATOR_ADDRS[@]} validator keys"
echo ""

# ─── Step 2: Generate Genesis ─────────────────────────────────
log "Step 2/4 — Generating genesis.json with IBFT2 consensus..."

# ─── Allocation Addresses ────────────────────────────────────
# Derived from project HD wallet (BIP-44: m/44'/60'/0'/0/N)
# All pools are controlled by the same mnemonic, different derivation paths.
# See WHITEPAPER.md Section 6 (Tokenomics) for full details.
#
# Path  | Address                                    | Pool
# 0     | 0x0B263D083969946fA2bB44Af2debA69D3d3d0220 | Main Wallet (Reward Receiver)
# 1     | 0x2112b98e3ec5A252b7b2A8f02d498B64a2186A7f | Master Node Rewards
# 2     | 0xD2eAB07809921fcB36c7AB72D7B5D8D2C12A67d7 | Ecosystem Development
# 3     | 0xf46131C82819d7621163F482b3fe88a228A7807c | Team & Advisors
# 4     | 0x3F8EB4046F5C79fd0D67C7547B5830cB2Cfb401A | Token Sale
# 5     | 0x3da3776e0AB0F442c181aa031f47FA83696859AF | Liquidity & Market Making
# 6     | 0xA945d1bE9c1DDeaE75BBb9B39981D1CE6Ed7d9d5 | Community & Rewards

# Build premine args (7 Billion TPIX total, 18 decimals)
# Allocation per WHITEPAPER.md Tokenomics section:
#   Master Node Rewards:      1,400,000,000 TPIX (20.00%)
#   Ecosystem Development:    1,710,000,000 TPIX (24.43%) — reduced by 40M for validator stakes
#   Team & Advisors:            700,000,000 TPIX (10.00%)
#   Token Sale:                 700,000,000 TPIX (10.00%)
#   Liquidity & Market Making:1,050,000,000 TPIX (15.00%)
#   Community & Rewards:      1,400,000,000 TPIX (20.00%)
#   4x Validator Stakes:         40,000,000 TPIX ( 0.57%) — 10M each, funded from Ecosystem Dev
#   Total:                    7,000,000,000 TPIX (100%)

PREMINE_ARGS=""
# Pool 1: Master Node Rewards (20%) — m/44'/60'/0'/0/1
PREMINE_ARGS+=" --premine 0x2112b98e3ec5A252b7b2A8f02d498B64a2186A7f:1400000000000000000000000000"
# Pool 2: Ecosystem Development (24.43%) — m/44'/60'/0'/0/2 — originally 1,750M, minus 40M for validator stakes
PREMINE_ARGS+=" --premine 0xD2eAB07809921fcB36c7AB72D7B5D8D2C12A67d7:1710000000000000000000000000"
# Pool 3: Team & Advisors (10%) — m/44'/60'/0'/0/3
PREMINE_ARGS+=" --premine 0xf46131C82819d7621163F482b3fe88a228A7807c:700000000000000000000000000"
# Pool 4: Token Sale (10%) — m/44'/60'/0'/0/4
PREMINE_ARGS+=" --premine 0x3F8EB4046F5C79fd0D67C7547B5830cB2Cfb401A:700000000000000000000000000"
# Pool 5: Liquidity & Market Making (15%) — m/44'/60'/0'/0/5
PREMINE_ARGS+=" --premine 0x3da3776e0AB0F442c181aa031f47FA83696859AF:1050000000000000000000000000"
# Pool 6: Community & Rewards (20%) — m/44'/60'/0'/0/6
PREMINE_ARGS+=" --premine 0xA945d1bE9c1DDeaE75BBb9B39981D1CE6Ed7d9d5:1400000000000000000000000000"

# Premine 10,000,000 TPIX to each validator (Validator tier — highest tier)
# Funded from Ecosystem Development allocation (40M total)
for addr in "${VALIDATOR_ADDRS[@]}"; do
    PREMINE_ARGS+=" --premine ${addr}:10000000000000000000000000"
done

# Build bootnode args
BOOTNODE_ARGS=""
for bn in "${BOOTNODE_URLS[@]}"; do
    BOOTNODE_ARGS+=" --bootnode ${bn}"
done

# Generate genesis
# Flags verified against polygon-edge v0.9.0:
#   --ibft-validators-prefix-path (not --validators-prefix)
#   --ibft-validator-type bls
#   --price-limit is a server flag, not genesis — omit here
polygon-edge genesis \
    --consensus ibft \
    --ibft-validators-prefix-path "${DATA_DIR}/validator-" \
    --ibft-validator-type bls \
    --chain-id "${CHAIN_ID}" \
    --name "tpix-chain" \
    --block-gas-limit "${BLOCK_GAS_TARGET}" \
    --epoch-size "${EPOCH_LENGTH}" \
    --block-time "${BLOCK_TIME}s" \
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
