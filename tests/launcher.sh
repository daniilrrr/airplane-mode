#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$ROOT/src/airplane-mode.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home" BIN="$TEST_ROOT/bin" LOG="$TEST_ROOT/commands" STATE="$TEST_ROOT/ready"
mkdir -p "$HOME" "$BIN"
export PATH="$BIN:/usr/bin:/bin:/usr/sbin:/sbin"
cat > "$BIN/curl" <<'STUB'
#!/bin/bash
for arg in "$@"; do
  case "$arg" in
    */api/tags|*/health)
      [ "${NEVER_READY:-0}" = 0 ] && { [ "${READY:-1}" = 1 ] || [ -e "$STATE" ]; }; exit $? ;;
    */v1/models) printf '{"data":[{"id":"%s"}]}' "${ADVERTISED_MODEL:-qwen38-27b}"; exit ;;
    */api/generate) printf '%s' "${RESPONSE:-{\"done\":true,\"response\":\"hello\"}}"; exit ;;
    */completion) printf '{"content":"hello"}'; exit ;;
  esac
done
printf 'Unexpected curl request\n' >&2
exit 1
STUB
cat > "$BIN/ollama" <<'STUB'
#!/bin/bash
printf 'ollama %s\n' "$*" >> "$LOG"
case "$1" in
  serve)
    printf 'serve env %s %s %s %s %s %s\n' "$OLLAMA_HOST" "$OLLAMA_NO_CLOUD" "$OLLAMA_CONTEXT_LENGTH" "$OLLAMA_FLASH_ATTENTION" "$OLLAMA_KV_CACHE_TYPE" "$OLLAMA_KEEP_ALIVE" >> "$LOG"
    [ "${START_FAIL:-0}" = 0 ] || exit 7
    touch "$STATE" ;;
  show) [ "${MISSING:-0}" = 0 ] ;;
  launch) printf 'autoupdate %s\n' "${OPENCODE_DISABLE_AUTOUPDATE:-}" >> "$LOG"; exit "${LAUNCH_FAIL:-0}" ;;
  pull) exit "${PULL_FAIL:-0}" ;;
esac
STUB
cat > "$BIN/opencode" <<'STUB'
#!/bin/bash
printf 'opencode %s\nconfig %s\n' "$*" "${OPENCODE_CONFIG_CONTENT:-}" >> "$LOG"
printf 'autoupdate %s\n' "${OPENCODE_DISABLE_AUTOUPDATE:-}" >> "$LOG"
if [ -n "${OPENCODE_CONFIG_CONTENT:-}" ]; then
  /usr/bin/perl -MJSON::PP -e 'decode_json($ENV{OPENCODE_CONFIG_CONTENT})' || exit
fi
[ "$1" != --version ] || printf 'opencode v2.2.3\n'
STUB
cat > "$BIN/llama-server" <<'STUB'
#!/bin/bash
printf 'llama-server %s\n' "$*" >> "$LOG"
[ "${DOWNLOAD_FAIL:-0}" = 0 ] || exit 8
touch "$STATE"
STUB
cat > "$BIN/sleep" <<'STUB'
#!/bin/bash
/bin/sleep 0.01
STUB
cat > "$BIN/brew" <<'STUB'
#!/bin/bash
printf 'brew %s\n' "$*" >> "$LOG"
case "$*" in
  'list --cask --full-name') printf '%s\n' "${CASK:-}" ;;
  'list --formula --full-name') printf '%s\n' "${FORMULA:-}" ;;
  --prefix*) printf '%s\n' "$BIN" ;;
  upgrade*) exit "${UPGRADE_FAIL:-0}" ;;
  install*) exit "${INSTALL_FAIL:-0}" ;;
  *) exit 1 ;;
esac
STUB
cat > "$BIN/uname" <<'STUB'
#!/bin/bash
printf 'Darwin\n'
STUB
chmod +x "$BIN/"*

