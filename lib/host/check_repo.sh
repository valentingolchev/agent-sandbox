#!/usr/bin/env bash
# Validate repo structure. Usage: check_repo.sh <repo-root>
set -euo pipefail

root="${1:?Usage: check_repo.sh <repo-root>}"

ok=0
for dir in lib base stacks; do
    [ -d "$root/$dir" ] || { echo "  Missing: $dir/" >&2; ok=1; }
done

for f in common.sh config.sh runtime.sh stacks.sh prompts.sh credentials.sh; do
    [ -f "$root/lib/$f" ] || { echo "  Missing: lib/$f" >&2; ok=1; }
done

[ -f "$root/base/Containerfile" ] || { echo "  Missing: base/Containerfile" >&2; ok=1; }

if [ $ok -eq 1 ]; then
    echo
    echo "To fix, run install.sh from the repository root:"
    echo "    cd /path/to/agent-sandbox"
    echo "    ./install.sh"
    echo
    exit 1
fi
