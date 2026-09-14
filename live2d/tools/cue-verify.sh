#!/usr/bin/env bash
# That Arisu's state cue actually reaches the screen, checked in a real browser.
#
# Usage: cue-verify.sh [base-url]
#   default base: http://127.0.0.1:8899
#
# Needs the threaded rig server on the lain tree:
#   python3 tools/serve.py 8899 /path/to/lain
#
# What this is for, and what it is not: lain/tests/test_state_cues.js checks the
# decisions -- colours, labels, which state wins -- with no browser at all. This
# checks the half a Node test cannot see: that the light layer has a size and a
# gradient, and that a state's class lands on it. "The variable is set" and
# "there is a light on the screen" are different claims.
#
# It walks each state through the page's own window.__setState, which is the
# function a real event calls a moment later. The alternative is a live realtime
# session and a microphone per state, and a bill.
#
# The harness is its own file, harness.js, next to this one. It began as a
# heredoc in here and collected three separate quoting failures: an apostrophe in
# JavaScript closing a python -c, a sentinel element that read_run.sh silently ate
# (read -d '' stops at the first NUL and drops the rest), and a line-based cases
# file that cut the script at its first newline. A file has none of those
# problems.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="${1:-http://127.0.0.1:8899}"

# Where the client page actually is under this base, rather than assuming. The
# vendored face is reachable as both /arisu/ (doc root lain) and / (doc root
# lain/arisu), and hard-coding the wrong one measures an error page -- which has
# happened here twice.
CLIENT=""
for cand in "$BASE/arisu/" "$BASE/"; do
  if [ "$(curl -s -o /dev/null -w '%{http_code}' "$cand")" = "200" ]; then
    CLIENT="$cand"; break
  fi
done
if [ -z "$CLIENT" ]; then
  echo "error: no client page under $BASE (tried /arisu/ and /)" >&2
  echo "       serve the lain repo root: python3 tools/serve.py 8899 /path/to/lain" >&2
  exit 2
fi

if [ ! -f "$HERE/harness.js" ]; then
  echo "error: no harness.js beside this script" >&2
  exit 2
fi

RESULT="$(mktemp -t arisu-cue)"
trap 'rm -f "$RESULT" "$RESULT.cases"' EXIT

echo "Arisu state-cue DOM verification against $CLIENT"
echo

# Two cases. The first walks the states and measures the halo; the second drives
# the Glow sliders in the settings sheet. Both on the client page, which owns the
# sheet and puts the face in an iframe.
#
# JSON cases, built by python from the harness files: a case is {url, inject} and
# inject is a script, so the file cannot be one case per line.
CLIENT="$CLIENT" HARNESS_DIR="$HERE" python3 -c 'import json, os, io
d = os.environ["HARNESS_DIR"]
print(json.dumps([
    {"name": "state cues", "url": os.environ["CLIENT"],
     "inject": io.open(os.path.join(d, "harness.js")).read()},
    {"name": "glow controls", "url": os.environ["CLIENT"],
     "inject": io.open(os.path.join(d, "harness-glow.js")).read()},
]))' > "$RESULT.cases"

# 25s per case, not 8: openSettings() fetches the character before the panel
# draws, and on this rig that fetch is a 404 with a retry behind it. At 8s the
# probe gave up before the controls existed and reported no snapshots for a
# harness that was about to produce six.
node "$HERE/live2d-probe.mjs" --batch "$RESULT.cases" 25000 > "$RESULT.json" 2>/dev/null

# Two verdicts over the two result lines, and the exit status is the sum: a
# failure in either has to fail the run, or the half nobody looks at is the half
# that rots.
python3 "$HERE/cue-verdict.py" "$RESULT.json"
cues=$?
python3 "$HERE/glow-controls-verdict.py" "$RESULT.json"
glow=$?
exit $((cues + glow))
