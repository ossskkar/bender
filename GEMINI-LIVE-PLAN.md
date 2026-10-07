# Arisu on Gemini Live — plan for a decision (2026-10-07)

Nothing here is built. Building starts only on Oscar's explicit go.

## Why
Today every turn is a relay: her OpenAI voice model plans (~0.9 s) → Hermes
thinks on Gemini (~2 s per model call, 2+ calls with a tool) → her voice model
speaks (~0.9 s). Median first word 4.9 s, 1 in 10 turns over 14 s (167 real
turns, 30 Sep–6 Oct). Tuning got simple turns to ~1.5 s; the relay itself is
the ceiling. ChatGPT/Claude voice feel fast because one model hears, thinks
and speaks.

## Measured (test on architect, synthetic speech, real `my_day` data)
Time from the end of his speech to her first sound, tool calls included:

| model | greeting | "what's next" (my_day) | "light blue" (light) |
|---|---|---|---|
| **Gemini 3.1 Flash Live** | 1.5–1.6 s | 1.7–1.9 s | 1.7–2.0 s |
| Gemini 3.8 Live | 1.5–1.9 s | 2.0 s | 1.8–2.3 s |
| Gemini 2.5 Flash Native Audio | no answer | 5.5 s | 4.3 s |
| today's Arisu (real calls) | ~1.5 s | 4–6 s | 4–6 s |

Three runs per model (one 3.8 run lost its tool turns to a test bug).
Figures checked against the raw output with Jev; one range corrected.
Answers were correct and called the right tool with the right arguments.
Seen: "Hey Arisu" heard as "care su" (synthetic voice), and a habit of
ending with "Anything else?" — both prompt work.

## Cost (Google's price page, 2026-10-07)
3.1 Flash Live / 3.8 Live: audio in $0.005/min, her speech out $0.018/min,
text $0.75/M in, $4.50/M out. A measured turn ≈ $0.0025. **Estimate**:
30 min of talking a day ≈ $0.30/day ≈ €8–10/month; an open mic with nobody
talking still bills audio in ($0.30/hour), so she must stop listening when
idle, as today. Not measured: the current OpenAI realtime bill, so no
before/after on cost yet.

## Design
- **One Gemini Live session holds the conversation** (voice in, voice out,
  barge-in built in). Recommended model: 3.1 Flash Live (fastest, cheapest
  per turn); 3.8 Live as the fallback if 3.1's answers prove too thin.
- **She calls lain tools directly** (my_day, planner, to-do, habits, diary,
  light, memory, chat search) through lain's existing `/arisu/tool` door.
- **Hermes stays for heavy jobs** only — coding tasks, email, web research,
  backlog edits — as one `think` tool, the slow path, said as such.
- **Privacy:** her voice moves off OpenAI onto Gemini, which closes the open
  Backlog item (his rule: Gemini or Anthropic only).
- **Security:** lain mints a short-lived token per screen (1 min to connect,
  30 min per session, config locked server-side); the API key never leaves
  architect. Sessions over ~10 min reconnect with session resumption.

## Stages (each needs his go, each keeps today's voice as fallback)
1. lain: token minting + tool bridge + her instructions. Web page first,
   behind a switch (`?live=gemini`), today's voice untouched.
2. Real calls on the web; measure first word and correctness from the log.
3. iPad app, same switch; rebuild and install.
4. Make it the default only when 2–3 are proven; remove OpenAI after.

## Open before stage 1
- Voice: audition the prebuilt Gemini voices (AI Studio) for her character.
- Her face: lip-sync reads her audio level — new audio stream, same idea;
  needs checking on the iPad.
- Preview model: 3.1 Flash Live is a preview and may change or be renamed.
