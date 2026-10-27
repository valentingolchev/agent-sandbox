#!/usr/bin/env bash
# test-build.sh — build and test image composition locally.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0
ok()  { echo "  ✓ $*"; pass=$((pass+1)); }
bad() { echo "  ✗ $*" >&2; fail=$((fail+1)); }
step() { echo; echo "==> $*"; }

IMG="localhost/agent-sandbox"
RUNTIME="${CONTAINER_RUNTIME:-podman}"
UID_ARG="$(id -u)"
GID_ARG="$(id -g)"

step "Build: base-tools"
if "$RUNTIME" build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
     -t "$IMG:base-tools" -f "$ROOT/base/Containerfile" "$ROOT/base" 2>&1 | tail -1; then
    ok "base-tools built"
else
    bad "base-tools build failed"
fi

step "Build: base-tools + claude harness"
tmpfile=$(mktemp)
{
    echo "FROM $IMG:base-tools"
    echo "USER root"
    cat "$ROOT/base/harness/claude.sh"
    echo "RUN chown -R agent:agent /home/agent"
    echo "USER agent"
} > "$tmpfile"
if "$RUNTIME" build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
     -t "$IMG:base-tools-claude" -f "$tmpfile" "$ROOT/base" 2>&1 | tail -1; then
    ok "base-tools-claude built"
else
    bad "base-tools-claude build failed"
fi
rm -f "$tmpfile"

step "Build: python + claude"
if "$RUNTIME" build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
     --build-arg BASE_IMAGE="$IMG:base-tools-claude" \
     -t "$IMG:python-claude" -f "$ROOT/stacks/python/Containerfile" "$ROOT/stacks/python/" 2>&1 | tail -1; then
    ok "python-claude built"
else
    bad "python-claude build failed"
fi

step "Build: python + manual (no harness)"
if "$RUNTIME" build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
     --build-arg BASE_IMAGE="$IMG:base-tools" \
     -t "$IMG:python-manual" -f "$ROOT/stacks/python/Containerfile" "$ROOT/stacks/python/" 2>&1 | tail -1; then
    ok "python-manual built"
else
    bad "python-manual build failed"
fi

step "Build: multi-level chain (clojure → web-cljs)"
if "$RUNTIME" build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
     --build-arg BASE_IMAGE="$IMG:base-tools-claude" \
     -t "$IMG:clojure-claude" -f "$ROOT/stacks/clojure/Containerfile" "$ROOT/stacks/clojure/" 2>&1 | tail -1; then
    ok "clojure-claude built"
else
    bad "clojure-claude build failed"
fi
if "$RUNTIME" build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
     --build-arg BASE_IMAGE="$IMG:clojure-claude" \
     -t "$IMG:web-cljs-claude" -f "$ROOT/stacks/web-cljs/Containerfile" "$ROOT/stacks/web-cljs/" 2>&1 | tail -1; then
    ok "web-cljs-claude built"
else
    bad "web-cljs-claude build failed"
fi

echo
echo "==> Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
