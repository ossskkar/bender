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

python3 - "$DEMO" "$GLUE" <<'PY'
import sys, pathlib, re, json, shutil

demo = pathlib.Path(sys.argv[1])

def apply(relpath, open_s, close_s, body, anchor):
    """Replace between sentinels if present, else insert the block above anchor."""
    p = demo / relpath
    src = p.read_text()
    block = f"{open_s}\n{body}{close_s}\n"
    # The closing sentinel must sit at the end of a line. Without that, the
    # pattern for `// >>> arisu: scene` also matches `// >>> arisu: scene-canvas
    # teardown`, so applying one patch DELETED the other's block. The two then
    # fought: each run re-added what the other had removed, in the wrong method,
    # and the generated file drifted into a shape neither patch describes. That
    # is what put `this.initializeScene()` inside release() and left a bare
    # `teardown` on its own line in the bundle Safari refused to run.
    pattern = re.escape(open_s) + r".*?" + re.escape(close_s) + r"[ \t]*\n"
    if re.search(pattern, src, flags=re.S):
        new = re.sub(pattern, block, src, count=1, flags=re.S)
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


# The error reporter goes first of all -- above Cubism Core -- so it hears
# Core's and the bundle's failures too. Its own block because the one below is
# anchored after Core.
apply(
    "index.html",
    "  <!-- >>> arisu: glow-css -->",
    "  <!-- <<< arisu: glow-css -->",
    "  <style>\n"
    "    /* The state glow, on its own layer between the room and the model.\n"
    "       Mirrors the host page's #glow -- the same gradients, the same\n"
    "       variables -- but in this document, because the room canvas here would\n"
    "       otherwise cover the host's glow. */\n"
    "    /* A static element ignores z-index completely, and the SDK creates its\n"
    "       model canvas position: static. Its z-index 2 therefore did nothing,\n"
    "       so the glow's z-index 1 put the light OVER her -- a translucent film\n"
    "       that dimmed her face instead of a halo behind it. Positioning the\n"
    "       canvas is the whole of why the three layers stack room (0) / light\n"
    "       (1) / her (2); without it the glow is not behind anything. */\n"
    "    body > canvas:not(#arisu-scene) {\n"
    "      position: relative; z-index: 2;\n"
    "    }\n"
    "    #glow {\n"
    "      position: fixed; inset: 0; pointer-events: none; z-index: 1;\n"
    "      /* No mix-blend-mode: screen over a transparent backdrop (this iframe's\n"
    "         body) does not composite, so the light vanished. A glow is a translucent\n"
    "         layer, and source-over is the right composite for it. */\n"
    "      background:\n"
    "        radial-gradient(circle at var(--glow-x, 54%) var(--glow-y, 42%),\n"
    "                  rgba(var(--state), var(--glow)) 0%,\n"
    "                  rgba(var(--state), calc(var(--glow) * 0.92))\n"
    "                    calc(26% * var(--glow-size, 1)),\n"
    "                  rgba(var(--state), calc(var(--glow) * 0.62))\n"
    "                    calc(52% * var(--glow-size, 1)),\n"
    "                  rgba(var(--state), calc(var(--glow) * 0.28))\n"
    "                    calc(78% * var(--glow-size, 1)),\n"
    "                  rgba(var(--state), 0) calc(110% * var(--glow-size, 1))),\n"
    "        radial-gradient(circle at var(--glow-x, 54%) var(--glow-y, 42%),\n"
    "                  rgba(var(--state), var(--glow)) 0%,\n"
    "                  rgba(var(--state), calc(var(--glow) * 0.95))\n"
    "                    calc(13% * var(--glow-size, 1)),\n"
    "                  rgba(var(--state), 0) calc(46% * var(--glow-size, 1))),\n"
    "        radial-gradient(ellipse at 50% 104%,\n"
    "                  rgba(var(--state), calc(var(--glow) * 0.7)) 0%,\n"
    "                  rgba(var(--state), calc(var(--glow) * 0.3))\n"
    "                    calc(34% * var(--glow-size, 1)),\n"
    "                  rgba(var(--state), 0) calc(84% * var(--glow-size, 1)));\n"
    "      transition: background 600ms ease;\n"
    "    }\n"
    "    #glow::after {\n"
    "      content: ''; position: absolute; inset: 0;\n"
    "      background: radial-gradient(circle at 50% 46%,\n"
    "                  rgba(var(--state), 0.30) 0%,\n"
    "                  rgba(var(--state), 0.10) 40%,\n"
    "                  rgba(var(--state), 0) 70%);\n"
    "      opacity: var(--loud, 0);\n"
    "      transition: opacity 90ms linear;\n"
    "    }\n"
    "    @keyframes arisu-think { 0%, 100% { opacity: 1; } 50% { opacity: 0.45; } }\n"
    "    @keyframes arisu-speak { 0%, 100% { opacity: 1; } 50% { opacity: 0.78; } }\n"
    "    #glow.thinking { animation: arisu-think 2.6s ease-in-out infinite; }\n"
    "    #glow.speaking { animation: arisu-speak 1.1s ease-in-out infinite; }\n"
    "    @media (prefers-reduced-motion: reduce) { #glow, #glow.thinking, #glow.speaking { animation: none; } }\n"
    "  </style>\n",
    "  <!-- Live2DCubismCore script -->",
)

