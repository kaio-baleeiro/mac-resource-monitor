#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$PROJECT_DIR/dist/Monitoramento de Recursos.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/local.macresourcemonitor.plist"
USER_ID="$(id -u)"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Aplicativo não encontrado; compilando o app..."
    "$PROJECT_DIR/scripts/build-app.sh" >/dev/null
fi

mkdir -p "$LAUNCH_AGENTS_DIR"
cp "$PROJECT_DIR/Resources/local.macresourcemonitor.launchagent.plist" "$PLIST_PATH"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:2 $APP_PATH" "$PLIST_PATH"

/bin/launchctl bootout "gui/$USER_ID" "$PLIST_PATH" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$USER_ID" "$PLIST_PATH"
/bin/launchctl enable "gui/$USER_ID/local.macresourcemonitor"

echo "Inicialização automática instalada."
echo "LaunchAgent: $PLIST_PATH"
