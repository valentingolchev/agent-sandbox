# PLAN — Feature roadmap

Future improvements, ordered by priority. Not scheduled — pick when relevant.

| # | Feature | Priority | Section |
|---|---------|----------|---------|
| 1 | Mise tasks for scripting | P1 | [#1](#1-mise-tasks-for-scripting-p1) |
| 2 | Docker testing in CI | **P1** | [#2](#2-docker-testing-in-ci-p1) |
| 3 | Chezmoi support | P2 | [#3](#3-chezmoi-support-p2) |
| 4 | Config validation | P2 | [#4](#4-config-validation-p2) |
| 5 | New stacks: Go, Zig | P2 | [#5](#5-new-stacks-go-zig-p2) |
| 6 | TUI UX improvements | P2 | [#6](#6-tui-ux-improvements-p2) |
| 7 | Windows host support | P2 | [#7](#7-windows-host-support-p2) |
| 8 | Other ideas | P3 | [#8](#8-other-ideas-p3-unscheduled) |

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

## 2. Docker testing in CI (P1)

**Goal:** Test with Docker in addition to Podman in CI.

**Why:**
- CI only tests podman — Docker users may hit different bugs
- Docker is the default on macOS and many Linux setups
- Catch runtime-specific issues (userns, SELinux, mounts)
- **Top priority: CI failures are blockers — need Docker coverage ASAP**

**Changes:**
- Add `CONTAINER_RUNTIME` matrix to CI workflow:
  ```yaml
  strategy:
    matrix:
      runtime: [podman, docker]
  ```
- Docker requires `sudo` on GitHub runners — use `docker` service or `sudo docker`
- `test.sh`: accept `--runtime docker` flag, pass through to builds
- `lib/runtime.sh`: ensure `user_args()` and `security_opts()` work for both
- Document any Docker-specific quirks in README

**Files:**
- Modify: `.github/workflows/ci.yml` (matrix), `test.sh` (--runtime flag)
- Modify: `README.md` (Docker notes)

---

## 3. Chezmoi support (P2)

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

## 4. Config validation (P2)

**Goal:** Add `agent-sandbox --check` to validate the config file before running.

**Why:**
- Config errors (typos in keys, invalid values, bad paths) only surface at runtime
- Catching them early saves debugging time
- Useful in CI or pre-commit hooks

**Changes:**
- New flag: `agent-sandbox --check` (or `--validate`)
- Validates:
  - Config file syntax (INI parse errors)
  - Known keys only (`stack`, `harness`, `memory`, `cpus`, etc.)
  - Stack names exist in `STACKS`
  - Harness names are valid
  - Memory/CPU values are parseable
  - `[path]` sections have valid paths (expand `~`, check existence)
  - `harness_state_action` is one of `keep|reset|discard|prompt`
- Exit 0 if valid, exit 1 with error messages if not
- Integrate into `install.sh` as a final step (warn if config invalid)

**Files:**
- New: `lib/validate.sh` — config validation logic
- Modify: `.local/bin/agent-sandbox` (add `--check` flag)
- Modify: `install.sh` (run validation after config creation)
- Modify: `README.md`, `AGENTS.md`

---

## 5. New stacks: Go, Zig (P2)

**Goal:** Add Go and Zig development stacks.

**Why:**
- Go is widely used for CLI tools, servers, and infrastructure
- Zig is growing for systems programming, WebAssembly
- Both are simple to add (single package or installer)

**Changes:**

### Go stack (`stacks/go/Containerfile`)
```dockerfile
ARG BASE_IMAGE=agent-sandbox:base-tools
FROM ${BASE_IMAGE}
USER root
RUN microdnf --setopt=install_weak_deps=False --setopt=tsflags=nodocs install -y \
        golang && \
    microdnf clean all
ENV GOPATH=/home/agent/go \
    PATH=/home/agent/go/bin:$PATH
USER agent
```
- Installs Go from Fedora repos (version may lag — pin if needed)
- `GOPATH` in `/home/agent/go` (covered by `PERSIST_CACHES` volume)
- `gopls` (LSP) installed via `go install` at runtime or in image

### Zig stack (`stacks/zig/Containerfile`)
```dockerfile
ARG BASE_IMAGE=agent-sandbox:base-tools
FROM ${BASE_IMAGE}
USER root
RUN curl -sSL https://ziglang.org/download/index.json | \
        jq -r '.master.version' | xargs -I {} \
        curl -sSL https://ziglang.org/download/{}/zig-linux-x86_64-{}.tar.xz | \
        tar -xJ -C /opt && \
    ln -s /opt/zig-linux-x86_64-*/zig /usr/local/bin/zig
USER agent
```
- Zig has no Fedora package — install from upstream tarball
- Pin version (check ziglang.org/download)
- Alternatively: use `mise use zig` at runtime

**Files:**
- New: `stacks/go/Containerfile`, `stacks/zig/Containerfile`
- Modify: `README.md` (add to stacks table)
- Modify: `test.sh` (add go/zig to build tests, or separate optional test)

---

## 6. TUI UX improvements (P2)

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
| Image pruning | `agent-sandbox --prune` — remove stale/unused images interactively |
| Better fallback | Colored numbered menu when fzf/TTY unavailable (currently plain text) |
| Progress indicators | Spinner for image builds (currently just text output) |

**Changes:**
- `lib/prompts.sh`: fzf preview pane with stack/harness metadata
- New: `lib/recent.sh` — track recent workspaces in `~/.local/state/agent-sandbox/recent`
- New: `lib/state_ui.sh` — interactive state management (list/reset/delete)
- New: `lib/prune.sh` — interactive image pruning (list by age/size, select to remove)
- `.local/bin/agent-sandbox`: add `--recent`, `--state`, `--rebuild`, `--prune` flags

**Files:**
- Modify: `lib/prompts.sh`, `.local/bin/agent-sandbox`
- New: `lib/recent.sh`, `lib/state_ui.sh`, `lib/prune.sh`
- Modify: `README.md`, `AGENTS.md`

---

## 7. Windows host support (P2)

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

## 8. Other ideas (P3, unscheduled)

### Harness: aider

**Goal:** Add [aider](https://aider.chat/) as a supported harness.

**Why:**
- Aider is a popular AI pair-programming tool — works directly in the terminal
- Strong at editing files in-place, git integration, multi-file edits
- Different model: uses its own config (`~/.aider.conf.yml`), supports many LLM providers
- Complements existing harnesses (claude, opencode, vibe, pi) — some users prefer aider's edit-focused workflow

**Changes:**
- New: `base/harness/aider.sh`:
  ```dockerfile
  # shellcheck shell=bash
  # Aider harness (https://aider.chat/).
  # Python-based, installed with uv system-wide.
  # Version pinned: X.Y.Z (update deliberately, check security advisories)
  RUN mkdir -p /opt/uv-home && \
      HOME=/opt/uv-home uv tool install aider-chat==X.Y.Z && \
      rm -rf /opt/uv-home/.cache
  ```
- Add `aider` to `HARNESSES` in `lib/prompts.sh`
- Add API key mappings in `lib/credentials.sh`:
  - `HARNESS_ENV_KEYS[aider]` — aider supports many providers (OpenAI, Anthropic, Gemini, etc.)
  - Forward all common keys (like opencode/pi do)
  - `HARNESS_KEYRING[aider]` — optional keyring entry
- Add state mappings in `lib/state.sh`:
  - `HARNESS_CONFIG[aider]` — `~/.aider.conf.yml` (config file, synced from host)
  - `HARNESS_STATE_DIRS[aider]` — `~/.aider` (chat history, cache — snapshot only)
- Aider config can also use `.aider.conf.yml` in the workspace — document this
- Test: `aider --version` in built image

**Files:**
- New: `base/harness/aider.sh`
- Modify: `lib/prompts.sh`, `lib/credentials.sh`, `lib/state.sh`
- Modify: `README.md` (harness table), `test.sh` (optional aider build test)

### Other ideas

- **macOS CI** — test on macOS runner (podman machine or docker)
- **Shell completions** — bash/zsh/fish completions for `agent-sandbox`
- **Stack: haskell** — GHC + cabal/stack
- **Stack: nix** — Nix package manager + nix-shell
- **Stack: java** — JDK + Maven/Gradle (for non-Clojure JVM work)
- **Harness: cline** — add Cline (VS Code extension, CLI mode) as a harness
- **Harness: gemini-cli** — add Google Gemini CLI as a harness
