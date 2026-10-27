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

step "Lint: bash syntax"
local_ok=1
while IFS= read -r -d '' f; do
    bash -n "$f" || local_ok=0
done < <(find "$ROOT" -name '*.sh' -not -path '*/.git/*' -print0)
for f in .local/bin/agent-sandbox setup.sh scripts/run.sh scripts/lint.sh scripts/test-build.sh scripts/test.sh scripts/ci-setup.sh; do
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
