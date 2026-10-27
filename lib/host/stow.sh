#!/usr/bin/env bash
# Stow agent-sandbox into ~/.local. Usage: stow.sh <repo-root>
set -euo pipefail

root="${1:?Usage: stow.sh <repo-root>}"

info() { echo "  • $*"; }

info "Creating $HOME/.local/bin..."
mkdir -p "$HOME/.local/bin"

info "Creating symlinks..."
if ! (cd "$root" && stow -t "$HOME/.local" --restow .local); then
    echo
    echo "Error: stow failed" >&2
    echo "This usually means a file already exists at the target location." >&2
    echo "Remove or rename the existing file, then re-run: ./setup.sh" >&2
    exit 1
fi
chmod +x "$root/.local/bin/agent-sandbox"
info "Linked: $HOME/.local/bin/agent-sandbox"
