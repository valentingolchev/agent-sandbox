#!/usr/bin/env bash
# test-build.sh — build and test image composition locally.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0
# _ok/_bad (not ok/bad) — validate.sh defines ok() without counters; avoid collision.
_ok()  { echo "  ✓ $*"; pass=$((pass+1)); }
_bad() { echo "  ✗ $*" >&2; fail=$((fail+1)); }
step() { echo; echo "==> $*"; }

IMG="localhost/agent-sandbox"
RUNTIME="${CONTAINER_RUNTIME:-podman}"
UID_ARG="$(id -u)"
GID_ARG="$(id -g)"

# ---- unit tests: extra tools + config validation (no runtime needed) ----

step "Unit: extra tools resolution"
UNIT_ROOT="$(mktemp -d)"
trap 'rm -rf "$UNIT_ROOT"' EXIT
mkdir -p "$UNIT_ROOT/base/tools"
cat > "$UNIT_ROOT/base/tools/ok.sh" <<'EOF'
#!/usr/bin/env bash
# Example extra tool script (see base/tools/README.md for the rules).
set -euo pipefail
echo "extra tool ok"
EOF

source "$ROOT/lib/common.sh"
source "$ROOT/lib/extra_tools.sh"
SANDBOX_ROOT="$UNIT_ROOT"

if resolve_extra_tools "ok" &&
   [ "${TOOLS_SEL[0]:-}" = "ok" ] &&
   [ "${TOOL_FILES[0]:-}" = "$UNIT_ROOT/base/tools/ok.sh" ] &&
   [[ "$TOOLS_SUFFIX" =~ ^[0-9a-f]{12}$ ]]; then
    _ok "resolve_extra_tools selects 'ok' with hash suffix"
else
    _bad "resolve_extra_tools 'ok'"
fi

check_rejects() {
    if ( resolve_extra_tools "$1" ) >/dev/null 2>&1; then
        _bad "resolve_extra_tools '$1' should fail"
    else
        _ok "resolve_extra_tools rejects '$1'"
    fi
}
check_rejects "nope"
check_rejects "bad/name"
check_rejects "../evil"

# Empty selection: no tools selected — TOOLS_SUFFIX must stay empty so no
# tools layer tag is applied (ensure_image skips the layer entirely).
if resolve_extra_tools "" &&
   [ "${#TOOLS_SEL[@]}" -eq 0 ] &&
   [ "${#TOOL_FILES[@]}" -eq 0 ] &&
   [ -z "$TOOLS_SUFFIX" ]; then
    _ok "resolve_extra_tools '' leaves TOOLS_SUFFIX empty (no tools layer tag)"
else
    _bad "resolve_extra_tools '' (expected empty selection, empty TOOLS_SUFFIX)"
fi

step "Unit: extra_tools config validation"
source "$ROOT/lib/config.sh"
source "$ROOT/lib/validate.sh"
# validate.sh defines ok() (no test counters) — counter helpers above are
# named _ok/_bad so they survive sourcing it.

printf 'extra_tools = ok\n' > "$UNIT_ROOT/valid.conf"
if validate_config "$UNIT_ROOT/valid.conf" >/dev/null 2>&1; then
    _ok "validate_config accepts known extra tool"
else
    _bad "validate_config rejects valid extra_tools"
fi

printf 'extra_tools = nope\n' > "$UNIT_ROOT/invalid.conf"
if validate_config "$UNIT_ROOT/invalid.conf" >/dev/null 2>&1; then
    _bad "validate_config accepts unknown extra tool"
else
    _ok "validate_config rejects unknown extra tool"
fi

printf 'extra_tools = ../evil\n' > "$UNIT_ROOT/path.conf"
if validate_config "$UNIT_ROOT/path.conf" >/dev/null 2>&1; then
    _bad "validate_config accepts path traversal in extra_tools ('../evil')"
else
    _ok "validate_config rejects path traversal in extra_tools ('../evil')"
fi

# ---- build tests (require a container runtime) ----

if ! command -v "$RUNTIME" >/dev/null 2>&1; then
    echo
    echo "==> SKIP: container runtime '$RUNTIME' not found — build tests skipped"
    echo "    (unit tests above still ran)"
    echo
    echo "==> Results: $pass passed, $fail failed (build tests skipped)"
    # Unit tests passed and nothing is left to run — exit now instead of
    # falling through to the build tests, which need the runtime.
    exit "$fail"
fi

step "Build: base-tools"
if "$RUNTIME" build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
     -t "$IMG:base-tools" -f "$ROOT/base/Containerfile" "$ROOT/base" 2>&1 | tail -1; then
    _ok "base-tools built"
else
    _bad "base-tools build failed"
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
    _ok "base-tools-claude built"
else
    _bad "base-tools-claude build failed"
fi
rm -f "$tmpfile"

step "Build: python + claude"
if "$RUNTIME" build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
     --build-arg BASE_IMAGE="$IMG:base-tools-claude" \
     -t "$IMG:python-claude" -f "$ROOT/stacks/python/Containerfile" "$ROOT/stacks/python/" 2>&1 | tail -1; then
    _ok "python-claude built"
else
    _bad "python-claude build failed"
fi

step "Build: python + manual (no harness)"
if "$RUNTIME" build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
     --build-arg BASE_IMAGE="$IMG:base-tools" \
     -t "$IMG:python-manual" -f "$ROOT/stacks/python/Containerfile" "$ROOT/stacks/python/" 2>&1 | tail -1; then
    _ok "python-manual built"
else
    _bad "python-manual build failed"
fi

step "Build: multi-level chain (clojure → web-cljs)"
if "$RUNTIME" build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
     --build-arg BASE_IMAGE="$IMG:base-tools-claude" \
     -t "$IMG:clojure-claude" -f "$ROOT/stacks/clojure/Containerfile" "$ROOT/stacks/clojure/" 2>&1 | tail -1; then
    _ok "clojure-claude built"
else
    _bad "clojure-claude build failed"
fi
if "$RUNTIME" build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
     --build-arg BASE_IMAGE="$IMG:clojure-claude" \
     -t "$IMG:web-cljs-claude" -f "$ROOT/stacks/web-cljs/Containerfile" "$ROOT/stacks/web-cljs/" 2>&1 | tail -1; then
    _ok "web-cljs-claude built"
else
    _bad "web-cljs-claude build failed"
fi

echo
echo "==> Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
