#!/usr/bin/env bash
# Rebuild the Live2D bundle and vendor it into lain, in one step.
#
# The two halves are not optional and not independent: `patch-sdk.sh` applies
# glue/ into the (gitignored) SDK tree, `vite build` bundles it, and the result
# has to be copied into lain/arisu/live2d/ where the desk actually serves it.
# Doing them by hand is how a stale arisu-scene.js ends up being what gets
# verified -- which happened, and cost a full verification run that failed for a
# reason that had nothing to do with the code under test.
#
# Usage: ./revendor.sh [path-to-lain]
#
# Nothing is committed and nothing is deployed. This only makes the working tree
# in lain match the arisu source, ready to test and then to push.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LAIN="${1:-$HERE/../../lain}"
DIST="$HERE/CubismSdkForWeb/Samples/TypeScript/Demo/dist"
DEST="$LAIN/arisu/live2d"

if [ ! -d "$HERE/CubismSdkForWeb/Samples/TypeScript/Demo" ]; then
  echo "error: no SDK tree -- unpack CubismSdkForWeb under live2d/ first" >&2
  exit 1
fi
if [ ! -d "$DEST" ]; then
  echo "error: no vendored copy at $DEST" >&2
  exit 1
fi

echo "1. patch"
"$HERE/patch-sdk.sh"

echo
echo "2. build"
( cd "$HERE/CubismSdkForWeb/Samples/TypeScript/Demo" && npm run build:prod )

echo
echo "3. vendor -> $DEST"

# index.html carries the script tags and the bundle hash, so it is copied whole.
cp "$DIST/index.html" "$DEST/index.html"

# The glue, as the build left it. Copied wholesale rather than name by name so a
# new arisu-*.js cannot be silently left behind.
cp "$DIST"/arisu-*.js "$DEST/"

# The hashed bundle. The old hash is removed rather than left to rot -- two
# bundles in the tree is a page loading one and you reading the other.
BUNDLE="$(cd "$DIST/assets" && ls index-*.js)"
cp "$DIST/assets/$BUNDLE" "$DEST/assets/"
find "$DEST/assets" -name 'index-*.js' ! -name "$BUNDLE" -delete

echo "      $BUNDLE"

# A vendored copy that disagrees with itself is the failure this script exists to
# prevent, so check the one thing that links the two: the page must reference the
# bundle that is actually there.
REF="$(grep -o 'assets/index-[A-Za-z0-9_-]*\.js' "$DEST/index.html" | head -1)"
if [ "$REF" != "assets/$BUNDLE" ]; then
  echo "error: index.html references $REF but $BUNDLE was vendored" >&2
  exit 1
fi
echo "      index.html -> $REF  (matches)"

# And that every glue file the page loads is present.
missing=0
for f in $(grep -o 'src = "\./arisu-[a-z-]*\.js"' "$DEST/index.html" | sed 's/.*"\.\///; s/"//'); do
  if [ ! -f "$DEST/$f" ]; then
    echo "error: index.html loads $f, which is not in $DEST" >&2
    missing=1
  fi
done
[ "$missing" = 0 ] || exit 1

echo
echo "vendored. verify with:"
echo "  cd $LAIN/arisu && python3 -m http.server 8899 --bind 127.0.0.1 &"
echo "  $HERE/tools/live2d-verify.sh"
