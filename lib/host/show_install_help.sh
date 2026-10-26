#!/usr/bin/env bash
# Show install instructions for missing tools.
# Usage: show_install_help.sh tool1 tool2 ...
set -euo pipefail

echo "Missing required tools: $*"
echo
echo "To fix, install them:"
echo

case "$(uname -s)" in
    Linux*)
        if [ -f /etc/fedora-release ]; then
            echo "  Fedora/RHEL/CentOS:"
            echo "    sudo dnf install $*"
        elif [ -f /etc/debian_version ]; then
            echo "  Debian/Ubuntu:"
            echo "    sudo apt install $*"
        elif [ -f /etc/arch-release ]; then
            echo "  Arch Linux:"
            echo "    sudo pacman -S $*"
        elif [ -f /etc/os-release ]; then
            echo "  Generic (adjust for your distro):"
            echo "    Install: stow, and podman or docker"
        else
            echo "  Common distros:"
            echo "    Fedora/RHEL:   sudo dnf install stow podman"
            echo "    Debian/Ubuntu: sudo apt install stow podman"
            echo "    Arch:          sudo pacman -S stow podman"
        fi
        ;;
    Darwin*)
        echo "  macOS (Homebrew):"
        echo "    brew install stow fzf"
        echo
        echo "  For Docker Desktop:"
        echo "    https://docs.docker.com/desktop/install/mac-install/"
        echo
        echo "  Or podman on macOS:"
        echo "    brew install podman"
        echo "    podman machine init"
        echo "    podman machine start"
        ;;
esac

echo
echo "After installing, re-run: ./install.sh"
