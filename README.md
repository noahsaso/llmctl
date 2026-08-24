# llmctl — local LLM stack for Apple Silicon

Two local models served as OpenAI-compatible endpoints, orchestrated by `llmctl`,
wired into pi, and optionally reachable from mobile over Tailscale.

All measurements below were taken on a Mac mini M4 Pro / 64 GB; treat them as a
reference point for similar hardware, not as guarantees.

| | Model A | Model B |
|---|---|---|
| Model | Qwen3.6-35B-A3B | Qwen3.8-27B-Uncensored |
| Runtime | llama.cpp (GGUF) | MLX |
| Shape | MoE, ~3B active | dense, all 27B active |
| Port | 8080 | 8081 |
| Generation | **39.9 tok/s** | **12.9 tok/s** |

Both fit in RAM individually; running them **at the same time** is tight against
the 48 GiB Metal working set — see the memory notes in each section.

Started 2026-08-16 (Model A); Model B added 2026-08-24.

## What runs where

| Piece | Where | Notes |
|---|---|---|
| llama-server | tmux session `llama` | `~/models/qwen3.6/serve.sh`, binds `127.0.0.1:8080` |
| mlx_lm.server | tmux session `mlx` | `~/models/qwen3.8-mlx/serve.sh`, binds `127.0.0.1:8081` |
| pi | tmux session `pi` | cwd `~/workspace`, provider `llama-server` |
| pi-remote | pi extension (not the CLI binary) | discovery on `:7008`, session on `:7009` |
| Tailscale serve | `<host>.<tailnet>.ts.net` | `/pi/` → 7008, `/pi/<id>/` → 7009 |

All three tmux sessions are parented to the tmux server, so they survive terminal and
SSH disconnects.

## Quick start

```bash
# model server
tmux new-session -d -s llama -c ~/models/qwen3.6 './serve.sh'

# second model server (MLX)
tmux new-session -d -s mlx -c ~/models/qwen3.8-mlx './serve.sh'

# pi
tmux new-session -d -s pi -c ~/workspace \
  "pi --provider llama-server --model 'Qwen3.6-35B-A3B-UD-Q4_K_M.gguf'"

# attach, then run /remote inside pi for phone access
tmux attach -t pi
```

Health checks: `curl -s localhost:8080/health` · `curl -s localhost:8081/v1/models`


## Orchestration: `llmctl`

`~/models/llmctl` (symlinked onto PATH as `llmctl`) drives the model servers.

```
llmctl status              what is running right now
llmctl list                available models
llmctl start <model>       start one (stops the others first)
llmctl stop [<model>|all]  stop one or everything
llmctl restart <model>     stop + start
llmctl use <model>         start it and print the pi command to match
llmctl doctor              verify pi config matches reality
llmctl logs <model> [n]    tail that server's tmux output
```

**`start` enforces one model at a time** — it stops the others first, because
together they exceed the 48 GiB Metal working set. Override with `--keep` if you
genuinely want both up (`llmctl start qwen3.8 --keep`).

`doctor` is the one to run when something looks wrong. It checks, per model:
weights present, `serve.sh` executable, the pi provider exists and its `baseUrl`
points at the right port, the pi model id matches, and — for llama-server — that
pi's `contextWindow` equals the running `-c`. That last one is the failure this
setup actually hit: the two are independent settings, and a mismatch silently
makes pi compact early or overflow the server. It also warns if more than one
server is up, and if tmux `extended-keys-format` is not `csi-u`.

Measured cold starts: qwen3.6 ~10s, qwen3.8 ~12s (weights in page cache).


## Tool policy

pi's `--tools` is an **allowlist** spanning built-in, extension and custom tools.
`llmctl` keeps a policy per model and emits the right flag from `llmctl use`:

```
llmctl tools              show both models' effective lists
llmctl tools qwen3.8      show one
llmctl tools scan         rediscover tool names from pi's extensions
```

| Policy | Meaning |
|---|---|
| `all` | built-ins + every extension tool, network included |
| `offline` | same, minus anything that reaches the internet |
| `default` | pass no `--tools`; pi's own defaults |
| *literal list* | used verbatim as the allowlist |

Current defaults: **qwen3.6 = `all`** (34 tools), **qwen3.8 = `offline`** (30) —
excluding `websearch`, `web_search_exa`, `webfetch` and `generate_image`.

Two things worth knowing:

