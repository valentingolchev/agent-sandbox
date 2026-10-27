#!/usr/bin/env bash
# ci-setup.sh — build base images for CI jobs. Usage: ci-setup.sh [harness]
#
# Builds:
#   - base-tools (always)
#   - base-tools-<harness> (if harness arg given)
#
# Uses $CONTAINER_RUNTIME (default: podman).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME="${CONTAINER_RUNTIME:-podman}"
IMG="localhost/agent-sandbox"
HARNESS="${1:-}"

"$RUNTIME" build --build-arg UID=1000 --build-arg GID=1000 \
    -t "$IMG:base-tools" "$ROOT/base"

if [ -n "$HARNESS" ]; then
    tmpfile=$(mktemp)
    trap 'rm -f "$tmpfile"' EXIT
    {
        echo "FROM $IMG:base-tools"
        echo "USER root"
        cat "$ROOT/base/harness/${HARNESS}.sh"
        echo "RUN chown -R agent:agent /home/agent"
        echo "USER agent"
    } > "$tmpfile"
    "$RUNTIME" build --build-arg UID=1000 --build-arg GID=1000 \
        -t "$IMG:base-tools-${HARNESS}" \
        -f "$tmpfile" "$ROOT/base"
fi