apply(
    "index.html",
    "  <!-- >>> arisu: diag -->",
    "  <!-- <<< arisu: diag -->",
    '  <script src = "./arisu-diag.js"></script>\n',
    "  <!-- Live2DCubismCore script -->",
)

# Load Arisu's scripts before the module bundle. Classic scripts, so they are
# ready before any module code runs.
apply(
    "index.html",
    "  <!-- >>> arisu -->",
    "  <!-- <<< arisu -->",
    '  <script src = "./arisu-scene.js"></script>\n'
    '  <script src = "./arisu-lipsync.js"></script>\n'
    '  <script src = "./arisu-face.js"></script>\n'
    '  <script src = "./arisu-avatar.js"></script>\n'
    '  <script src = "./arisu-harness.js"></script>\n',
    "  <!-- Build script -->",
)

apply(
    "index.html",
    "  <!-- >>> arisu: glow-element -->",
    "  <!-- <<< arisu: glow-element -->",
    '  <div id="glow"></div>\n',
    "  <!-- Build script -->",
)

# --- the scene: background, room colour, display ---------------------------------
#
# The model canvas clears to transparent, so everything behind the model is drawn
# by us on a second, 2D canvas underneath it. A 2D context rather than more GL on
# purpose: the background is a flat gradient and occasionally one image, and
# doing it in GL would mean a second program, a quad and a texture per scene for
# no gain.
#
# The 2D canvas is appended to document.body, which the demo's own stylesheet
# already makes `display:flex; flex-wrap:wrap`. An absolutely positioned child is
# out of that flow, so the model canvas still measures the full viewport and this
# one does not push it anywhere.
# The scene canvas, created at the top of initialize().
#
# Not an apply(): apply() inserts a block ABOVE an anchor line, so the call it
# inserted landed before the method's signature -- outside the body, where a bare
# statement is a syntax error. And the sentinels for this one kept colliding with
# the teardown's ("scene" is a prefix of "scene teardown"), so the two patches
# deleted and re-added each other until the generated file was a shape neither of
# them describes. That is what put this call in release() and left a bare
# `teardown` identifier in the bundle -- which Safari refused to run, with no
# face at all and therefore nothing for a glow to sit behind.
#
# So: strip every scene block this file may hold, then insert the call
# immediately after the method's opening brace, keyed on that brace. Idempotent
# by construction, and it repairs whatever a previous run left behind.
scene = demo / "src/lappdelegate.ts"
src = scene.read_text()
src = re.sub(r"[ \t]*// >>> arisu: scene-canvas[ \t]*\n.*?// <<< arisu: scene-canvas[ \t]*\n",
             "", src, flags=re.S)
src = re.sub(r"[ \t]*// >>> arisu: scene[ \t]*\n.*?// <<< arisu: scene[ \t]*\n",
             "", src, flags=re.S)
