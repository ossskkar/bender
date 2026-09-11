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
2. Clone `CubismWebSamples`, download the Cubism SDK for Web, copy `Core/` in.
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
