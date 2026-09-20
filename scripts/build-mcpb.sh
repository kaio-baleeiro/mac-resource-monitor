#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

swift build -c release --product MacResourceMonitorMCP
BIN_PATH="$(swift build --show-bin-path --configuration release)/MacResourceMonitorMCP"
OUTPUT_PATH="$PROJECT_DIR/dist/mac-resource-monitor.mcpb"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

mkdir -p "$TEMP_DIR/server" "$PROJECT_DIR/dist"
cp "$PROJECT_DIR/Resources/mcpb-manifest.json" "$TEMP_DIR/manifest.json"
cp "$BIN_PATH" "$TEMP_DIR/server/mac-resource-monitor-mcp"
chmod +x "$TEMP_DIR/server/mac-resource-monitor-mcp"

rm -f "$OUTPUT_PATH"
(cd "$TEMP_DIR" && zip -q -r "$OUTPUT_PATH" manifest.json server)
echo "$OUTPUT_PATH"