src = re.sub(r"^[ \t]*teardown[ \t]*\n", "", src, flags=re.M)

key = "public initialize(): boolean {\n"
if src.count(key) != 1:
    raise SystemExit("error: initialize() is not where this patch expects it")
src = src.replace(key, key
                  + "    // >>> arisu: scene-canvas\n"
                    "    this.initializeScene();\n"
                    "    // <<< arisu: scene-canvas\n", 1)
scene.write_text(src)
print("  src/lappdelegate.ts  scene canvas placed at the top of initialize()")

apply(
    "src/lappdelegate.ts",
    "  // >>> arisu: scene-methods",
    "  // <<< arisu: scene-methods",
    "  /**\n"
    "   * The scene behind the model: one 2D canvas, the room colour, and an\n"
    "   * optional background image. Everything comes from window.ArisuScene,\n"
    "   * which parses the URL -- see glue/arisu-scene.js.\n"
    "   */\n"
    "  private initializeScene(): void {\n"
    "    const scene = (window as any).ArisuScene;\n"
    "    if (!scene) return;\n"
    "\n"
    "    const canvas = document.createElement('canvas');\n"
    "    canvas.id = 'arisu-scene';\n"
    "    canvas.style.position = 'fixed';\n"
    "    canvas.style.inset = '0';\n"
    "    canvas.style.width = '100vw';\n"
    "    canvas.style.height = '100vh';\n"
    "    canvas.style.zIndex = '0';\n"
    "    canvas.style.pointerEvents = 'none';\n"
    "    this._sceneCanvas = canvas;\n"
    "    this._scene2d = canvas.getContext('2d');\n"
    "\n"
    "    // Behind the model canvases: inserted first, and the model canvases\n"
    "    // carry z-index 0, so the order holds whichever way they are appended.\n"
    "    document.body.insertBefore(canvas, document.body.firstChild);\n"
    "\n"
    "    window.addEventListener('resize', () => this.drawScene());\n"
    "    // The scene's own repaint, so a change made on a live page -- the\n"
    "    // settings panel moving a slider -- lands on the next tick instead of\n"
    "    // waiting for a resize that may never come.\n"
    "    if (scene.onRedraw) scene.onRedraw(() => this.drawScene());\n"
    "    // Reachable for the headless probe: proving that a settings change\n"
    "    // repaints needs to call the same repaint the settings change calls.\n"
    "    (window as any).__arisuDrawScene = () => this.drawScene();\n"
    "    this.drawScene();\n"
    "  }\n"
    "\n"
    "  /**\n"
    "   * Repaint the scene at the canvas's own resolution.\n"
    "   */\n"
    "  private drawScene(): void {\n"
    "    const canvas = this._sceneCanvas;\n"
    "    const c = this._scene2d;\n"
    "    if (!canvas || !c) return;\n"
    "\n"
    "    const scene = (window as any).ArisuScene;\n"
    "    if (!scene) return;\n"
    "\n"
    "    const dpr = window.devicePixelRatio || 1;\n"
    "    const w = Math.max(1, Math.round(canvas.clientWidth * dpr));\n"
    "    const h = Math.max(1, Math.round(canvas.clientHeight * dpr));\n"
    "    if (canvas.width !== w || canvas.height !== h) {\n"
    "      canvas.width = w;\n"
    "      canvas.height = h;\n"
    "    }\n"
    "\n"
    "    c.setTransform(1, 0, 0, 1, 0, 0);\n"
    "    c.clearRect(0, 0, w, h);\n"
    "\n"
    "    const bg = scene.background;\n"
    "    if (bg.mode === 'none') {\n"
    "      this.paintWash(c, w, h, scene);\n"
    "      return;\n"
    "    }\n"
    "\n"
    "    if (bg.mode === 'image') {\n"
    "      const img = scene.backgroundImage();\n"
    "      // Paint the gradient first and let the image land on top of it. A\n"
    "      // background image is a network fetch, and without this the frame is\n"
    "      // simply empty until it arrives -- an unlit room reads as a broken\n"
    "      // face, and the slower the connection the longer it reads that way.\n"
    "      this.paintGradient(c, w, h, scene);\n"
    "      if (img) {\n"
    "        // Cover fit: fill the frame, crop the overflow, never letterbox.\n"
    "        const s = Math.max(w / img.naturalWidth, h / img.naturalHeight);\n"
    "        const dw = img.naturalWidth * s;\n"
    "        const dh = img.naturalHeight * s;\n"
    "        c.drawImage(img, (w - dw) / 2, (h - dh) / 2, dw, dh);\n"
    "        // The room colour washes the image rather than replacing it, so a\n"
    "        // scene can be tinted without losing it.\n"
    "        const room = scene.room;\n"
    "        c.globalCompositeOperation = 'multiply';\n"
    "        c.fillStyle = `rgb(${room[0]}, ${room[1]}, ${room[2]})`;\n"
    "        c.fillRect(0, 0, w, h);\n"
    "        c.globalCompositeOperation = 'source-over';\n"
    "      }\n"
    "      // An image that 404s leaves the gradient underneath it, which is the\n"
    "      // floor of this whole branch: there is never an empty frame.\n"
    "      this.paintWash(c, w, h, scene);\n"
    "      return;\n"
    "    }\n"
    "\n"
    "    this.paintGradient(c, w, h, scene);\n"
    "    this.paintWash(c, w, h, scene);\n"
    "  }\n"
    "\n"
    "  /**\n"
    "   * The room: the room colour at the top falling to its floor at the bottom.\n"
    "   */\n"
    "  private paintGradient(\n"
    "    c: CanvasRenderingContext2D,\n"
    "    w: number,\n"
    "    h: number,\n"
    "    scene: any\n"
    "  ): void {\n"
    "    const room = scene.room;\n"
    "    if (scene.background.mode === 'flat') {\n"
    "      c.fillStyle = `rgb(${room[0]}, ${room[1]}, ${room[2]})`;\n"
    "      c.fillRect(0, 0, w, h);\n"
    "      return;\n"
    "    }\n"
    "    const floor = scene.floor();\n"
    "    const g = c.createLinearGradient(0, 0, 0, h);\n"
    "    g.addColorStop(0, `rgb(${room[0]}, ${room[1]}, ${room[2]})`);\n"
    "    g.addColorStop(1, `rgb(${floor[0]}, ${floor[1]}, ${floor[2]})`);\n"
    "    c.fillStyle = g;\n"
    "    c.fillRect(0, 0, w, h);\n"
    "  }\n"
    "\n"
    "  /**\n"
    "   * The optional wash over the whole scene. Painted under the model, so it\n"
    "   * can tint the room without tinting her.\n"
    "   */\n"
    "  private paintWash(\n"
    "    c: CanvasRenderingContext2D,\n"
    "    w: number,\n"
    "    h: number,\n"
    "    scene: any\n"
    "  ): void {\n"
    "    const o = scene.overlay;\n"
    "    if (!o.tint || !(o.alpha > 0)) return;\n"
    "    c.fillStyle = `rgba(${o.tint[0]}, ${o.tint[1]}, ${o.tint[2]}, ${o.alpha})`;\n"
    "    c.fillRect(0, 0, w, h);\n"
    "  }\n",
    "  /**\n"
    "   * Canvasを生成配置、Subdelegateを初期化する\n"
    "   */",
)

