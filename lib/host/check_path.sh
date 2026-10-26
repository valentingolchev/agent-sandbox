#!/usr/bin/env bash
# Check ~/.local/bin is in PATH. Exits 1 with warning if not.
set -euo pipefail

bin="$HOME/.local/bin"
case ":$PATH:" in
    *":$bin:"*) exit 0 ;;
esac
echo "Warning: $bin not in PATH" >&2
echo "  Add: export PATH=\"\$HOME/.local/bin:\$PATH\"" >&2
exit 1
