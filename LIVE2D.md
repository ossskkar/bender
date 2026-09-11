# Arisu — 2D Live2D avatar

Direction decided 2026-09-11. Supersedes the VRM/3D and generative-3D options
that were on the table. Meshy and the Booth VRM catalogue are **out**: Meshy
auto-rigs a body and leaves the facial blendshapes as a manual Blender step,
and 3D buys nothing here that Live2D does not.

## Goal

An animated 2D anime avatar that renders on iPad and web and lip-syncs to
Arisu's spoken responses.

## Architecture

One codebase across iPad and web: **Cubism SDK for Web**, wrapped in a
`WKWebView` for the native iPad app. A native Cubism SDK for iOS exists but
doubles the maintenance.

The avatar layer stays separate from the LLM and voice loop. The contract
between them is narrow: Arisu produces audio, we feed amplitude, amplitude
drives the mouth parameter.

## What a model MUST ship

- **Cubism 3+ export**: `.model3.json`, `.moc3`, textures, physics.
  Reject Cubism 2 (`.moc` only), the current SDK will not load it.
- **Parameters on the rig**:
  - `ParamMouthOpenY` — required for lip-sync. `ParamMouthForm` ideally too.
  - `ParamEyeLOpen` / `ParamEyeROpen` — auto-blink.
  - at least one idle `.motion3.json`.
- **`.exp3.json` expressions**, not just the base rig.
- Full source (`.cmo3` / `.can3` plus layered PSD) only if we want to edit the
  rig later. Optional, costs more.

## Prototype with free assets first, before buying a character

- **Eight sample models are already bundled in `CubismWebSamples`**, under
  `Samples/Resources/`. No separate download is needed for the model itself.
  Only Cubism Core is licence-gated. Audited 2026-09-12 by reading each
  `.model3.json` and grepping each `.moc3` for parameter IDs:

  | Model  | Expressions | Motions | MouthOpenY | MouthForm | Eyes | Pose |
  |--------|------------:|--------:|:----------:|:---------:|:----:|:----:|
  | Natori |          11 |       8 | yes        | yes       | yes  | yes  |
  | Haru   |           8 |       6 | yes        | yes       | yes  | yes  |
  | Ren    |           5 |       3 | yes        | yes       | yes  | no   |
  | Mao    |           8 |       8 | **no**     | no        | yes  | yes  |
  | Hiyori |           0 |      10 | yes        | yes       | yes  | yes  |
  | Mark   |           0 |       6 | yes        | no        | yes  | no   |
  | Rice   |           0 |       4 | **no**     | no        | yes  | no   |
  | Wanko  |           0 |       5 | **no**     | no        | no   | no   |

  **Use Natori.** It is the only model that clears the whole checklist with room
  to spare: most expressions, full lip-sync parameters, physics and pose.
  Haru is the fallback.

  Two traps in that table. **Hiyori ships no expressions at all**, despite being
  the obvious default, so prototyping on her cannot exercise step 5. And **Mao
  has no `ParamMouthOpenY`** — its mouth is driven by shape parameters
  (`ParamMouthUp`, `ParamMouthDown`, `ParamMouthAngry`), so amplitude lip-sync
  would need a custom mapping. Wanko is a dog and exposes none of the standard
  humanoid parameters.
- Official sample models, 20+, free: https://www.live2d.com/en/learn/sample/
  - **motion-sync sample model**, same page — built to demonstrate realistic
    lip-sync. Copy its parameter setup.
- Web runtime with a working demo, TypeScript, runs in iPad Safari:
  https://github.com/Live2D/CubismWebSamples
  The repo does **not** bundle Cubism Core. Download the Cubism SDK for Web
  separately and copy its `Core/` files in; the README covers this.
- Lighter wrapper over the same Core: `pixi-live2d-display` on npm. Friendlier
  than the full framework sample.

## Build steps

1. Download Hiyori from the sample page.
2. ~~Clone `CubismWebSamples`~~ **Do not.** That repo ships neither Core nor its
   Framework submodule and will not build. Download the Cubism SDK for Web
   instead: it is self-contained (Core, Framework, Samples, all eight models)
   and is what is now unpacked at `live2d/CubismSdkForWeb`, gitignored.
3. Get the sample rendering on a desktop browser **and** iPad Safari. Confirm
   both before writing any glue.
4. Wire Arisu audio to amplitude to `ParamMouthOpenY`. Basic lip-sync loop.
5. Add auto-blink and idle motion for liveliness.
6. Only once the pipeline runs end to end, choose and buy the real character.

## Licence gates — do not skip

