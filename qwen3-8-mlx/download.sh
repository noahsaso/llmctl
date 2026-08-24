#!/usr/bin/env bash
# Download Qwen3.8-27B-Uncensored (MLX). ~16 GB for 4-bit + MTP draft.
# Safe to re-run: hf resumes and skips complete files.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="orcarouter/Qwen3.8-27B-Uncensored-MLX"
QUANT="${QUANT:-4-bit}"   # 2-bit | 4-bit | 6-bit | 8-bit

command -v hf >/dev/null || { echo "error: 'hf' CLI not found (pip install -U huggingface_hub)" >&2; exit 1; }

# NOTE: this repo carries FIVE full copies of the model (2/4/6/8-bit plus a root
# copy) totalling ~95 GB. Never clone or snapshot it whole — fetch one quant.
#
# --include must be REPEATED. `--include "a/*" "b/*"` makes the CLI treat b/* as
# a literal filename, silently ignore --include, and exit 0 having done nothing.
echo "==> $QUANT + mtp draft"
hf download "$REPO" \
  --include "${QUANT}/*" \
  --include "mtp/*" \
  --local-dir "$DIR"

echo
echo "done:"
du -sh "$DIR/$QUANT" "$DIR/mtp" 2>/dev/null || true
