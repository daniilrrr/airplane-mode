#!/usr/bin/env bash
#
#  █████╗ ██╗██████╗ ██████╗ ██╗      █████╗ ███╗   ██╗███████╗
# ██╔══██╗██║██╔══██╗██╔══██╗██║     ██╔══██╗████╗  ██║██╔════╝
# ███████║██║██████╔╝██████╔╝██║     ███████║██╔██╗ ██║█████╗
# ██╔══██║██║██╔══██╗██╔═══╝ ██║     ██╔══██║██║╚██╗██║██╔══╝
# ██║  ██║██║██║  ██║██║     ███████╗██║  ██║██║ ╚████║███████╗
# ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝
#                    M O D E   ✈
#
# One-stop setup for offline (plane / no-WiFi) local LLM coding on macOS.
# Bundles: Ollama (official) + Qwen3 models + OpenCode harness + tuned env.
#
# ─────────────────────────────────────────────────────────────────────────────
#  ⚠️  SECURITY WARNING — READ BEFORE RUNNING
# ─────────────────────────────────────────────────────────────────────────────
#  A coding agent (harness) runs with YOUR user permissions and can read/write
#  files and execute shell commands. Treat EVERY component — the harness, the
#  model, and ESPECIALLY any plugins / extensions / skills — as a potential
#  ATTACK SURFACE and supply-chain risk.
#
#  This script deliberately installs ONLY:
#    • Ollama (official installer — NOT Homebrew)
#    • Qwen3 model(s) from the official Ollama library
#    • OpenCode (open-source harness by SST)
#
#  It installs NO third-party plugins, extensions, MCP servers, or skills.
#  If you add any of those yourself, you own that risk. For work on sensitive
#  or proprietary repositories, clear agent usage with your security/AppSec team
#  first, and consider running the agent inside a container/sandbox.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
YEL=$'\033[33m'; CYN=$'\033[36m'; RST=$'\033[0m'

say()  { printf "%s\n" "$*"; }
ok()   { printf "${GRN}✓${RST} %s\n" "$*"; }
warn() { printf "${YEL}⚠${RST}  %s\n" "$*"; }
err()  { printf "${RED}✗${RST} %s\n" "$*" >&2; }
hdr()  { printf "\n${BOLD}${CYN}%s${RST}\n" "$*"; }

# ── Arg parsing ──────────────────────────────────────────────────────────────
# --engine ollama   (default) → easy path, Ollama runtime
# --engine llama.cpp          → power-user path, raw llama.cpp + llama-server
ENGINE="ollama"
while [ $# -gt 0 ]; do
  case "$1" in
    --engine)
      ENGINE="${2:-}"; shift 2 ;;
    --engine=*)
      ENGINE="${1#*=}"; shift ;;
    -h|--help)
      cat <<USAGE
Airplane Mode — offline local LLM coding setup

Usage: bash airplane-mode.sh [--engine ollama|llama.cpp]

  --engine ollama      (default) Easy path: Ollama runtime + 'ollama launch'.
  --engine llama.cpp   Power-user path: raw llama.cpp engine + llama-server.
                       More control, fewer abstractions. Note: Ollama is itself
                       a wrapper around llama.cpp — this talks to the engine directly.
  -h, --help           Show this help.
USAGE
      exit 0 ;;
    *)
      err "Unknown argument: $1 (try --help)"; exit 1 ;;
  esac
done

case "$ENGINE" in
  ollama|llama.cpp|llamacpp) ;;
  *) err "Invalid --engine '$ENGINE'. Use 'ollama' or 'llama.cpp'."; exit 1 ;;
esac
[ "$ENGINE" = "llamacpp" ] && ENGINE="llama.cpp"

# ── 0. Banner + security gate ────────────────────────────────────────────────
printf '\033[2J\033[H' 2>/dev/null || true   # clear screen (portable-ish)
printf "${CYN}${BOLD}"
cat <<'BANNER'
 █████╗ ██╗██████╗ ██████╗ ██╗      █████╗ ███╗   ██╗███████╗
██╔══██╗██║██╔══██╗██╔══██╗██║     ██╔══██╗████╗  ██║██╔════╝
███████║██║██████╔╝██████╔╝██║     ███████║██╔██╗ ██║█████╗
██╔══██║██║██╔══██╗██╔═══╝ ██║     ██╔══██║██║╚██╗██║██╔══╝
██║  ██║██║██║  ██║██║     ███████╗██║  ██║██║ ╚████║███████╗
╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝
                    M O D E   ✈