# The fields the scene canvas and its context live in, and the teardown that
# removes the element as well -- release() can run while the page outlives the
# delegate, and a canvas left in the DOM would stack up behind the next one.
apply(
    "src/lappdelegate.ts",
    "  // >>> arisu: scene-fields",
    "  // <<< arisu: scene-fields",
    "  /**\n"
    "   * The scene behind the model -- see initializeScene().\n"
    "   */\n"
    "  private _sceneCanvas: HTMLCanvasElement;\n"
    "  private _scene2d: CanvasRenderingContext2D;\n"
    "\n",
    "  /**\n"
    "   * 操作対象のcanvas要素\n"
    "   */\n"
    "  private _canvases: Array<HTMLCanvasElement>;",
)

apply(
    "src/lappdelegate.ts",
    "    // >>> arisu: scene-teardown",
    "    // <<< arisu: scene-teardown",
    "    if (this._sceneCanvas) {\n"
    "      this._sceneCanvas.remove();\n"
    "      this._sceneCanvas = null;\n"
    "      this._scene2d = null;\n"
    "    }\n"
    "\n",
    "    this.releaseSubdelegates();\n",
)

# --- display: how big the model is and where it sits -----------------------------
#
# The stock code shows the model at a fixed fit and lets the canvas aspect decide
# the crop, which is right for a demo and wrong for a desk pet: on a wide screen
# she ends up small and centred with a lot of room around her. scene.display
# multiplies that fit -- 1 is exactly what shipped -- and shifts her, both as
# fractions of the canvas.
# The model canvas renders in front of the glow. Without this, the glow -- at
# z-index 1 -- paints OVER her and screen-blends into her face instead of sitting
# behind her. Two canvasless siblings (scene at 0, glow at 1) and the model at 2.
apply(
    "src/lappdelegate.ts",
    "    // >>> arisu: model-z",
    "    // <<< arisu: model-z",
    "      canvas.style.zIndex = '2';\n",
    "      canvas.style.width = `${width}vw`;\n",
)

