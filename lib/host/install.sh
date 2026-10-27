#!/usr/bin/env bash
# install.sh — actual install logic (called by `mise run setup`).
# Bootstrap lives in setup.sh at repo root. Tools are managed by mise (mise.toml [tools]).
#
# Steps:
#   1. Symlink agent-sandbox into ~/.local/bin (stow)
#   2. Create default config from template
#   3. Verify ~/.local/bin is in PATH
#   4. Check container runtime is working
#   5. Validate config
#   6. Validate repository structure
#
# Safe to run multiple times.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="$ROOT/lib/host"

# Pretty output
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

step() { echo; echo -e "${BOLD}==>${NC} ${BOLD}$*${NC}"; }
ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}!${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

echo
echo -e "${BOLD}agent-sandbox setup${NC}"
echo

# ── Step 1: Stow ────────────────────────────────────────────────
step "Step 1/5: Setting up symlinks"
"$HOST/stow.sh" "$ROOT"
ok "Installed to $HOME/.local/bin/agent-sandbox"

# ── Step 2: Config ──────────────────────────────────────────────
step "Step 2/5: Creating default config"
"$HOST/create_config.sh" "$ROOT"
ok "Config ready at $HOME/.config/agent-sandbox/config"

# ── Step 3: Check PATH ──────────────────────────────────────────
step "Step 3/5: Checking PATH"
if "$HOST/check_path.sh" 2>&1; then
    ok "$HOME/.local/bin is in PATH"
else
    warn "PATH needs updating — follow the instructions above"
fi

# ── Step 4: Check runtime ───────────────────────────────────────
step "Step 4/5: Checking container runtime"
if "$HOST/check_runtime.sh" 2>&1; then
    ok "Container runtime is ready"
else
    warn "Runtime needs attention — follow the instructions above"
fi

# ── Step 5: Validate config ─────────────────────────────────────
step "Step 5/6: Validating config"
if "$ROOT/.local/bin/agent-sandbox" --check 2>&1; then
    ok "Config valid"
else
    warn "Config has issues — see above"
fi

# ── Step 6: Validate repo ───────────────────────────────────────
step "Step 6/6: Validating repository"
if "$HOST/check_repo.sh" "$ROOT" 2>&1; then
    ok "Repository structure valid"
else
    fail "Repository validation failed"
    exit 1
fi

# ── Done ────────────────────────────────────────────────────────
echo
echo -e "${GREEN}${BOLD}Setup complete!${NC}"
echo
echo "Next steps:"
echo "  1. Reload your shell or start a new terminal"
echo "  2. Run: ${BOLD}agent-sandbox${NC}"
echo
echo "Configuration: $HOME/.config/agent-sandbox/config"
echo "Documentation: README.md"