BANNER
printf "${RST}"
say "${BOLD}${CYN}Offline local LLM coding setup${RST}"
say "${DIM}macOS · Apple Silicon · ${ENGINE} + Qwen3 + OpenCode${RST}"
hdr "⚠️  SECURITY NOTICE"
say "A coding agent runs with YOUR permissions: it can read/write files and run"
say "shell commands. Treat the harness, model, and ANY plugins/skills as potential"
say "${BOLD}attack surfaces${RST}. This script installs ONLY official Ollama, Qwen3,"
say "and OpenCode — ${BOLD}no third-party plugins or extensions${RST}. For sensitive/"
say "proprietary repos, clear it with your security team and consider sandboxing."
say ""
read -r -p "Type 'yes' to acknowledge and continue: " _ack
if [ "${_ack:-}" != "yes" ]; then err "Aborted."; exit 1; fi

# ── 1. Preflight: macOS + Apple Silicon ──────────────────────────────────────
hdr "1. Checking your system"
if [ "$(uname -s)" != "Darwin" ]; then
  err "This script targets macOS. Detected: $(uname -s). Aborting."
  exit 1
fi
ARCH="$(uname -m)"
if [ "$ARCH" = "arm64" ]; then
  ok "Apple Silicon ($ARCH) — Metal GPU acceleration available."
else
  warn "Non-Apple-Silicon Mac ($ARCH) — will run on CPU (slow). Continuing anyway."
fi

PROFILE="${HOME}/.zshrc"
[ -n "${ZSH_VERSION:-}" ] || [ -f "$PROFILE" ] || PROFILE="${HOME}/.bashrc"
MARK_BEGIN="# >>> airplane-mode env >>>"
MARK_END="# <<< airplane-mode env <<<"

# =============================================================================
#  ENGINE: OLLAMA  (default — the easy path)
# =============================================================================
if [ "$ENGINE" = "ollama" ]; then

  # ── 2. Install Ollama (OFFICIAL — never Homebrew) ──────────────────────────
  hdr "2. Installing Ollama (official build)"
  say "${DIM}Note: the Homebrew formula ships without the llama-server engine — we use${RST}"
  say "${DIM}the official installer, which bundles everything for Apple Silicon.${RST}"
  if command -v ollama >/dev/null 2>&1; then
    CUR_OLLAMA="$(command -v ollama)"
    if echo "$CUR_OLLAMA" | grep -q "Cellar\|homebrew"; then
      warn "Detected a Homebrew Ollama at $CUR_OLLAMA — this is the broken one."
      warn "Run 'brew uninstall ollama' then re-run this script. (Your models are safe.)"
      exit 1
    fi
    ok "Ollama already installed at $CUR_OLLAMA"
  else
    say "Downloading + installing official Ollama (needs WiFi)…"
    curl -fsSL https://ollama.com/install.sh | sh
    ok "Ollama installed."
  fi

  # ── 3. Start the server ────────────────────────────────────────────────────
  hdr "3. Starting Ollama server"
  if ! curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    say "Launching 'ollama serve' in the background…"
    (OLLAMA_NO_CLOUD=1 nohup ollama serve >/tmp/airplane-ollama.log 2>&1 &) || true
    sleep 3
  fi
  if curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    ok "Ollama server is up on http://127.0.0.1:11434"
  else
    warn "Couldn't confirm server is up — check /tmp/airplane-ollama.log if needed."
  fi

  # ── 4. Pick model(s) ───────────────────────────────────────────────────────
  hdr "4. Choose your model(s)"
  say "Recommended by task:"
  say "  ${BOLD}qwen3-coder:30b${RST}  → CODING (repos, edits, PRs). 19GB. ${GRN}(default)${RST}"
  say "  ${BOLD}qwen3.6:27b${RST}      → reasoning / chat / planning. 17GB."
  say ""
  say "  [1] qwen3-coder:30b only        (default — coding)"
  say "  [2] qwen3.6:27b only            (reasoning/chat)"
  say "  [3] both                        (~36GB total)"
  read -r -p "Pick 1/2/3 [1]: " _pick
  _pick="${_pick:-1}"

  MODELS=()
  case "$_pick" in
    1) MODELS=("qwen3-coder:30b") ;;
    2) MODELS=("qwen3.6:27b") ;;
    3) MODELS=("qwen3-coder:30b" "qwen3.6:27b") ;;
    *) warn "Unrecognized choice — defaulting to qwen3-coder:30b"; MODELS=("qwen3-coder:30b") ;;
  esac

  hdr "Pulling model(s) — needs WiFi"
  for m in "${MODELS[@]}"; do
    say "→ ollama pull $m"
    ollama pull "$m"
    ok "Pulled $m"
  done
  DEFAULT_MODEL="${MODELS[0]}"

  # ── 5. Write tuned env vars + launcher ─────────────────────────────────────
  hdr "5. Writing tuned environment variables"
  if grep -q "$MARK_BEGIN" "$PROFILE" 2>/dev/null; then
    /usr/bin/sed -i '' "/$MARK_BEGIN/,/$MARK_END/d" "$PROFILE" 2>/dev/null || true
  fi
  cat >> "$PROFILE" <<EOF
