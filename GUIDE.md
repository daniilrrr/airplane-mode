# Prepare and use offline coding

Start with the [README quickstart](README.md). Complete setup and updates while
online. Ordinary launches use downloaded models only.

## Prepare models

The Ollama default is `qwen3.8:27b-q4_K_M`. Setup offers that exact tag,
`qwen3-coder:30b`, or both. The first selected model becomes your launch default.
To add the alternative later, run this while online:

```bash
OLLAMA_HOST=127.0.0.1:11434 ollama pull qwen3-coder:30b
airplane-mode qwen3-coder:30b
```

Use `ollama list` to inspect downloads and `ollama show MODEL` to inspect an exact
model. See the [Ollama model library](https://ollama.com/library) for available tags.
The launcher's missing-model error prints the preparation command instead of
starting a download.

## Check offline operation

Turn Wi-Fi off on the ground. Run `airplane-mode` in a small local repository.
Ask OpenCode to inspect a file and make a small change, then review the diff.
This checks the coding tool, model, and project commands together. A model-only
smoke test cannot prove that your project's dependencies work offline.

During the session, run `ollama ps` in another terminal. Check the loaded model,
processor allocation, and context. If memory pressure is high, close other
applications or use a smaller model or context. Model weights, context state,
runtime buffers, and other applications all share unified memory. Quantization
and cache choices have model-dependent tradeoffs.

The generated launcher requests 64,000 tokens of context, flash attention,
`q8_0` cache, and indefinite keep-alive. Those settings apply before a new Ollama
server starts. An existing server keeps its original settings. Quit that server
or the Ollama app yourself, then run `airplane-mode` to start a tuned server.
Setup and launch never stop an existing server. See the [Ollama FAQ](https://docs.ollama.com/faq)
and [context documentation](https://docs.ollama.com/context-length) for adjustments.

## Maintain tools

```bash
bash src/airplane-mode.sh --update
```

The update command upgrades only already-installed OpenCode and the selected
engine. It preserves Homebrew formula installations, the official Ollama app,
and OpenCode's official `~/.opencode` installation. Homebrew-managed Ollama casks
also use Homebrew. It refuses unrecognized managers with a manual-update hint.
It does not change models or shell profiles. The official Ollama updater may
close the Ollama app while replacing it. Start the app or run `airplane-mode`
afterward. Restart any older server yourself to use the updated engine.
Rerun normal setup to refresh the managed launcher after updating this repository.

New OpenCode installations prefer Homebrew. Without Homebrew, setup uses the
[official v2 installer](https://opencode.ai/v2/install). OpenCode v2 is required.
An existing v1 installation needs an explicit upgrade. See [OpenCode installation
and update instructions](https://opencode.ai/docs/) and [Ollama updates](https://docs.ollama.com/faq#how-can-i-upgrade-ollama).
Existing OpenCode settings remain untouched. `--standalone` keeps each launch
independent of an already-running OpenCode service.

## Use llama.cpp instead

```bash
bash src/airplane-mode.sh --engine llama.cpp
```

This installs missing `llama-server` through Homebrew and prepares a GGUF while
online. The default source is
[`unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_M`](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF).
Its file is `Qwen3.8-27B-UD-Q4_K_M.gguf`. The menu also offers
[`Qwen/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M`](https://huggingface.co/Qwen/Qwen3-Coder-30B-A3B-Instruct-GGUF)
as a fallback. These are separate downloads from Ollama's model store.

Preparation must reach a healthy temporary server before setup continues.
Normal launches use `--offline`, start a local server on port 8080, and register
its OpenAI-compatible endpoint with OpenCode for that invocation. Your global
OpenCode provider settings stay unchanged. `airplane-serve` starts only the
server. `airplane-mode` starts the server and OpenCode. Both use the model
selected during setup and reject a different repository argument. To change
models, rerun setup while online to select and prepare the new default, source
the updated profile, then stop the old server yourself before launching.
See the [llama.cpp server documentation](https://github.com/ggml-org/llama.cpp/tree/master/tools/server)
for cache locations and server options.

## Resolve launch failures

- If a model is missing, run the printed download command while online.
- If readiness fails, read `~/.airplane-ollama.log` or `~/.airplane-llamacpp.log`.
  GGUF preparation logs are in `~/.airplane-llamacpp-download.log`.
- If port 18080 is occupied, stop its owner yourself before GGUF preparation.
- If an Ollama backend fails, inspect its logs and installation before replacing
  it. Both official and Homebrew installations are supported.
- If profile markers are malformed, repair the marked block before rerunning.
  Setup refuses ambiguous replacements and keeps backups next to the profile.

To verify changes to this repository without installing tools or downloading
models, run `bash tests/launcher.sh`. It exercises the emitted launchers under
macOS Bash and zsh with isolated command stubs.
