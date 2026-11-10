# base/tools/

Repo-provided tool install scripts, layered onto a sandbox image at build
time. Each `<name>.sh` here becomes a selectable extra tool (the
`extra_tools` config key or `EXTRA_TOOLS` env var, space-separated names).

## Rules

- `#!/usr/bin/env bash` shebang and `set -euo pipefail` at the top
- Pin all versions — no `latest`, no unpinned downloads
- Never `curl | sh` — download to a file, then execute (lint rejects
  pipe-to-shell patterns)
- No secrets in scripts; no host state access
- Scripts run as root at build time only; the image drops to `USER agent`
  afterwards
- Scripts are copied to `/opt/agent-sandbox/extra-tools/` in the image and
  executed with `bash -euo pipefail` during the build — a failing script
  fails the build

## Rebuild behavior

The tools layer image tag carries a content hash
(`<final>-tools-<hash>`): changing a script or the selection rebuilds that
layer. `REBUILD=1` forces a full rebuild.

Security: scripts come from this repo only, tool names are validated
against this directory, and nothing is fetched at container runtime.
