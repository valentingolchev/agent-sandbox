#!/usr/bin/env bash
# install.sh — bootstrap mise, then delegate to `mise run install`.
set -euo pipefail

if ! command -v mise >/dev/null 2>&1; then
    echo "Installing mise..."
    curl -fsSL https://mise.run | sh || {
        echo "mise install failed — see https://mise.jdx.dev" >&2
        exit 1
    }
    export PATH="$HOME/.local/bin:$PATH"
fi

exec mise run install "$@"
