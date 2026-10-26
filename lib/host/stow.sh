#!/usr/bin/env bash
# Stow agent-sandbox into ~/.local. Usage: stow.sh <repo-root>
set -euo pipefail

root="${1:?Usage: stow.sh <repo-root>}"

mkdir -p "$HOME/.local/bin" "$HOME/.config/agent-sandbox"

link="$HOME/.local/bin/agent-sandbox"
if [ -L "$link" ]; then
    [ "$(readlink "$link")" = "$root/.local/bin/agent-sandbox" ] && exit 0
    rm -f "$link"
fi

(cd "$root" && stow --restow .local .config)
chmod +x "$root/.local/bin/agent-sandbox"
