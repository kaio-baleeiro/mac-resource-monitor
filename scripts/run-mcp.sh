#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MCP_BINARY="$PROJECT_DIR/dist/mac-resource-monitor-mcp"

if [[ ! -x "$MCP_BINARY" ]]; then
    echo "MCP binary not found. Run ./scripts/build-mcp.sh first." >&2
    exit 1
fi

exec "$MCP_BINARY"
