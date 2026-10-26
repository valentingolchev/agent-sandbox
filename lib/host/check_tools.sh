#!/usr/bin/env bash
# Check required tools. Outputs missing tools (one per line), exits 1 if any missing.
set -euo pipefail

missing=()
for tool in stow bash git; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
command -v podman >/dev/null 2>&1 || command -v docker >/dev/null 2>&1 ||
    missing+=("podman-or-docker")

if [ ${#missing[@]} -gt 0 ]; then
    printf '%s\n' "${missing[@]}"
    exit 1
fi
