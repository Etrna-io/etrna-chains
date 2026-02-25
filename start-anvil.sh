#!/usr/bin/env bash
# =============================================================================
# Etrna Chain Dev — Anvil Local Chain Launcher
# =============================================================================
# Usage: ./start-anvil.sh [fork]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT_DIR="$SCRIPT_DIR/snapshots"
mkdir -p "$SNAPSHOT_DIR"

if [ "$1" == "fork" ]; then
    echo ">> Starting Anvil with mainnet fork..."
    source ../docker/.env 2>/dev/null
    anvil \
        --fork-url "${FORK_RPC_URL:-https://eth-mainnet.g.alchemy.com/v2/demo}" \
        --fork-block-number 0 \
        --host 0.0.0.0 \
        --port 8545 \
        --accounts 10 \
        --balance 10000 \
        --block-time 1 \
        --state "$SNAPSHOT_DIR/fork-state.json"
else
    echo ">> Starting local Anvil chain..."
    anvil \
        --host 0.0.0.0 \
        --port 8545 \
        --accounts 10 \
        --balance 10000 \
        --block-time 1 \
        --state "$SNAPSHOT_DIR/local-state.json"
fi
