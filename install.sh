#!/usr/bin/env bash
# Bootstrap the local LLM stack.
#
#   ./install.sh                  check what's missing, print exact fix commands
#   ./install.sh --install-deps   actually install the missing dependencies
#   ./install.sh --no-pi          skip pi provider configuration
#   ./install.sh --with-tmux-conf also persist pi's tmux key setting
#
# Default is check-only on purpose: --install-deps runs brew/pip/npm installs.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DO_PI=1; DO_INSTALL=0; DO_TMUX=0
for a in "$@"; do
  case "$a" in
    --no-pi)          DO_PI=0 ;;
    --install-deps)   DO_INSTALL=1 ;;
    --with-tmux-conf) DO_TMUX=1 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  esac
done

ok()   { printf "  \033[32mok\033[0m    %s\n" "$1"; }
bad()  { printf "  \033[31mmiss\033[0m  %s\n" "$1"; }
note() { printf "  \033[33mwarn\033[0m  %s\n" "$1"; }
run()  { echo "        + $*"; "$@" || return 1; }

missing=0; todo=""
want() { todo="$todo$1\n"; }

echo "platform"
if [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
  ok "macOS on Apple Silicon ($(sysctl -n hw.memsize | awk '{printf "%d GB RAM", $1/1073741824}'))"
  MEM=$(sysctl -n hw.memsize | awk '{print int($1/1073741824)}')
  [ "$MEM" -lt 32 ] && note "under 32 GB RAM — these models will not fit comfortably"
else
  note "not macOS/arm64 — Metal and MLX are Apple-Silicon only"
fi
FREE=$(df -g / 2>/dev/null | awk 'NR==2{print $4}')
[ -n "$FREE" ] && { [ "$FREE" -lt 45 ] && note "only ${FREE} GB free — both models need ~40 GB" || ok "${FREE} GB free disk"; }

echo
echo "core tools"
for c in git tmux python3 curl; do
  command -v "$c" >/dev/null && ok "$c" || { bad "$c"; missing=1; want "  $c: install via Xcode CLT (xcode-select --install) or Homebrew"; }
done

if command -v brew >/dev/null; then ok "homebrew"
else
  bad "homebrew — needed for llama.cpp"
  want '  homebrew: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  missing=1
fi

echo
echo "runtimes"
if command -v llama-server >/dev/null; then
  ok "llama-server (build $(llama-server --version 2>&1 | head -1 | awk '{print $2}'))"
else
  bad "llama-server — required for qwen3-6"
  if [ "$DO_INSTALL" = 1 ] && command -v brew >/dev/null; then
    run brew install llama.cpp && ok "installed llama.cpp" || want "  llama.cpp: brew install llama.cpp"
  else want "  llama.cpp: brew install llama.cpp"; fi
fi

PIP="${PIP:-python3 -m pip}"
if command -v mlx_lm.server >/dev/null || [ -x "$HOME/anaconda3/bin/mlx_lm.server" ]; then ok "mlx_lm.server"
else
  note "mlx_lm.server — required for qwen3-8 (optional if you only run qwen3-6)"
  if [ "$DO_INSTALL" = 1 ]; then
    run $PIP install -U mlx-lm && ok "installed mlx-lm" || want "  mlx-lm: $PIP install -U mlx-lm"
  else want "  mlx-lm: $PIP install -U mlx-lm"; fi
fi

if command -v hf >/dev/null; then ok "hf (HuggingFace CLI)"
else
  bad "hf — required to download weights"
  if [ "$DO_INSTALL" = 1 ]; then
    run $PIP install -U huggingface_hub && ok "installed huggingface_hub" || want "  hf: $PIP install -U huggingface_hub"
  else want "  hf: $PIP install -U huggingface_hub"; fi
fi

echo
echo "pi (the client)"
if command -v pi >/dev/null; then ok "pi $(pi --version 2>&1 | head -1)"
else
  note "pi not found (optional — the servers work with any OpenAI-compatible client)"
  if [ "$DO_INSTALL" = 1 ] && command -v npm >/dev/null; then
    run npm install -g @earendil-works/pi-coding-agent && ok "installed pi" \
      || want "  pi: npm install -g @earendil-works/pi-coding-agent"
  else want "  pi: npm install -g @earendil-works/pi-coding-agent  (needs node/npm)"; fi
fi

echo
echo "llmctl on PATH"
TARGET=""
for d in "$HOME/.local/bin" "$HOME/n/bin" "$HOME/bin" /opt/homebrew/bin; do
  case ":$PATH:" in *":$d:"*) [ -d "$d" ] && [ -w "$d" ] && { TARGET="$d"; break; } ;; esac
done
if [ -n "$TARGET" ]; then ln -sf "$DIR/llmctl" "$TARGET/llmctl" && ok "$TARGET/llmctl -> $DIR/llmctl"
else note "no writable PATH dir; add:  export PATH=\"$DIR:\$PATH\""; fi

echo
echo "tmux"
if grep -q "extended-keys-format csi-u" "$HOME/.tmux.conf" 2>/dev/null; then
  ok "csi-u persisted in ~/.tmux.conf"
elif [ "$DO_TMUX" = 1 ]; then
  printf '\n# pi renders best with csi-u key encoding\nset -g extended-keys-format csi-u\n' >> "$HOME/.tmux.conf"
  tmux set -g extended-keys-format csi-u 2>/dev/null
  ok "appended csi-u to ~/.tmux.conf"
else
  note "pi wants csi-u keys; re-run with --with-tmux-conf, or add to ~/.tmux.conf:"
  echo "        set -g extended-keys-format csi-u"
fi

echo
echo "defaults"
"$DIR/llmctl" config init >/dev/null 2>&1 || true
ok "overrides file: $("$DIR/llmctl" config path)"
"$DIR/llmctl" config show 2>/dev/null | tail -n +3 | sed 's/^/    /'
echo "    edit that file, or: llmctl config set <model>.<key> <value>"

if [ "$DO_PI" = 1 ] && command -v pi >/dev/null; then
  echo
  echo "pi providers"
  "$DIR/llmctl" pi-setup || note "pi-setup failed"
  echo
  echo "pi tool-policy extension"
  "$DIR/llmctl" pi-extension install || note "extension registration failed"
fi

if [ -n "$todo" ]; then
  echo
  echo "still to install:"
  printf "$todo"
  echo
  echo "  re-run with --install-deps to do the brew/pip/npm steps automatically"
fi

echo
echo "next steps"
echo "  llmctl download qwen3-6     # ~23 GB"
echo "  llmctl start qwen3-6"
echo "  llmctl doctor"
[ "$missing" = 1 ] && exit 1
exit 0
