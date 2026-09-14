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

# JSON cases, built by python from the harness file: a case is {url, inject} and
# inject is a script, so the file cannot be one case per line.
CLIENT="$CLIENT" HARNESS_JS="$HERE/harness.js" python3 -c 'import json, os, io
print(json.dumps([{
    "name": "state cues",
    "url": os.environ["CLIENT"],
    "inject": io.open(os.environ["HARNESS_JS"]).read(),
}]))' > "$RESULT.cases"

node "$HERE/live2d-probe.mjs" --batch "$RESULT.cases" 8000 > "$RESULT.json" 2>/dev/null

python3 "$HERE/cue-verdict.py" "$RESULT.json"
