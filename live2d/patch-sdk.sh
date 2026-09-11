#!/usr/bin/env bash
# Re-apply every Arisu edit to the Cubism SDK tree.
#
# The SDK is gitignored (licence-gated, ~200 MB), so nothing inside it survives
# re-unpacking the zip. Every edit we make in there lives in `glue/` instead and
# is applied by this script. Run it after unpacking a fresh SDK — or any time
# the demo behaves like a stock sample.
#
# Idempotent: safe to run repeatedly.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEMO="$HERE/CubismSdkForWeb/Samples/TypeScript/Demo"
GLUE="$HERE/glue"

if [ ! -d "$DEMO" ]; then
  echo "error: no SDK at $DEMO — unpack CubismSdkForWeb there first" >&2
  exit 1
fi

# 1. vite config: allowedHosts for the tailscale proxy, plus the preview block.
#    Without allowedHosts the iPad gets a bare 403 on every file.
cp "$GLUE/vite.config.mts" "$DEMO/vite.config.mts"
echo "  vite.config.mts  <- glue"

# 2. Arisu's own scripts, served from public/ so the built dist carries them.
cp "$GLUE/arisu-lipsync.js" "$GLUE/arisu-harness.js" "$DEMO/public/"
echo "  public/arisu-*.js <- glue"

python3 - "$DEMO" <<'PY'
import sys, pathlib

demo = pathlib.Path(sys.argv[1])

def patch(relpath, anchor, replacement, marker):
    p = demo / relpath
    src = p.read_text()
    if marker in src:
        print(f"  {relpath}  already patched")
        return
    if anchor not in src:
        raise SystemExit(f"error: anchor not found in {relpath} — SDK changed, "
                         f"re-derive the patch by hand")
    p.write_text(src.replace(anchor, replacement, 1))
    print(f"  {relpath}  patched")

# 3. Load the lip-sync module before the bundle. Classic scripts, so they are
#    ready before any module code runs.
patch(
    "index.html",
    '  <!-- Build script -->',
    '  <!-- Arisu lip-sync: amplitude source, and the throwaway test overlay -->\n'
    '  <script src = "./arisu-lipsync.js"></script>\n'
    '  <script src = "./arisu-harness.js"></script>\n'
    '  <!-- Build script -->',
    'arisu-lipsync.js',
)

# 4. The lip-sync hook itself. This runs after the SDK's own updaters, so it
#    overrides CubismLipSyncUpdater — which sits at 0 anyway, because nothing
#    here plays a wav through the wav handler.
patch(
    "src/lappmodel.ts",
    "    this._updateScheduler.onLateUpdate(this._model, deltaTimeSeconds);\n"
    "\n"
    "    this._model.update();",
    "    this._updateScheduler.onLateUpdate(this._model, deltaTimeSeconds);\n"
    "\n"
    "    // Arisu lip-sync. One amplitude, applied to every LipSync parameter the\n"
    "    // model declares. value() advances its own smoothing, so it must be\n"
    "    // called exactly once per frame -- here, and nowhere else.\n"
    "    const arisuLipSync = (window as any).ArisuLipSync;\n"
    "    if (arisuLipSync && this._lipSyncIds.length > 0) {\n"
    "      const mouth: number = arisuLipSync.value();\n"
    "      (window as any).__arisuMouth = mouth;\n"
    "      for (let i = 0; i < this._lipSyncIds.length; ++i) {\n"
    "        this._model.setParameterValueById(this._lipSyncIds[i], mouth, 1.0);\n"
    "      }\n"
    "    }\n"
    "\n"
    "    this._model.update();",
    "ArisuLipSync",
)

# 5. Natori first. It is the only sample clearing the whole checklist:
#    ParamMouthOpenY, ParamMouthForm, eye blink, physics, pose, 11 expressions.
#    Haru -- the stock default -- is the fallback. See LIVE2D.md for the audit.
d = demo / "src/lappdefine.ts"
src = d.read_text()
if "'Natori',\n  'Haru'" in src:
    print("  src/lappdefine.ts  already patched")
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
    print("  src/lappdefine.ts  patched")
PY

echo
echo "done. build and serve with:"
echo "  cd $DEMO && npm run build:prod && npx vite preview --port 5001 --strictPort --host"
