#!/usr/bin/env bash
# Validate container runtime. Exits 1 with warning if not working.
set -euo pipefail

if command -v podman >/dev/null 2>&1; then
    [ "$(uname -s)" != "Darwin" ] && exit 0
    podman machine list 2>/dev/null | grep -q "Currently running" || {
        echo "Warning: podman machine not running (podman machine start)" >&2
        exit 1
    }
elif command -v docker >/dev/null 2>&1; then
    docker info >/dev/null 2>&1 || {
        echo "Warning: docker daemon not running" >&2
        exit 1
    }
fi
