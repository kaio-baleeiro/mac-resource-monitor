#!/bin/zsh
set -euo pipefail

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/local.macresourcemonitor.plist"
USER_ID="$(id -u)"

/bin/launchctl bootout "gui/$USER_ID" "$PLIST_PATH" 2>/dev/null || true
rm -f "$PLIST_PATH"

echo "Inicialização automática removida."
