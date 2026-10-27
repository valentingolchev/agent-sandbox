# agent-sandbox

Run LLM coding agents (claude, opencode, pi, vibe) in hardened containers.

## Requirements

- **Linux**: podman (rootless, preferred) or docker (daemon)
- **macOS**: Docker Desktop (or podman machine)
- `stow` — only needed for Option A (install); symlinks the runner into `~/.local/bin`
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
agent-sandbox                    # installed
./run.sh                         # from repo, no install

# Skip prompts with env vars
AGENT_IMAGE=agent-sandbox:python HARNESS=opencode agent-sandbox

# Run in a specific directory
agent-sandbox ~/projects/my-app
./run.sh ~/projects/my-app

# Enable harness state (agents, skills, config from host)
HARNESS_STATE=1 agent-sandbox

# Rebuild images from scratch
REBUILD=1 agent-sandbox
```

## Configuration

The config file is created by `install.sh` from `.config/agent-sandbox/config.template`
and is a regular file — edit it freely. It is never overwritten by reinstalling.

Location: `~/.config/agent-sandbox/config` (override with `AGENT_SANDBOX_CONFIG`)

```ini
# Global defaults
stack = base
harness = manual
memory = 8g
cpus = 4
no_network = false
persist_caches = false
harness_state = false
harness_state_action = prompt
env_keys =

# Per-project overrides (longest matching path wins; ~ expands to $HOME)
# The install script adds a section for the agent-sandbox repo itself:
[/path/to/agent-sandbox]
stack = base
harness = opencode

