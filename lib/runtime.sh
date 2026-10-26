#!/usr/bin/env bash
# Container runtime abstraction: podman or docker.
# Detects the runtime, validates it's working, and provides runtime-specific
# arguments (user mapping, security opts).
#
# Expects: CONFIG (optional), die() from common.sh
# Provides: RUNTIME, detect_runtime, check_runtime, user_args, security_opts,
#           image_exists, build_image

RUNTIME=""

# Priority: CONTAINER_RUNTIME env > config > auto-detect (podman preferred)
detect_runtime() {
    if [ -n "${CONTAINER_RUNTIME:-}" ]; then
        command -v "$CONTAINER_RUNTIME" >/dev/null 2>&1 ||
            die "CONTAINER_RUNTIME=$CONTAINER_RUNTIME not found in PATH"
        RUNTIME="$CONTAINER_RUNTIME"
    elif [ -n "${CONFIG[runtime]:-}" ]; then
        RUNTIME="${CONFIG[runtime]}"
        command -v "$RUNTIME" >/dev/null 2>&1 ||
            die "Config runtime '$RUNTIME' not found in PATH"
    elif command -v podman >/dev/null 2>&1; then
        RUNTIME="podman"
    elif command -v docker >/dev/null 2>&1; then
        RUNTIME="docker"
    else
        die "No container runtime found. Install podman or docker, or set CONTAINER_RUNTIME."
    fi
}

check_runtime() {
    case "$RUNTIME" in
        podman)
            if [[ "$(uname -s)" == "Darwin" ]]; then
                podman machine list 2>/dev/null | grep -q "Currently running" ||
                    die "Podman machine not running. Start with: podman machine start"
            fi
            ;;
        docker)
            docker info >/dev/null 2>&1 ||
                die "Docker daemon not running. Start Docker Desktop or: sudo systemctl start docker"
            ;;
        *)
            die "Unknown runtime: $RUNTIME (expected podman or docker)"
            ;;
    esac
}

# User mapping args for `run`.
# Podman rootless: --userns=keep-id maps host UID to same UID in container.
# Docker: --user=UID:GID. On macOS, Docker Desktop's VM handles file sharing,
# so we use the image's agent user (1000:1000) and let the VM map ownership.
# Note: use = syntax because mapfile reads each line as a single array element.
user_args() {
    case "$RUNTIME" in
        podman)
            echo "--userns=keep-id"
            ;;
        docker)
            if [[ "$(uname -s)" == "Darwin" ]]; then
                echo "--user=1000:1000"
            else
                echo "--user=$(id -u):$(id -g)"
            fi
            ;;
    esac
}

# SELinux label disable: needed on SELinux-enabled Linux (Fedora) with podman.
# Docker ignores it; harmless to include but we skip on non-SELinux systems.
# Note: use = syntax (--security-opt=label=disable) because mapfile reads this
# as a single array element; space-separated would be passed as one argument.
security_opts() {
    if [[ "$(uname -s)" == "Linux" ]] &&
       command -v selinuxenabled >/dev/null 2>&1 &&
       selinuxenabled 2>/dev/null; then
        echo "--security-opt=label=disable"
    fi
}

image_exists() {
    "$RUNTIME" image exists "agent-sandbox:$1" 2>/dev/null
}

build_image() {
    local name="$1" context="$2"
    echo "Building agent-sandbox:$name with $RUNTIME ..."
    "$RUNTIME" build \
        --build-arg UID="$(id -u)" \
        --build-arg GID="$(id -g)" \
        -t "agent-sandbox:$name" \
        "$context"
}
