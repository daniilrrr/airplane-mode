#!/usr/bin/env bash
set -euo pipefail

DEFAULT_MODEL='qwen3.8:27b-q4_K_M'
CODING_MODEL='qwen3-coder:30b'
DEFAULT_HF_REPO='unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_M'
CODING_HF_REPO='Qwen/Qwen3-Coder-30B-A3B-Instruct-GGUF:Q4_K_M'
MARK_BEGIN='# >>> airplane-mode env >>>'
MARK_END='# <<< airplane-mode env <<<'

say() { printf '%s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; return 1; }

install_script() {
  local url="$1" script
  script=$(mktemp) || return
  if ! curl -fsSL --connect-timeout 15 --max-time 120 "$url" -o "$script"; then
    rm -f "$script"
    fail "Could not download $url"; return 1
  fi
  local rc=0
  OLLAMA_NO_START=1 bash "$script" || rc=$?
  rm -f "$script"
  return "$rc"
}

brew_formula() {
  local tool="$1" path="$2" formula prefix
  command -v brew >/dev/null 2>&1 || return 1
  local formulas
  formulas=$(brew list --formula --full-name) || return 2
  while IFS= read -r formula; do
    case "$tool:${formula##*/}" in
      opencode:opencode|opencode:opencode-v2|ollama:ollama|llama-server:llama.cpp)
        prefix=$(brew --prefix "$formula") || return 2
        prefix=$(/usr/bin/perl -MCwd=abs_path -e 'print abs_path($ARGV[0]) // die "Cannot resolve Homebrew prefix\n"' "$prefix") || return 2
        case "$path" in "$prefix"/*) printf '%s\n' "$formula"; return 0 ;; esac ;;
    esac
  done <<EOF
$formulas
EOF
  return 1
}

update_tool() {
  local tool="$1" path resolved formula
  path=$(command -v "$tool") || { say "$tool is not installed; skipped."; return 0; }
  resolved=$(/usr/bin/perl -MCwd=abs_path -e 'print abs_path($ARGV[0]) // die "Cannot resolve executable\n"' "$path") || return
  local casks manager_status
  if [ "$tool" = ollama ] && command -v brew >/dev/null 2>&1; then
    casks=$(brew list --cask --full-name) || return
    if printf '%s\n' "$casks" | grep -qx ollama; then
      case "$resolved" in
        /Applications/Ollama.app/*) brew upgrade --cask ollama; return ;;
      esac
    fi
  fi
  if formula=$(brew_formula "$tool" "$resolved"); then
    say "Updating $tool with Homebrew ($formula)."
    brew upgrade "$formula"
    return
  else
    manager_status=$?
    [ "$manager_status" -eq 1 ] || { fail "Could not inspect the Homebrew installation for $tool."; return 1; }
  fi
  case "$tool:$resolved" in
    ollama:/Applications/Ollama.app/*)
      install_script https://ollama.com/install.sh ;;
    opencode:*/.opencode/bin/opencode)
      install_script https://opencode.ai/v2/install ;;
    *) fail "Cannot safely update $path. Update $tool with its original installer, then rerun setup." ;;
  esac
}

ensure_tools() {
  if ! command -v opencode >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then brew install opencode || return
    else install_script https://opencode.ai/v2/install || return
    fi
    export PATH="$HOME/.opencode/bin:$PATH"
  fi
  local version
  version=$(opencode --version) || return
  version="${version##* }"
  case "$version" in 2.*|v2.*) ;; *) fail "OpenCode v2 is required (found $version). Run setup --update or update with its original manager."; return 1 ;; esac
  if [ "$ENGINE" = ollama ]; then
    command -v ollama >/dev/null 2>&1 || install_script https://ollama.com/install.sh
  elif ! command -v llama-server >/dev/null 2>&1; then
    command -v brew >/dev/null 2>&1 || { fail 'Install llama.cpp from https://github.com/ggml-org/llama.cpp or install Homebrew, then rerun.'; return 1; }
    brew install llama.cpp || return
  fi
}

