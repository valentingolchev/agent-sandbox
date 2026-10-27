#!/usr/bin/env bash
# init.sh — runs inside the container before the harness starts.
# Configured via `init_script` in ~/.config/agent-sandbox/config.
#
# Example: install mise tools (shellcheck, fzf) for development.
# Runs in /workspace/<name>, so mise.toml is read from the workspace.
set -euo pipefail

if [ -f mise.toml ]; then
    mise install
fi
