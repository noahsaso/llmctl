#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local output="$1" expected="$2"
  [[ "$output" == *"$expected"* ]] || fail "expected output to contain: $expected"
}

# Keep doctor independent of services that might be running on the test host.
mkdir -p "$TMP/bin" "$TMP/home"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/curl"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/tmux"
chmod +x "$TMP/bin/curl" "$TMP/bin/tmux"

# An override path can contain ordinary filesystem characters such as spaces or
# apostrophes. doctor must validate and read this file rather than ~/.pi's file.
models="$TMP/pi config's/models.json"
mkdir -p "$(dirname "$models")"
python3 - "$models" "$ROOT" <<'PY'
import json
import sys

path, root = sys.argv[1:]
doc = {
    "providers": {
        "llama-server": {
            "baseUrl": "http://127.0.0.1:8080/v1",
            "models": [{
                "id": "Qwen3.6-35B-A3B-UD-Q4_K_M.gguf",
                "contextWindow": 131072,
            }],
        },
        "mlx-qwen3-8": {
            "baseUrl": "http://127.0.0.1:8081/v1",
            "models": [{
                "id": f"{root}/qwen3-8-mlx/4-bit",
                "contextWindow": 65536,
            }],
        },
    }
}
with open(path, "w") as file:
    json.dump(doc, file)
PY

output=$(cd "$ROOT" && HOME="$TMP/home" PI_MODELS="$models" \
  PATH="$TMP/bin:$PATH" ./llmctl doctor 2>&1) || true

# Other doctor checks depend on locally downloaded weights, but config checks
# must report the overridden file and both providers as valid.
assert_contains "$output" "models.json is valid JSON"
assert_contains "$output" "provider 'llama-server' -> http://127.0.0.1:8080/v1"
assert_contains "$output" "provider 'mlx-qwen3-8' -> http://127.0.0.1:8081/v1"

printf 'ok - doctor honors PI_MODELS override\n'
