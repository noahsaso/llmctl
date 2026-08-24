#!/usr/bin/env bash
# Download Qwen3.6-35B-A3B weights (GGUF, for llama.cpp).
# ~23 GB total. Safe to re-run: hf resumes and skips complete files.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="unsloth/Qwen3.6-35B-A3B-GGUF"
QUANT="${QUANT:-UD-Q4_K_M}"
WEIGHTS="Qwen3.6-35B-A3B-${QUANT}.gguf"

command -v hf >/dev/null || { echo "error: 'hf' CLI not found (pip install -U huggingface_hub)" >&2; exit 1; }

echo "==> $WEIGHTS  (~22 GB)"
hf download "$REPO" "$WEIGHTS" --local-dir "$DIR"

# Vision projector — Qwen3.6 is multimodal; serve.sh picks this up if present.
echo "==> mmproj-F16.gguf  (~0.9 GB)"
hf download "$REPO" "mmproj-F16.gguf" --local-dir "$DIR"

echo
echo "done:"
ls -lh "$DIR"/*.gguf
