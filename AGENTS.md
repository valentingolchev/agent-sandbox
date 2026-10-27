# AGENTS.md — Agent Guidelines for agent-sandbox

Guidelines for AI agents (claude, opencode, pi, vibe) working on this repo.

---

## Git Workflow

**🚨 CRITICAL: Only create commits when the user explicitly asks.**

- Stage changes and show the diff when asked
- Wait for explicit instruction before `git commit`
- Never commit proactively
- If unsure, ask: "Should I commit these changes?"

**Push:** Only when explicitly asked. Use `--force-with-lease` for rewritten history.

**🚨 CRITICAL: Before every commit, run `mise run test` (or `./test.sh`) and assess if README.md needs updating.**
- `mise run test` = `mise run lint` + `mise run test-build` (same as CI). Fix failures before committing.
- If the commit changes user-facing behavior (env vars, config keys, stacks,
  harnesses, install steps, security model), update README.md in the same commit.
- Don't commit code changes that make the README stale or fail CI.

---

## Script Architecture

- **Small and focused** — Each script does ONE thing
- **Composable** — Scripts compose to build bigger logic
- **Isolated** — Prefer subprocess calls over sourcing
- **No implicit ordering** — Scripts don't depend on call order
- **Minimal output** — Bare essential messages
- **mise tasks** — Task runner defined in `mise.toml`. Scripts are implementation; mise tasks are the entry point. `./setup.sh` bootstraps mise, then delegates.

### Calling vs Sourcing

| Approach | Use for | Isolation |
|----------|---------|-----------|
| **Call (subprocess)** | Tools, checks, actions | Full — no shared state |
| **Source** | Pure helper libraries (e.g., `common.sh`) | None — shares shell state |

**Rule:** Call scripts as subprocesses. Source only pure function libraries.

### Script Template

```bash
#!/usr/bin/env bash
# Brief description. Usage: script.sh <args>
set -euo pipefail
```

- Always include shebang: `#!/usr/bin/env bash`
- Always use `set -euo pipefail`
- Make executable scripts executable (`chmod +x`)

---

## Security Conventions

**🚨 CRITICAL: Security is not optional. Every change must be reviewed for security impact.**

### Container Security (non-negotiable)

- Read-only root filesystem (`--read-only`)
- All capabilities dropped (`--cap-drop=ALL`)
- `no-new-privileges` security option
- Non-root user (`USER agent` in all Containerfiles)
- PID limit (`--pids-limit 512`)
- Memory/CPU limits (defaults 8g/4)
- tmpfs for `/tmp` and `/home/agent` with size caps
- `--no-hosts`, `--init`, `--rm`, `--pull=never`
- **Never mount the Docker socket** — docker-cli is present but daemonless
- **Never mount host `/`, `/etc`, `/var`** into the container

### Secrets Handling

- **API keys:** Only forward for the active harness (`lib/credentials.sh`)
- **Never put secrets on the command line** — use `--env-file` or `-e KEY` (name only)
- **Keyring temp files:** Set EXIT trap IMMEDIATELY after `mktemp` (before any
  interactive prompts, scans, or operations that could abort the script)
- **Reject multi-line secrets** — they can inject extra lines into `--env-file`
- **Keyring secrets go to `/run/user/<uid>/`** (user-private, not `/tmp`)
- **Session log:** Record metadata only — never env vars, never key values

### Supply Chain

- **Pin ALL versions** in Containerfiles (npm packages, curl downloads, etc.)
- **Never use `latest` or `latest/download` URLs** — pin a release tag
- **Never `curl | sh`** in Containerfiles — download to file first, then execute
- **Base images:** Prefer digest-pinned (`@sha256:...`) over tag-pinned
- **Harness scripts:** Version-pinned with comment to check security advisories
- **mise tools:** Pin versions in `mise.toml` `[tools]`

### Host State Protection

- **Harness state:** Use snapshot approach (`lib/state.sh`) — host state NEVER modified
- **Snapshot sync is one-way:** host → snapshot only, no sync-back
- **Snapshot dir permissions:** `chmod 700` (may contain OAuth tokens)
- **Config file permissions:** `chmod 600` (may contain env_keys, paths)
- **`create_config.sh` never overwrites** existing user config

