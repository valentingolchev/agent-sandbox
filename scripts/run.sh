#!/usr/bin/env bash
# run.sh — run agent-sandbox directly from this repo (no install needed).
#
# Usage:
#   ./scripts/run.sh              # interactive: pick stack + harness
#   ./scripts/run.sh /path/to/project
#   HARNESS=claude ./scripts/run.sh
#
# Requires: podman or docker (same as agent-sandbox itself).
# Skips ./setup.sh entirely — no stow, no PATH changes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT/.local/bin/agent-sandbox" "$@"
