#!/usr/bin/env bash
# Inkling 2 Mini (looped MoE, 128 experts / 8 active) on llama-server with Metal.
# Endpoint: http://127.0.0.1:8082/v1
#
# Needs a llama-server with looped-architecture support; see build-llama.sh.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
MODEL="$DIR/Inkling-2-Mini-${QUANT:-IQ4_NL}.gguf"
MMPROJ="$DIR/mmproj-Inkling-2-Mini-Q8_0.gguf"
CTX="${CTX:-65536}"
PORT="${PORT:-8082}"

# Prefer the pinned PR build; fall back to PATH once upstream ships support.
BIN="${LLAMA_SERVER:-$ROOT/.build/llama.cpp-inkling/build/bin/llama-server}"
[ -x "$BIN" ] || BIN="$(command -v llama-server || true)"
[ -n "$BIN" ] || { echo "error: no llama-server. Run $DIR/build-llama.sh" >&2; exit 1; }

ARGS=(-m "$MODEL" --host 127.0.0.1 --port "$PORT" -ngl 99 -c "$CTX" -fa on -np 1 --jinja)
[ -f "$MMPROJ" ] && ARGS+=(--mmproj "$MMPROJ")
exec "$BIN" "${ARGS[@]}" "$@"