write_launcher_block() {
  printf '%s\n' "$MARK_BEGIN"
  cat <<'COMMON'
_airplane_wait() {
  local url="$1" pid="$2" limit="$3" log="$4" attempt=0
  while [ "$attempt" -lt "$limit" ]; do
    if curl -fsS --connect-timeout 1 --max-time 2 "$url" >/dev/null 2>&1; then return 0; fi
    if ! kill -0 "$pid" 2>/dev/null; then
      printf 'Server exited before becoming ready. See %s\n' "$log" >&2; return 1
    fi
    sleep 1
    attempt=$((attempt + 1))
  done
  printf 'Server readiness timed out. See %s\n' "$log" >&2
  return 1
}
COMMON
  if [ "$ENGINE" = ollama ]; then
    printf "_airplane_default_model='%s'\n" "$SELECTED_MODEL"
    cat <<'OLLAMA'
_airplane_ready() {
  export OLLAMA_HOST=127.0.0.1:11434 OLLAMA_NO_CLOUD=1
  export OLLAMA_CONTEXT_LENGTH=64000 OLLAMA_FLASH_ATTENTION=1
  export OLLAMA_KV_CACHE_TYPE=q8_0 OLLAMA_KEEP_ALIVE=-1
  if curl -fsS --connect-timeout 1 --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then return 0; fi
  local log="$HOME/.airplane-ollama.log" pid
  nohup ollama serve >"$log" 2>&1 &
  pid=$!
  _airplane_wait http://127.0.0.1:11434/api/tags "$pid" 60 "$log"
}
_airplane_check() {
  _airplane_ready || return
  if ! ollama show "$1" >/dev/null; then
    printf 'Model is unavailable locally. While online run: OLLAMA_HOST=127.0.0.1:11434 ollama pull %s\n' "$1" >&2
    return 1
  fi
}
airplane-mode() (
  [ "$#" -le 1 ] || { printf 'Usage: airplane-mode [model]\n' >&2; return 1; }
  local model="${1:-$_airplane_default_model}"
  _airplane_check "$model" || return
  OPENCODE_DISABLE_AUTOUPDATE=true ollama launch opencode --model "$model" -- --standalone
)
_airplane_smoke() (
  _airplane_check "$_airplane_default_model" || return
  curl -fsS --connect-timeout 5 --max-time 180 http://127.0.0.1:11434/api/generate \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$_airplane_default_model\",\"prompt\":\"Say hello.\",\"stream\":false,\"options\":{\"num_predict\":16}}" | /usr/bin/perl -MJSON::PP -e '
      local $/; my $v = decode_json(<STDIN> // "");
      die "No completed model response\n" unless $v->{done} && length(($v->{response} // "") . ($v->{thinking} // ""));
      print(($v->{response} || $v->{thinking}), "\n");' || return
  OPENCODE_DISABLE_AUTOUPDATE=true ollama launch opencode --model "$_airplane_default_model" -- --standalone --version
)
OLLAMA
  else
    printf "_airplane_default_repo='%s'\n_airplane_model_alias='%s'\n" "$HF_REPO" "$MODEL_ALIAS"
    cat <<'LLAMA'
airplane-serve() (
  [ "$#" -le 1 ] || { printf 'Usage: airplane-serve [configured-HF-repository:quant]\n' >&2; return 1; }
  local repo="${1:-$_airplane_default_repo}" log="$HOME/.airplane-llamacpp.log" pid
  if [ "$repo" != "$_airplane_default_repo" ]; then
    printf 'Rerun bash src/airplane-mode.sh --engine llama.cpp to select and prepare a different default, then source the updated profile and stop the old server yourself.\n' >&2; return 1
  fi
  if curl -fsS --connect-timeout 1 --max-time 2 http://127.0.0.1:8080/health >/dev/null 2>&1; then
    return 0
  fi
  nohup llama-server -hf "$repo" --alias "$_airplane_model_alias" \
    --host 127.0.0.1 --port 8080 -c 64000 -fa on -ctk q8_0 -ctv q8_0 \
    --offline --no-webui >"$log" 2>&1 &
  pid=$!
  _airplane_wait http://127.0.0.1:8080/health "$pid" 180 "$log"
)
_airplane_check() {
  airplane-serve "$1" || return
  local models
  models=$(curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:8080/v1/models) || return
  if ! printf '%s' "$models" | grep -Fq "\"$_airplane_model_alias\""; then
    printf 'The running llama-server does not advertise %s. Stop it yourself and retry.\n' "$_airplane_model_alias" >&2
    return 1
  fi
}
airplane-mode() (
  [ "$#" -le 1 ] || { printf 'Usage: airplane-mode [configured-HF-repository:quant]\n' >&2; return 1; }
  _airplane_check "${1:-$_airplane_default_repo}" || return
  OPENCODE_DISABLE_AUTOUPDATE=true OPENCODE_CONFIG_CONTENT="{\"providers\":{\"airplane\":{\"package\":\"@opencode/ai/providers/openai-compatible\",\"settings\":{\"baseURL\":\"http://127.0.0.1:8080/v1\",\"apiKey\":\"local\"},\"models\":{\"$_airplane_model_alias\":{\"limit\":{\"context\":64000,\"output\":8192},\"capabilities\":{\"tools\":true}}}}}}" \
    opencode --standalone --model "airplane/$_airplane_model_alias"
)
_airplane_smoke() (
  _airplane_check "$_airplane_default_repo" || return
  curl -fsS --connect-timeout 5 --max-time 180 http://127.0.0.1:8080/completion \
    -H 'Content-Type: application/json' -d '{"prompt":"Say hello.","n_predict":16}' | /usr/bin/perl -MJSON::PP -e '
      local $/; my $v = decode_json(<STDIN> // "");
      die "No model response\n" unless length($v->{content} // "");
      print $v->{content}, "\n";'
)
LLAMA
  fi
  printf '%s\n' "$MARK_END"
}

replace_profile_block() {
  /usr/bin/perl - "$PROFILE" "$1" "$MARK_BEGIN" "$MARK_END" <<'PERL'
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Temp qw(tempfile);
my ($profile, $blockfile, $begin, $end) = @ARGV;
my $target = -l $profile ? abs_path($profile) : $profile;
defined $target or die "Cannot resolve profile symlink $profile\n";
my $original = '';
my $mode = 0600;
if (-e $target) {
  open my $in, '<', $target or die "Read $target: $!\n";
  local $/; $original = <$in>; close $in or die "Close $target: $!\n";
  $mode = (stat $target)[2] & 07777;
}
my @begins = ($original =~ /^\Q$begin\E\r?$/mg);
my @ends = ($original =~ /^\Q$end\E\r?$/mg);
(@begins == @ends && @begins <= 1) or die "Malformed airplane-mode profile markers in $profile\n";
open my $input, '<', $blockfile or die "Read launcher: $!\n";
local $/; my $block = <$input>; close $input or die "Close launcher: $!\n";
my $updated = $original;
if (@begins) {
  $updated =~ s/^\Q$begin\E\r?\n.*?^\Q$end\E\r?(?:\n|\z)/$block/msg
    or die "Reversed or malformed airplane-mode profile markers in $profile\n";
} else {
  $updated .= "\n" if length($updated) && $updated !~ /\n\z/;
  $updated .= $block;
}
exit 0 if $updated eq $original;
if (-e $target) {
  my ($backup, $backupname) = tempfile("$target.airplane-backup.XXXXXX", UNLINK => 0);
  close $backup or die "Close backup: $!\n";
  copy($target, $backupname) or die "Backup $target: $!\n";
  chmod($mode, $backupname) or die "Set backup permissions: $!\n";
  print "Backup: $backupname\n";
}
my ($out, $temporary) = tempfile('.airplane-profile.XXXXXX', DIR => dirname($target), UNLINK => 0);
print {$out} $updated or die "Write profile: $!\n";
close $out or die "Close profile: $!\n";
chmod($mode, $temporary) or die "Set profile permissions: $!\n";
rename($temporary, $target) or die "Replace profile: $!\n";
PERL
}

prepare_llama_model() {
  local log="$HOME/.airplane-llamacpp-download.log" pid rc=0
  if curl -fsS --connect-timeout 1 --max-time 2 http://127.0.0.1:18080/health >/dev/null 2>&1; then
    fail 'Port 18080 is already in use. Stop that server yourself before preparing the GGUF.'; return 1
  fi
  llama-server -hf "$HF_REPO" --host 127.0.0.1 --port 18080 -c 512 --no-webui >"$log" 2>&1 &
  pid=$!
  _airplane_wait http://127.0.0.1:18080/health "$pid" 600 "$log" || rc=$?
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" || return
    local stopped=0
    wait "$pid" || stopped=$?
    case "$stopped" in 0|130|143) ;; *) fail "Model preparation exited with $stopped. See $log"; return 1 ;; esac
  fi
  [ "$rc" -eq 0 ] || return "$rc"
  say "GGUF prepared. See $log"
}

main() {
  ENGINE=ollama
  local update=0 arg
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --engine) [ "$#" -ge 2 ] || { fail '--engine requires a value.'; return 1; }; ENGINE="$2"; shift 2 ;;
      --engine=*) ENGINE="${1#*=}"; shift ;;
      --update) update=1; shift ;;
      -h|--help)
        say 'Usage: bash src/airplane-mode.sh [--engine ollama|llama.cpp] [--update]'
        say '--update upgrades existing tools for the selected engine and exits without downloading models.'
        return 0 ;;
      *) fail "Unknown argument $1. Try --help."; return 1 ;;
    esac
  done
  case "$ENGINE" in ollama|llama.cpp) ;; llamacpp) ENGINE=llama.cpp ;; *) fail "Unknown engine $ENGINE"; return 1 ;; esac
  [ "$(uname -s)" = Darwin ] || { fail 'This setup targets macOS.'; return 1; }
  if [ "$update" -eq 1 ]; then
    update_tool opencode || return
    if [ "$ENGINE" = ollama ]; then update_tool ollama; else update_tool llama-server; fi
    return
  fi
  say 'Airplane Mode setup. This downloads tools and models while online.'
  say 'OpenCode runs with your file and shell permissions. Review its actions and any plugins you add.'
  local ack pick
  read -r -p "Type 'yes' to continue: " ack
  [ "$ack" = yes ] || { fail 'Aborted.'; return 1; }
  ensure_tools || return
  say "[1] $DEFAULT_MODEL (default)"
  say "[2] $CODING_MODEL"
  if [ "$ENGINE" = ollama ]; then say '[3] Both'; fi
  read -r -p 'Choose [1]: ' pick
  local models
  case "${pick:-1}" in
    1) SELECTED_MODEL="$DEFAULT_MODEL"; HF_REPO="$DEFAULT_HF_REPO"; MODEL_ALIAS=qwen38-27b; models=("$DEFAULT_MODEL") ;;
    2) SELECTED_MODEL="$CODING_MODEL"; HF_REPO="$CODING_HF_REPO"; MODEL_ALIAS=qwen3-coder-30b; models=("$CODING_MODEL") ;;
    3) [ "$ENGINE" = ollama ] || { fail 'Choose 1 or 2.'; return 1; }; SELECTED_MODEL="$DEFAULT_MODEL"; models=("$DEFAULT_MODEL" "$CODING_MODEL") ;;
    *) fail 'Choose a listed model.'; return 1 ;;
  esac
  local block
  block=$(mktemp) || return
  trap "rm -f '$block'" EXIT
  write_launcher_block >"$block" || return
  . "$block"
  if [ "$ENGINE" = ollama ]; then
    if curl -fsS --connect-timeout 1 --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
      say 'Reusing the existing Ollama server. Restart it yourself to apply changed server settings.'
    fi
    _airplane_ready || return
    for arg in "${models[@]}"; do
      if ! ollama show "$arg" >/dev/null 2>&1; then ollama pull "$arg" || return; fi
    done
  else
    prepare_llama_model || return
  fi
  say 'Checking the generated launcher and a local model response.'
  _airplane_smoke || return
  PROFILE="$HOME/.zshrc"
  [ -n "${ZSH_VERSION:-}" ] || [ -f "$PROFILE" ] || PROFILE="$HOME/.bashrc"
  replace_profile_block "$block" || return
  rm -f "$block"
  trap - EXIT
  say "Ready. Run: source $PROFILE"
  say 'Then run airplane-mode. Turn Wi-Fi off and complete a real task before travelling.'
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
