#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release --product DNSLeakGuard
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$ROOT/dist/DNSLeakGuard.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 755 "$BIN_DIR/DNSLeakGuard" "$APP/Contents/MacOS/DNSLeakGuard"
install -m 644 "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
    ICONSET="$ROOT/.build/AppIcon.iconset"
    swift "$ROOT/Tools/GenerateIcon.swift" "$ICONSET"
    iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
fi

install -m 644 "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null
touch "$APP"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
fi

echo "$APP"