must_contain() { grep -Fq -- "$2" "$1" || { printf 'Missing expected output: %s\n' "$2" >&2; cat "$1" >&2; exit 1; }; }
must_not_contain() { if grep -Fq -- "$2" "$1"; then printf 'Unexpected output: %s\n' "$2" >&2; cat "$1" >&2; exit 1; fi; }
reset_case() {
  : > "$LOG"
  rm -f "$STATE"
  export READY=1 NEVER_READY=0 START_FAIL=0 MISSING=0 DOWNLOAD_FAIL=0 LAUNCH_FAIL=0 PULL_FAIL=0
  unset RESPONSE ADVERTISED_MODEL OPENCODE_DISABLE_AUTOUPDATE
}
run_mode() { "$SHELL_BIN" -c '. "$1"; shift; airplane-mode "$@"' airplane-test "$BLOCK" "$@"; }

ENGINE=ollama SELECTED_MODEL="$DEFAULT_MODEL"
BLOCK="$TEST_ROOT/ollama.sh"
write_launcher_block > "$BLOCK"
for SHELL_BIN in /bin/bash /bin/zsh; do
  [ -x "$SHELL_BIN" ] || { printf 'Required verification shell missing: %s\n' "$SHELL_BIN" >&2; exit 1; }
  "$SHELL_BIN" -n "$BLOCK"
  reset_case
  run_mode
  must_contain "$LOG" 'ollama show qwen3.8:27b-q4_K_M'
  must_contain "$LOG" 'ollama launch opencode --model qwen3.8:27b-q4_K_M -- --standalone'
  must_contain "$LOG" 'autoupdate true'
  must_not_contain "$LOG" 'ollama pull'
  must_not_contain "$LOG" 'ollama serve'
  reset_case
  run_mode qwen3-coder:30b
  must_contain "$LOG" 'ollama launch opencode --model qwen3-coder:30b -- --standalone'
  reset_case
  export MISSING=1
  if run_mode >"$TEST_ROOT/error" 2>&1; then fail 'Missing model unexpectedly launched'; exit 1; fi
  must_contain "$TEST_ROOT/error" 'While online run:'
  must_not_contain "$LOG" 'ollama pull'
  must_not_contain "$LOG" 'ollama launch'
  reset_case
  export READY=0
  run_mode
  must_contain "$LOG" 'serve env 127.0.0.1:11434 1 64000 1 q8_0 -1'
  reset_case
  export READY=0 START_FAIL=1
  if run_mode >"$TEST_ROOT/error" 2>&1; then fail 'Failed server unexpectedly launched'; exit 1; fi
  must_contain "$TEST_ROOT/error" 'before becoming ready'
  must_not_contain "$LOG" 'ollama launch'
  reset_case
  export NEVER_READY=1
  if run_mode >"$TEST_ROOT/error" 2>&1; then fail 'Unready server unexpectedly launched'; exit 1; fi
  must_not_contain "$LOG" 'ollama launch'
  reset_case
  export NEVER_READY=1
  if "$SHELL_BIN" -c '. "$1"; _airplane_wait http://127.0.0.1:11434/api/tags "$$" 2 test-log' airplane-test "$BLOCK" >"$TEST_ROOT/error" 2>&1; then fail 'Readiness timeout was ignored'; exit 1; fi
  must_contain "$TEST_ROOT/error" 'readiness timed out'
  reset_case
  export LAUNCH_FAIL=6
  if run_mode; then fail 'OpenCode launch failure was ignored'; exit 1; fi
  reset_case
  "$SHELL_BIN" -c '. "$1"; _airplane_smoke' airplane-test "$BLOCK" >"$TEST_ROOT/smoke"
  must_contain "$LOG" '--standalone --version'
  export RESPONSE='{"done":false,"response":""}'
  if "$SHELL_BIN" -c '. "$1"; _airplane_smoke' airplane-test "$BLOCK" >"$TEST_ROOT/error" 2>&1; then fail 'Invalid model response passed smoke'; exit 1; fi
  printf 'PASS Ollama launcher in %s\n' "$SHELL_BIN"
done

