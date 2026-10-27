#!/usr/bin/env bash
# install.sh — bootstrap mise, then delegate to `mise run install`.
#
# This is the only script that runs without mise. It installs mise if
# missing, then hands off to the mise task runner (mise.toml).
set -euo pipefail

# Install mise if not present
if ! command -v mise >/dev/null 2>&1; then
    echo "mise not found — installing..."
    curl -fsSL https://mise.run | sh
    export PATH="$HOME/.local/bin:$PATH"
    echo "mise installed to $HOME/.local/bin/mise"
    echo
fi

# Delegate to mise task runner
exec mise run install "$@"
