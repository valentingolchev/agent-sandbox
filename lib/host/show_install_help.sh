#!/usr/bin/env bash
# Show install instructions. Usage: show_install_help.sh tool1 tool2 ...
set -euo pipefail

echo "Missing: $*"
case "$(uname -s)" in
    Linux*)
        echo "  Fedora: sudo dnf install $*"
        echo "  Debian: sudo apt install $*"
        ;;
    Darwin*)
        echo "  brew install stow fzf"
        echo "  Docker: https://docs.docker.com/desktop/install/mac-install/"
        ;;
esac
