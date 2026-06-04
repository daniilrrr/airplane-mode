# Running a Local LLM Offline (Plane / No-WiFi) — Complete Tutorial

A front-to-back guide for running a local coding LLM on your Mac, built for
offline work (flights, no-WiFi). Written for someone new to local LLMs.

> **WiFi legend used throughout this doc:**
> - 🛜 **NEEDS GOOD WIFI** — must be done *before* you fly. Downloads from the internet.
> - ✈️ **OFFLINE OK** — works with no connection. Safe to do on the plane.

---

## ✈ Quickstart: "Airplane Mode" (the one-stop setup)

The fastest path is the bundled **`airplane-mode.sh`** script. It installs the
official Ollama, lets you pick your Qwen3 model (defaults to the coding model),
writes the tuned env vars, installs the OpenCode harness, and runs a smoke test —
then gives you a single `airplane-mode` command to launch the whole stack.

```bash
# 🛜 Run once on good WiFi (it acknowledges a security notice, then sets everything up):
bash airplane-mode.sh

# ✈️ After that, any time you want to code offline:
airplane-mode                 # launches OpenCode + your model
airplane-mode qwen3.6:27b     # or pick a different model
```

> ### ⚠️ Security first
> A coding agent runs with **your** permissions — it can read/write files and run
> shell commands. Treat the harness, the model, and **especially any
> plugins/extensions/skills** as potential **attack surfaces** and supply-chain
> risk. Airplane Mode deliberately bundles **only** official Ollama + Qwen3 +
> OpenCode — **no third-party plugins**. For sensitive/proprietary repos, clear
> agent usage with your security/AppSec team and consider sandboxing.

**What Airplane Mode bundles:**

| Component | What | Why it's trusted |
| --------- | ---- | ---------------- |
| **Ollama** (official installer) | model runtime | NOT Homebrew (brew bottle is broken — see Part 1) |
| **Qwen3 model** | the brain | `qwen3-coder:30b` (coding, default) or `qwen3.6:27b` (reasoning) |
| **OpenCode** | the harness | open-source, by SST; leaner prompt than Claude Code |
| **Tuned env vars** | config | 64k context, flash attention, q8_0 KV cache, offline mode |

The rest of this doc explains every piece in detail (and how to do it manually).

---

## TL;DR (the manual path, in 6 steps)

```bash
# 1. 🛜 Install Ollama — OFFICIAL installer, NOT brew (brew bottle is broken)
curl -fsSL https://ollama.com/install.sh | sh

# 2. 🛜 Download your model (good wifi — THIS is the critical offline-prep step)
ollama pull qwen3-coder:30b      # coding (default) — see model-by-task rule

# 3. ✈️ Verify it's on disk
ollama list

# 4. ✈️ Configure for offline coding (see env vars below)

# 5. ✈️ Launch your coding tool wired to the local model
ollama launch opencode --model qwen3-coder:30b

# 6. ✈️ Turn WiFi OFF and test before you fly
```

**The one rule that matters most:** a model only runs offline *after* `ollama pull`
finishes downloading it. Pull on good WiFi (hotel/home), never on plane WiFi.

---

## Part 1 — Install Ollama

**🛜 NEEDS GOOD WIFI**

Ollama is the easiest way to run local models — think "Docker for LLMs." It runs
`llama.cpp` under the hood and auto-configures coding tools like Claude Code and
OpenCode.

