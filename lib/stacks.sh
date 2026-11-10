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
# With extra tools selected (TOOLS_SUFFIX set by lib/extra_tools.sh), a
# content-hashed layer is applied once on top of the final image:
#   ... → <final>-tools-<hash>
#
# Expects: SANDBOX_ROOT, REBUILD (optional), die() from common.sh,
#          RUNTIME, image_exists from runtime.sh,
#          TOOLS_SUFFIX/TOOL_FILES from extra_tools.sh (optional)
# Provides: STACKS (array), STACK_PARENT (assoc array), context_for, ensure_image, remove_harness_images, reinstall_harness, image_name_for, FINAL_IMAGE

declare -A STACK_PARENT=()
STACKS=()

# Local images are tagged with localhost/ prefix — podman short-name
# resolution requires TTY in CI, so use fully-qualified local names.
IMAGE_PREFIX="localhost/agent-sandbox"

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
        echo "Building $IMAGE_PREFIX:base-tools with $RUNTIME ..."
        "$RUNTIME" build \
            --build-arg UID="$(id -u)" \
            --build-arg GID="$(id -g)" \
            -t "$IMAGE_PREFIX:base-tools" \
            -f "$SANDBOX_ROOT/base/Containerfile" \
            "$SANDBOX_ROOT/base"
    fi
}

# Build base-tools + harness image by generating a temp Containerfile.
# The harness install script is at base/harness/<harness>.sh (contains RUN commands).
build_base_with_harness() {
    local harness="$1"
    local image="$IMAGE_PREFIX:base-tools-${harness}"
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
        echo "FROM $IMAGE_PREFIX:base-tools"
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
    local image="$IMAGE_PREFIX:${stack}-${harness}"
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
        -f "$context/Containerfile" \
        "$context"
}

# Remove the harness layer image and every <stack>-<harness> image, so the
# next ensure_image rebuilds them with the current harness script. Also
# removes derived extra-tools layers (tags ending in -tools-<hash>; harness
# names are never hex hashes, so base-tools* tags don't match).
remove_harness_images() {
    local harness="$1" stack tag
    if image_exists "base-tools-${harness}"; then
        echo "Removing $IMAGE_PREFIX:base-tools-${harness} ..."
        "$RUNTIME" rmi -f "$IMAGE_PREFIX:base-tools-${harness}" >/dev/null 2>&1 || true
    fi
    for stack in "${STACKS[@]}"; do
        [ "$stack" = "base" ] && continue
        tag="${stack}-${harness}"
        if image_exists "$tag"; then
            echo "Removing $IMAGE_PREFIX:$tag ..."
            "$RUNTIME" rmi -f "$IMAGE_PREFIX:$tag" >/dev/null 2>&1 || true
        fi
    done
    while IFS= read -r tag; do
        [ -n "$tag" ] || continue
        echo "Removing $tag ..."
        "$RUNTIME" rmi -f "$tag" >/dev/null 2>&1 || true
    done < <("$RUNTIME" images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null |
        grep "^$IMAGE_PREFIX:.*-tools-[0-9a-f]\{8,12\}$" || true)
}

# Reinstall a harness: drop all harness images, rebuild the chain for the
# selected stack via ensure_image, then return (caller exits — no session).
reinstall_harness() {
    local stack="$1" harness="$2"
    if [ "$harness" = "manual" ]; then
        die "manual harness has no image to reinstall"
    fi
    if [ ! -f "$SANDBOX_ROOT/base/harness/${harness}.sh" ]; then
        die "No harness script for '$harness'"
    fi
    remove_harness_images "$harness"
    ensure_image "$stack" "$harness"
    echo "Harness '$harness' reinstalled for stack '$stack'."
}

# Build the image chain without the extra-tools layer; sets FINAL_IMAGE to
# the resulting plain image tag. Recursion for child stacks stays inside
# this function so the tools layer is applied exactly once (see ensure_image).
ensure_image_chain() {
    local stack="$1"
    local harness="$2"

    # "base" means just base-tools + harness (no language stack)
    if [ "$stack" = "base" ]; then
        ensure_base_tools
        if [ "$harness" != "manual" ]; then
            build_base_with_harness "$harness"
            FINAL_IMAGE="$IMAGE_PREFIX:base-tools-${harness}"
        else
            FINAL_IMAGE="$IMAGE_PREFIX:base-tools"
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
            parent_image="$IMAGE_PREFIX:base-tools"
        else
            build_base_with_harness "$harness"
            parent_image="$IMAGE_PREFIX:base-tools-${harness}"
        fi
    else
        # Child stack: build parent chain first (no tools layer on parents —
        # it is applied once, on top of the final image)
        ensure_image_chain "$parent" "$harness"
        parent_image="$FINAL_IMAGE"
    fi

    build_stack_with_harness "$stack" "$harness" "$parent_image"
    FINAL_IMAGE="$IMAGE_PREFIX:${stack}-${harness}"
}

# Ensure a composed image exists for the given stack + harness, with the
# extra-tools layer (content-hashed tag) applied once on top when selected.
# Builds the full chain: base-tools → base-tools-<harness> → <stack1>-<harness> → ...
ensure_image() {
    local stack="$1"
    local harness="$2"

    ensure_image_chain "$stack" "$harness"

    if [ -n "${TOOLS_SUFFIX:-}" ]; then
        local tools_tag="${FINAL_IMAGE}-tools-${TOOLS_SUFFIX}"
        build_extra_tools_layer "$FINAL_IMAGE" "$tools_tag" "$SANDBOX_ROOT/base"
        FINAL_IMAGE="$tools_tag"
    fi

    # Prune stale extra-tools layers: an edited script or changed selection
    # yields a new TOOLS_SUFFIX, orphaning the old <final>-tools-<hash> tag.
    # Remove every -tools-<hash> image for this prefix except the current
    # final tag. Simple and safe: the hash-only suffix keeps base-tools* and
    # <stack>-<harness> tags unmatched, the current tag is skipped, rmi
    # failures are ignored (the image may be in use), and a missing runtime
    # only skips the prune (the listing is best-effort).
    local stale
    while IFS= read -r stale; do
        [ -n "$stale" ] || continue
        if [ "$stale" = "$FINAL_IMAGE" ]; then continue; fi
        echo "Removing stale $stale ..."
        "$RUNTIME" rmi -f "$stale" >/dev/null 2>&1 || true
    done < <("$RUNTIME" images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null |
        grep -E "^$IMAGE_PREFIX:.*-tools-[0-9a-f]{8,12}$" || true)
}

# Get the image name for a stack + harness combination (including the
# extra-tools suffix when TOOLS_SUFFIX is set — must match ensure_image).
image_name_for() {
    local stack="$1"
    local harness="$2"
    local base
    if [ "$harness" = "manual" ]; then
        if [ "$stack" = "base" ]; then
            base="$IMAGE_PREFIX:base-tools"
        else
            base="$IMAGE_PREFIX:${stack}-manual"
        fi
    else
        if [ "$stack" = "base" ]; then
            base="$IMAGE_PREFIX:base-tools-${harness}"
        else
            base="$IMAGE_PREFIX:${stack}-${harness}"
        fi
    fi
    if [ -n "${TOOLS_SUFFIX:-}" ]; then
        echo "${base}-tools-${TOOLS_SUFFIX}"
    else
        echo "$base"
    fi
}

# Initialize on source
discover_stacks
