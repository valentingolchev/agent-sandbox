#!/usr/bin/env bash
# Validate container runtime. Exits 1 with fix instructions if not working.
set -euo pipefail

if command -v podman >/dev/null 2>&1; then
    if [ "$(uname -s)" = "Darwin" ]; then
        if podman machine list 2>/dev/null | grep -q "Currently running"; then
            exit 0
        fi
        echo
        echo "Podman machine is not running."
        echo
        echo "To fix, start it:"
        echo "    podman machine start"
        echo
        exit 1
    fi
    exit 0
elif command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        exit 0
    fi
    echo
    echo "Docker daemon is not running."
    echo
    case "$(uname -s)" in
        Darwin*)
            echo "To fix, start Docker Desktop:"
            echo "    open -a Docker"
            echo
            echo "Wait for Docker to start, then re-run: ./install.sh"
            ;;
        Linux*)
            echo "To fix, start the Docker service:"
            echo "    sudo systemctl start docker"
            echo "    sudo systemctl enable docker  # enable on boot"
            echo
            echo "Add your user to the docker group (optional, avoids sudo):"
            echo "    sudo usermod -aG docker $USER"
            echo "    newgrp docker  # apply group change"
            echo
            echo "Then re-run: ./install.sh"
            ;;
    esac
    echo
    exit 1
fi
