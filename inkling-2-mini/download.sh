#!/usr/bin/env bash
# Download Inkling 2 Mini (GGUF). ~18 GB. Re-runnable.
#
# Uses ggml-org's conversion, NOT unsloth/Inkling-2-Mini-GGUF: as of 2026-11-20
# the unsloth files declare block_count=48 while packing 24 physical blocks and
# fail to load ("tensor 'blk.24.attn_q.weight' not found"). ggml-org's files
# (architecture inkling2_loop, block_count=24) match the loader in PR #32694.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-ggml-org/Inkling-2-Mini-GGUF}"
QUANT="${QUANT:-IQ4_NL}"   # IQ4_NL (17.6 GB) | Q8_0 (27.8 GB)
command -v hf >/dev/null || { echo "error: 'hf' CLI not found (pip install -U huggingface_hub)" >&2; exit 1; }
hf download "$REPO" "Inkling-2-Mini-${QUANT}.gguf" "mmproj-Inkling-2-Mini-Q8_0.gguf" --local-dir "$DIR"
ls -lh "$DIR"/*.gguf
