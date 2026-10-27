#!/usr/bin/env bash
# test.sh — run all checks (lint + build). Composer for lint.sh + test-build.sh.
# Prefer: mise run test   (or: mise run lint / mise run test-build)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$ROOT/lint.sh"
"$ROOT/test-build.sh"
