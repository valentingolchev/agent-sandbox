#!/usr/bin/env bash
# lint.sh — shellcheck + bash syntax check.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0
ok()  { echo "  ✓ $*"; pass=$((pass+1)); }
bad() { echo "  ✗ $*" >&2; fail=$((fail+1)); }
step() { echo; echo "==> $*"; }

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

step "Lint: extra tools (no pipe-to-shell downloads)"
if [ -d "$ROOT/base/tools" ]; then
    tools_ok=1
    # Tool scripts run as root at build time — never pipe a download into
    # another command. Reject any pipe on a curl/wget line; download to a
    # file first, then execute (see base/tools/README.md).
    while IFS= read -r -d '' f; do
        if grep -En '(curl|wget).*\|' "$f"; then
            echo "  ✗ $f: pipe on a curl/wget line — download to a file first (see base/tools/README.md)" >&2
            tools_ok=0
        fi
    done < <(find "$ROOT/base/tools" -name '*.sh' -print0)
    if [ "$tools_ok" -eq 1 ]; then
        ok "extra tools clean"
    else
        bad "extra tools contain pipe-to-shell downloads"
    fi
else
    ok "no base/tools/ directory (nothing to lint)"
fi

step "Lint: bash syntax"
local_ok=1
while IFS= read -r -d '' f; do
    bash -n "$f" || local_ok=0
done < <(find "$ROOT" -name '*.sh' -not -path '*/.git/*' -print0)
for f in .local/bin/agent-sandbox setup.sh init.sh scripts/run.sh scripts/lint.sh scripts/test-build.sh scripts/test.sh scripts/ci-setup.sh; do
    bash -n "$ROOT/$f" || local_ok=0
done
if [ "$local_ok" -eq 1 ]; then
    ok "bash syntax clean"
else
    bad "bash syntax errors"
fi

echo
echo "==> Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
