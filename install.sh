#!/usr/bin/env bash
# Install agent-sandbox on the host.
# Each step runs as an isolated subprocess — no shared state, no ordering deps.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="$ROOT/lib/host"

# Check tools; capture missing list from stdout
if ! missing="$("$HOST/check_tools.sh")"; then
    "$HOST/show_install_help.sh" $missing
    exit 1
fi

"$HOST/stow.sh" "$ROOT"
"$HOST/check_path.sh" || true
"$HOST/check_runtime.sh" || true
"$HOST/check_repo.sh" "$ROOT"

echo "Done."