> ### ⚠️ USE THE OFFICIAL INSTALLER — NOT HOMEBREW (hard-won lesson)
>
> **Do NOT use `brew install ollama`.** The Homebrew bottle ships *without* the
> `llama-server` inference engine binary and the Metal GPU backend. You'll get
> 500 errors like:
> ```
> error starting llama-server: llama-server binary not found ...
> Run 'cmake -S llama/server --preset cpu && cmake --build --preset cpu' first
> ```
> **That cmake suggestion is a red herring** (it's for source builds). The real
> fix is to use the official build, which bundles everything pre-compiled for
> Apple Silicon.

```bash
# ✅ Official install script (CLI — recommended)
curl -fsSL https://ollama.com/install.sh | sh
```

Or download the `.dmg` from [ollama.com/download](https://ollama.com/download) and
drag Ollama to Applications (the CLI comes with it; you can ignore the menubar app).
Needs **v0.15+** for the `ollama launch` command.

**If you already installed via brew and hit the error:**
```bash
brew uninstall ollama                       # your models in ~/.ollama/models are SAFE
curl -fsSL https://ollama.com/install.sh | sh
which ollama                                # should now be /usr/local/bin/ollama
```

Start the server:

```bash
ollama serve
```

> **How to confirm it's healthy:** in the `ollama serve` logs after a model loads,
> look for `offloaded NN/NN layers to GPU` and `library=Metal`. That means the
> model is running fully on your Apple GPU (not CPU). `reason=metal_partial_offload`
> with all layers offloaded is normal/fine.

---

## Part 2 — Download a Model (the critical offline-prep step)

**🛜 NEEDS GOOD WIFI — do this before you fly**

The model is only cached to disk *after* the pull completes. Once downloaded, it
runs 100% offline.

```bash
# Recommended: the current Qwen3.6 line (updated continuously — verify on ollama.com/search)
ollama pull qwen3.6:27b        # 17GB dense — roomy, great default

# Battle-tested fallback (8 months old, fewer kinks)
ollama pull qwen3-coder:30b    # 19GB MoE
```

**🛜** Verify the download succeeded:

```bash
ollama list                    # confirms the model is on disk
ollama show qwen3.6:27b        # inspect params, quant, context, license
```

### IMPORTANT: `ollama pull qwen3-coder` is NOT the latest model

- `ollama pull qwen3-coder` resolves to `qwen3-coder:30b` — a solid 19GB model, but
  **~8 months old.**
- The current line is **`qwen3.6`** (updated within days). `ollama run qwen3.6`
  defaults to `qwen3.6:35b-a3b` (24GB, q4, 256K context, MoE with 3B active).
- Always check the live library at **[ollama.com/search](https://ollama.com/search)**
  or `ollama.com/library/<model>/tags` for the newest tags and exact sizes.

### Which model should I pull? (depends on your USABLE memory, not total)

The hard rule: **the model + its KV cache must both fit in available unified
memory**, or it spills to CPU and crawls (and drains battery faster).

**Your total RAM is NOT your budget.** Subtract the OS and everything else running:

| What's eating RAM            | Typical cost |
| ---------------------------- | ------------ |
| macOS + background/menubar   | ~8–10 GB     |
| One JetBrains IDE (RustRover/GoLand) | ~3 GB |
| Browser / Slack / terminal / misc    | ~2–4 GB |

> **Worked example — 36GB Mac with one IDE open:**
> 36GB − ~9GB (OS) − ~3GB (IDE) − ~3GB (misc) ≈ **~21GB usable** for the model + cache.
> Close the second IDE you're not using to reclaim ~3GB — meaningful at this budget.

**Model fit table (with a 64k context + `q8_0` KV cache):**

| Model | Model size | + 64k KV (q8_0) | Fits ~18–22GB usable (1 IDE open)? |
| ----- | ---------- | --------------- | ---------------------------------- |
| `qwen3.6:27b` (q4)        | 17GB | ~20–21GB | ✅ Comfortably — **recommended** |
| `qwen3-coder:30b`         | 19GB | ~22–23GB | ⚠️ Borderline (good fallback)    |
| `qwen3.6:35b-a3b` (q4)    | 24GB | ~27–28GB | ❌ Too tight w/ IDE (offloads to CPU) |
| `qwen3.6:27b-q8_0`        | 30GB | —        | ❌ Eats your whole budget          |
| `qwen3.6:35b-a3b-q8_0`    | 39GB | —        | ❌ Too big                         |

**Recommendation for a 36GB Mac that runs an IDE alongside:** `qwen3.6:27b`. It's the
*dense* model (a touch smarter than the 35B MoE per community testing, just slightly
slower), leaves room for an IDE + 64k context, and runs cooler — which matters on a
14" chassis under sustained load. The 35B MoE is faster but needs the machine mostly
to itself (close IDEs, dial context to ~32k).

Check your memory: **Apple menu → About This Mac → Memory.** Verify the model fits on
GPU after launch with `ollama ps` (look for `100% GPU`).

> **Apple Silicon note:** M-series Macs get Metal GPU acceleration automatically —
> no setup needed. A well-quantized smaller model beats a butchered big one;
> don't cram an oversized model at aggressive quant (<Q8) just to fit it — it
> compounds into loops/errors as context grows.

### Where models are stored (for backup / verification)

- macOS: `~/.ollama/models`
- Linux: `/usr/share/ollama/.ollama/models`
- Windows: `C:\Users\<you>\.ollama\models`

Change the location with `OLLAMA_MODELS=/your/path` (e.g. an external SSD).

---

## Part 3 — Configure for Offline Coding

**✈️ OFFLINE OK** (configuration only — no downloads)

These settings make the difference between a smooth flight and a frustrating one.

### The env vars that matter

| Variable                  | Value     | Why                                                   |
| ------------------------- | --------- | ----------------------------------------------------- |
| `OLLAMA_CONTEXT_LENGTH`   | `64000`   | Coding/agents need ≥64k; defaults are too small       |
| `OLLAMA_FLASH_ATTENTION`  | `1`       | Cuts memory growth as context grows                   |
| `OLLAMA_KV_CACHE_TYPE`    | `q8_0`    | ~half the KV cache memory, ~no quality loss           |
| `OLLAMA_KEEP_ALIVE`       | `-1`      | Keep model pinned in RAM (default unloads after 5min) |
| `OLLAMA_NO_CLOUD`         | `1`       | Force true offline; never phone home                  |

### Setting them — two ways depending on how you run Ollama

**If you run `ollama serve` in a terminal:** prefix the command.

```bash
OLLAMA_CONTEXT_LENGTH=64000 \
OLLAMA_FLASH_ATTENTION=1 \
OLLAMA_KV_CACHE_TYPE=q8_0 \
OLLAMA_KEEP_ALIVE=-1 \
OLLAMA_NO_CLOUD=1 \
ollama serve
```

**If you run the Ollama menubar app on macOS (the gotcha):** shell env vars won't
reach the app. You must use `launchctl`, then restart the app.

```bash
launchctl setenv OLLAMA_CONTEXT_LENGTH "64000"
launchctl setenv OLLAMA_FLASH_ATTENTION "1"
launchctl setenv OLLAMA_KV_CACHE_TYPE "q8_0"
launchctl setenv OLLAMA_KEEP_ALIVE "-1"
launchctl setenv OLLAMA_NO_CLOUD "1"
# then QUIT and REOPEN the Ollama app
```

### Alternative: set context length live inside a session

```bash
/set parameter num_ctx 64000
```

### Force true offline mode (belt-and-suspenders)

Either the `OLLAMA_NO_CLOUD=1` env var above, or edit `~/.ollama/server.json`:

```json
{ "disable_ollama_cloud": true }
```

Logs will confirm `Ollama cloud disabled: true`.

---

## Part 4 — Launch Your Coding Tool

**✈️ OFFLINE OK** (after the model is already pulled)

### Option A — Claude Code (feels like home if you're a `claude code` user)

One-liner:

```bash
ollama launch claude
```

Or wire it manually (points Claude Code's API at the local Ollama server):

```bash
export ANTHROPIC_AUTH_TOKEN=ollama
export ANTHROPIC_API_KEY=""
export ANTHROPIC_BASE_URL=http://localhost:11434
claude --model qwen3-coder
```

Headless / scripted mode:

```bash
ollama launch claude --model qwen3-coder --yes -- -p "how does this repo work?"
```

`--yes` auto-pulls + skips the selector. Everything after `--` is passed to Claude Code.

### Option B — OpenCode

```bash
ollama launch opencode
```

> Note: `ollama launch opencode` injects config inline via `OPENCODE_CONFIG_CONTENT`
> but still deep-merges your existing `~/.config/opencode/opencode.json`. Models
> declared *only* in that file won't show in the launch picker.

---

## Part 5 — Verify & Test Before You Fly

**✈️ OFFLINE OK — do this on the ground with WiFi OFF**

```bash
# Turn WiFi OFF first, then:
ollama launch claude        # run a small test task

# In another terminal, confirm the setup is healthy:
ollama ps
```

In `ollama ps`, verify:
- **PROCESSOR** column shows `100% GPU` (not CPU or a split — CPU means it'll crawl)
- **CONTEXT** column shows `64000` (or your target)

If it works on the ground with WiFi off, it works at 40,000 feet.

---

## Part 6 — In-Flight Survival Tips

**✈️ OFFLINE OK — this is the stuff that actually makes or breaks the flight**

### 1. The #1 killer: infinite loops

Models can spin in "Wait, actually... on second thought..." loops. Two fixes:

**Set sampling params correctly** (from the Qwen3.6 model card — fixes most loops):

- **Precise coding:** `temperature=0.6, top_p=0.95, top_k=20, min_p=0.0, presence_penalty=0.0, repetition_penalty=1.0`
- **General:** `temperature=1.0, top_p=0.95, top_k=20, min_p=0.0`

**Cap the reasoning budget** (if using llama.cpp directly): `--reasoning-budget 1024`
to force it to stop deliberating and answer.

### 2. One problem per session (most-repeated advice)

Don't let it grind for hours on a huge task — it *will* choke or loop. Do small
chunks, clear context (restart the harness), repeat. Write long plans to a
markdown file the model re-reads. This even works better for Claude itself.

### 3. Avoid compaction

It's painfully slow locally. Restart fresh with a plan in a markdown file instead.

### 4. Battery & heat management

- Sustained inference drains ~1%/min even while plugged into 60W.
- **Use a real laptop charging cable, not an iPhone cable** — one HN test lost 34W
  (36%!) to a weak cable and throttled the whole flight. Bring your beefy USB-C cable.
- Some plane sockets cut out entirely if you exceed their draw limit.

### 5. Model loading

- Keep the model pinned with `OLLAMA_KEEP_ALIVE=-1` so it doesn't unload mid-task.
- Preload before you need it: `ollama run qwen3-coder:30b ""`

---

## Performance: Why It Feels Slow (and how to fix it)

A local model that takes ~2 minutes to answer "hello" is almost never the model
being slow — it's these, in order of impact:

**1. The harness injects a HUGE system prompt.** Claude Code stuffs ~25,000+ tokens
of system prompt/context in front of your message. At ~600 tokens/sec prefill,
that's *45-70 seconds just reading the prompt* before it responds. Check your
`ollama serve` logs for `task.n_tokens = 26454` (or similar) — that's the culprit.
- **Fix:** Use **OpenCode** (`ollama launch opencode`) — it injects a *leaner*
  prompt than Claude Code, which is tuned for huge-context Claude.

**2. Thinking mode adds a long delay.** `qwen3.6` is a *thinking model* — it
generates a long internal reasoning block before every answer ("Thought for 1m 42s").
- **Fix:** Turn OFF thinking/extended reasoning for quick tasks, or use a
  non-thinking model. You don't need deep reasoning to chat.

**3. Context keeps growing in agentic loops.** Every grep/file-read/tool-call gets
appended to context, and the model re-prefills the new tokens each turn. The static
system prompt caches after msg 1, but tool output does not.

**4. ⚠️ Architecture matters for caching.** `qwen3.6` uses a *hybrid/recurrent*
architecture (SSM / Gated-DeltaNet layers). Its KV cache doesn't behave like a
standard transformer — you may see this in the logs:
```
forcing full prompt re-processing due to lack of cache data
(likely due to SWA or hybrid/recurrent memory)
```
That means it sometimes **re-processes the whole prompt from scratch** even on a
cache "hit" — painful in long, tool-heavy sessions.

**Healthy speed reference (27B on M5 Max):** ~20 tokens/sec generation,
~600 tokens/sec prompt processing. If you're in that range, the model is fine —
the wait is prompt size + thinking, not raw speed.

---

## Choosing a Model for Agentic Coding (grep a repo + write a PR)

For tool-heavy work — grepping a repo, reading many files, editing code in a loop —
**`qwen3-coder:30b` is the better pick than `qwen3.6`**, even though qwen3.6 is newer:

| Factor | `qwen3-coder:30b` | `qwen3.6:27b` |
| ------ | ----------------- | ------------- |
| Architecture | Standard transformer → **clean KV caching** | Hybrid/recurrent → re-prefills more |
| Tuning | Purpose-built for **agentic coding** (SWE-Bench) | Smarter generalist + vision |
| Thinking delays | Minimal — just does the work | Long `<think>` blocks per turn |
| Context | 256K | 256K |
| **Best for** | **Repo grep + PR loops** | Chat, reasoning, one-shot tasks |

**Recommended agentic combo:**
```bash
ollama launch opencode --model qwen3-coder:30b
```
OpenCode (leaner prompt) + qwen3-coder:30b (clean caching, coding-tuned).

### Rule of thumb: pick the model by the TASK

- **Coding / agentic work (grep, edit, PRs, refactors) → `qwen3-coder:30b`.** It's
  purpose-built for code, caches cleanly for tool-heavy loops, and skips the slow
  thinking blocks. This is your default for anything in a repo.
- **Non-coding / reasoning / chat (planning, explanations, analysis, questions)
  → `qwen3.6:27b`.** It's the smarter generalist with stronger reasoning (and
  vision), and the thinking blocks that slow it down for coding are actually useful
  here.

Keep both pulled and switch with `--model` depending on what you're doing:
```bash
ollama launch opencode --model qwen3-coder:30b   # coding
ollama run qwen3.6:27b                            # reasoning / chat / planning
```

### Surviving a large monorepo (e.g. `mono`)

Grepping a huge repo will blow your context budget and crush speed. Discipline:
- **One focused task per session** — "in `path/to/service`, change X," not
  "understand the whole repo."
- **Point it at specific dirs/files**, not the whole tree.
- **Write your plan to a markdown file** and have the model work against that.
- Restart the session (clear context) between distinct tasks.

---

## Tool Comparison: Ollama vs. the Alternatives

| Tool          | Best for                          | Trade-off                              |
| ------------- | --------------------------------- | -------------------------------------- |
| **Ollama**    | Easiest start; closest to `claude code` | Less tunable; finicky with brand-new models |
| **LM Studio** | GUI-first; nice model browser     | Heavier; GUI-centric vs terminal       |
| **oMLX**      | Apple Silicon power users; tiered KV cache persists context across restarts; multi-model serving | Mac-only; more setup & knobs |
| **llama.cpp** | Max control & raw performance     | Hand-tune everything yourself          |

**Recommendation:** Start with **Ollama**. Graduate to **oMLX** later only if you
hit its niche (persistent KV cache across restarts, multi-model serving, or you
want to squeeze max perf-per-watt out of Apple Silicon on battery).

---

## The "Before You Fly" Checklist

```
🛜 ON GOOD WIFI:
  1. curl -fsSL https://ollama.com/install.sh | sh   # OFFICIAL — not brew!
  2. ollama pull qwen3-coder:30b   # best for agentic coding / repo+PR work
     ollama pull qwen3.6:27b       # optional: smarter generalist / chat
  3. ollama list                  # confirm model is on disk

✈️ CAN DO OFFLINE:
  4. Set env vars in ~/.zshrc (brew/official CLI — no launchctl needed):
       OLLAMA_CONTEXT_LENGTH=64000
       OLLAMA_FLASH_ATTENTION=1
       OLLAMA_KV_CACHE_TYPE=q8_0    # halves KV cache — critical on tight RAM
       OLLAMA_KEEP_ALIVE=-1
       OLLAMA_NO_CLOUD=1
  5. ollama launch opencode --model qwen3-coder:30b   # leaner prompt + clean cache
  6. Turn WiFi OFF, run a test task
  7. ollama ps  →  verify 100% GPU + CONTEXT 64000
  8. Watch serve logs: confirm "offloaded NN/NN layers to GPU" + library=Metal
  9. Close the IDE you're not using (frees ~3GB on a tight budget)
 10. Pack your beefy USB-C charging cable (not an iPhone cable)
```

---

## Managing Models on Disk

```bash
ollama list                       # models registered on disk (name, size, ID)
ollama show <model>               # params, quant, context, license
ollama ps                         # what's loaded now + GPU/CPU split
ollama rm <model>                 # delete a completed model
du -sh ~/.ollama/models           # total disk used by all Ollama models
```

### Cleaning up an aborted / partial pull

If you `Ctrl+C` a `pull`, the download stops but the **partial blob stays on disk**
(Ollama keeps it so you can resume). It won't show in `ollama list` (the manifest
never completed), but it still uses space.

```bash
# 1. Try the clean removal (works if a manifest exists)
ollama rm qwen3.6:35b-a3b

# 2. If that says "not found", clear the orphaned partial blob(s):
ls -lh ~/.ollama/models/blobs/ | grep -i partial
rm -f ~/.ollama/models/blobs/*partial*

# 3. Confirm space reclaimed
du -sh ~/.ollama/models
ollama list
```

> Re-running the same `ollama pull` will **resume** from the partial rather than
> restart — handy if you got most of the way and want to finish it instead.

---

## Troubleshooting (real issues hit)

### `llama-server binary not found` / 500 errors on every request

**Cause:** you installed Ollama via Homebrew, whose bottle ships without the
inference engine. **Fix:** reinstall with the official installer (see Part 1).
Don't run the `cmake` command the error suggests — that's for source builds.

```bash
brew uninstall ollama
curl -fsSL https://ollama.com/install.sh | sh
```

### Error logs reference paths inside your work repo (e.g. `~/yourrepo/build/...`)

That's a red herring — Ollama checks paths relative to your *current working
directory*. It's not the cause; the missing binary is. Verify there's no PATH
shadow and no rogue env var:
```bash
which -a ollama          # should be ONE path, the official/brew bin
env | grep -i ollama     # should only show your intended OLLAMA_* vars
```

### Model runs on CPU instead of GPU (slow)

Check `ollama serve` logs for `library=Metal` and `offloaded NN/NN layers to GPU`.
If it's on CPU: the model + KV cache don't fit in available memory. Close apps/IDE,
use `OLLAMA_KV_CACHE_TYPE=q8_0`, drop the context size, or pick a smaller model.
Confirm fit with `ollama ps` → `PROCESSOR = 100% GPU`.

### Responses take ~2 minutes even for "hello"

Not a hardware problem — see **Performance: Why It Feels Slow** above. It's the
harness's giant system prompt + thinking mode, not raw speed.

---

## Field Notes (Daniil — 14" M5 Max, 36GB)

Real-world results from actually running this setup:

- **OpenCode + `qwen3-coder:30b` is a usable harness+model combo.** Gets results in
  about **30–60 seconds** for typical tasks. This is the recommended pairing.
- **Claude Code is noticeably slower — 1–2+ minutes** to reply even to simple tasks,
  almost certainly due to its enormous injected system context (~26k tokens of prompt
  before your message is even read).
- **The machine gets HOT under sustained inference** — exactly as the flight blogger
  warned about the 14" chassis. Plan for it on a plane (insulation, watch thermals).

**Takeaway:** for this hardware, go **OpenCode + qwen3-coder:30b**, not Claude Code,
if you care about response latency.

**Model-by-task rule:** use **`qwen3-coder:30b` for coding** (repos, edits, PRs) and
**`qwen3.6:27b` for non-coding/reasoning** (planning, explanations, analysis). Keep
both pulled and swap with `--model`.

---

## Sources

The four starting references this guide was built from:

- [Running Local LLMs Offline on a Ten-Hour Flight](https://deploy.live/blog/running-local-llms-offline-on-a-ten-hour-flight/) — the field report (the original blog)
- [Hacker News discussion](https://news.ycombinator.com/item?id=47921064) — sampling params, loop fixes, hardware notes (the HN thread)
- [oMLX](https://github.com/jundot/omlx) — Apple Silicon inference server with tiered KV caching
- [Ollama launch blog](https://ollama.com/blog/launch) — `ollama launch` for coding tools

Additional references gathered during research:

- [Official Ollama docs](https://docs.ollama.com/) — CLI, context length, FAQ, integrations, hardware, troubleshooting
- [Ollama model library](https://ollama.com/search) — browse models, tags, and exact sizes
- [Pi coding agent](https://pi.dev) / [Pi packages](https://pi.dev/packages) — minimal extensible harness + extension catalog
- [OpenCode](https://opencode.ai) — open-source terminal coding agent (by SST)