# Your own projects:
# [~/git/my-project]
# stack = python
# harness = claude
# harness_state = true
```

## Environment variables

| Variable | Description |
|----------|-------------|
| `AGENT_IMAGE` | Stack tag, e.g. `agent-sandbox:python` or `agent-sandbox:python-claude` (skips prompt) |
| `HARNESS` | `claude`, `opencode`, `vibe`, `pi`, `manual` (skips prompt) |
| `CONTAINER_RUNTIME` | `podman` or `docker` (overrides auto-detection) |
| `REBUILD=1` | Rebuild the image chain first (busts cache) |
| `NO_NETWORK=1` | No networking at all (breaks AI API calls) |
| `PERSIST_CACHES=1` | Keep tool caches across runs (named volumes) |
| `HARNESS_STATE=1` | Enable harness state snapshot — syncs host agents/skills/config (default: disabled) |
| `HARNESS_STATE_ACTION` | `keep`, `reset`, `discard`, or `prompt` (default: prompt) |
| `SESSION_LOG` | Append session metadata to this file (audit log) |
| `MEMORY`, `CPUS` | Resource limits (default 8g / 4) |
| `ENV_KEYS` | Extra env var names to pass into the container (space-separated) |
| `AGENT_SANDBOX_CONFIG` | Alternative config file path |

## Stacks

Auto-discovered from `stacks/*/Containerfile`. Images are composed ad hoc:
`base-tools` + `<harness>` + `<stack chain>`, tagged as `agent-sandbox:<stack>-<harness>`.
Manual mode (no harness) skips the harness layer: `agent-sandbox:base-tools` for base,
`agent-sandbox:<stack>-manual` for language stacks.

| Stack | Description | Image (with harness) | Image (manual) |
|-------|-------------|----------------------|----------------|
| `base` | Core tooling, no language stack | `agent-sandbox:base-tools-claude` | `agent-sandbox:base-tools` |
| `python` | Python development environment | `agent-sandbox:python-claude` | `agent-sandbox:python-manual` |
| `node` | Node.js development environment | `agent-sandbox:node-opencode` | `agent-sandbox:node-manual` |
| `rust` | Rust development environment | `agent-sandbox:rust-vibe` | `agent-sandbox:rust-manual` |
| `elixir` | Elixir development environment | `agent-sandbox:elixir-claude` | `agent-sandbox:elixir-manual` |
| `lua-nvim` | Lua + Neovim for dotfiles development | `agent-sandbox:lua-nvim-pi` | `agent-sandbox:lua-nvim-manual` |
| `clojure` | JDK 21 + Clojure CLI | `agent-sandbox:clojure-claude` | `agent-sandbox:clojure-manual` |
| `web-cljs` | Clojure + pnpm for shadow-cljs | `agent-sandbox:web-cljs-claude` | `agent-sandbox:web-cljs-manual` |
| `react-native-cljs` | web-cljs + full JDK for Android | `agent-sandbox:react-native-cljs-vibe` | `agent-sandbox:react-native-cljs-manual` |

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

Note: opencode syncs `~/.claude/skills/` because opencode configs often reference
skill files via `instructions` (e.g. `~/.claude/skills/caveman/SKILL.md`).

First run prompts: **[K]eep** (sync configs) / **[R]eset** (fresh from host) /
**[D]iscard** (empty). Set `HARNESS_STATE_ACTION=keep|reset|discard` to skip.

Snapshots live at `~/.local/share/agent-sandbox/state/<harness>/`. Delete a
harness's snapshot dir to reset its state.

## How it works

1. **Runtime detection** — podman (rootless) or docker, auto-detected
2. **Config load** — reads `~/.config/agent-sandbox/config` for defaults and
   per-project overrides (longest matching path wins)
3. **Stack & harness selection** — fzf fuzzy finder or numbered menu
   (env vars `AGENT_IMAGE` / `HARNESS` skip prompts)
4. **Ad hoc image composition** — generates and builds the image on demand:
   - `base-tools` (core tooling, no harnesses)
   - `base-tools-<harness>` (adds the selected harness via `base/harness/<name>.sh`)
   - `<stack>-<harness>` (adds language stack on top via `stacks/<name>/Containerfile`)
   - Layers are cached — only unique layers are stored
5. **Harness state** (optional, `HARNESS_STATE=1`) — syncs host config/agents/skills
   into a snapshot, mounts it into the container
6. **Container run** — hardened: read-only, dropped caps, no new privs,
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

## Development

```bash
# Run from source (no install)
./run.sh

# Syntax-check all shell scripts
find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 -I {} bash -n {}
bash -n .local/bin/agent-sandbox
bash -n install.sh
bash -n run.sh

# Build and test images locally
REBUILD=1 ./run.sh

# List built images
podman images agent-sandbox

# Clean up images
podman rmi -f $(podman images -q agent-sandbox)
```

See [AGENTS.md](AGENTS.md) for contributor guidelines (git workflow, script
architecture, security conventions, code style).

### Adding a stack

1. Create `stacks/<name>/Containerfile`:
   ```dockerfile
   ARG BASE_IMAGE=agent-sandbox:base-tools
   FROM ${BASE_IMAGE}
   USER root
   RUN ...
   RUN chown -R agent:agent /home/agent   # if install creates files in $HOME
   USER agent
   ```
2. For a child stack (e.g. `web-cljs` on top of `clojure`), set the default
   `ARG BASE_IMAGE=agent-sandbox:<parent>-<harness>` — the build system
   always overrides this with `--build-arg`.

### Adding a harness

1. Create `base/harness/<name>.sh` with `RUN` commands to install the harness
   (versions pinned, check security advisories).
2. Add the harness name to `HARNESSES` in `lib/prompts.sh`.
3. Add API key mappings in `lib/credentials.sh` (`HARNESS_ENV_KEYS`, `HARNESS_KEYRING`).
4. Add state mappings in `lib/state.sh` (`HARNESS_CONFIG`, `HARNESS_STATE_DIRS`).

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `EACCES` writing to `~/.local/share/<harness>/` | Rebuild with `REBUILD=1` — old images had root-owned dirs in `/home/agent` |
| Harness can't see host agents/skills/config | Set `HARNESS_STATE=1` (see [Harness state](#harness-state-agents-skills-config)) |
| `Permission denied` on bind mounts (SELinux) | Already handled — `--security-opt label=disable` is added automatically on SELinux hosts |
| `stow` fails: target already exists | Remove the conflicting file/symlink at `~/.local/bin/agent-sandbox` and re-run `./install.sh` |
| Images not found after repo move | Run `REBUILD=1 ./run.sh` to rebuild with correct paths |
| `podman machine not running` (macOS) | `podman machine start` |
| Docker daemon not running | `sudo systemctl start docker` (Linux) or start Docker Desktop (macOS) |

## License

MIT — see [LICENSE](LICENSE)
