# agent-sandbox

Run LLM coding agents (claude, opencode, pi, vibe) in hardened containers.

## Requirements

- **Linux**: podman (rootless, preferred) or docker (daemon)
- **macOS**: Docker Desktop (or podman machine)
- `stow` — symlinks the runner into `~/.local/bin`
- `fzf` — optional, for fuzzy-search prompts

## Installation

```bash
./install.sh
```

This checks for required tools, stows the `agent-sandbox` script into
`~/.local/bin`, and validates your container runtime.

Make sure `~/.local/bin` is in your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
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
| `AGENT_IMAGE` | Stack tag, e.g. `agent-sandbox:python` (skips prompt) |
| `HARNESS` | `claude`, `opencode`, `vibe`, `pi`, `manual` (skips prompt) |
| `CONTAINER_RUNTIME` | `podman` or `docker` (overrides auto-detection) |
| `REBUILD=1` | Rebuild the image chain first |
| `NO_NETWORK=1` | No networking at all |
| `PERSIST_CACHES=1` | Keep tool caches across runs (named volumes) |
| `HARNESS_STATE=0` | Don't share host harness logins/config |
| `MEMORY`, `CPUS` | Resource limits (default 8g / 4) |
| `ENV_KEYS` | Extra env var names to pass into the container |
| `AGENT_SANDBOX_CONFIG` | Alternative config file path |

## Stacks

Auto-discovered from `stacks/*/Containerfile`:

| Stack | Description |
|-------|-------------|
| `base` | Base image with core tooling and harnesses |
| `python` | Python development environment |
| `node` | Node.js development environment |
| `rust` | Rust development environment |
| `elixir` | Elixir development environment |
| `lua-nvim` | Lua + Neovim for dotfiles development |
| `clojure` | JDK 21 + Clojure CLI |
| `web-cljs` | Clojure + pnpm for shadow-cljs |
| `react-native-cljs` | web-cljs + full JDK for Android |

## Harnesses

| Harness | Command |
|---------|---------|
| `claude` | `claude` (Anthropic Claude Code) |
| `opencode` | `opencode` |
| `vibe` | `vibe` (Mistral Vibe) |
| `pi` | `pi` (@earendil-works/pi-coding-agent) |
| `manual` | `/bin/bash` (shell only) |

## How it works

1. **Runtime detection** — podman (rootless) or docker, auto-detected
2. **Stack selection** — fzf fuzzy finder or numbered menu
3. **Image build** — builds the stack chain if needed (cached layers)
4. **Container run** — hardened: read-only, dropped caps, no new privs,
   pids limit, tmpfs for `/tmp` and `/home/agent`

## Security

- Read-only root filesystem
- All capabilities dropped (`--cap-drop=ALL`)
- `no-new-privileges` security option
- PID limit (512)
- SELinux label disable on SELinux-enabled hosts
- API keys passed via `--env-file` (never on command line)

## License

MIT — see [LICENSE](LICENSE)
