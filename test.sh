#!/usr/bin/env bash
# test.sh — run CI checks locally. No CI dependency.
#
# Usage: ./test.sh [--skip-build] [--skip-lint]
#
# Checks:
#   1. Shellcheck (if installed)
#   2. Bash syntax (all .sh files + extensionless scripts)
#   3. Build base-tools image
#   4. Test harness composition (base-tools + claude)
#   5. Test stack composition (python + claude, manual)
#   6. Test multi-level chain (web-cljs → clojure → base-tools-claude)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKIP_BUILD=0
SKIP_LINT=0
for arg in "$@"; do
    case "$arg" in
        --skip-build) SKIP_BUILD=1 ;;
        --skip-lint)  SKIP_LINT=1 ;;
        *) echo "Unknown arg: $arg" >&2; exit 1 ;;
    esac
done

pass=0
fail=0
ok()   { echo "  ✓ $*"; pass=$((pass+1)); }
bad()  { echo "  ✗ $*" >&2; fail=$((fail+1)); }
step() { echo; echo "==> $*"; }

IMG="localhost/agent-sandbox"

# ── 1. Lint ─────────────────────────────────────────────────────
if [ "$SKIP_LINT" -eq 0 ]; then
    step "Lint: shellcheck"
    if command -v shellcheck >/dev/null 2>&1; then
        if find "$ROOT" -name '*.sh' -not -path '*/.git/*' -print0 | \
           xargs -0 shellcheck --severity=warning; then
            ok "shellcheck clean"
        else
            bad "shellcheck found issues"
        fi
    else
        echo "  ! shellcheck not installed, skipping"
        echo "    Install: sudo dnf install ShellCheck  (Fedora)"
        echo "             sudo apt install shellcheck   (Debian/Ubuntu)"
    fi

    step "Lint: bash syntax"
    local_ok=1
    while IFS= read -r -d '' f; do
        bash -n "$f" || local_ok=0
    done < <(find "$ROOT" -name '*.sh' -not -path '*/.git/*' -print0)
    for f in .local/bin/agent-sandbox install.sh run.sh test.sh; do
        bash -n "$ROOT/$f" || local_ok=0
    done
    if [ "$local_ok" -eq 1 ]; then
        ok "bash syntax clean"
    else
        bad "bash syntax errors"
    fi
fi

# ── 2. Build ────────────────────────────────────────────────────
if [ "$SKIP_BUILD" -eq 0 ]; then
    UID_ARG="$(id -u)"
    GID_ARG="$(id -g)"

    step "Build: base-tools"
    if podman build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
         -t "$IMG:base-tools" "$ROOT/base" 2>&1 | tail -1; then
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
    if podman build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
         -t "$IMG:base-tools-claude" -f "$tmpfile" "$ROOT/base" 2>&1 | tail -1; then
        ok "base-tools-claude built"
    else
        bad "base-tools-claude build failed"
    fi
    rm -f "$tmpfile"

    step "Build: python + claude"
    if podman build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
         --build-arg BASE_IMAGE="$IMG:base-tools-claude" \
         -t "$IMG:python-claude" "$ROOT/stacks/python/" 2>&1 | tail -1; then
        ok "python-claude built"
    else
        bad "python-claude build failed"
    fi

    step "Build: python + manual (no harness)"
    if podman build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
         --build-arg BASE_IMAGE="$IMG:base-tools" \
         -t "$IMG:python-manual" "$ROOT/stacks/python/" 2>&1 | tail -1; then
        ok "python-manual built"
    else
        bad "python-manual build failed"
    fi

    step "Build: multi-level chain (clojure → web-cljs)"
    if podman build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
         --build-arg BASE_IMAGE="$IMG:base-tools-claude" \
         -t "$IMG:clojure-claude" "$ROOT/stacks/clojure/" 2>&1 | tail -1; then
        ok "clojure-claude built"
    else
        bad "clojure-claude build failed"
    fi
    if podman build --build-arg UID="$UID_ARG" --build-arg GID="$GID_ARG" \
         --build-arg BASE_IMAGE="$IMG:clojure-claude" \
         -t "$IMG:web-cljs-claude" "$ROOT/stacks/web-cljs/" 2>&1 | tail -1; then
        ok "web-cljs-claude built"
    else
        bad "web-cljs-claude build failed"
    fi
fi

# ── Summary ─────────────────────────────────────────────────────
echo
echo "==> Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
