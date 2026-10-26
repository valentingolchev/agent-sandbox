# agent-sandbox

Run LLM coding agents (claude, opencode, pi, vibe) in hardened containers.

## Requirements

- **Linux**: podman (rootless, preferred) or docker (daemon)
- **macOS**: Docker Desktop (or podman machine)
- `stow` — symlinks the runner into `~/.local/bin`
- `fzf` — optional, for fuzzy-search prompts

## Installation

### Option A: Install (recommended)

```bash
./install.sh
```

This checks for required tools, symlinks `agent-sandbox` into
`~/.local/bin`, creates a default config at `~/.config/agent-sandbox/config`
from `.config/agent-sandbox/config.template` (with a per-project override
for this repo), and validates your container runtime. The config is a
regular file — edit it freely, it is not managed by the repo.
 
Make sure `~/.local/bin` is in your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Option B: Run from source (no install)

```bash
./run.sh
```

Runs `agent-sandbox` directly from the repo checkout. No stow, no PATH
changes needed. Requires podman or docker (same as the installed version).
All arguments and env vars pass through, e.g.:

```bash
HARNESS=claude ./run.sh ~/projects/my-app
```

## Usage

```bash
# Interactive: pick a stack and harness
agent-sandbox

# Skip prompts with env vars
AGENT_IMAGE=agent-sandbox:python HARNESS=opencode agent-sandbox

# Run in a specific directory
agent-sandbox ~/projects/my-app
```

## Configuration

Edit `~/.config/agent-sandbox/config` for defaults:

```ini
stack = base
harness = manual
memory = 8g
cpus = 4
persist_caches = false
harness_state = true

# Per-project overrides (longest matching path wins)
[~/git/dotfiles]
stack = lua-nvim
```

## Environment variables

| Variable | Description |
|----------|-------------|
| `AGENT_IMAGE` | Stack tag, e.g. `agent-sandbox:python` or `agent-sandbox:python-claude` (skips prompt) |
| `HARNESS` | `claude`, `opencode`, `vibe`, `pi`, `manual` (skips prompt) |
| `CONTAINER_RUNTIME` | `podman` or `docker` (overrides auto-detection) |
| `REBUILD=1` | Rebuild the image chain first |
| `NO_NETWORK=1` | No networking at all |
| `PERSIST_CACHES=1` | Keep tool caches across runs (named volumes) |
| `HARNESS_STATE=1` | Enable harness state snapshot (default: disabled) |
| `HARNESS_STATE_ACTION` | `keep`, `reset`, `discard`, or `prompt` (default: prompt) |
| `SESSION_LOG` | Append session metadata to this file (audit log) |
| `MEMORY`, `CPUS` | Resource limits (default 8g / 4) |
| `ENV_KEYS` | Extra env var names to pass into the container |
| `AGENT_SANDBOX_CONFIG` | Alternative config file path |

## Stacks

Auto-discovered from `stacks/*/Containerfile`. Images are composed ad hoc:
`base-tools` + `<harness>` + `<stack chain>`, tagged as `agent-sandbox:<stack>-<harness>`.
Manual mode (no harness) skips the harness layer: `agent-sandbox:base-tools` for base,
`agent-sandbox:<stack>-manual` for language stacks.

| Stack | Description | Image example |
|-------|-------------|---------------|
| `base` | Core tooling + harness only | `agent-sandbox:base-tools-claude` |
| `python` | Python development environment | `agent-sandbox:python-claude` |
| `node` | Node.js development environment | `agent-sandbox:node-opencode` |
| `rust` | Rust development environment | `agent-sandbox:rust-vibe` |
| `elixir` | Elixir development environment | `agent-sandbox:elixir-claude` |
| `lua-nvim` | Lua + Neovim for dotfiles development | `agent-sandbox:lua-nvim-pi` |
| `clojure` | JDK 21 + Clojure CLI | `agent-sandbox:clojure-claude` |
| `web-cljs` | Clojure + pnpm for shadow-cljs | `agent-sandbox:web-cljs-claude` |
| `react-native-cljs` | web-cljs + full JDK for Android | `agent-sandbox:react-native-cljs-vibe` |

## Harnesses

Harnesses are installed ad hoc — only the selected harness is in the image.
Install scripts are in `base/harness/<name>.sh`.

| Harness | Command | Install script |
|---------|---------|----------------|
| `claude` | `claude` (Anthropic Claude Code) | `base/harness/claude.sh` |
| `opencode` | `opencode` | `base/harness/opencode.sh` |
| `vibe` | `vibe` (Mistral Vibe) | `base/harness/vibe.sh` |
| `pi` | `pi` (@earendil-works/pi-coding-agent) | `base/harness/pi.sh` |
| `manual` | `/bin/bash` (shell only) | — (no harness installed) |

## Harness state (agents, skills, config)

By default, the container starts with a fresh home directory — your host's
harness config (agents, skills, commands, API keys in config) is NOT visible.

Enable **harness state snapshots** to sync your host config into the container:

```bash
# Option 1: env var (one-off)
HARNESS_STATE=1 agent-sandbox

# Option 2: config file (persistent)
# ~/.config/agent-sandbox/config:
harness_state = true
```

What gets synced per harness:

| Harness | Config (synced from host) | State (snapshot, accumulates) |
|---------|---------------------------|-------------------------------|
| `claude` | `~/.claude.json` | `~/.claude/` |
| `opencode` | `~/.config/opencode/opencode.json`, `agents/`, `commands/`, `~/.claude/skills/` | `~/.local/share/opencode/` |
| `vibe` | `~/.vibe/config.json` | `~/.vibe/sessions/` |
| `pi` | `~/.config/pi/settings.json` | `~/.pi/sessions/`, `~/.config/pi/cache/` |

Host config wins on conflict. State dirs accumulate across runs (chat history,
sessions). Host state is never modified.

First run prompts: **[K]eep** (sync configs) / **[R]eset** (fresh from host) /
**[D]iscard** (empty). Set `HARNESS_STATE_ACTION=keep|reset|discard` to skip.

## How it works

1. **Runtime detection** — podman (rootless) or docker, auto-detected
2. **Stack & harness selection** — fzf fuzzy finder or numbered menu
3. **Ad hoc image composition** — generates and builds the image on demand:
   - `base-tools` (core tooling, no harnesses)
   - `base-tools-<harness>` (adds the selected harness)
   - `<stack>-<harness>` (adds language stack on top)
   - Layers are cached — only unique layers are stored
4. **Container run** — hardened: read-only, dropped caps, no new privs,
   pids limit, tmpfs for `/tmp` and `/home/agent`

Images are stored locally on the host (never in git) and tagged as
`agent-sandbox:<stack>-<harness>`. List them with `podman images`.

## Security

- **Ad hoc composition** — only the selected harness is installed (smaller attack surface)
- Read-only root filesystem
- All capabilities dropped (`--cap-drop=ALL`)
- `no-new-privileges` security option
- PID limit (512)
- SELinux label disable on SELinux-enabled hosts
- API keys passed via `--env-file` (never on command line)
- API keys scoped to active harness only
- Harness state snapshot — host state never modified
- Workspace mounted at `/workspace/<name>` — host path hidden
- Package versions pinned in all Containerfiles

## License

MIT — see [LICENSE](LICENSE)
