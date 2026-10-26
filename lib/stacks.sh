#!/usr/bin/env bash
# Stack registry and ad hoc image composition.
#
# Stacks are auto-discovered from stacks/*/Containerfile. Each stack defines
# its parent (parsed from FROM line) for topological ordering.
#
# Images are composed ad hoc at build time:
#   base-tools → base-tools-<harness> → <stack1>-<harness> → <stack2>-<harness> → ...
#
# This keeps the attack surface minimal (only the selected harness is installed)
# while sharing layers via container image caching.
#
# Expects: SANDBOX_ROOT, REBUILD (optional), die() from common.sh,
#          RUNTIME, image_exists from runtime.sh
# Provides: STACKS (array), STACK_PARENT (assoc array), context_for, ensure_image

declare -A STACK_PARENT=()
STACKS=()

# Discover stacks from stacks/*/Containerfile and parse parent from FROM line.
# "base" is a pseudo-stack meaning base-tools + harness (no language stack).
discover_stacks() {
    STACK_PARENT=([base]="")
    STACKS=(base)

    local dir name containerfile parent
    for dir in "$SANDBOX_ROOT"/stacks/*/; do
        [ -d "$dir" ] || continue
        name="$(basename "$dir")"
        containerfile="$dir/Containerfile"
        [ -f "$containerfile" ] || continue

        # Parse parent from: FROM agent-sandbox:<parent> or FROM ${BASE_IMAGE}
        # For stacks with ARG BASE_IMAGE, the parent is in the default value
        parent=""
        if grep -q '^FROM agent-sandbox:' "$containerfile" 2>/dev/null; then
            parent="$(grep -m1 '^FROM agent-sandbox:' "$containerfile" |
                      sed 's/^FROM agent-sandbox://' | awk '{print $1}' |
                      sed 's/-<harness>$//')"
        elif grep -q 'ARG BASE_IMAGE=agent-sandbox:' "$containerfile" 2>/dev/null; then
            parent="$(grep -m1 'ARG BASE_IMAGE=agent-sandbox:' "$containerfile" |
                      sed 's/.*agent-sandbox://' | awk '{print $1}' |
                      sed 's/-<harness>$//')"
        fi

        # Empty parent means it builds on base-tools
        [ -n "$parent" ] || parent="base-tools"

        STACK_PARENT[$name]="$parent"
        STACKS+=("$name")
    done

    # Topological sort: parents before children (for menu display order).
    local -a sorted=()
    local -A added=([base]=1 [base-tools]=1)
    sorted=(base)
    local changed=1 stack
    while [ "$changed" -eq 1 ]; do
        changed=0
        for stack in "${STACKS[@]}"; do
            [ -n "${added[$stack]+x}" ] && continue
            if [ -z "${STACK_PARENT[$stack]}" ] || [ -n "${added[${STACK_PARENT[$stack]}]+x}" ]; then
                sorted+=("$stack")
                added[$stack]=1
                changed=1
            fi
        done
    done
    STACKS=("${sorted[@]}")
}

context_for() {
    local name="$1"
    if [[ "$name" == "base" ]]; then
        echo "$SANDBOX_ROOT/base"
    else
        echo "$SANDBOX_ROOT/stacks/$name"
    fi
}

# Build base-tools image (no harnesses, just core tooling).
ensure_base_tools() {
    if [[ "${REBUILD:-0}" == "1" ]] || ! image_exists "base-tools"; then
        echo "Building agent-sandbox:base-tools with $RUNTIME ..."
        "$RUNTIME" build \
            --build-arg UID="$(id -u)" \
            --build-arg GID="$(id -g)" \
            -t "agent-sandbox:base-tools" \
            "$SANDBOX_ROOT/base"
    fi
}

# Build base-tools + harness image by generating a temp Containerfile.
# The harness install script is at base/harness/<harness>.sh (contains RUN commands).
build_base_with_harness() {
    local harness="$1"
    local image="agent-sandbox:base-tools-${harness}"
    local harness_script="$SANDBOX_ROOT/base/harness/${harness}.sh"

    # Skip if already built
    if [[ "${REBUILD:-0}" != "1" ]] && image_exists "base-tools-${harness}"; then
        return 0
    fi

    [ -f "$harness_script" ] || die "No harness script for '$harness' at $harness_script"

    echo "Building $image with $RUNTIME ..."

    # Generate temporary Containerfile
    local tmpfile
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/agent-sandbox-Containerfile.XXXXXX")

    {
        echo "FROM agent-sandbox:base-tools"
        echo "USER root"
        cat "$harness_script"
        # Harness installs (npm, uv) create dirs in $HOME as root.
        # Fix ownership so the agent user can write at runtime (tmpfs copy-up).
        echo "RUN chown -R agent:agent /home/agent"
        echo "USER agent"
    } > "$tmpfile"

    "$RUNTIME" build \
        --build-arg UID="$(id -u)" \
        --build-arg GID="$(id -g)" \
        -t "$image" \
        -f "$tmpfile" \
        "$SANDBOX_ROOT/base"

    rm -f "$tmpfile"
}

# Build a stack image on top of a harness-specific base.
build_stack_with_harness() {
    local stack="$1"
    local harness="$2"
    local parent_image="$3"
    local image="agent-sandbox:${stack}-${harness}"
    local context
    context="$(context_for "$stack")"

    # Skip if already built
    if [[ "${REBUILD:-0}" != "1" ]] && image_exists "${stack}-${harness}"; then
        return 0
    fi

    [[ -f "$context/Containerfile" ]] || {
        die "No Containerfile for stack '$stack' in $context."
    }

    echo "Building $image with $RUNTIME ..."

    "$RUNTIME" build \
        --build-arg UID="$(id -u)" \
        --build-arg GID="$(id -g)" \
        --build-arg BASE_IMAGE="$parent_image" \
        -t "$image" \
        "$context"
}

# Ensure a composed image exists for the given stack + harness.
# Builds the full chain: base-tools → base-tools-<harness> → <stack1>-<harness> → ...
ensure_image() {
    local stack="$1"
    local harness="$2"

    # "base" means just base-tools + harness (no language stack)
    if [ "$stack" = "base" ]; then
        ensure_base_tools
        if [ "$harness" != "manual" ]; then
            build_base_with_harness "$harness"
        fi
        return 0
    fi

    # Build the stack chain with the harness
    local parent="${STACK_PARENT[$stack]:-}"
    local parent_image

    if [ -z "$parent" ] || [ "$parent" = "base-tools" ]; then
        # Top-level stack: builds on base-tools-<harness> (or base-tools for manual)
        ensure_base_tools
        if [ "$harness" = "manual" ]; then
            parent_image="agent-sandbox:base-tools"
        else
            build_base_with_harness "$harness"
            parent_image="agent-sandbox:base-tools-${harness}"
        fi
    else
        # Child stack: build parent chain first
        ensure_image "$parent" "$harness"
        parent_image="agent-sandbox:${parent}-${harness}"
    fi

    build_stack_with_harness "$stack" "$harness" "$parent_image"
}

# Get the image name for a stack + harness combination.
image_name_for() {
    local stack="$1"
    local harness="$2"
    if [ "$harness" = "manual" ]; then
        if [ "$stack" = "base" ]; then
            echo "agent-sandbox:base-tools"
        else
            echo "agent-sandbox:${stack}-manual"
        fi
    else
        if [ "$stack" = "base" ]; then
            echo "agent-sandbox:base-tools-${harness}"
        else
            echo "agent-sandbox:${stack}-${harness}"
        fi
    fi
}

# Initialize on source
discover_stacks