- Sample downloads are gated by the Free Material License Agreement and the
  Live2D Cubism Sample Data Terms of Use.
- General users and small enterprises (annual sales under 10M yen) may use the
  samples commercially and non-commercially, **except Unity-chan and Hatsune
  Miku**, which carry separate restrictions. Skip the Miku sample for anything
  but a throwaway test.
- The Cubism SDK itself is under the Cubism SDK Release License: free under a
  revenue and entity threshold, commercial licensing above it. Verify the
  current terms.
- **If Arisu ever attaches to anything work or Rabobank related, the sample-data
  terms do not cover it.** That needs a purchased or commissioned model with
  explicit rights.
- **The "no AI" clause is narrower than it sounds — checked 2026-09-11.** The
  wording that appears on BOOTH listings is "use for AI **learning** purposes",
  meaning do not feed the artwork to a model trainer. It is not a ban on an AI
  character speaking through the rig. A sampled listing that carries that clause
  also explicitly permits "apps/games, video works, VTuber activities", which is
  exactly what Arisu is. So the market is open to us, but the check is still per
  listing: **app use, modification, AI learning**.
- A second, realer gate on the same listing: "a model for tracking software
  called VTube Studio and nizima LIVE. Operation with other software cannot be
  guaranteed." That is not a licence bar, but it means the rig is authored
  against those hosts and nothing promises it behaves under the Web SDK. Check
  the parameter list above rather than trusting the listing.

## Where to buy the real character later

- **nizima** (https://nizima.com/) — the official Live2D marketplace, English
  supported.
- **BOOTH** (https://booth.pm/) — Pixiv, larger selection, roughly 4,000 to
  7,000 yen ready-made, mostly Japanese. Filter on Live2D.

## Open decisions

- Native iPad app versus webview-wrapped web. **Recommendation: webview**, for
  the single codebase.
- Where rendering happens if Arisu runs on constrained hardware. Live2D is far
  lighter than VRM or 3D, so on-device 2D is viable, but confirm the frame rate
  on the actual iPad target.


## Prototype status — 2026-09-12

**Step 3 is half done. The demo builds and runs on the Mac.**

- SDK: `CubismSdkForWeb-5-r.5`, unpacked to `live2d/CubismSdkForWeb` and
  gitignored. Cubism Core reports version 6.0.1.
- The demo builds clean (`npm run build`) and serves via the `live2d` entry in
  `claude-projects/.claude/launch.json`, pinned to port 5001.
- Verified in the browser: Core loads, `CubismFramework.startUp()` and
  `initialize()` both complete, model index 0 loads, and a 1024x768 canvas has a
  live WebGL context.
- **Confirmed rendering and animating in Safari on the Mac, 2026-09-12.** Haru
  draws, moves and holds frame. The desktop half of step 3 is done.
- **Not yet verified: iPad Safari, and frame rate on the iPad.** That is the
  half of step 3 that actually gates the decision.

Debugging note, so the next session does not repeat it: a page showing only the
classroom background with no model is **not** a broken render path. Core, the
framework, the shaders, the moc3, the textures, the motions and the expressions
all fetch 200 and the console is clean in that state. Check the window and the
tab are actually visible and frontmost before investigating anything, because a
backgrounded tab pauses the requestAnimationFrame loop and leaves exactly that
picture.

Vite binds all interfaces, so the iPad reaches the Mac over tailnet at
`http://100.104.94.85:5001/`.

Run it with:

    cd live2d/CubismSdkForWeb/Samples/TypeScript/Demo && npm start

## Reaching it from the iPad

Safari upgrades plain `http://` to HTTPS and then fails with "this site can't
provide a secure connection", so the raw Vite port is unreachable from the iPad.
Front it with `tailscale serve` on the Mac:

    tailscale serve --bg --https 8444 http://127.0.0.1:5001

That gives https://oscars-macbook-pro.tailaa64e9.ts.net:8444/ and leaves the
existing :8443 entry alone. Turn it off with `tailscale serve --https=8444 off`.

**Two gotchas, both of which look like a broken proxy and are not.**

- Vite answers a proxied request with a **bare 403** unless the forwarded host is
  allowed. `vite.config.mts` now carries `allowedHosts: ['.ts.net']`.
- **That edit lives inside the gitignored SDK directory**, so it does not survive
  re-unpacking the zip. Re-apply it by hand, or the iPad gets 403 on every file
  with nothing in the log to explain why.

The Mac's existing serve entry on :8443 still proxies to a dead `127.0.0.1:8887`,
as the workspace notes say. Untouched here, still rotten.
