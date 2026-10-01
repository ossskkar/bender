#!/bin/sh
# Build ArisuMeter.app into ~/Applications, signed with his development
# identity so the audio-recording grant survives a rebuild.
set -e
here=$(cd "$(dirname "$0")" && pwd)
app="$HOME/Applications/ArisuMeter.app"
mkdir -p "$app/Contents/MacOS"
cp "$here/Info.plist" "$app/Contents/Info.plist"
swiftc -O "$here/main.swift" -o "$app/Contents/MacOS/ArisuMeter"
codesign --force --sign "Apple Development: ossskkar@gmail.com (QZZNU5ZQW2)" "$app"
echo "$app"
