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
4. ~~Wire Arisu audio to amplitude to `ParamMouthOpenY`.~~ **Done 2026-09-12**,
   see *Step 4* below.
5. ~~Add auto-blink and idle motion for liveliness.~~ **Done 2026-09-12**,
   and mostly free -- see *Step 5* below.
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

### Candidates found — 2026-09-12

**Arisu's portrait is Yamato (One Piece), and so is Chopper's source.** No
Live2D model of either exists on BOOTH (searched `ヤマト live2d`), and a fan rig
of a copyrighted character would be personal-use only at best. So "buy Arisu"
really means a look-alike original (white hair, red horns, oni) or a commission.
nizima's search page did not load outside a real browser; not searched yet.

| BOOTH item | Price | Fit | Licence |
|---|---|---|---|
| [Silver-haired girl, やま缶](https://booth.pm/en/items/3978690) | 5,500 JPY | silver hair, horns, fox ears; ships moc3, exp3, motions | apps and games allowed, credit required. **Best so far.** Its expressions are toggles (ears, horns, outfit), not moods, so our five states would need hand-written `.exp3.json` |
| [Oni VTuber package, streamskins](https://booth.pm/en/items/7426773) | 1,500 JPY | oni theme, horn variants, five mood presets | streaming only named; files not listed; ask the seller |
| [White-haired demon kitten, 细雨气](https://booth.pm/en/items/6330457) | 4,500 JPY | white hair, horns, dark skin | **ruled out**: "non-official platforms" banned, texture edits banned |

**Budget: 20 EUR max (about 3,200 JPY), set by Oscar 2026-09-12.** That rules
out the silver-haired girl above. Under budget:

| BOOTH item | Price | Fit | Licence |
|---|---|---|---|
| [White-haired young lady, 小喵招财屋](https://booth.pm/en/items/8537341) | 700 JPY | white hair, no horns; 10 keybind faces (blush, heart and sparkle eyes, pale) | **apps and games named as allowed**, colour changes allowed, no AI clause. **Pick so far** |
| [Noble Devil, enximadesign](https://booth.pm/en/items/7564335) | 1,780 JPY | white hair, horns, tail; may read male | VTuber, video and SNS only; apps not mentioned |
| [White-haired girl, 高木](https://booth.pm/en/items/4862137) | 3,000 JPY | white hair, ponytail variant | personal VTubing; edits banned beyond overlays |
| [Kurogane, 2dlivemodelStudio](https://booth.pm/en/items/8634062) | 2,500 JPY | male | **ruled out**: "AI-powered applications, chatbot software" banned |

**Taste, set by Oscar 2026-09-12: no little girls, no uniforms.** Adult
white-collar professionals or funny creatures instead. That retires every pick
above. Under budget and within that:

| BOOTH item | Price | Look | Licence |
|---|---|---|---|
| [ゆるでびる, 萬工房](https://booth.pm/en/items/6703020) | 800 JPY | small loose devil/bat mascot; eye states, laugh, staff poses | **"app works, game works" allowed**, modification allowed within limits, cmo3 sold separately on nizima. **Pick** |
| [ビジネスパーソン2 眼鏡, 外堀ゆきも](https://booth.pm/en/items/6685030) | 1,500 JPY | adult man, suit no tie, removable glasses | **apps allowed**, credit @sotohori; expressions not listed |
| [BusinessGuy, 外堀ゆきも](https://booth.pm/en/items/4287506) | 1,500 JPY | adult man, suit; bow, card exchange, phone-call motions | **apps allowed**, credit @sotohori |
| [Grumpy slime, 汎用モデル屋さん](https://booth.pm/en/items/8058536) | 880 JPY | mean-eyed jiggly slime, no expressions | streaming and video only; ask the creator |
| [Gem monster, 星河工房](https://booth.pm/en/items/5394000) | 1,500 JPY | relaxed gem creature | **ruled out**: model and texture edits banned |
| [Tibetan sand fox, だいふく製作所](https://booth.pm/en/items/7676991) | 2,000 JPY | deadpan fox | **ruled out**: edits banned, apps not named |

No adult woman in office wear exists as a rigged model under budget (searched
`スーツ`, `社会人`, `OL`).

**Also bright and cheerful, set by Oscar 2026-09-12** — ゆるでびる read too sad
and dark. Bright creatures, checked the same day:

| BOOTH item | Price | Look | Licence |
|---|---|---|---|
| [とらねこのペパー, 栗城はる](https://booth.pm/en/items/3877967) | 1,000 JPY | chocolate-mint tiger cat | **"apps, games, chat avatars" named**, credit 栗城はる on web. **Pick** |
| [辰マスコット, めれー](https://booth.pm/en/items/5416633) | 1,000 JPY (2,000 with cmo3) | cheerful dragon mascot | **apps and games allowed**, customisation free; expressions not listed |
| [ぽよぽよひよこ, chido-mona](https://booth.pm/en/items/4082766) | 1,000 JPY | yellow chick, 10 faces | apps not mentioned; ask the creator. Best expressions |
| [ペンギン, chido-mona](https://booth.pm/en/items/3758586) | 1,800 JPY | bouncy penguin, 11 faces | apps not mentioned; ask the creator |
| [おほしさま, amase-oruko](https://booth.pm/en/items/5376734) | 1,500 JPY | star mascot, happy/sad/angry | apps not mentioned, data edits banned |
| くまもどき, もちもちクリーチャー, パフェちゃん, おきつねらて | 600–1,500 JPY | bright | **ruled out**: edits banned or VTS-only data |

**Any look is fine except the female-student kind — Oscar, 2026-09-12.** That
reopens adult women, robots and other creatures. Checked the same day:

| BOOTH item | Price | Look | Licence |
|---|---|---|---|
| [解説できるロボット, ゆるぼっくす](https://booth.pm/en/items/8052027) | 2,000 JPY | light, loose cute robot; six faces (angry, sad, pale), pointer stick, wave | **"apps, games, business" named**, recolour free, no credit needed. **Pick** |
| [おとなのお姉さん, jenny](https://booth.pm/en/items/3713392) | 3,000 JPY | adult woman; 6 hair, 5 clothes, 5 skin colours | **apps and games named**, texture edits allowed; vowel mouth shapes, brows, blush. No cmo3 |
| [ミミズク / ふくろう, たんよ](https://booth.pm/en/items/6266819) | 1,480 JPY (2,480 with psd+cmo3) | round-eyed owl; heart, star, spiral eyes, tears | "games, SNS, VTuber etc." (apps not named), customisation free |
| [まるロボ, マルイヌ店](https://booth.pm/en/items/4094876) | 1,000 JPY | round robot, shutter blink | video and VTuber only |

**Final taste rule, Oscar 2026-09-12: grown-up looking only, nothing
child-looking, no revealing outfits; fantasy is fine.** Judged from each
listing's cover image, not its text — text never says a model looks childish.

| BOOTH item | Price | Look (from the cover) | Licence |
|---|---|---|---|
| [ビジネスパーソン2 眼鏡, 外堀ゆきも](https://booth.pm/en/items/6685030) | 1,500 JPY | grown man, blue flat style, glasses, no tie | **apps allowed**, credit @sotohori. **Pick** |
| [BusinessGuy, 外堀ゆきも](https://booth.pm/en/items/4287506) | 1,500 JPY | same style, suit and tie | **apps allowed**, credit @sotohori |
| [異形頭さん, USAGI STORE](https://booth.pm/en/items/7165476) | 3,000 JPY | suit with an object head (clock, sunflower, TV); 8 reactions | **apps and games allowed**, recolour free. **No mouth**, so the jaw pipeline has nothing to drive |
| [おとなのお姉さん, jenny](https://booth.pm/en/items/3713392) | 3,000 JPY | adult woman, but low-cut dresses | apps allowed; **fails the outfit rule** |
| Grace the elf 5274884, 優しいお姉さん 5303684, 二形態の魔女 6238039 | — | revealing or young-looking | **ruled out** |
| 女子大生風エルフ 6051801 | 1,500 JPY | modest, but sold as a student and no expressions | **ruled out** |
| 黒髪イケメンスーツ 7659956, 狐モチーフ 5174752 | — | adult | **ruled out**: dark / apps not named; fox bans AI use |

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
- **Step 3 is complete, 2026-09-12.** Confirmed by Oscar on the iPad over
  tailnet: renders, animates smoothly, and all eight models cycle on tap. The
  frame rate holds. Live2D on the iPad is viable and the direction survives its
  own gate.

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
- **Do not use the dev server for anything on the iPad.** Its HMR websocket
  cannot reach back through the tailscale proxy, so it gives up and reloads the
  whole page every few seconds. That reads as a stuttering avatar and makes any
  frame-rate judgement worthless. Build once and serve the built output:

      npm run build:prod
      npx vite preview --port 5001 --strictPort --host

  The `live2d` entry in `launch.json` now does the second line. Confirmed no
  `vite/client` in the built `index.html`, so there is no socket to drop.
- **That edit lives inside the gitignored SDK directory**, so it does not survive
  re-unpacking the zip. Re-apply it by hand, or the iPad gets 403 on every file
  with nothing in the log to explain why.

The Mac's existing serve entry on :8443 still proxies to a dead `127.0.0.1:8887`,
as the workspace notes say. Untouched here, still rotten.


## Step 4 — lip sync, done 2026-09-12

**Her audio drives `ParamMouthOpenY`, verified end to end on Natori.** Real
audio through the analyser, through the expander, into the model, with the
mouth visibly opening and closing in the rendered frame.

### Where the code lives, and why

Everything we add to the SDK tree lives in **`live2d/glue/`** and is applied by
**`live2d/patch-sdk.sh`**. The SDK is gitignored, so every edit inside it dies
the moment the zip is re-unpacked — which already cost one session when the
`vite.config.mts` host allowance vanished and the iPad started 403ing. The
script is idempotent. Run it after unpacking a fresh SDK, or any time the demo
starts behaving like a stock sample.

It applies four things:

| What | Where | Why |
|---|---|---|
| `vite.config.mts` | copied whole | `allowedHosts` for the tailscale proxy, and the preview block |
| `arisu-lipsync.js`, `arisu-harness.js` | `public/` | so the built `dist` carries them |
| two `<script>` tags | `index.html` | classic scripts, loaded before the module bundle |
| the lip-sync hook | `src/lappmodel.ts` | ~8 lines in `update()` |
| Natori first | `src/lappdefine.ts` | the audited pick, ahead of the stock Haru |

The hook sits **after** `_updateScheduler.onLateUpdate` and before
`_model.update()`, so it overrides `CubismLipSyncUpdater` — which sits at 0
anyway, because nothing here plays a wav through the wav handler.

`arisu-lipsync.js` knows nothing about Live2D and Live2D knows nothing about her
voice. The whole contract is one number per frame. `window.__arisuMouth` mirrors
it for debugging.

### The API

- `attachStream(stream)` — her WebRTC output track. **This is the real path.**
  Deliberately not connected to `destination`: the `<audio>` element already
  plays the remote track and connecting both doubles her volume.
- `attachAudio(el)` — an `<audio>` element. Same call the portrait renderer uses.
- `setAmplitude(v)` — for a host that already computed amplitude.
- `speakDemo()`, `useMic()` — test only.

`value()` advances its own smoothing, so it must be called **exactly once per
frame**. Calling it twice moves the jaw at double speed.

### A fixed gain is wrong for a jaw, and this is why

The portrait renderer's band math was reused verbatim, because it is already
proven against her real voice. Reusing its *gain* was the mistake. Measured
against a real speech clip:

| | value |
|---|---|
| raw band energy, quietest point of speech | 0.87 |
| raw band energy, peak | 1.74 |

Both are above 1.0, which is where `ParamMouthOpenY` clamps. The portrait feeds
a glow, where clipping is invisible; a jaw just hangs open and wobbles. The
first version pinned at 1.0 for 11 of 95 frames and averaged 0.82 — a gaping
mouth, not a talking one.

Two fixes, in order of how much they mattered:

1. **An expander, not a gain.** Normalise against a running peak (instant
   attack, slow release), and treat **half the peak as closed**. Dividing by the
   peak alone is not enough, because the quiet level of speech is nowhere near
   zero. A tracked running minimum was tried first and is worse: it converges far
   too slowly to be useful inside a single utterance, whereas half the peak
   converges the instant the peak does and landed within 0.05 of the measured
   floor.
2. **Less analyser smoothing**, 0.55 down to 0.2. The portrait wants a glow that
   looks continuous. A jaw wants the gaps between syllables to survive.

After both: mean 0.49, four frames pinned, 29 frames near-closed, 36 distinct
values across 1.5 seconds. That is a mouth that talks.

**Caveat, and it is the honest one: this was tuned against a Live2D sample wav,
not against Arisu's own TTS.** The expander is level-independent by design, so
it should carry over, but `FLOOR_RATIO` is the first knob to reach for if her
mouth looks lazy (raise it) or twitchy (lower it). `setAutoGain(false)` falls
back to the fixed gain for a host that already sends normalised amplitude.

### Gotcha that will waste an hour

**`requestAnimationFrame` stops completely when the page is not visible**, and a
hidden browser pane counts. The symptom is not a frozen picture — it is
`__arisuMouth` staying `undefined` while the console is clean and every asset
loads 200. `value()` can still be pumped by hand to test the audio path, but
nothing reaches the model. This is the same trap the previous session hit from
the other side, and it is worth checking *first* every time.


## Step 5 — blink, idle motion, face states, done 2026-09-12

**Auto-blink and idle motion needed no code.** The Cubism SDK already wires eye
blink, breath, physics and pose, and plays a random idle motion whenever the
motion queue empties. Measured on Natori over twelve seconds:

| Parameter | Behaviour |
|---|---|
| `ParamEyeLOpen` / `ParamEyeROpen` | 2 blinks, full 0 to 1 |
| `ParamAngleX` / `Y`, `ParamBodyAngleX` | continuous, 200+ distinct values |
| `ParamBreath` | continuous, full range |
| `ParamMouthOpenY` | flat 0 — our hook owns it, nothing leaks in |

So the actual gap was **expressions**. Natori ships eleven and nothing selected
any of them. `live2d/glue/arisu-face.js` now maps Arisu's five states onto them,
the same five the portrait renderer uses, so the two faces stay interchangeable.

### The mapping, and why not the obvious one

| State | Expression | Why |
|---|---|---|
| idle | `Normal` | literally no parameter changes |
| listening | `exp_02` | brows up, faint smile, **eyes open** |
| thinking | `exp_04` | brows raised and drawn in, mouth small |
| speaking | `Normal` | nothing may touch `ParamMouthForm` |
| asleep | `exp_05` + forced eyes | relaxed brows, soft mouth |

Picked by reading each `.exp3.json`, not by name, and the names mislead:

- **`Smile` closes the eyes.** `ParamEyeLOpen Add -1` turns them into happy
  crescents. It is the obvious pick for listening and it is wrong — an attentive
  face with its eyes shut.
- **`Sad` and `Angry` pull `ParamMouthForm` to -2**, reshaping a mouth that lip
  sync is opening at the same time. Neither belongs anywhere near speaking.
- **Every expression writes `ParamEyeLOpen` and `ParamMouthOpenY` as `Add 0`.**
  That is what makes this layer safe to stack: an expression can never fight the
  blink or the lip sync. Worth re-checking on a bought model, which may not be
  authored so politely.

**Asleep forces the eyes shut in the hook rather than trusting `exp_05`.** The
expression does close them, but the blink updater also writes those parameters
on its own schedule, and two writers on one parameter is how you get a sleeping
face that flutters its eyelids. Verified: nine seconds at exactly 0, one
distinct value.

### The patcher bug, because it will look like something else

`patch-sdk.sh` tested for a single marker string to decide whether a file was
already patched. When a later edit added something to the same block, the marker
was still present, so **the entire block was skipped without a word** — and the
symptom is new code that appears not to load at all. That cost two rounds. The
script now wraps inserted blocks in sentinel comments and replaces them
wholesale, so a re-run updates rather than skips. Running it twice is a no-op.

### Verifying without a visible window

`window.__arisuParam('ParamEyeLOpen')` reads any parameter straight off the rig.
There is no other way to see what it is doing — the model lives in module scope,
and watching pixels to guess whether blink is running is exactly that, guessing.

To measure at all, the page must be rendering, and **`requestAnimationFrame`
stops dead when the page is not visible**. For headless checks, replacing
`window.requestAnimationFrame` with a `setTimeout` shim keeps the app's own loop
running while hidden. That belongs in the console, never in the page.


## Step 4b — `window.avatar`, done 2026-09-12, and where it stops

**The Live2D page now exposes the interface her clients already drive.** Both
her browser client (`lain/arisu/index.html`) and her iOS app load a face page in
a frame and talk to it through `face.contentWindow.avatar` — `setState()` for
the phase, `setAmplitude()` on a 50 ms tick for the mouth. Neither knows or
cares what is drawing. `live2d/glue/arisu-avatar.js` matches that surface
exactly, no-op members included.

**Verified through an actual same-origin iframe**, driven exactly as the client
drives it: the mouth ran 0 to 0.83 over 29 distinct values, and `asleep` shut
the eyes to 0.

### Host amplitude is passed through, not expanded

The lip-sync expander applies only to audio this module analyses itself. When
the host asserts an amplitude, it is used as given. That is not laziness — the
browser client injects a **synthetic 0.10 to 0.26 envelope** whenever Safari
hands back a silent analyser for a remote WebRTC stream, which it does often.
Expanding those against a running peak would floor them to zero and freeze the
mouth in precisely the case that workaround exists for. Checked both ways: a
real 0-0.8 meter reaches 0.78 and closes between peaks, and the synthetic band
still opens the mouth to 0.45.

### Reactions

`react()` maps `surprise`, `amused`, `confused`, `error`, plus `sleep`, `wake`
and `thinking` onto states. It returns **false** for anything else rather than
guessing. `nod` is unmapped on purpose: it is a head movement, not an
expression, and driving it from Natori's `TapBody` motions would fight the idle
motion queue.

A reaction holds for 2200 ms because **Cubism cross-fades an expression in over
about 880 ms and out over another 880 ms** (measured on Natori, `ParamMouthForm`
0 to -3 and back). Anything much shorter starts reverting before it has arrived,
and reads as a twitch rather than a face.

### Making it an actual lain face — done 2026-09-12

**It is live.** `https://architect-server.tailaa64e9.ts.net:8443/arisu/?face=live2d`

A face is a renderer, not a character, so it got its own switch: `?face=live2d`
swaps what draws her without touching who she is. The portrait renderer stays
the default and is untouched.

- The client reaches the face through `contentWindow`, so the page must be
  **same-origin**. Pointing the frame at a separate port will not work.
- Same-origin means the built bundle ships inside lain — **including Cubism
  Core, which is licence-gated**.
- **`ossskkar/lain` is private. `ossskkar/bender`, which holds arisu, is
  public.** That asymmetry is exactly why this repo gitignores the SDK, and it
  is why the answer cannot simply be copied across.

Vendoring redistributable-restricted files, even into a private repo, is his
call and not an expensive one to get right later. The adapter is written and
proven, so whenever that is settled the remaining work is a build step and an
iframe `src`.

### The debug probe is deliberate

`window.__arisuParam(id)` stays in the patched build on purpose. It is
read-only, it lives inside the gitignored SDK tree rather than in shipped Arisu
code, and without it there is no way to see what the rig is doing — the model is
module-scoped, and reading pixels to decide whether blink is running is
guessing.

### Do not use the Vite dev server for anything on the iPad

Its hot-reload socket cannot reach back through the tailscale proxy, so the
page reloads every few seconds and every test is worthless. Build and serve
`dist` instead. `npm run build:prod && npx vite preview --port 5001 --host`.

## Step 7 — her real voice, and the background — 2026-09-12

### The host path had the bug the module path was built to avoid

The face passes host amplitude through unexpanded, on purpose. What that left
unexamined is the layer feeding it: the browser client computed `rms * 2.2`, a
**fixed gain** — exactly what the module's own path rejected, for exactly the
reason it rejected it.

Replayed end to end against sentence-length speech at four stream levels,
reading `ParamMouthOpenY` itself:

| stream level | jaw p50, before | jaw p50, after |
|---|---|---|
| 0.15 | 0.10 | 0.47 |
| 1.00 | 0.54 | 0.45 |

Before, her mouth followed the connection rather than her voice, and never
passed 0.79 even at full scale — the top third of her range was unreachable.
After, a **12x change in stream level produces the same face**: p50 0.46,
p95 0.90, max 0.97, shut on 9% of frames, mean change 0.034 per frame.

**The expander belongs in the client, not the face.** The face cannot tell a
measured level from the synthetic envelope Safari forces, which is why it
passes host amplitude through; expanding that envelope would floor it to zero
and freeze the mouth in the one case the fallback exists for. The client knows
which of the two it is holding. So it expands what it measured and leaves the
fallback on the old fixed gain.

Two constants, both measured rather than inherited:

- **`PEAK_FLOOR` is 0.02.** At 0.05 — tried first — the peak pinned to the
  floor on a quiet stream, because 0.05 is where a quiet stream's rms peak
  actually lands, and the quiet case never expanded at all. The `< 0.005`
  dead-frame test already catches real silence, so the floor does not need to
  be high.
- **`FLOOR_RATIO` stays 0.5.** Voiced frames are bimodal on rms: a vowel
  cluster at 0.67-0.91 of the running peak, a consonant cluster at 0.07-0.32,
  and little between. Half the peak lands in that gap, so it separates the two
  rather than cutting through either.

### No classroom behind her

`back_class_normal.png` was the one thing on the page that gave away that she
came from a sample. Both edits are in `patch-sdk.sh`, so a fresh SDK does not
bring it back.

The texture is **not loaded at all**, rather than the sprite hidden at render
time — `render()` already guards on `_back`, so a hidden background would only
be a PNG fetched and uploaded to the GPU on every load. And the clear goes to
alpha zero, or removing the classroom only swaps it for a black rectangle.
Verified by putting a colour behind the frame: it shows everywhere except her,
with clean edges.

**She takes several seconds to appear, and an empty canvas before then looks
exactly like a broken build.** Both were briefly blamed on this change, until
the previous bundle turned out to do the same thing. Wait ten seconds before
believing a Live2D page is broken.

The gear icon in the corner is still the sample's, and still there.

### The five states are distinct, and the rig is alive — measured 2026-09-12

The expressions were chosen by reading parameter values and had never been
watched. They still have not been *judged* — that needs eyes — but they are no
longer unverified: each state applies a different face, and the SDK's own
animation is running underneath.

| state | expression | ParamMouthForm | brows | eyes |
|---|---|---|---|---|
| idle | Normal | 0 | 0 | open, blinking |
| listening | exp_02 | +1 | 0.1 | open, blinking |
| thinking | exp_04 | -3 | 0.2 | open, blinking |
| speaking | Normal | 0 | 0 | open, blinking |
| asleep | exp_05 | -3 | 0 | held shut at 0 |

**`thinking` and `asleep` share `ParamMouthForm = -3`.** They are told apart by
the eyes and the brows, not the mouth, which is fine while asleep holds the
eyes shut — but it is the pair to look at first if two states ever read alike.

Blink measured in `idle`: **two blinks in twelve seconds**, matching what was
measured when the rig first ran. In `speaking`, a single blink of about 450 ms
with the eyes open 92% of the time.

**A short sample will lie to you here.** Sampling a single frame caught `idle`
mid-blink and read the eyes as shut; a 4.5-second window happened to miss a
blink entirely and read `idle` as never blinking at all. Both looked like real
bugs. Sample twelve seconds and print the series before believing either.

### The test overlay hides itself when framed — fixed 2026-09-12

Shipping the face inside lain shipped the debug bar with it. `?face=live2d`
loads the page in an iframe, the overlay built unconditionally, and a row of
test buttons and an amplitude meter sat on top of her face on the iPad.

**Two things were wrong, and the second hid the first.** `showPanel(false)` set
`bar.hidden`, and the bar carries an inline `display:flex` — an inline style
outranks the user agent's `[hidden]{display:none}`, so the only means of hiding
it had always been a silent no-op. Nobody noticed because nothing called it.
Both now go through `style.display`.

The overlay is hidden when `window.self !== window.top` and shown otherwise, so
the five state buttons still work the way they are meant to be used, by opening
`/arisu/live2d/` directly. `avatar.showPanel(true)` brings it back inside the
frame. Verified all three ways: standalone `flex`, framed `none`, and
`showPanel` toggling `flex`/`none` across the iframe boundary.

This is why the overlay is no longer "the one piece meant to be deleted". It
costs nothing when framed and it is the only hand test of the rig.
