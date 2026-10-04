#!/bin/zsh
# Build "Arisu Canvas.app" next to this script.
#
# A bundle rather than the bare binary, because a loose executable gets the
# wrong focus behaviour and no stable identity: macOS keys window position,
# UserDefaults and (one day) notification permission off the bundle id. Ad-hoc
# signed, which is enough to run it here -- nothing is distributed.
set -e
cd "$(dirname "$0")"

APP="Arisu Canvas.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Her face is compiled from the iPad app's own sources, not a copy of them:
# two apps drawing her must never be two different drawings.
swiftc -O main.swift \
  ../native/Arisu/VoiceVisual.swift ../native/Arisu/Skin.swift \
  -o "$APP/Contents/MacOS/ArisuCanvas"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Arisu Canvas</string>
  <key>CFBundleIdentifier</key><string>com.oscar.arisu-canvas</string>
  <key>CFBundleExecutable</key><string>ArisuCanvas</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <!-- No Dock icon: these are widgets, not an app he switches to. -->
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $PWD/$APP"

# Installed outside ~/Documents on purpose: macOS TCC refuses a launchd agent
# access to Documents, so an app left in the checkout starts at login and then
# cannot read itself. ~/Applications is where MacropadType.app and
# ArisuMeter.app already live for the same reason.
if [ "$1" = "install" ]; then
  rm -rf ~/Applications/"$APP"
  cp -R "$APP" ~/Applications/
  echo "installed ~/Applications/$APP"
fi