### Script Security

- **Quote all variables:** `"$var"` — unquoted expansion is a bug
- **No `eval`** — ever
- **Validate user input** against fixed lists (harness names, stack names, etc.)
- **Reject path traversal** — validate paths don't contain `../`
- **`mktemp` for all temp files** — never hardcode `/tmp/foo`
- **Set EXIT trap for temp file cleanup** — immediately after creation
- **`set -euo pipefail`** — always
- **`|| true` on `find` in `$(...)`** — `set -e` kills script on unreadable dirs

### Workspace & Mounts

- **Workspace mounted at `/workspace/<name>`** — host path hidden from CWD
- **Document that `/proc/self/mountinfo` reveals host paths** — path hiding is
  cosmetic, not a security boundary. Don't claim otherwise.
- **Validate workspace name** — no `:` (breaks `-v host:container:rw` parsing)
- **init_script mounted `:ro`** — read-only, runs as agent user

### CI/CD Security

- **Quote all GHA inputs** in composite actions — unquoted `${{ inputs.x }}` is injection
- **Validate inputs** against fixed lists in scripts (harness, stack, runtime)
- **CI permissions:** `contents: read` only
- **No secrets in CI logs** — never echo env vars, keys, or tokens

### Image Names

- **Use `localhost/agent-sandbox:` prefix** — podman short-name resolution
  requires TTY in CI. `IMAGE_PREFIX` in `lib/stacks.sh`.

### Before Committing (Security Checklist)

Ask yourself:
1. Does this change touch secrets, keys, or credentials? → Review carefully
2. Does this change add a download? → Pin version + use HTTPS
3. Does this change add a mount? → Is it necessary? Read-only if possible?
4. Does this change run code inside the container? → Validate inputs first
5. Does this change modify host state? → It should NEVER write to host
6. Does this change add a new Containerfile layer? → `chown -R agent:agent /home/agent`
   if the install creates files in `$HOME`
7. Does this change add a config key? → Add to `lib/config.sh` whitelist AND
   `lib/validate.sh` VALID_KEYS

---

## Code Style

- Use `[[ ]]` for conditionals
- Use `local` for function variables
- Quote variables: `"$var"`
- Functions: `snake_case`, Variables: `UPPER_CASE` for globals

---

## Documentation (README.md)

- **Terse.** Bare essentials. No filler, no repetition, no marketing language.
- **Technical terms exact.** Use real names: `HARNESS_STATE`, `base-tools`, `agent-sandbox:python-claude`.
- **Tables over prose** for reference data (env vars, stacks, harnesses).
- **Code blocks** for commands and config examples.
- **Keep in sync.** Every user-facing change must update README in the same commit.
- **Assess before finishing a task:** "Does this change affect what a user sees or does?"
  If yes, update README before declaring done.

---

## Quick Reference

| Task | Command |
|------|---------|
| List all tasks | `mise tasks` |
| Set up | `mise run setup` (or `./setup.sh` to bootstrap mise) |
| Run agent | `agent-sandbox` |
| Run from source | `mise run start` (or `./scripts/run.sh`) |
| **Run all checks** | **`mise run test`** (config + lint + build) |
| Validate config | `mise run check` (or `agent-sandbox --check`) |
| Lint only | `mise run lint` (or `./scripts/lint.sh`) |
| Build tests only | `mise run test-build` (or `./scripts/test-build.sh`) |
| Build base-tools | `mise run build` |
| Clean images | `mise run clean` |
| Force rebuild | `REBUILD=1 agent-sandbox` |
| No network | `NO_NETWORK=1 agent-sandbox` |
| Specific harness | `HARNESS=claude agent-sandbox` |
| Enable state | `HARNESS_STATE=1 agent-sandbox` |
| Audit log | `SESSION_LOG=~/audit.log agent-sandbox` |

See [PLAN.md](PLAN.md) for the feature roadmap.