ENGINE=llama.cpp HF_REPO="$DEFAULT_HF_REPO" MODEL_ALIAS=qwen38-27b
BLOCK="$TEST_ROOT/llama.sh"
write_launcher_block > "$BLOCK"
for SHELL_BIN in /bin/bash /bin/zsh; do
  "$SHELL_BIN" -n "$BLOCK"
  reset_case
  export READY=0
  if run_mode "$CODING_HF_REPO" >"$TEST_ROOT/error" 2>&1; then fail 'Different llama repository unexpectedly launched'; exit 1; fi
  must_contain "$TEST_ROOT/error" 'Rerun bash src/airplane-mode.sh --engine llama.cpp'
  must_not_contain "$LOG" 'llama-server '
  must_not_contain "$LOG" 'opencode '
  if "$SHELL_BIN" -c '. "$1"; airplane-serve "$2"' airplane-test "$BLOCK" "$CODING_HF_REPO" >"$TEST_ROOT/error" 2>&1; then fail 'Different llama repository unexpectedly served'; exit 1; fi
  must_not_contain "$LOG" 'llama-server '
  must_not_contain "$LOG" 'opencode '
  run_mode
  must_contain "$LOG" 'llama-server -hf unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_M --alias qwen38-27b'
  must_contain "$LOG" 'opencode --standalone --model airplane/qwen38-27b'
  must_contain "$LOG" 'autoupdate true'
  reset_case
  run_mode "$DEFAULT_HF_REPO"
  must_contain "$LOG" 'opencode --standalone --model airplane/qwen38-27b'
  reset_case
  run_mode
  must_contain "$LOG" 'opencode --standalone --model airplane/qwen38-27b'
  must_contain "$LOG" '@opencode/ai/providers/openai-compatible'
  must_contain "$LOG" '"baseURL":"http://127.0.0.1:8080/v1"'
  must_contain "$LOG" '"context":64000,"output":8192'
  must_contain "$LOG" '"tools":true'
  reset_case
  export READY=0
  run_mode
  must_contain "$LOG" 'llama-server -hf unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_M'
  must_contain "$LOG" '--offline --no-webui'
  reset_case
  export ADVERTISED_MODEL=another-model
  if run_mode >"$TEST_ROOT/error" 2>&1; then fail 'Wrong running llama model accepted'; exit 1; fi
  must_not_contain "$LOG" 'opencode '
  reset_case
  export READY=0 DOWNLOAD_FAIL=1
  if run_mode >"$TEST_ROOT/error" 2>&1; then fail 'Failed llama server unexpectedly launched'; exit 1; fi
  must_not_contain "$LOG" 'opencode '
  printf 'PASS llama.cpp launcher in %s\n' "$SHELL_BIN"
done

PROFILE="$HOME/.zshrc"
printf 'before without newline' > "$HOME/profile-target"
chmod 640 "$HOME/profile-target"
ln -s "$HOME/profile-target" "$PROFILE"
replace_profile_block "$BLOCK" >"$TEST_ROOT/profile-output"
[ -L "$PROFILE" ] || { fail 'Profile symlink was replaced'; exit 1; }
[ "$(/usr/bin/perl -e 'printf "%o",(stat $ARGV[0])[2]&07777' "$PROFILE")" = 640 ]
cp "$PROFILE" "$TEST_ROOT/expected-profile"
replace_profile_block "$BLOCK" >"$TEST_ROOT/profile-output"
cmp "$PROFILE" "$TEST_ROOT/expected-profile"
[ "$(find "$HOME" -name '*airplane-backup*' | wc -l | tr -d ' ')" = 1 ]
printf 'after\n' >> "$PROFILE"
replace_profile_block "$BLOCK" >"$TEST_ROOT/profile-output"
must_contain "$PROFILE" 'before without newline'
must_contain "$PROFILE" 'after'
for malformed in missing duplicate reversed; do
  case "$malformed" in
    missing) printf '%s\n' "$MARK_BEGIN" > "$PROFILE" ;;
    duplicate) cat "$BLOCK" "$BLOCK" > "$PROFILE" ;;
    reversed) printf '%s\n%s\n' "$MARK_END" "$MARK_BEGIN" > "$PROFILE" ;;
  esac
  cp "$PROFILE" "$TEST_ROOT/invalid-profile"
  if replace_profile_block "$BLOCK" >"$TEST_ROOT/error" 2>&1; then fail 'Malformed markers accepted'; exit 1; fi
  cmp "$PROFILE" "$TEST_ROOT/invalid-profile"
