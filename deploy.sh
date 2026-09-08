#!/usr/bin/env bash
# Put the face on the desk Mac, next to the brain.
#
# GitHub Pages keeps serving the same file as a brainless pet -- that copy is
# `git push`, not this. This one exists because the brain (lain/server/arisu.py)
# answers relative URLs: served from the Mac at /arisu/ the face finds it and
# talks; served from Pages the same fetches 404 and it stays a pet.
#
# The phone opens https://oscars-macbook-pro.tailaa64e9.ts.net:8443/arisu/
#
#   ./deploy.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESK="$HOME/.voicemode/hud/arisu"

echo "→ desk ($DESK)"
mkdir -p "$DESK"
cp "$REPO/index.html" "$DESK/"
cp -R "$REPO/assets" "$DESK/"
echo "done — https://oscars-macbook-pro.tailaa64e9.ts.net:8443/arisu/"
