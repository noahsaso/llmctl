#!/usr/bin/env bash
# Qwen3.8-27B-Uncensored (dense, 4-bit MLX) on mlx_lm.server.
# Usage: ./serve.sh [extra mlx_lm.server args...]
#
# Endpoint: http://127.0.0.1:8081/v1  (OpenAI-compatible)
# Port 8081 deliberately — 8080 belongs to the Qwen3.6 llama-server.
#
# NOTE: the mtp/ draft model in this repo is NOT usable with mlx_lm 0.31.1.
# Its model_type is `qwen3_5_mtp`, which mlx_lm has no module for, so
# --draft-model errors out. Retry after an mlx_lm upgrade adds support.
set -euo pipefail

MODEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${PORT:-8081}"

# Locate mlx_lm.server: PATH first, then common env locations. Override with PY=.
if [ -n "${PY:-}" ]; then :
elif command -v mlx_lm.server >/dev/null 2>&1; then PY="$(command -v mlx_lm.server)"
elif [ -x "$HOME/anaconda3/bin/mlx_lm.server" ]; then PY="$HOME/anaconda3/bin/mlx_lm.server"
elif [ -x "$HOME/miniconda3/bin/mlx_lm.server" ]; then PY="$HOME/miniconda3/bin/mlx_lm.server"
else
  echo "error: mlx_lm.server not found. pip install -U mlx-lm (or set PY=/path/to/mlx_lm.server)" >&2
  exit 1
fi

exec "$PY" \
  --model "$MODEL_DIR/4-bit" \
  --host 127.0.0.1 \
  --port "$PORT" \
  "$@"