done
printf 'PASS profile idempotency, preservation, symlink, permissions, and malformed markers\n'

reset_case
export FORMULA=opencode
update_tool opencode
must_contain "$LOG" 'brew upgrade opencode'
must_not_contain "$LOG" 'ollama pull'
reset_case
export FORMULA=opencode UPGRADE_FAIL=9
if update_tool opencode; then fail 'Update failure was ignored'; exit 1; fi
reset_case
export FORMULA=''
if update_tool opencode >"$TEST_ROOT/error" 2>&1; then fail 'Unknown manager accepted'; exit 1; fi
must_not_contain "$LOG" 'brew upgrade'
reset_case
export FORMULA=llama.cpp UPGRADE_FAIL=0
update_tool llama-server
must_contain "$LOG" 'brew upgrade llama.cpp'
printf 'PASS targeted updates and manager failure\n'

reset_case
export READY=0 DOWNLOAD_FAIL=1
. "$BLOCK"
if prepare_llama_model >"$TEST_ROOT/error" 2>&1; then fail 'Failed GGUF download was ignored'; exit 1; fi
must_contain "$TEST_ROOT/error" 'before becoming ready'
printf 'PASS failed GGUF preparation\n'

reset_case
rm "$PROFILE"
printf 'keep me\n' > "$HOME/.bashrc"
export FORMULA='' UPGRADE_FAIL=0
printf 'yes\n1\n' | /bin/bash "$ROOT/src/airplane-mode.sh" >"$TEST_ROOT/setup-output"
must_contain "$TEST_ROOT/setup-output" 'Ready. Run:'
must_contain "$HOME/.bashrc" 'keep me'
must_contain "$HOME/.bashrc" "_airplane_default_model='qwen3.8:27b-q4_K_M'"
must_not_contain "$LOG" 'ollama pull'
reset_case
export MISSING=1 PULL_FAIL=9
cp "$HOME/.bashrc" "$TEST_ROOT/before-failure"
if printf 'yes\n1\n' | /bin/bash "$ROOT/src/airplane-mode.sh" >"$TEST_ROOT/setup-output" 2>&1; then fail 'Failed preparation reported success'; exit 1; fi
must_not_contain "$TEST_ROOT/setup-output" 'Ready. Run:'
cmp "$HOME/.bashrc" "$TEST_ROOT/before-failure"
printf 'PASS setup uses the emitted smoke artifact and does not report failed preparation as ready\n'

reset_case
export FORMULA=$'opencode\nollama' UPGRADE_FAIL=0
cp "$HOME/.bashrc" "$TEST_ROOT/before-update"
/bin/bash "$ROOT/src/airplane-mode.sh" --update >"$TEST_ROOT/update-output"
must_contain "$LOG" 'brew upgrade opencode'
must_contain "$LOG" 'brew upgrade ollama'
must_not_contain "$LOG" 'ollama show'
must_not_contain "$LOG" 'ollama pull'
cmp "$HOME/.bashrc" "$TEST_ROOT/before-update"
reset_case
export UPGRADE_FAIL=9
if /bin/bash "$ROOT/src/airplane-mode.sh" --update >"$TEST_ROOT/update-output" 2>&1; then fail 'Main update ignored upgrade failure'; exit 1; fi
must_not_contain "$LOG" 'brew upgrade ollama'
cmp "$HOME/.bashrc" "$TEST_ROOT/before-update"
printf 'PASS update CLI changes only existing selected tools and propagates failures\n'