- `grep`, `find` and `ls` are built in but **off by default** in pi. Any policy
  meaning "everything" has to name them explicitly, which `all` does.
- **pi silently ignores unknown tool names.** A typo, or an extension you
  removed, quietly disables a tool with no error. `llmctl doctor` guards this by
  scanning pi's extension sources and reporting names that are configured but
  missing, or discovered but not yet categorised.

Edit `TOOLS_BUILTIN` / `TOOLS_EXT` / `TOOLS_NET` at the top of `llmctl` after
changing extensions; `llmctl tools scan` prints what to put there.

## Bootstrapping a new machine

This repo holds the layout, scripts, and docs — **not** the weights (tens of GB,
gitignored). Weights are re-downloaded per machine.

### Requirements

- **Apple Silicon Mac.** Metal and MLX are Apple-only; nothing here runs on Intel
  or Linux as written.
- **32 GB RAM minimum**, 64 GB to run comfortably. The numbers throughout this
  README were measured on an M4 Pro / 64 GB.
- **~40 GB free disk** for both models (23 GB + 16 GB), plus room to work.

`install.sh` verifies all three and warns if the machine falls short.

### From scratch

```bash
git clone git@github.com:noahsaso/llmctl.git ~/models
cd ~/models

./install.sh                  # check what's missing (safe, changes nothing)
./install.sh --install-deps   # actually install it

llmctl download qwen3.6       # ~23 GB
llmctl start qwen3.6
llmctl doctor
```