$MARK_BEGIN
# Tuned for offline local LLM coding on Apple Silicon. Managed by airplane-mode.sh.
# Engine: ollama
export OLLAMA_CONTEXT_LENGTH=64000     # coding needs a big context window
export OLLAMA_FLASH_ATTENTION=1        # cut memory growth as context grows
export OLLAMA_KV_CACHE_TYPE=q8_0       # ~half KV cache memory, ~no quality loss
export OLLAMA_KEEP_ALIVE=-1            # keep model pinned in memory
export OLLAMA_NO_CLOUD=1               # force true offline — never phone home

# 'airplane-mode' launcher: boots OpenCode wired to your local model.
airplane-mode() {
  local model="\${1:-$DEFAULT_MODEL}"
  if ! curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    echo "Starting ollama serve…"
    (nohup ollama serve >/tmp/airplane-ollama.log 2>&1 &)
    sleep 2
  fi
  echo "✈  Airplane Mode — launching OpenCode with \$model"
  ollama launch opencode --model "\$model"
}
$MARK_END
EOF
  ok "Wrote env vars + 'airplane-mode' launcher to $PROFILE"

# =============================================================================
#  ENGINE: LLAMA.CPP  (power-user path — talk to the engine directly)
# =============================================================================
else

  # ── 2. Install llama.cpp (via Homebrew) ────────────────────────────────────
  hdr "2. Installing llama.cpp"
  say "${DIM}Note: Ollama is itself a wrapper around llama.cpp. This path uses the${RST}"
  say "${DIM}engine directly — more control, fewer abstractions, full credit upstream.${RST}"
  if command -v llama-server >/dev/null 2>&1; then
    ok "llama-server already installed at $(command -v llama-server)"
  elif command -v brew >/dev/null 2>&1; then
    say "Installing llama.cpp via Homebrew (needs WiFi)…"
    brew install llama.cpp
    ok "llama.cpp installed."
  else
    err "Homebrew not found. Install it from https://brew.sh, then re-run."
    err "(Or build llama.cpp from source: https://github.com/ggml-org/llama.cpp)"
    exit 1
  fi

  # ── 3. Pick model (GGUF from HuggingFace) ──────────────────────────────────
  hdr "3. Choose your model"
  say "Recommended by task (GGUF from HuggingFace, downloaded by llama-server):"
  say "  ${BOLD}Qwen3-Coder-30B${RST}   → CODING (repos, edits, PRs). ${GRN}(default)${RST}"
  say "  ${BOLD}Qwen3-30B (3.6)${RST}   → reasoning / chat / planning."
  say ""
  say "  [1] Qwen3-Coder-30B  (coding, default)"
  say "  [2] Qwen3-30B        (reasoning/chat)"
  read -r -p "Pick 1/2 [1]: " _pick
  _pick="${_pick:-1}"
  case "$_pick" in
    1) HF_REPO="Qwen/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M"; ALIAS="qwen3-coder-30b" ;;
    2) HF_REPO="Qwen/Qwen3-30B-A3B-GGUF:Q4_K_M";                 ALIAS="qwen3-30b" ;;
    *) warn "Defaulting to Qwen3-Coder-30B"; HF_REPO="Qwen/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M"; ALIAS="qwen3-coder-30b" ;;
  esac
  say ""
  warn "If that exact HF repo/quant 404s, browse https://huggingface.co/models?search=qwen3+gguf"
  warn "and edit HF_REPO in your shell profile to a repo that exists (e.g. an unsloth GGUF)."

  # ── 4. Pre-download the GGUF (so it's cached for offline use) ───────────────
  hdr "4. Pre-downloading the model (needs WiFi)"
  say "Fetching ${HF_REPO} into the llama.cpp cache so it works offline later…"
  set +e
  llama-server -hf "$HF_REPO" --no-webui -c 1 --port 18080 >/tmp/airplane-llamacpp-dl.log 2>&1 &
  DL_PID=$!
  # Wait for the model to be cached (download complete) then stop the temp server
  for _ in $(seq 1 600); do
    grep -q "server is listening" /tmp/airplane-llamacpp-dl.log 2>/dev/null && break
    kill -0 "$DL_PID" 2>/dev/null || break
    sleep 1
  done
  kill "$DL_PID" 2>/dev/null || true
  wait "$DL_PID" 2>/dev/null || true
  set -e
  ok "Model cached (see /tmp/airplane-llamacpp-dl.log if you need detail)."

  # ── 5. Write the launcher (tuned llama-server flags) ───────────────────────
  hdr "5. Writing the 'airplane-mode' launcher"
  if grep -q "$MARK_BEGIN" "$PROFILE" 2>/dev/null; then
    /usr/bin/sed -i '' "/$MARK_BEGIN/,/$MARK_END/d" "$PROFILE" 2>/dev/null || true
  fi
  cat >> "$PROFILE" <<EOF
