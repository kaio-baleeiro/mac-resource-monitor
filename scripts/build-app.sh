#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

swift build -c release --product MacResourceMonitor
BIN_PATH="$(swift build --show-bin-path --configuration release)/MacResourceMonitor"
APP_PATH="$PROJECT_DIR/dist/Monitoramento de Recursos.app"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH" "$APP_PATH/Contents/MacOS/MacResourceMonitor"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/MacResourceMonitorIcon.png" "$APP_PATH/Contents/Resources/MacResourceMonitorIcon.png"
cp "$PROJECT_DIR/Resources/MacResourceMonitorIcon.icns" "$APP_PATH/Contents/Resources/MacResourceMonitorIcon.icns"

codesign --force --deep --sign - "$APP_PATH" >/dev/null
echo "$APP_PATH"