`install.sh` is **check-only by default** — it inspects and prints exact fix
commands without touching anything. `--install-deps` performs the brew/pip/npm
installs. Extra flags: `--with-tmux-conf` (persist pi's key setting),
`--no-pi` (skip pi provider configuration).

What it handles:

| Step | Default | With `--install-deps` |
|---|---|---|
| platform / RAM / disk check | reports | reports |
| `git` `tmux` `python3` `curl` | reports | reports (install via Xcode CLT) |
| Homebrew | reports + install cmd | reports + install cmd |
| `llama.cpp` (Model A) | prints cmd | `brew install llama.cpp` |
| `mlx-lm` (Model B) | prints cmd | `pip install -U mlx-lm` |
| `huggingface_hub` (downloads) | prints cmd | `pip install -U huggingface_hub` |
| `pi` (client) | prints cmd | `npm install -g @earendil-works/pi-coding-agent` |
| `llmctl` onto PATH | symlinks | symlinks |
| pi provider entries | runs `pi-setup` | runs `pi-setup` |
| tmux `csi-u` | prints line to add | appends with `--with-tmux-conf` |

Homebrew is never auto-installed — it is a large system-wide change, so the
command is printed for you to run deliberately. `pi` is optional: the servers
speak plain OpenAI-compatible HTTP and work with any client.

### pi configuration

`llmctl pi-setup` writes the provider entries into `~/.pi/agent/models.json`,
merging with whatever is already there and backing up to `.bak` first. It
refuses to write if the existing file is malformed rather than clobbering it.

This is generated, not committed, for a reason: the MLX model id is an
**absolute path**, so it differs per machine and per username. Re-run it after
changing a model's port or context window.

### Download scripts

Each model dir has a `download.sh`, also reachable as `llmctl download <model>`.
Both are re-runnable — `hf` resumes partial files and skips complete ones.
Quant is overridable: `QUANT=6-bit ./qwen3.8-mlx/download.sh`.

Weights come from public HuggingFace repos; no HF token is needed.

### Optional: phone access

Not covered by `install.sh` — see [Phone access](#phone-access) below. It needs
Tailscale on the machine, plus
[`noahsaso/pi-remote`](https://github.com/noahsaso/pi-remote) registered in pi's
`settings.json` under `packages`.

---

# Model A — Qwen3.6-35B-A3B (GGUF, MoE)

## Model

`unsloth/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf` — 22,134,528,992 bytes (verified against
the HuggingFace-reported size).

MoE: 256 experts, 8 active → ~3B active params per token. That is the whole
reason this is fast; the dense Qwen3.6-27B at the same quant runs roughly a third
the speed. Unsloth's UD quants are calibrated dynamic quants, which matter more
for MoE than for dense models.

`mmproj-F16.gguf` (858 MB) is also present — Qwen3.6 is multimodal, and serve.sh
picks the projector up automatically if the file exists.

## Configuration rationale

See `serve.sh`. The non-obvious choices:

- **`-ngl 99`** — all 40 layers on Metal.
- **`-fa on`** — flash attention; significant on Apple GPUs and required for the
  quantized KV cache.
- **`-ctk/-ctv q8_0`** — halves KV cost at negligible quality loss.
- **`-c 131072`** — see below.
- **`-np 1`** — single slot, so one conversation gets the full context. Note this
  means concurrent requests queue, and a second client evicts the first's cached
  prefix.

### Context sizing

Architecture: 40 layers, 2 KV heads, head_dim 256. That is a very lean GQA
setup — **40 KiB/token** with the q8_0 cache (80 KiB at f16).

| Context | KV | Total resident |
|---|---|---|
| 65536 | 2.5 GiB | ~22 GiB |
| **131072 (current)** | **5 GiB** | **~24.6 GiB** |
| 262144 (model max) | 10 GiB | ~29.6 GiB |

Metal working set is 48 GiB, so even full 256K fits. Raise with
`CTX=262144 ./serve.sh`.

**Raising `-c` costs only KV memory.** Prefill time scales with tokens actually
processed, not capacity reserved — an 11k-token prompt costs the same at 64k as
at 256k.

## Measured performance

Generation, via `llama-bench`:

| Metric | Result |
|---|---|
| Generation (tg128) | **39.9 tok/s** |
| Prompt processing (pp512) | **485 tok/s** |

Prefill is **not linear** — attention is quadratic in sequence length. Measured on
this machine, fitting `T = 0.0015·N + 3.22e-8·N²` (residuals < 0.3s):

| Context | Full cold prefill | Effective tok/s | Attention share |
|---|---|---|---|
| 8k | 0.2 min | 566 | 15% |
| 32k | 1.4 min | 391 | 41% |
| 64k | 3.9 min | 277 | 58% |
| 128k | 12.5 min | 175 | 74% |
| 256k | 43.4 min | 101 | 85% |

64k → 128k is 3.2× the time for 2× the tokens. **These are cold, full prefills.**
In practice llama.cpp caches the prefix, so a conversation growing to 100k over
many turns only prefills each turn's delta. The cost is only paid in full by
pasting a huge document in one shot.

Real pi session numbers:

- Cold start: **11,705 tokens in 24.8s** (system prompt + skills + tool defs)
- Every turn after: 50–300 tokens, **under 1 second**

That 11.7k prefix is nearly all skills and extension tool definitions. To cut the
cold start, trim skills (`-ns`, or `--skill` with a shortlist).

## Gotchas (Qwen3.6)

**It is a reasoning model.** Responses split across two fields:

- `.choices[0].message.reasoning_content` — chain of thought
- `.choices[0].message.content` — the answer

A small `max_tokens` gets spent entirely on thinking and returns an empty
`content`. Skip thinking for latency-sensitive calls:

```json
"chat_template_kwargs": {"enable_thinking": false}
```

Verified: "What is 2+2?" returns `4` in 2 tokens instead of ~190.

---

# Model B — Qwen3.8-27B-Uncensored (MLX, dense)

Added 2026-08-24. Lives at `~/models/qwen3.8-mlx/`, served by `mlx_lm.server`
on **port 8081** (8080 belongs to the llama-server above).

```bash
tmux new-session -d -s mlx -c ~/models/qwen3.8-mlx './serve.sh'
curl -s localhost:8081/v1/models
```

Source: `orcarouter/Qwen3.8-27B-Uncensored-MLX`, `4-bit/` subfolder (15 GB) plus
`mtp/` (829 MB).

**The repo holds five full copies** (2/4/6/8-bit plus a root copy) totaling
94.7 GB. Never clone or snapshot it whole — fetch one quant:

```bash
hf download orcarouter/Qwen3.8-27B-Uncensored-MLX \
  --include "4-bit/*" --include "mtp/*" --local-dir ~/models/qwen3.8-mlx
```

`--include` must be **repeated**, not given multiple patterns. `--include "a/*" "b/*"`
makes the CLI treat `b/*` as a literal filename, silently ignore `--include`, and
exit 0 having downloaded nothing.

## Dense, not MoE — expect it to be slower

| | Qwen3.6-35B-A3B (MoE) | Qwen3.8-27B (dense) |
|---|---|---|
| Generation | **39.9 tok/s** | **12.9 tok/s** |
| Active params | ~3B of 35B | all 27B |
| Layers / KV heads | 40 / 2 | 64 / 4 |
| KV per token | 80 KiB (f16) | **256 KiB (f16)** |

Both measured on this machine. The 3× generation gap is the dense/MoE tradeoff.

**Context is 3.2× more expensive here** — 256 KiB/token:

| Context | KV | + 15 GB weights |
|---|---|---|
| 16384 | 4 GiB | 19 GB |
| **32768 (pi default)** | **8 GiB** | **23 GB** |
| 65536 | 16 GiB | 31 GB |
| 131072 | 32 GiB | 47 GB |

The Metal working set is 48 GiB total. At 32768 this coexists with the
Qwen3.6 llama-server (~24.6 GB) only just — 47.6 GB combined. **In practice run
one at a time**; stop the other session before pushing either to long context.

`mlx_lm.server` has no `-c` equivalent; the cache grows as needed. Bound it with
`--prompt-cache-bytes` / `--prompt-cache-size` if desired.

## MTP draft model does not work yet

`mtp/` was downloaded (829 MB) but **cannot be used with mlx_lm 0.31.1**. Its
`model_type` is `qwen3_5_mtp`; mlx_lm ships `qwen3`, `qwen3_5`, `qwen3_5_moe`,
`qwen3_moe`, `qwen3_next`, `qwen3_vl`, `qwen3_vl_moe` — no MTP module. Passing
`--draft-model` errors. Kept on disk for a future mlx_lm that supports it; it
would help most here, since dense generation is the slow path.

## Pi provider

`mlx-qwen3.8` in `~/.pi/agent/models.json` → `http://127.0.0.1:8081/v1`,
model id is the **absolute path** `<repo>/qwen3.8-mlx/4-bit`
(that is what `/v1/models` reports).

Response field differs from llama.cpp: MLX returns `message.reasoning`, whereas
llama-server returns `message.reasoning_content`.

The stale `mlx-llm-turboquant-server` provider was **removed**. It pointed at
:8080 — llama-server — which answers any model id, so selecting it silently
returned Qwen3.6 output labelled as the old MLX model. Backup of the previous
config: `~/.pi/agent/models.json.bak`.

---

# Shared setup

## Pi integration

Provider lives in `~/.pi/agent/models.json`:

```json
"llama-server": {
  "baseUrl": "http://127.0.0.1:8080/v1",
  "apiKey": "unused",
  "models": [{
    "id": "Qwen3.6-35B-A3B-UD-Q4_K_M.gguf",
    "contextWindow": 131072,
    "maxTokens": 8192,
    "api": "openai-completions"
  }]
}
```

**Keep `contextWindow` in sync with `-c` in serve.sh.** They are independent
settings: `-c` is the real KV allocation, `contextWindow` is what pi believes and
uses to decide when to compact or truncate. If pi's value is lower, it compacts
early and wastes capacity; if higher, requests overflow the server.

Pi reads `models.json` at **startup** — restart the pi session after changing it.

Both local providers live in this one file — see each model section above for
its entry. A backup of the pre-MLX config is at `~/.pi/agent/models.json.bak`.

## Phone access

Requires Tailscale running on the host, plus
[`noahsaso/pi-remote`](https://github.com/noahsaso/pi-remote) — published as
[`@noahsaso/pi-remote`](https://www.npmjs.com/package/@noahsaso/pi-remote) —
registered in pi's `settings.json` under `packages`:

```json
"packages": ["~/path/to/pi-remote/packages/remote"]
```

Then inside a pi session run `/remote`. The **extension** starts the discovery
service and registers the Tailscale route. Do **not** use the `pi-remote` CLI
binary — it serves a session but skips the discovery-service setup.

From the phone (on the same tailnet): `https://<host>.<tailnet>.ts.net/pi/`
(`tailscale serve status` prints the real hostname).

Token auth is enforced; the token is printed with a QR code in the terminal.

Note llama-server binds `127.0.0.1` only. The phone talks to pi-remote, never
directly to the model server — port 8080 is never exposed to the tailnet.

## Gotchas (both models)

**It does not know what it is.** Asked "who are you", it confabulated
"I'm Codex — Google's native coding agent." A local GGUF has no idea what harness
it is running in, and pi does not tell it. Set identity in `~/.pi/agent/AGENTS.md`
or via `--system-prompt` if it matters.

**tmux keys.** pi wants `extended-keys-format csi-u`; the default `xterm`
degrades its TUI. Set on the running server, but add to `~/.tmux.conf` to persist:

```
set -g extended-keys-format csi-u
```
