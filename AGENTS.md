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

---

## Script Architecture

- **Small and focused** — Each script does ONE thing
- **Composable** — Scripts compose to build bigger logic
- **Isolated** — Prefer subprocess calls over sourcing
- **No implicit ordering** — Scripts don't depend on call order
- **Minimal output** — Bare essential messages

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

- **API keys:** Only forward for the active harness
- **Harness state:** Use snapshot approach (`lib/state.sh`) — host state never modified
- **Package versions:** Pin all versions in Containerfiles
- **Container:** Read-only root, drop all caps, no new privs, non-root user
- **Workspace:** Mounted at `/workspace/<name>` — host path hidden from agent

---

## Code Style

- Use `[[ ]]` for conditionals
- Use `local` for function variables
- Quote variables: `"$var"`
- Functions: `snake_case`, Variables: `UPPER_CASE` for globals

---

## Quick Reference

| Task | Command |
|------|---------|
| Run installer | `./install.sh` |
| Run agent | `agent-sandbox` |
| Force rebuild | `REBUILD=1 agent-sandbox` |
| No network | `NO_NETWORK=1 agent-sandbox` |
| Specific harness | `HARNESS=claude agent-sandbox` |
| Enable state | `HARNESS_STATE=1 agent-sandbox` |
| Audit log | `SESSION_LOG=~/audit.log agent-sandbox` |
