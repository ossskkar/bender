#!/usr/bin/env bash
# Every claim about the Live2D scene, checked in a real browser.
#
# Usage: live2d-verify.sh [base-url]
#   default base: http://127.0.0.1:8899
#
# Needs the threaded rig server on the lain tree:
#   python3 tools/serve.py 8899 /path/to/lain
#
# One Chrome runs every case -- see the note in live2d-probe.mjs about why a
# browser per case poisons the run. The exit status is the number of failures.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="${1:-http://127.0.0.1:8899}"

# Where the face page actually is under this base, rather than assuming.
#
# The vendored face lives at `arisu/live2d/` in the lain repo, so it is reachable
# as both `/live2d/` (doc root lain/arisu) and `/arisu/live2d/` (doc root lain).
# Hard-coding the first and serving the second meant every case 404'd the face
# page and reported "no model canvas" -- a green-looking rig measuring error
# pages. It happened twice: once here, once with the parent page. So: ask.
PAGE=""
for cand in "$BASE/arisu/live2d/index.html" "$BASE/live2d/index.html"; do
  if [ "$(curl -s -o /dev/null -w '%{http_code}' "$cand")" = "200" ]; then
    PAGE="$cand"; break
  fi
done
if [ -z "$PAGE" ]; then
  echo "error: no face page under $BASE (tried /arisu/live2d/ and /live2d/)" >&2
  echo "       serve the lain repo root:  python3 tools/serve.py 8899 /path/to/lain" >&2
  exit 2
fi
FACE_DIR="${PAGE%/index.html}"
BASE_DIR="${FACE_DIR%/live2d}"
PARENT="$BASE_DIR/"

CASES="$(mktemp -t arisu-cases)"
RESULTS="$(mktemp -t arisu-results)"
trap 'rm -f "$CASES" "$RESULTS"' EXIT

# add <name> <url> [preset-js] [check]
#
# The name, the url and the check go in one line, tab separated. The check is
# last because it is the only field that contains tabs never and quotes often.
# The check file stays line-based (name, url, check -- no newlines in any of
# them). The probe's case file is JSON, because `inject` is a script and a script
# has newlines: see the note in live2d-probe.mjs about a harness silently cut in
# half at its first newline.
add() {
  local name="$1" url="$2" preset="${3:-}" check="${4:?a case needs a check}"
  printf '%s\t%s\t%s\n' "$name" "$url" "$check" >> "$CASES"
  NAME="$name" URL="$url" INJECT="$preset" python3 -c '
import json, os, sys
print(json.dumps({"name": os.environ["NAME"], "url": os.environ["URL"],
                  "inject": os.environ["INJECT"] or None}))
' >> "$RESULTS.cases"
}
: > "$CASES"
: > "$RESULTS.cases"

# ---------------------------------------------------------------- the cases
#
# The checks run with NO builtins at all -- not even len(). Indexing works, and
# an empty list is falsy, so `frames and frames[0][...]` is the idiom here. The
# frame check has now failed twice as a name error (bool, then len) rather than
# as a wrong answer, which is a confusing way to lose an afternoon.
#
# None of the checks below may index model["lit"] directly: a model that has not
# drawn returns no "lit" key at all, and a KeyError reads as a broken test rather
# than a broken model. It cost two rounds of confusion; assert on it, do not
# assume it.

add "default is a gradient room" "$PAGE?model=Natori&probe=1" "" \
  'scene["mode"]=="gradient" and scene["room"]==[6,8,12] and scene["spread"]>0 and model["lit"]>0'
add "room colour is honoured" "$PAGE?model=Natori&room=4a2f6b&probe=1" "" \
  'scene["room"]==[74,47,107] and scene["spread"]>40'
add "a dark room gives a dark gradient" "$PAGE?model=Natori&probe=1" "" \
  'scene["room"]==[6,8,12] and 0<scene["spread"]<20 and model["lit"]>0'
add "depth 0 is a flat wall" "$PAGE?model=Natori&room=4a2f6b&depth=0&probe=1" "" \
  'scene["mode"]=="gradient" and scene["spread"]<12 and model["lit"]>0'
add "flat mode fills one colour" "$PAGE?model=Natori&bg=flat&room=2a4a2a&probe=1" "" \
  'scene["mode"]=="flat" and scene["spread"]<12'
add "classroom image loads and is painted" "$PAGE?model=Natori&bg=classroom&room=4a2f6b&probe=1" "" \
  'scene["mode"]=="image" and paint["failed"]==False and paint["hasImage"]==True and paint["natural"]==[512,512] and 20<scene["spread"]<115 and model["lit"]>0'
