#!/usr/bin/env bash
# run.sh — run agent-sandbox directly from this repo (no install needed).
#
# Usage:
#   ./run.sh              # interactive: pick stack + harness
#   ./run.sh /path/to/project
#   HARNESS=claude ./run.sh
#
# Requires: podman or docker (same as agent-sandbox itself).
# Skips ./setup.sh entirely — no stow, no PATH changes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/.local/bin/agent-sandbox" "$@"
