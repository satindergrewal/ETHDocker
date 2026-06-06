#!/bin/bash
# Quick RPC health check — verifies Geth and Lighthouse are responding
set -euo pipefail

echo "=== ETH Docker RPC Health Check ==="
echo ""

# Geth JSON-RPC
echo -n "Geth RPC (8545):      "
RESULT=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://127.0.0.1:8545 2>/dev/null)
if [ -n "$RESULT" ]; then
    BLOCK=$(echo "$RESULT" | python3 -c "import sys,json; print(int(json.load(sys.stdin)['result'],16))" 2>/dev/null || echo "error")
    echo "OK (block $BLOCK)"
else
    echo "FAILED (no response)"
fi

# Geth WebSocket
echo -n "Geth WS (8546):       "
if command -v websocat >/dev/null 2>&1; then
    WS_RESULT=$(echo '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | websocat ws://127.0.0.1:8546 2>/dev/null)
    [ -n "$WS_RESULT" ] && echo "OK" || echo "FAILED"
else
    echo "SKIP (websocat not installed)"
fi

# Lighthouse Beacon API
echo -n "Lighthouse API (5052): "
SYNC=$(curl -s http://127.0.0.1:5052/eth/v1/node/syncing 2>/dev/null)
if [ -n "$SYNC" ]; then
    IS_SYNCING=$(echo "$SYNC" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['is_syncing'])" 2>/dev/null || echo "unknown")
    echo "OK (syncing: $IS_SYNCING)"
else
    echo "FAILED (no response)"
fi

echo ""
echo "Metamask: http://127.0.0.1:8545 | Chain ID: 1"
