#!/usr/bin/env bash
# Build a llama-server that can load Inkling 2 Mini.
#
# Inkling 2 Mini is a looped transformer. As of 2026-11-20 no llama.cpp release
# supports it: Homebrew stable (v1.0.0) predates Inkling entirely, and loop
# support lives in the open PR ggml-org/llama.cpp#32694. This builds that PR,
# pinned to a commit, into <repo>/.build so the system llama.cpp is untouched.
#
# Once the PR is merged and released, delete .build/ and drop LLAMA_SERVER from
# serve.sh's lookup; a normal `brew upgrade llama.cpp` will do.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/.build/llama.cpp-inkling"
REF="${LLAMA_REF:-refs/pull/32694/head}"
PIN="${LLAMA_PIN:-d7cb78c91}"   # set LLAMA_PIN= (empty) to take the PR's latest

command -v cmake >/dev/null || { echo "error: cmake not found (brew install cmake)" >&2; exit 1; }

if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$SRC" && git -C "$SRC" init -q
  git -C "$SRC" remote add origin https://github.com/ggml-org/llama.cpp.git
fi
git -C "$SRC" fetch -q --depth 50 origin "$REF"
git -C "$SRC" checkout -q "${PIN:-FETCH_HEAD}" 2>/dev/null || git -C "$SRC" checkout -q FETCH_HEAD
echo "building $(git -C "$SRC" log --oneline -1)"

cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=ON \
  -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF >/dev/null
cmake --build "$SRC/build" --target llama-server llama-bench -j "$(sysctl -n hw.ncpu)"
echo "built: $SRC/build/bin/llama-server"