add "an image paints over the gradient, not instead of it" "$PAGE?model=Natori&bg=classroom&room=4a2f6b&probe=1" "" \
  'scene["mode"]=="image" and paint["hasImage"]==True and scene["spread"]!=122'
add "missing image falls back to gradient" "$PAGE?model=Natori&bg=images/nope.png&room=4a2f6b&probe=1" "" \
  'scene["mode"]=="image" and scene["failed"]==True and scene["spread"]>100 and model["lit"]>0'
add "bg=off leaves no background" "$PAGE?model=Natori&bg=off&probe=1" "" \
  'scene["mode"]=="none"'
add "default scale 1 matches stock framing" "$PAGE?model=Natori&probe=1" "" \
  'scene["display"]=={"scale":1.0,"x":0.0,"y":0.0} and 0.25<model["width"]<0.45'
# A bigger model is measured by lit pixels, not by bounding-box width: at 1.5
# the model is taller than the canvas and gets cropped, so its width stops
# growing while its area nearly doubles (85k -> 161k lit). Asserting on width
# called a working 1.5 "not enlarged".
add "scale 1.5 enlarges the model" "$PAGE?model=Natori&scale=1.5&probe=1" "" \
  'scene["display"]["scale"]==1.5 and model["lit"]>120000'
add "scale 0.6 shrinks the model" "$PAGE?model=Natori&scale=0.6&probe=1" "" \
  'scene["display"]["scale"]==0.6 and model["width"]<0.25'
add "y -0.12 moves the model down" "$PAGE?model=Natori&y=-0.12&probe=1" "" \
  'scene["display"]["y"]==-0.12 and model["centre"]["y"]>0.56'
add "stock Natori table" "$PAGE?model=Natori&probe=1" "" \
  'probe["states"]=={"idle":None,"listening":"exp_02","thinking":"exp_04","speaking":"Normal","asleep":"exp_05"}'
add "default model is Natori" "$PAGE?probe=1" "" \
  'probe["model"]=="Natori"'
add "another rig loads with its own table" "$PAGE?model=Mao&probe=1" "" \
  'probe["model"]=="Mao" and probe["states"]["thinking"]=="exp_05"'
add "a host override replaces one state" "$PAGE?model=Natori&probe=1" \
  '{"expressions":{"Natori":{"states":{"listening":"exp_01"}}}}' \
  'probe["states"]["listening"]=="exp_01" and probe["states"]["thinking"]=="exp_04"'
add "the parent page relays the scene to the face iframe" \
  "$PARENT?face=live2d&model=Haru&bg=classroom&room=4a2f6b&scale=1.3" "" \
  'frames and frames[0]["scene"]["mode"]=="image" and frames[0]["scene"]["room"]==[74,47,107] and frames[0]["scene"]["display"]["scale"]==1.3 and frames[0]["scene"]["model"]=="Haru"'

# The room has to be one colour on both sides of the iframe boundary, or the
# model reads as a picture pasted on a card. This asserts the page's own ground,
# which the iframe knows nothing about.
add "the parent page's own ground takes the room colour" \
  "$PARENT?face=live2d&model=Haru&bg=classroom&room=4a2f6b&scale=1.3" "" \
  'ground["ground"] and ground["hasRoomClass"]==True and ground["roomVar"]=="74, 47, 107"'

echo "Live2D scene verification against $BASE"
echo

# The probe exits non-zero if any case did not render, and that is information
# rather than failure -- a case that expected no model still counts. The verdicts
# are what decide, so the probe's status is deliberately not checked here.
node "$HERE/live2d-probe.mjs" --batch "$RESULTS.cases" 6000 > "$RESULTS.json" 2>/dev/null

# Through a file, not a pipe: a while loop on the right of a pipe runs in a
# subshell, so its counters would be gone by the time the summary printed. That
# failure mode is a report that always says zero, which is worse than no report.
python3 "$HERE/probe-verdict.py" "$CASES" "$RESULTS.json" > "$RESULTS.verdicts"

pass=0
fail=0
while IFS=$'\t' read -r tag name detail; do
  [ -n "${tag:-}" ] || continue
  if [ "$tag" = "PASS" ]; then
    pass=$((pass + 1)); printf '  ok   %-52s %s\n' "$name" "$detail"
  else
    fail=$((fail + 1)); printf '  FAIL %-52s %s\n' "$name" "$detail"
  fi
done < "$RESULTS.verdicts"

echo
echo "-----------------------------------------------"
printf '  %d passed, %d failed\n' "$pass" "$fail"
exit "$fail"
