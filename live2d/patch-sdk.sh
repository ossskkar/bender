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

# Resources are fetched relative to the page. The stock '../../Resources/' only
# works because a browser clamps a path that climbs above the site root -- serve
# the page from a subdirectory and it resolves outside the bundle and 404s.
d = demo / "src/lappdefine.ts"
src = d.read_text()
if "export const ResourcesPath = './Resources/';" in src:
    print("  src/lappdefine.ts    resources unchanged")
else:
    old_rp = "export const ResourcesPath = '../../Resources/';"
    if old_rp not in src:
        raise SystemExit("error: ResourcesPath not in the expected shape")
    d.write_text(src.replace(old_rp, "export const ResourcesPath = './Resources/';", 1))
    print("  src/lappdefine.ts    resources patched")

# The demo declares its OWN shader path and passes it to setShaderPath, which
# overrides the Framework default -- so patching the Framework alone changes
# nothing. Both have to be relative.
src = d.read_text()
if "export const ShaderPath = './Framework/Shaders/WebGL/';" in src:
    print("  src/lappdefine.ts    shaders unchanged")
else:
    old_sh = "export const ShaderPath = '../../Framework/Shaders/WebGL/';"
    if old_sh not in src:
        raise SystemExit("error: ShaderPath not in the expected shape")
    d.write_text(src.replace(
        old_sh, "export const ShaderPath = './Framework/Shaders/WebGL/';", 1))
    print("  src/lappdefine.ts    shaders patched")

# The Framework fetches its WebGL shaders at runtime, from the same kind of
# climbing path as Resources. Same failure, and a nastier one: the renderer
# retries in a tight loop, so a subdirectory deploy produces hundreds of 404s
# per second while the model still appears to load.
f = demo.parent.parent.parent / "Framework/src/rendering/cubismshader_webgl.ts"
src = f.read_text()
if "this._defaultShaderPath = './Framework/Shaders/WebGL/';" in src:
    print("  Framework shaders    unchanged")
else:
    old_sp = "this._defaultShaderPath = '../../Framework/Shaders/WebGL/';"
    if old_sp not in src:
        raise SystemExit("error: _defaultShaderPath not in the expected shape")
    f.write_text(src.replace(
        old_sp, "this._defaultShaderPath = './Framework/Shaders/WebGL/';", 1))
    print("  Framework shaders    patched")

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

# No classroom behind her. The sample draws `back_class_normal.png` across the
# whole canvas; Arisu is a face on lain's own background, and a stock classroom
# under her is the single thing that gives away where she came from.
#
# The texture load goes entirely, rather than the sprite being hidden at render
# time -- an unused background is still a PNG fetched and uploaded to the GPU on
# every page load. `render()` already guards on `this._back`, so dropping the
# load is all that is needed; `_back` simply stays null.
d = demo / "src/lappview.ts"
src = d.read_text()
if "// >>> arisu: no background" in src:
    print("  src/lappview.ts      background unchanged")
else:
    m = re.search(r"[ \t]*// \u80cc\u666f\u753b\u50cf\u521d\u671f\u5316.*?initBackGroundTexture\n[ \t]*\);\n",
                  src, re.S)
    if not m:
        raise SystemExit("error: the background sprite block is not where it "
                         "was in lappview.ts -- re-derive this patch by hand")
    d.write_text(src[:m.start()]
                 + "    // >>> arisu: no background. She is drawn over lain's\n"
                   "    // own backdrop, so the sample's classroom is not loaded\n"
                   "    // at all. render() guards on _back, which stays null.\n"
                   "    // <<< arisu\n"
                 + src[m.end():])
    print("  src/lappview.ts      background patched")

# No gear either, and this one is not cosmetic. The sample's gear sprite is a
# tap target: `isHit` -> `nextScene()`, which swaps the model. Left in place, a
# stray tap in the corner of Arisu's face turns her into Haru or Mao. It is a
# sample's model switcher sitting on a character, not a control she has.
#
# The hit test goes with the sprite, and it has to: the stock line calls
# `this._gear.isHit(...)` with no null guard, so dropping the sprite alone
# throws on every touch instead.
d = demo / "src/lappview.ts"
src = d.read_text()
if "// >>> arisu: no gear" in src:
    print("  src/lappview.ts      gear unchanged")
else:
    m = re.search(r"[ \t]*// \u6b6f\u8eca\u753b\u50cf\u521d\u671f\u5316.*?initGearTexture\n[ \t]*\);\n",
                  src, re.S)
    if not m:
        raise SystemExit("error: the gear sprite block moved in lappview.ts -- "
                         "re-derive this patch by hand")
    src = (src[:m.start()]
           + "    // >>> arisu: no gear. The sample's gear is a model switcher,\n"
             "    // and a stray tap on her face should not turn her into Haru.\n"
             "    // <<< arisu\n"
           + src[m.end():])
    g = re.search(r"[ \t]*// \u6b6f\u8eca\u306b\u30bf\u30c3\u30d7\u3057\u305f\u304b\n[ \t]*if \(this\._gear\.isHit\(posX, posY\)\) \{\n.*?\n[ \t]*\}\n",
                  src, re.S)
    if not g:
        raise SystemExit("error: the gear hit test moved in lappview.ts -- "
                         "re-derive this patch by hand")
    src = src[:g.start()] + src[g.end():]
    d.write_text(src)
    print("  src/lappview.ts      gear patched")

# Guard the sprite teardown. `release()` calls `this._gear.release()` and
# `this._back.release()` with no null check, which is safe only while the
# sample always builds both. Arisu builds neither, so the stock lines throw on
# the first one and abandon the rest of the teardown -- the GL program is never
# deleted, and on the iPad this runs on an orientation change, not just on page
# unload. Belongs with the two removals above, not in a later debugging round.
d = demo / "src/lappview.ts"
src = d.read_text()
if "this._gear?.release();" in src:
    print("  src/lappview.ts      release unchanged")
else:
    old = ("    this._gear.release();\n"
           "    this._gear = null;\n"
           "\n"
           "    this._back.release();\n"
           "    this._back = null;\n")
    if old not in src:
        raise SystemExit("error: the sprite release block moved in lappview.ts "
                         "-- re-derive this patch by hand")
    new = ("    this._gear?.release();\n"
           "    this._gear = null;\n"
           "\n"
           "    this._back?.release();\n"
           "    this._back = null;\n")
    d.write_text(src.replace(old, new, 1))
    print("  src/lappview.ts      release patched")

# ...and clear to transparent rather than opaque black, or removing the
# classroom just swaps it for a black rectangle. webgl2 contexts are alpha:true
# by default here, so the page behind the canvas shows through once the clear
# alpha is zero.
d = demo / "src/lappsubdelegate.ts"
src = d.read_text()
if "gl.clearColor(0.0, 0.0, 0.0, 0.0);" in src:
    print("  src/lappsubdelegate.ts  clear unchanged")
elif "gl.clearColor(0.0, 0.0, 0.0, 1.0);" in src:
    d.write_text(src.replace("gl.clearColor(0.0, 0.0, 0.0, 1.0);",
                             "gl.clearColor(0.0, 0.0, 0.0, 0.0);", 1))
    print("  src/lappsubdelegate.ts  clear patched")
else:
    raise SystemExit("error: clearColor not in the expected shape")
PY

echo
echo "done. build and serve with:"
echo "  cd $DEMO && npm run build:prod && npx vite preview --port 5001 --strictPort --host"
