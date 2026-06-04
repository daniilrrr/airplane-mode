# ✈ Airplane Mode

**One-stop setup for offline local LLM coding on your Mac.** Built for flights and
no-WiFi situations — get a real coding agent running locally with one command.

Bundles the official **Ollama** runtime, **Qwen3** models, and the **OpenCode**
harness, with environment settings tuned for Apple Silicon.

> **Note:** The default model choices and tuned settings in this repo were dialed in
> for a **14" MacBook Pro (M-series, 36GB unified memory)**. They're a solid starting
> point for similar Apple Silicon Macs, but if you have more or less memory, adjust
> the model size and context accordingly — see [GUIDE.md](./GUIDE.md) for the memory
> math.

---

## ⚠️ Security first — read this

A coding agent runs with **your** user permissions. It can read/write files and
execute shell commands. Treat **every** component — the harness, the model, and
**especially any plugins / extensions / skills** — as a potential **attack surface**
and supply-chain risk.

Airplane Mode deliberately bundles **only**:

- **Ollama** — official installer (not Homebrew)
- **Qwen3** — models from the official Ollama library
- **OpenCode** — open-source harness by [SST](https://github.com/sst/opencode)

It installs **no third-party plugins, extensions, MCP servers, or skills.** If you
add any yourself, you own that risk. **For work on sensitive or proprietary
repositories, clear agent usage with your security/AppSec team first**, and consider
running the agent inside a container/sandbox.

---

## Quickstart

```bash
# 1. 🛜 Clone + run once on good WiFi (acknowledges a security notice, then sets up)
git clone https://github.com/daniilrrr/airplane-mode.git
cd airplane-mode
bash ./src/airplane-mode.sh

# 2. ✈️ Any time you want to code offline:
airplane-mode                 # launches OpenCode + your model
airplane-mode qwen3.6:27b     # or pick a different model
```

**Before you fly:** turn WiFi OFF on the ground and run a real task. If it works
dry, it works at 40,000 feet.

---

## What the script does

| Step | Action | WiFi? |
| ---- | ------ | ----- |
| 1 | Security acknowledgment gate (type `yes`) | — |
| 2 | Verify macOS + Apple Silicon | — |
| 3 | Install **official** Ollama (rejects the broken Homebrew build) | 🛜 |
| 4 | Start the Ollama server in offline mode | — |
| 5 | **Pick your model** (defaults to `qwen3-coder:30b`) and pull it | 🛜 |
| 6 | Write tuned env vars + an `airplane-mode` launcher to your shell profile | — |
| 7 | Install **OpenCode** | 🛜 |
| 8 | Smoke test (loads the model on GPU, up to a 3-min timeout) | — |

Everything after the pulls works fully offline.

---

## Model-by-task

| Model | Use for | Size |
| ----- | ------- | ---- |
| **`qwen3-coder:30b`** | **Coding** — repos, edits, PRs, refactors (default) | 19GB |
| **`qwen3.6:27b`** | Reasoning / chat / planning | 17GB |

Use the coding model for repo work (it caches cleanly and skips slow "thinking"
blocks); use the reasoning model for non-coding tasks. Switch with
`airplane-mode <model>`.

---

## Requirements

- macOS Sonoma (14) or newer
- **Apple Silicon** (M-series) strongly recommended — Metal GPU acceleration
- ~20–40GB free disk (per model)
- Enough unified memory: the model + its KV cache must fit. **16GB is tight; 24GB+
  comfortable; 36GB+ ideal.** Remember your IDE and other apps eat into this — see
  [GUIDE.md](./GUIDE.md) for the memory math.

> Reference machine for the defaults: **14" MacBook Pro, M-series, 36GB unified memory.**

---

## Tuned environment variables

The script writes these to your shell profile:

| Variable | Value | Why |
| -------- | ----- | --- |
| `OLLAMA_CONTEXT_LENGTH` | `64000` | Coding/agents need a big context window |
| `OLLAMA_FLASH_ATTENTION` | `1` | Cuts memory growth as context grows |
| `OLLAMA_KV_CACHE_TYPE` | `q8_0` | ~half the KV cache memory, ~no quality loss |
| `OLLAMA_KEEP_ALIVE` | `-1` | Keep the model pinned in memory |
| `OLLAMA_NO_CLOUD` | `1` | Force true offline — never phone home |

---

## Full guide

See **[GUIDE.md](./GUIDE.md)** for the complete walkthrough: install details,
the memory budgeting math, performance tuning, troubleshooting (including the
"`llama-server` not found" Homebrew gotcha), harness comparison, and in-flight
survival tips.

---

## Troubleshooting (quick hits)

- **`llama-server binary not found` / 500 errors** → you have the Homebrew Ollama.
  `brew uninstall ollama` and re-run the script. (Don't run the `cmake` command the
  error suggests — that's a red herring.)
- **Slow responses (1–2 min)** → usually the harness's huge system prompt + a
  model's "thinking" mode, not raw speed. OpenCode + `qwen3-coder:30b` is the
  snappy combo. See GUIDE.md → *Performance*.
- **Running on CPU instead of GPU** → the model doesn't fit in memory. Close apps,
  use a smaller model, or lower the context. Confirm with `ollama ps` →
  `PROCESSOR = 100% GPU`.

---

## License

MIT