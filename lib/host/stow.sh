#!/usr/bin/env bash
# Stow agent-sandbox into ~/.local. Usage: stow.sh <repo-root>
set -euo pipefail

root="${1:?Usage: stow.sh <repo-root>}"

info() { echo "  • $*"; }

info "Creating ~/.local/bin and ~/.config/agent-sandbox..."
mkdir -p "$HOME/.local/bin" "$HOME/.config/agent-sandbox"

link="$HOME/.local/bin/agent-sandbox"
if [ -L "$link" ]; then
    if [ "$(readlink "$link")" = "$root/.local/bin/agent-sandbox" ]; then
        info "Already stowed: $link"
        exit 0
    fi
    info "Removing old symlink: $link"
    rm -f "$link"
fi

info "Creating symlinks..."
if ! (cd "$root" && stow --restow .local .config); then
    echo
    echo "Error: stow failed" >&2
    echo "This usually means a file already exists at the target location." >&2
    echo "Remove or rename the existing file, then re-run: ./install.sh" >&2
    exit 1
fi

chmod +x "$root/.local/bin/agent-sandbox"
info "Linked: $link"
info "Config: $HOME/.config/agent-sandbox/config"
