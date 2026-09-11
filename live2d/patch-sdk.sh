#!/usr/bin/env bash
# Re-apply every Arisu edit to the Cubism SDK tree.
#
# The SDK is gitignored (licence-gated, ~200 MB), so nothing inside it survives
# re-unpacking the zip. Every edit we make in there lives in `glue/` instead and
# is applied by this script. Run it after unpacking a fresh SDK -- or any time
# the demo behaves like a stock sample.
#
# Idempotent AND updatable: inserted blocks are wrapped in sentinel comments and
# replaced wholesale on a re-run. An earlier version of this script tested for a
# single marker string instead, which quietly skipped the whole block whenever a
# later edit added something to it. That cost two debugging rounds, both of which
# looked like the new code simply not loading.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEMO="$HERE/CubismSdkForWeb/Samples/TypeScript/Demo"
GLUE="$HERE/glue"

if [ ! -d "$DEMO" ]; then
  echo "error: no SDK at $DEMO -- unpack CubismSdkForWeb there first" >&2
  exit 1
fi

# vite config: allowedHosts for the tailscale proxy, plus the preview block.
# Without allowedHosts the iPad gets a bare 403 on every file.
cp "$GLUE/vite.config.mts" "$DEMO/vite.config.mts"
echo "  vite.config.mts   <- glue"

# Arisu's own scripts, served from public/ so the built dist carries them.
cp "$GLUE"/arisu-*.js "$DEMO/public/"
echo "  public/arisu-*.js <- glue"

python3 - "$DEMO" <<'PY'
import sys, pathlib, re

demo = pathlib.Path(sys.argv[1])

def apply(relpath, open_s, close_s, body, anchor):
    """Replace between sentinels if present, else insert the block above anchor."""
    p = demo / relpath
    src = p.read_text()
    block = f"{open_s}\n{body}{close_s}\n"
    if open_s in src and close_s in src:
        new = re.sub(re.escape(open_s) + r".*?" + re.escape(close_s) + r"\n?",
                     block, src, count=1, flags=re.S)
        verb = "updated"
    else:
        if anchor not in src:
            raise SystemExit(f"error: anchor not found in {relpath} -- the SDK "
                             f"changed, re-derive this patch by hand")
        new = src.replace(anchor, block + anchor, 1)
        verb = "patched"
    if new == src:
        verb = "unchanged"
    p.write_text(new)
    print(f"  {relpath:<20} {verb}")


# Load Arisu's scripts before the module bundle. Classic scripts, so they are
# ready before any module code runs.
apply(
    "index.html",
    "  <!-- >>> arisu -->",
    "  <!-- <<< arisu -->",
    '  <script src = "./arisu-lipsync.js"></script>\n'
    '  <script src = "./arisu-face.js"></script>\n'
    '  <script src = "./arisu-avatar.js"></script>\n'
    '  <script src = "./arisu-harness.js"></script>\n',
    "  <!-- Build script -->",
)

# The per-frame hook. It runs after the SDK's own updaters, so it overrides
# CubismLipSyncUpdater -- which sits at 0 anyway, because nothing here plays a
# wav through the wav handler -- and wins over the blink updater when asleep.
apply(
    "src/lappmodel.ts",
    "    // >>> arisu",
    "    // <<< arisu",
    "    // Lip sync. One amplitude, applied to every LipSync parameter the model\n"
    "    // declares. value() advances its own smoothing, so it must be called\n"
    "    // exactly once per frame -- here, and nowhere else.\n"
    "    const arisuLipSync = (window as any).ArisuLipSync;\n"
    "    if (arisuLipSync && this._lipSyncIds.length > 0) {\n"
    "      const mouth: number = arisuLipSync.value();\n"
    "      (window as any).__arisuMouth = mouth;\n"
    "      for (let i = 0; i < this._lipSyncIds.length; ++i) {\n"
    "        this._model.setParameterValueById(this._lipSyncIds[i], mouth, 1.0);\n"
    "      }\n"
    "    }\n"
    "\n"
    "    // Face state: an expression when it changes, and the eyes held shut\n"
    "    // while she is asleep. Also after the scheduler, so it wins over the\n"
    "    // blink updater rather than fighting it frame by frame.\n"
    "    const arisuFace = (window as any).ArisuFace;\n"
    "    if (arisuFace) {\n"
    "      const pendingExpression: string = arisuFace.takePendingExpression();\n"
    "      if (pendingExpression) {\n"
    "        this.setExpression(pendingExpression);\n"
    "      }\n"
    "      const eyes: number | null = arisuFace.eyeOverride();\n"
    "      if (eyes !== null) {\n"
    "        for (let i = 0; i < this._eyeBlinkIds.length; ++i) {\n"
    "          this._model.setParameterValueById(this._eyeBlinkIds[i], eyes, 1.0);\n"
    "        }\n"
    "      }\n"
    "    }\n"
    "\n"
    "    // Read-only probe. There is no other way to see what the rig is doing:\n"
    "    // the model lives in module scope, and pixel-watching the eyes to find\n"
    "    // out whether blink is running is guesswork.\n"
    "    (window as any).__arisuParam = (id: string): number =>\n"
    "      this._model.getParameterValueById(\n"
    "        CubismFramework.getIdManager().getId(id)\n"
    "      );\n",
    "    this._model.update();",
)

# Natori first. It is the only sample clearing the whole checklist:
# ParamMouthOpenY, ParamMouthForm, eye blink, physics, pose, 11 expressions.
# Haru -- the stock default -- is the fallback. See LIVE2D.md for the audit.
d = demo / "src/lappdefine.ts"
src = d.read_text()
if "'Natori',\n  'Haru'" in src:
    print("  src/lappdefine.ts    unchanged")
else:
    old = ("export const ModelDir: string[] = [\n"
           "  'Haru',\n  'Hiyori',\n  'Mark',\n  'Natori',\n"
           "  'Rice',\n  'Mao',\n  'Wanko',\n  'Ren'\n];")
    new = ("export const ModelDir: string[] = [\n"
           "  'Natori',\n  'Haru',\n  'Hiyori',\n  'Mark',\n"
           "  'Rice',\n  'Mao',\n  'Wanko',\n  'Ren'\n];")
    if old not in src:
        raise SystemExit("error: ModelDir not in the expected shape")
    d.write_text(src.replace(old, new, 1))
    print("  src/lappdefine.ts    patched")
PY

echo
echo "done. build and serve with:"
echo "  cd $DEMO && npm run build:prod && npx vite preview --port 5001 --strictPort --host"
