#!/usr/bin/env bash
# Create default agent-sandbox config from template. Usage: create_config.sh <repo-root>
#
# Creates ~/.config/agent-sandbox/config from the repo's config.template,
# replacing @SANDBOX_ROOT@ with the actual repo path. Does nothing if the
# config already exists (never overwrites user config).
set -euo pipefail

root="${1:?Usage: create_config.sh <repo-root>}"

info() { echo "  • $*"; }

config_dir="$HOME/.config/agent-sandbox"
config="$config_dir/config"
template="$root/.config/agent-sandbox/config.template"

# Handle broken symlink at config_dir (e.g. from old dotfiles stow).
if [ -L "$config_dir" ] && [ ! -d "$config_dir" ]; then
    info "Removing broken symlink: $config_dir"
    rm -f "$config_dir"
elif [ -e "$config_dir" ] && [ ! -d "$config_dir" ]; then
    echo "Error: $config_dir exists but is not a directory" >&2
    exit 1
fi

mkdir -p "$config_dir"

if [ -f "$config" ]; then
    info "Config exists: $config"
elif [ -f "$template" ]; then
    sed "s|@SANDBOX_ROOT@|$root|g" "$template" > "$config"
    info "Created config from template: $config"
else
    info "No template found at $template, skipping"
fi
