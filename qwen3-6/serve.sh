#!/usr/bin/env bash
# Qwen3.6-35B-A3B (MoE, 3B active) on llama-server with Metal.
# Usage: ./serve.sh [extra llama-server args...]
#
# Endpoint: http://127.0.0.1:8080  (OpenAI-compatible at /v1/chat/completions)
# Web UI:   http://127.0.0.1:8080  in a browser
#
# This is a REASONING model. Responses come back split across two fields:
#   .choices[0].message.reasoning_content  <- chain of thought
#   .choices[0].message.content            <- the actual answer
# Budget max_tokens accordingly; a small limit gets spent entirely on thinking
# and returns an empty content string.
#
# To skip thinking for simple/latency-sensitive calls, pass:
#   "chat_template_kwargs": {"enable_thinking": false}
set -euo pipefail

MODEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="$MODEL_DIR/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf"
MMPROJ="$MODEL_DIR/mmproj-F16.gguf"

# Context. Model supports up to 262144. KV costs ~40KB/token with the q8_0
# cache below, so: 65536 ≈ 2.5GB, 131072 ≈ 5GB, 262144 ≈ 10GB.
# Raising this costs only KV memory — prefill time scales with tokens actually
# used, not with capacity reserved. Override: CTX=262144 ./serve.sh
CTX="${CTX:-131072}"
PORT="${PORT:-8080}"

ARGS=(
  -m "$MODEL"
  --host 127.0.0.1
  --port "$PORT"

  # Metal: offload every layer to the GPU.
  -ngl 99

  -c "$CTX"

  # Flash attention is a significant win on Apple GPUs and is required
  # for the quantized KV cache below.
  -fa on

  # q8_0 KV cache halves context memory at negligible quality cost.
  # Drop these two lines if you want bit-exact f16 KV.
  -ctk q8_0
  -ctv q8_0

  # Batch sizes tuned for Metal prompt processing throughput.
  -b 2048
  -ub 512

  # Single-user setup: one slot gets the whole context.
  -np 1

  # Qwen3.6 ships a Jinja chat template with tool-call support.
  --jinja
)

# Vision support, if the projector was downloaded.
[ -f "$MMPROJ" ] && ARGS+=(--mmproj "$MMPROJ")

exec llama-server "${ARGS[@]}" "$@"
