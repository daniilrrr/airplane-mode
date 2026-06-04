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
say "${DIM}macOS · Apple Silicon · Ollama + Qwen3 + OpenCode${RST}"
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

# ── 2. Install Ollama (OFFICIAL — never Homebrew) ────────────────────────────
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

# ── 3. Start the server ──────────────────────────────────────────────────────
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

# ── 4. Pick model(s) ─────────────────────────────────────────────────────────
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

# ── 5. Write tuned env vars to shell profile ─────────────────────────────────
hdr "5. Writing tuned environment variables"
PROFILE="${HOME}/.zshrc"
[ -n "${ZSH_VERSION:-}" ] || [ -f "$PROFILE" ] || PROFILE="${HOME}/.bashrc"
MARK_BEGIN="# >>> airplane-mode env >>>"
MARK_END="# <<< airplane-mode env <<<"

# Remove any prior block (idempotent)
if grep -q "$MARK_BEGIN" "$PROFILE" 2>/dev/null; then
  /usr/bin/sed -i '' "/$MARK_BEGIN/,/$MARK_END/d" "$PROFILE" 2>/dev/null || true
fi

cat >> "$PROFILE" <<EOF
$MARK_BEGIN
# Tuned for offline local LLM coding on Apple Silicon. Managed by airplane-mode.sh.
export OLLAMA_CONTEXT_LENGTH=64000     # coding needs a big context window
export OLLAMA_FLASH_ATTENTION=1        # cut memory growth as context grows
export OLLAMA_KV_CACHE_TYPE=q8_0       # ~half KV cache memory, ~no quality loss
export OLLAMA_KEEP_ALIVE=-1            # keep model pinned in memory
export OLLAMA_NO_CLOUD=1               # force true offline — never phone home

# 'airplane-mode' launcher: boots OpenCode wired to your local model.
# Usage: airplane-mode [model]   (defaults to the model you installed)
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

# ── 6. Install OpenCode (the only harness — open source, by SST) ─────────────
hdr "6. Installing OpenCode harness"
if command -v opencode >/dev/null 2>&1; then
  ok "OpenCode already installed at $(command -v opencode)"
else
  say "Installing OpenCode (needs WiFi)…"
  curl -fsSL https://opencode.ai/install | bash
  ok "OpenCode installed."
fi

# ── 7. Self-test ─────────────────────────────────────────────────────────────
SMOKE_TIMEOUT=180   # 3 minutes
hdr "7. Smoke test (loads model on GPU)"
say "Running a tiny prompt ('say hi') to confirm the model loads and responds."
say "${DIM}First run loads the whole model into memory — this can take a while.${RST}"
say "${DIM}Local harnesses with big system prompts (e.g. Claude Code) can be even${RST}"
say "${DIM}slower on the first call. Allowing up to ${SMOKE_TIMEOUT}s before giving up.${RST}"
say ""
say "${DIM}── model output below ─────────────────────────────────────────${RST}"

# Pick a timeout command if available (gtimeout on mac via coreutils, else timeout)
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN="gtimeout"; fi

set +e
if [ -n "$TIMEOUT_BIN" ]; then
  # Stream output live (no redirect to /dev/null) so the user sees progress
  echo "say hi" | "$TIMEOUT_BIN" "${SMOKE_TIMEOUT}" ollama run "$DEFAULT_MODEL"
  RC=$?
else
  # No timeout binary available — run directly but still show output
  warn "(no 'timeout' command found — running without a hard time limit)"
  echo "say hi" | ollama run "$DEFAULT_MODEL"
  RC=$?
fi
set -e

say "${DIM}───────────────────────────────────────────────────────────────${RST}"
if [ "$RC" -eq 0 ]; then
  ok "Model responded — smoke test passed."
elif [ "$RC" -eq 124 ]; then
  warn "Smoke test timed out after ${SMOKE_TIMEOUT}s. The model may still be loading"
  warn "(large model + cold start). Try again, or run manually:"
  warn "  ollama run $DEFAULT_MODEL \"hi\""
else
  warn "Smoke test exited with code $RC. Inspect manually:"
  warn "  ollama run $DEFAULT_MODEL \"hi\""
fi
say ""
say "${DIM}Verify it's on the GPU (not CPU):${RST}"
say "  ollama ps   ${DIM}# want PROCESSOR=100% GPU and CONTEXT=64000${RST}"

# ── 8. Done ──────────────────────────────────────────────────────────────────
hdr "✈  READY TO FLY"
ok "Ollama (official) + ${DEFAULT_MODEL} + OpenCode are installed and tuned."
say ""
say "${BOLD}Next steps:${RST}"
say "  1. Open a NEW terminal (to load the env vars), or: source $PROFILE"
say "  2. Run:  ${BOLD}airplane-mode${RST}            ${DIM}# launches OpenCode + your model${RST}"
say "  3. ${BOLD}Test it with WiFi OFF on the ground${RST} before you fly."
say ""
say "${DIM}Model-by-task:  qwen3-coder:30b = coding · qwen3.6:27b = reasoning/chat${RST}"
say "${DIM}Switch models:  airplane-mode qwen3.6:27b${RST}"
say ""
warn "Reminder: do NOT add third-party plugins/MCP servers/skills without review."
warn "For sensitive repos, clear agent usage with your security team."