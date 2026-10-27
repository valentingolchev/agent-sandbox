#!/usr/bin/env bash
# install.sh — Set up agent-sandbox on your machine.
#
# Steps:
#   1. Check required tools (stow, podman/docker)
#   2. Symlink agent-sandbox into ~/.local/bin
#   3. Create default config from template
#   4. Verify ~/.local/bin is in PATH
#   5. Check container runtime is working
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
CYAN='\033[0;36m'
NC='\033[0m'

step() { echo; echo -e "${BOLD}==>${NC} ${BOLD}$*${NC}"; }
ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}!${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }
info() { echo -e "  ${CYAN}•${NC} $*"; }

echo
echo -e "${BOLD}agent-sandbox installer${NC}"
echo

# ── Step 1: Check tools ─────────────────────────────────────────
step "Step 1/6: Checking required tools"
if ! missing="$("$HOST/check_tools.sh" 2>&1)"; then
    fail "Missing tools: $(echo "$missing" | tr '\n' ' ')"
    echo
    "$HOST/show_install_help.sh" $missing  # word-split intentional: list of tools
    exit 1
fi
ok "All required tools found (stow, container runtime)"

# ── Step 2: Stow ────────────────────────────────────────────────
step "Step 2/6: Setting up symlinks"
"$HOST/stow.sh" "$ROOT"
ok "Installed to $HOME/.local/bin/agent-sandbox"

# ── Step 3: Config ──────────────────────────────────────────────
step "Step 3/6: Creating default config"
"$HOST/create_config.sh" "$ROOT"
ok "Config ready at $HOME/.config/agent-sandbox/config"

# ── Step 4: Check PATH ──────────────────────────────────────────
step "Step 4/6: Checking PATH"
if "$HOST/check_path.sh" 2>&1; then
    ok "$HOME/.local/bin is in PATH"
else
    warn "PATH needs updating — follow the instructions above"
fi

# ── Step 5: Check runtime ───────────────────────────────────────
step "Step 5/6: Checking container runtime"
if "$HOST/check_runtime.sh" 2>&1; then
    ok "Container runtime is ready"
else
    warn "Runtime needs attention — follow the instructions above"
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
echo
