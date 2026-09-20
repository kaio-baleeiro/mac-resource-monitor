#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

swift build -c release --product MacResourceMonitorMCP
BIN_PATH="$(swift build --show-bin-path --configuration release)/MacResourceMonitorMCP"
OUTPUT_PATH="$PROJECT_DIR/dist/mac-resource-monitor-mcp"

mkdir -p "$PROJECT_DIR/dist"
cp "$BIN_PATH" "$OUTPUT_PATH"
chmod +x "$OUTPUT_PATH"
echo "$OUTPUT_PATH"
