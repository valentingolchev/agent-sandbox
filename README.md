# agent-sandbox

Run LLM coding agents (claude, opencode, pi, vibe) in hardened containers.

## Requirements

- Linux: podman (rootless, preferred) or docker
- macOS: Docker Desktop or podman machine
- `stow` (install only), `fzf` (optional, fuzzy prompts)

## Install

```bash
./setup.sh            # bootstraps mise, then: stow + config + checks
./run.sh              # or run from source, no install
```

System tools: `stow` + `podman`/`docker` (package manager — see `mise.toml` comments).
Dev tools: `shellcheck`, `fzf` — auto-installed by `mise install` (run once after clone, or `./setup.sh` does it).

Config: `~/.config/agent-sandbox/config` (regular file, created from
`.config/agent-sandbox/config.template` — never overwritten on reinstall).

## Usage

```bash
agent-sandbox                          # interactive: pick stack + harness
AGENT_IMAGE=agent-sandbox:python HARNESS=opencode agent-sandbox
agent-sandbox ~/projects/my-app        # specific workspace
HARNESS_STATE=1 agent-sandbox          # sync host agents/skills/config
REBUILD=1 agent-sandbox                # rebuild images
```

## Configuration

INI format. Globals + `[path]` sections (longest prefix wins, `~` = `$HOME`).
Created by install with a section for the agent-sandbox repo itself.

```ini
stack = base
harness = manual
memory = 8g
cpus = 4
persist_caches = false
harness_state = false
harness_state_action = prompt
# init_script = ~/path/to/init.sh   # runs inside container before harness

[/path/to/agent-sandbox]
stack = base
harness = opencode
init_script = /path/to/agent-sandbox/init.sh   # mise install on container start
```

## Environment variables

| Variable | Description |
|----------|-------------|
| `AGENT_IMAGE` | Stack tag, e.g. `agent-sandbox:python-claude` (skips prompt) |
| `HARNESS` | `claude`, `opencode`, `vibe`, `pi`, `manual` (skips prompt) |
| `CONTAINER_RUNTIME` | `podman` or `docker` (overrides auto-detection) |
| `REBUILD=1` | Rebuild images (busts cache) |
| `NO_NETWORK=1` | No networking |
| `PERSIST_CACHES=1` | Keep tool caches across runs (named volumes) |
| `HARNESS_STATE=1` | Sync host agents/skills/config into container |
| `HARNESS_STATE_ACTION` | `keep`, `reset`, `discard`, `prompt` (default: prompt) |
| `SESSION_LOG` | Audit log file path |
| `MEMORY`, `CPUS` | Resource limits (default 8g / 4) |
| `ENV_KEYS` | Extra env vars to forward (space-separated) |
| `AGENT_SANDBOX_CONFIG` | Alternative config file path |

## Stacks

Auto-discovered from `stacks/*/Containerfile`. Images composed ad hoc:
`base-tools` → `base-tools-<harness>` → `<stack>-<harness>`.
Manual mode (no harness): `agent-sandbox:base-tools`, `agent-sandbox:<stack>-manual`.

| Stack | Description |
|-------|-------------|
| `base` | Core tooling, no language stack |
| `python` | Python development |
| `node` | Node.js + pnpm |
| `rust` | Rust (rustup, system-wide) |
| `elixir` | Erlang/Elixir + Phoenix deps |
| `lua-nvim` | Lua + Neovim for dotfiles |
| `clojure` | JDK 21 + Clojure CLI |
| `web-cljs` | Clojure + pnpm for shadow-cljs |
| `react-native-cljs` | web-cljs + full JDK for Android |

## Harnesses

Installed ad hoc via `base/harness/<name>.sh`. Only the selected harness is in the image.

| Harness | Command | State synced (with `HARNESS_STATE=1`) |
|---------|---------|--------------------------------------|
| `claude` | `claude` | config: `~/.claude.json`; state: `~/.claude/` |
| `opencode` | `opencode` | config: `~/.config/opencode/{opencode.json,agents,commands}`, `~/.claude/skills/`; state: `~/.local/share/opencode/` |
| `vibe` | `vibe` | config: `~/.vibe/config.json`; state: `~/.vibe/sessions/` |
| `pi` | `pi` | config: `~/.config/pi/settings.json`; state: `~/.pi/sessions/`, `~/.config/pi/cache/` |
| `manual` | `/bin/bash` | — (no harness, fresh home) |

Host config wins on conflict. State accumulates across runs. Host state is never
modified. Snapshots: `~/.local/share/agent-sandbox/state/<harness>/`.
First run prompts `[K]eep/[R]eset/[D]iscard`; set `HARNESS_STATE_ACTION` to skip.

## Security

- Only the selected harness is installed (smaller attack surface)
- Read-only root, all caps dropped, `no-new-privileges`, pids limit 512
- SELinux label disabled on SELinux hosts
- API keys via `--env-file`, scoped to active harness only
- Harness state: host never modified (snapshot copy-on-write)
- Workspace mounted at `/workspace/<name>` (host path hidden)
- Package versions pinned in all Containerfiles

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `EACCES` in `~/.local/share/<harness>/` | `REBUILD=1` — old images had root-owned dirs |
| Harness missing agents/skills | `HARNESS_STATE=1` |
| `stow` fails: target exists | Remove `~/.local/bin/agent-sandbox`, re-run `./setup.sh` |
| Images stale after repo move | `REBUILD=1 ./run.sh` |

## Development

Uses [mise](https://mise.jdx.dev) as task runner. `./setup.sh` bootstraps mise automatically.

```bash
mise tasks                  # list all tasks
mise run setup              # set up (stow + config + checks)
mise run test               # run all checks (lint + build tests)
mise run lint               # shellcheck + bash syntax only
mise run test-build         # build tests only
mise run start              # run agent-sandbox from source
mise run build              # build base-tools image
mise run clean              # remove all agent-sandbox images

# Entry points (scripts/ has the rest):
./setup.sh                  # bootstrap mise + setup
./scripts/run.sh            # run from source (no mise needed)
./scripts/test.sh           # all checks (no mise needed)
./scripts/lint.sh           # lint only (no mise needed)
```

See [AGENTS.md](AGENTS.md) for contributor guidelines.

**Add a stack**: create `stacks/<name>/Containerfile` with `ARG BASE_IMAGE` +
`FROM ${BASE_IMAGE}`. Add `RUN chown -R agent:agent /home/agent` if the install
creates files in `$HOME`.

**Add a harness**: create `base/harness/<name>.sh` (pinned versions). Register in
`lib/prompts.sh` (`HARNESSES`), `lib/credentials.sh` (API keys), `lib/state.sh` (state mapping).

## Roadmap

See [PLAN.md](PLAN.md) for full details.

| # | Feature | Priority |
|---|---------|----------|
| 1 | ~~Mise tasks~~ | ✅ |
| 2 | ~~Docker CI matrix~~ | ✅ |
| 3 | Chezmoi support (alternative to Stow) | P2 |
| 4 | Config validation (`--check`) | P2 |
| 5 | New stacks: Go, Zig | P2 |
| 6 | TUI UX improvements | P2 |
| 7 | Windows host support (WSL2 / native) | P2 |
| 8 | Other ideas (aider, macOS CI, completions, more) | P3 |

## License

MIT — see [LICENSE](LICENSE)
