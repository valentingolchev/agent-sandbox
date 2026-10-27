# PLAN — Feature roadmap

Future improvements, ordered by priority. Not scheduled — pick when relevant.

---

## 1. Mise tasks for scripting (P1)

**Goal:** Replace ad-hoc bash script invocations with `mise` tasks. Bash only for bootstrapping mise itself.

**Why:**
- Consistent task runner across the project (`mise run <task>`)
- mise already in base image — no new dependency
- Task dependencies, env vars, and descriptions in one place (`mise.toml`)
- Easier to discover (`mise tasks` lists everything)

**Changes:**
- Add `mise.toml` at repo root with tasks:
  - `install` → `./install.sh`
  - `test` → `./test.sh "$@"`
  - `run` → `./run.sh "$@"`
  - `lint` → shellcheck + bash -n
  - `build` → build base-tools image
  - `clean` → remove all agent-sandbox images
- Keep `install.sh`, `test.sh`, `run.sh` as thin wrappers (mise tasks call them)
- Bootstrap: `install.sh` checks for mise, installs if missing (curl script), then delegates

**Files:**
- New: `mise.toml`
- Modify: `install.sh` (mise bootstrap), `README.md`, `AGENTS.md`

---

## 2. Chezmoi support (P2)

**Goal:** Allow Chezmoi as an alternative to Stow for symlinking the runner into `~/.local/bin`.

**Why:**
- Some users prefer Chezmoi over Stow (templates, secrets management, cross-machine sync)
- Stow is a hard dependency for install — Chezmoi users shouldn't need both

**Changes:**
- `lib/host/stow.sh` → detect chezmoi (`command -v chezmoi`):
  - If chezmoi: use `chezmoi add` / `chezmoi apply` instead of `stow`
  - If stow: current behavior
  - If neither: error with install instructions for both
- Add `chezmoi` to `check_tools.sh` as optional (not required)
- Chezmoi source dir convention: `~/.local/share/chezmoi` — document how to add agent-sandbox
- Config creation (`create_config.sh`) stays the same (not symlinked)

**Files:**
- Modify: `lib/host/stow.sh` (rename to `link.sh`?), `lib/host/check_tools.sh`, `install.sh`
- Modify: `README.md` (Chezmoi install option)
- Modify: `.config/agent-sandbox/config.template` (comment about chezmoi)

---

## 3. TUI UX improvements (P2)

**Goal:** Better interactive experience when picking stack/harness and managing state.

**Why:**
- Current: fzf or numbered menu — functional but bare
- Users spend time in the picker — worth investing in UX

**Ideas (pick subset):**

| Feature | Description |
|---------|-------------|
| Stack/harness preview | Show stack description + last-used time in fzf preview pane |
| Image status | Show which images are built, size, age in picker |
| Recent runs | `agent-sandbox --recent` — list recent workspaces, re-enter with one key |
| State management | `agent-sandbox --state` — list/reset/delete harness state snapshots |
| Interactive rebuild | `agent-sandbox --rebuild` — pick which images to rebuild |
| Better fallback | Colored numbered menu when fzf/TTY unavailable (currently plain text) |
| Progress indicators | Spinner for image builds (currently just text output) |

**Changes:**
- `lib/prompts.sh`: fzf preview pane with stack/harness metadata
- New: `lib/recent.sh` — track recent workspaces in `~/.local/state/agent-sandbox/recent`
- New: `lib/state_ui.sh` — interactive state management (list/reset/delete)
- `.local/bin/agent-sandbox`: add `--recent`, `--state`, `--rebuild` flags

**Files:**
- Modify: `lib/prompts.sh`, `.local/bin/agent-sandbox`
- New: `lib/recent.sh`, `lib/state_ui.sh`
- Modify: `README.md`, `AGENTS.md`

---

## 4. Windows host support (P2)

**Goal:** Run agent-sandbox on Windows hosts (WSL2 or native with Docker Desktop).

**Why:**
- Many developers use Windows as primary OS
- WSL2 provides a Linux environment — most things work, but path/shell differences need handling
- Native Windows (Git Bash/MSYS2) is harder but possible with Docker Desktop

**Changes:**

| Area | Current | Windows approach |
|------|---------|------------------|
| Shell | bash (Linux/macOS) | WSL2: bash works. Native: Git Bash or MSYS2 |
| Container runtime | podman (rootless) / docker | WSL2: podman in WSL. Native: Docker Desktop |
| Paths | Unix (`/home/user`) | WSL2: translate with `wslpath`. Native: `cygpath` |
| Symlinking | stow / chezmoi | Chezmoi (works on Windows). Stow does not |
| Home dir | `$HOME` | `%USERPROFILE%` — use `$HOME` in WSL2, `cygpath` in Git Bash |
| mise | Linux binary | Windows binary available — bootstrap per-OS |
| Tmpfs mounts | Linux tmpfs | Docker Desktop handles this transparently |
| SELinux | Fedora hosts | N/A on Windows |

**WSL2 approach (recommended):**
- User installs WSL2 + podman inside WSL2
- `agent-sandbox` runs inside WSL2 (bash works natively)
- Workspace: access Windows files via `/mnt/c/...` or keep projects in WSL2
- `install.sh` detects WSL2 (`/proc/version` contains `microsoft`)

**Native Windows approach (harder):**
- Git Bash or MSYS2 for shell
- Docker Desktop for containers
- `cygpath` for path translation
- Chezmoi for symlinking (no Stow)
- mise for Windows

**Files:**
- Modify: `lib/runtime.sh` (detect WSL2, Docker Desktop)
- Modify: `lib/host/check_tools.sh` (Windows tool checks)
- Modify: `lib/host/stow.sh` → `link.sh` (Chezmoi on Windows)
- Modify: `install.sh` (WSL2 vs native detection)
- Modify: `.local/bin/agent-sandbox` (path translation)
- New: `lib/host/wsl.sh` (WSL2 helpers: `wslpath`, drive detection)
- Modify: `README.md` (Windows install instructions)

---

## 5. Other ideas (P3, unscheduled)

- **Docker support testing** — CI only tests podman; add docker matrix
- **macOS CI** — test on macOS runner (podman machine or docker)
- **Image pruning** — `agent-sandbox --prune` to remove stale images
- **Config validation** — `agent-sandbox --check` to validate config file
- **Shell completions** — bash/zsh/fish completions for `agent-sandbox`
- **Harness: aider** — add aider as a harness option
- **Stack: go** — Go development stack
- **Stack: zig** — Zig development stack