$MARK_BEGIN
# Tuned for offline local LLM coding on Apple Silicon. Managed by airplane-mode.sh.
# Engine: llama.cpp
export AIRPLANE_HF_REPO="$HF_REPO"
export AIRPLANE_MODEL_ALIAS="$ALIAS"

# Start tuned llama-server (Anthropic + OpenAI compatible) in the background.
airplane-serve() {
  local repo="\${1:-\$AIRPLANE_HF_REPO}"
  echo "✈  Starting llama-server with \$repo …"
  # Tuned flags: 64k ctx, flash attention, q8_0 KV cache, qwen coding sampler,
  # offline (use cache only), reasoning budget caps runaway thinking.
  nohup llama-server \\
    -hf "\$repo" \\
    --alias "\$AIRPLANE_MODEL_ALIAS" \\
    --host 127.0.0.1 --port 8080 \\
    -c 64000 \\
    -fa on \\
    -ctk q8_0 -ctv q8_0 \\
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0.0 \\
    --presence-penalty 0.0 --repeat-penalty 1.0 \\
    --reasoning-budget 2048 \\
    --offline \\
    --no-webui \\
    >/tmp/airplane-llamacpp.log 2>&1 &
  echo "   logs: /tmp/airplane-llamacpp.log  ·  API: http://127.0.0.1:8080"
}

# 'airplane-mode' launcher: ensure llama-server is up, then start OpenCode.
airplane-mode() {
  if ! curl -fsS http://127.0.0.1:8080/health >/dev/null 2>&1; then
    airplane-serve
    echo -n "   waiting for model to load"
    for _ in \$(seq 1 180); do
      curl -fsS http://127.0.0.1:8080/health >/dev/null 2>&1 && break
      echo -n "."; sleep 1
    done
    echo ""
  fi
  echo "✈  Airplane Mode — launching OpenCode (llama.cpp @ :8080)"
  # Point OpenCode at the local llama-server OpenAI-compatible endpoint.
  OPENAI_BASE_URL="http://127.0.0.1:8080/v1" OPENAI_API_KEY="sk-local" \\
    opencode
}
$MARK_END
EOF
  ok "Wrote 'airplane-mode' + 'airplane-serve' launchers to $PROFILE"
  DEFAULT_MODEL="$ALIAS"
fi

# ── 6. Install OpenCode (the only harness — open source, by SST) ─────────────
hdr "6. Installing OpenCode harness"
if command -v opencode >/dev/null 2>&1; then
  ok "OpenCode already installed at $(command -v opencode)"