apply(
    "src/lapplive2dmanager.ts",
    "      // >>> arisu: display",
    "      // <<< arisu: display",
    "      // The scene's own say over size and position. Applied after the SDK\n"
    "      // has chosen its fit, so 1/0/0 leaves the stock framing untouched.\n"
    "      const arisuScene = (window as any).ArisuScene;\n"
    "      if (arisuScene && arisuScene.display) {\n"
    "        const d = arisuScene.display;\n"
    "        if (d.scale !== 1) {\n"
    "          projection.scale(d.scale, d.scale);\n"
    "        }\n"
    "        if (d.x !== 0 || d.y !== 0) {\n"
    "          projection.translate(d.x, d.y);\n"
    "        }\n"
    "      }\n"
    "\n",
    "      // 必要があればここで乗算\n",
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
    "    if (arisuLipSync) {\n"
    "      const mouth: number = arisuLipSync.value();\n"
    "      (window as any).__arisuMouth = mouth;\n"
    "      if (this._lipSyncIds.length > 0) {\n"
    "        for (let i = 0; i < this._lipSyncIds.length; ++i) {\n"
    "          this._model.setParameterValueById(this._lipSyncIds[i], mouth, 1.0);\n"
    "        }\n"
    "      } else {\n"
    "        // Mark declares an empty LipSync group but has ParamMouthOpenY.\n"
    "        // Setting a parameter a model lacks is a no-op, so Rice -- which\n"
    "        // has no mouth at all -- is safe too.\n"
    "        this._model.setParameterValueById(\n"
    "          CubismFramework.getIdManager().getId('ParamMouthOpenY'), mouth, 1.0\n"
    "        );\n"
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
    "    // Body gestures. Asked for at occasions by the avatar, parked on\n"
    "    // ArisuFace, started here, and at PriorityNormal on purpose: a gesture\n"
    "    // interrupts the idle loop, and this same update() restarts idle when\n"
    "    // the motion manager reports finished -- so nothing here needs a timer\n"
    "    // or a per-frame driver. A rig with no TapBody group (Mark) is not a\n"
    "    // special case: startRandomMotion answers -1 for a group the model\n"
    "    // setting does not have.\n"
    "    if (arisuFace && arisuFace.takePendingMotion) {\n"
    "      const arisuMotion: any = arisuFace.takePendingMotion();\n"
    "      if (arisuMotion) {\n"
    "        const w = window as any;\n"
    "        // Seen, started and refused are three different things, and the queue\n"
    "        // reports none of them: a group the model setting does not have comes\n"
    "        // back as -1 rather than as an error. Counted separately here because\n"
    "        // 'no gesture played' has to be distinguishable from 'no gesture was\n"
    "        // ever asked for', and the probe is the only witness.\n"
    "        w.__arisuMotionSeen = (w.__arisuMotionSeen || 0) + 1;\n"
    "        const arisuStarted: number = this.startRandomMotion(\n"
    "          arisuMotion.group,\n"
    "          arisuMotion.priority\n"
    "        );\n"
    "        if (arisuStarted >= 0) {\n"
    "          w.__arisuMotionCount = (w.__arisuMotionCount || 0) + 1;\n"
    "        } else {\n"
    "          // -1 here means \"not now\", not \"never\": the sample's startMotion\n"
    "          // returns it for a motion whose file is still being preloaded,\n"
    "          // having already kicked the fetch off. So the request goes back to\n"
    "          // ArisuFace and is asked for again on the next frame, until its\n"
    "          // small budget runs out -- which is what makes the first gesture of\n"
    "          // a page's life play at all. Measured: the first ask of a page is\n"
    "          // routinely refused and the second accepted.\n"
    "          w.__arisuMotionRefused = (w.__arisuMotionRefused || 0) + 1;\n"
    "          w.__arisuMotionWhy = {\n"
    "            group: arisuMotion.group,\n"
    "            priority: arisuMotion.priority,\n"
    "            count: this._modelSetting.getMotionCount(arisuMotion.group),\n"
    "            tries: arisuMotion.tries,\n"
    "            finished: this._motionManager.isFinished()\n"
    "          };\n"
    "          // The raw return, recorded because \"startRandomMotion answered no\"\n"
    "          // has to be distinguishable from \"it answered nothing at all\":\n"
    "          // `undefined >= 0` is false, so a void return would read as a\n"
    "          // refusal in the counters while the motion played perfectly well --\n"
    "          // and that is the wrong conclusion to draw quietly.\n"
    "          w.__arisuMotionReturn = String(arisuStarted) +\n"
    "            ' (' + typeof arisuStarted + ')';\n"
    "          if (arisuFace.retryMotion) arisuFace.retryMotion(arisuMotion);\n"
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
    "      );\n"
    "    // The expressions this rig actually loaded, by the name the tables in\n"
    "    // arisu-face.js call them. setUp() reads them out of the .model3.json\n"
    "    // into a map keyed by name, and setExpression() silently does nothing\n"
    "    // for a name that is not in it -- so a table naming a file that was never\n"
    "    // registered fails quietly, and this is the only place that shows it.\n"
    "    (window as any).__arisuExpressionNames = (): string[] =>\n"
    "      Array.from(this._expressions.keys());\n"
    "    // The motions this rig has actually loaded, keyed `Group_index`. Unlike\n"
    "    // expressions these are not all read at setUp: startMotion() fetches a\n"
    "    // motion the first time it is asked for and returns -1 while it does, so\n"
    "    // a refused gesture is not the same thing as a gesture that did not\n"
    "    // happen -- the file lands a moment later and starts itself. Which names\n"
    "    // are in here is the only honest answer to 'did a gesture play'.\n"
    "    (window as any).__arisuMotionNames = (): string[] =>\n"
    "      Array.from(this._motions.keys());\n",
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

# Which sample loads comes from the page URL, `?model=Haru`. The client picks
# it from the character -- Arisu wears the female samples, Chopper the male
# ones -- so the face page never needs a switcher of its own. An unknown or
# missing name keeps index 0, Natori, which is also arisu-face.js's fallback.
apply(
    "src/lapplive2dmanager.ts",
    "    // >>> arisu: model",
    "    // <<< arisu: model",
    "    {\n"
    "      const wanted = new URLSearchParams(window.location.search).get('model');\n"
    "      const index = LAppDefine.ModelDir.indexOf(wanted);\n"
    "      if (index >= 0) {\n"
    "        this._sceneIndex = index;\n"
    "      }\n"
    "    }\n",
    "  }\n\n  /**\n   * \u89e3\u653e\u3059\u308b\u3002",
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

# No WebGL: log it, do not alert() and do not crash. The stock sample calls
# alert(), which freezes the page until someone dismisses it -- inside her
# client's iframe that is a dialog over the whole app, and in headless Chrome it
# never returns, so arisu-diag.js never gets to report. Then update() and
# isContextLost() call getGl().isContextLost() on null, a TypeError every frame.
# That was Oscar's Chrome with graphics acceleration off, 2026-09-13: a blank
# face and nothing said. console.error is what arisu-diag.js hears.
d = demo / "src/lappglmanager.ts"
src = d.read_text()
old_alert = "      alert('Cannot initialize WebGL. This browser does not support.');"
new_alert = "      console.error('Cannot initialize WebGL. This browser does not support.');"
if new_alert in src:
    print("  src/lappglmanager.ts    no-alert unchanged")
elif old_alert in src:
    d.write_text(src.replace(old_alert, new_alert, 1))
    print("  src/lappglmanager.ts    no-alert patched")
else:
    raise SystemExit("error: the WebGL alert moved in lappglmanager.ts")

d = demo / "src/lappsubdelegate.ts"
src = d.read_text()
pairs = [
    ("    if (this._glManager.getGl().isContextLost()) {\n      return;\n    }",
     "    const arisuGl = this._glManager.getGl();\n"
     "    if (!arisuGl || arisuGl.isContextLost()) {\n      return;\n    }"),
    ("    return this._glManager.getGl().isContextLost();",
     "    const arisuGl = this._glManager.getGl();\n"
     "    return !arisuGl || arisuGl.isContextLost();"),
]
for old, new in pairs:
    if new in src:
        print("  src/lappsubdelegate.ts  null-gl unchanged")
    elif old in src:
        src = src.replace(old, new, 1)
        print("  src/lappsubdelegate.ts  null-gl patched")
    else:
        raise SystemExit("error: isContextLost call moved in lappsubdelegate.ts")
d.write_text(src)

# --- hand-written expressions for the four samples that ship none ----------------
#
# Hiyori, Rice, Mark and Wanko ship no .exp3.json between them, so the five
# states and four reactions in arisu-face.js had nothing to say on those rigs.
# The files live in glue/expressions/ -- generated by tools/make-expressions.py,
# which is where a value gets changed -- and are copied in here for the same
# reason as everything else in this script: nothing inside the SDK tree survives
# re-unpacking the zip.
#
# The model3.json edit is a merge, not a write: a rig that later ships its own
# expressions keeps them, and ours are replaced rather than appended again on a
# re-run. Ours are the ones whose Name starts with exp_.
glue_expr = pathlib.Path(sys.argv[2]) / "expressions"
resources = demo.parent.parent / "Resources"

for model in ("Hiyori", "Rice", "Mark", "Wanko"):
    src_dir = glue_expr / model
    if not src_dir.is_dir():
        raise SystemExit(f"error: no expressions for {model} in {src_dir} -- "
                         f"run tools/make-expressions.py first")
    files = sorted(src_dir.glob("*.exp3.json"))

    dst_dir = resources / model / "exp"
    dst_dir.mkdir(parents=True, exist_ok=True)
    for f in files:
        shutil.copyfile(f, dst_dir / f.name)

    manifest = resources / model / f"{model}.model3.json"
    doc = json.loads(manifest.read_text())
    refs = doc.setdefault("FileReferences", {})
    theirs = [e for e in refs.get("Expressions", [])
              if not str(e.get("Name", "")).startswith("exp_")]
    # Not f.stem: on exp_idle.exp3.json that is "exp_idle.exp3", a name no
    # table in arisu-face.js asks for, so every expression was silently missing.
    ours = [{"Name": f.name.removesuffix(".exp3.json"), "File": f"exp/{f.name}"}
            for f in files]
    refs["Expressions"] = theirs + ours
    manifest.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
    print(f"  Resources/{model:<8} {len(ours)} expressions "
          f"({len(theirs)} of its own kept)")
PY

echo
echo "done. build and serve with:"
echo "  cd $DEMO && npm run build:prod && npx vite preview --port 5001 --strictPort --host"