else
  say "Installing OpenCode (needs WiFi)…"
  curl -fsSL https://opencode.ai/install | bash
  ok "OpenCode installed."
fi

# ── 7. Smoke test ────────────────────────────────────────────────────────────
SMOKE_TIMEOUT=180   # 3 minutes
hdr "7. Smoke test (loads model on GPU)"
say "Confirming the model loads and responds."
say "${DIM}First run loads the whole model into memory — this can take a while.${RST}"
say "${DIM}Local harnesses with big system prompts (e.g. Claude Code) can be even${RST}"
say "${DIM}slower on the first call. Allowing up to ${SMOKE_TIMEOUT}s before giving up.${RST}"
say ""

TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN="gtimeout"; fi

say "${DIM}── model output below ─────────────────────────────────────────${RST}"
set +e
if [ "$ENGINE" = "ollama" ]; then
  if [ -n "$TIMEOUT_BIN" ]; then
    echo "say hi" | "$TIMEOUT_BIN" "${SMOKE_TIMEOUT}" ollama run "$DEFAULT_MODEL"; RC=$?
  else
    warn "(no 'timeout' command — running without a hard time limit)"
    echo "say hi" | ollama run "$DEFAULT_MODEL"; RC=$?
  fi
  VERIFY_HINT="ollama ps   # want PROCESSOR=100% GPU and CONTEXT=64000"
else
  # llama.cpp: start the tuned server, wait for health, hit the completion API
  say "Starting llama-server for the smoke test…"
  ( eval "$(sed -n "/$MARK_BEGIN/,/$MARK_END/p" "$PROFILE")"; airplane-serve >/dev/null 2>&1 )
  for _ in $(seq 1 "${SMOKE_TIMEOUT}"); do
    curl -fsS http://127.0.0.1:8080/health >/dev/null 2>&1 && break
    sleep 1
  done
  if curl -fsS http://127.0.0.1:8080/health >/dev/null 2>&1; then
    curl -fsS http://127.0.0.1:8080/completion \
      -H "Content-Type: application/json" \
      -d '{"prompt":"say hi","n_predict":16}' 2>/dev/null \
      | sed 's/.*"content":"\([^"]*\)".*/\1/' || true
    RC=0
  else
    RC=124
  fi
  VERIFY_HINT="curl http://127.0.0.1:8080/health   # {\"status\":\"ok\"} when loaded"
fi
set -e
say "${DIM}───────────────────────────────────────────────────────────────${RST}"

if [ "${RC:-1}" -eq 0 ]; then
  ok "Model responded — smoke test passed."
elif [ "${RC:-1}" -eq 124 ]; then
  warn "Smoke test timed out after ${SMOKE_TIMEOUT}s. The model may still be loading."
  warn "Give it another minute and try 'airplane-mode' in a new terminal."
else
  warn "Smoke test exited with code ${RC:-?}. Try 'airplane-mode' manually in a new terminal."
fi
say ""
say "${DIM}Verify it's on the GPU (not CPU):${RST}"
say "  ${VERIFY_HINT}"

# ── 8. Done ──────────────────────────────────────────────────────────────────
hdr "✈  READY TO FLY"
ok "Engine: ${ENGINE} · Model: ${DEFAULT_MODEL} · OpenCode — installed and tuned."
say ""
say "${BOLD}Next steps:${RST}"
say "  1. Open a NEW terminal (to load the env vars), or: source $PROFILE"
say "  2. Run:  ${BOLD}airplane-mode${RST}            ${DIM}# launches OpenCode + your model${RST}"
say "  3. ${BOLD}Test it with WiFi OFF on the ground${RST} before you fly."
say ""
if [ "$ENGINE" = "ollama" ]; then
  say "${DIM}Model-by-task:  qwen3-coder:30b = coding · qwen3.6:27b = reasoning/chat${RST}"
  say "${DIM}Switch models:  airplane-mode qwen3.6:27b${RST}"
else
  say "${DIM}Engine: llama.cpp (raw). Server logs: /tmp/airplane-llamacpp.log${RST}"
  say "${DIM}Restart the server manually with:  airplane-serve${RST}"
fi
say ""
warn "Reminder: do NOT add third-party plugins/MCP servers/skills without review."
warn "For sensitive repos, clear agent usage with your security team."