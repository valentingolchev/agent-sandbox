#!/usr/bin/env bash
# Repo-provided extra tools: base/tools/*.sh install scripts layered onto a
# sandbox image at build time (see base/tools/README.md for the script rules).
#
# Selection comes from the extra_tools config key or EXTRA_TOOLS env var
# (space-separated names matching script basenames). The layer image gets a
# content-hash tag suffix so edits rebuild it: <final>-tools-<hash>.
#
# Expects: SANDBOX_ROOT, RUNTIME, REBUILD (optional), die() from common.sh,
#          image_exists from runtime.sh
# Provides: EXTRA_TOOLS_ALL, is_valid_tool_name, resolve_extra_tools
#           (sets TOOLS_SEL, TOOL_FILES, TOOLS_SUFFIX), build_extra_tools_layer

# All discovered tool names (basenames of base/tools/*.sh).
EXTRA_TOOLS_ALL=()

# Discover extra tool names from base/tools/*.sh.
discover_extra_tools() {
    EXTRA_TOOLS_ALL=()
    local f dir="$SANDBOX_ROOT/base/tools"
    [ -d "$dir" ] || return 0
    for f in "$dir"/*.sh; do
        [ -f "$f" ] || continue
        EXTRA_TOOLS_ALL+=("$(basename "$f" .sh)")
    done
}

# Tool names become image tag suffixes — keep them strict and shell/tag safe.
is_valid_tool_name() {
    [[ "$1" =~ ^[a-z0-9][a-z0-9_-]{0,63}$ ]]
}

# Resolve the extra tools selection (space-separated names): validate each
# name and script file, then compute the image tag suffix. Sets:
#   TOOLS_SEL     selected tool names (array)
#   TOOL_FILES    absolute paths of the selected scripts (array)
#   TOOLS_SUFFIX  content hash for image tags (empty if no tools selected)
# TOOLS_SEL/TOOL_FILES/TOOLS_SUFFIX are read by callers (lib/stacks.sh,
# scripts/test-build.sh) after sourcing — shellcheck can't see those reads.
# shellcheck disable=SC2034
resolve_extra_tools() {
    local selection="$1"
    TOOLS_SEL=()
    TOOL_FILES=()
    TOOLS_SUFFIX=""

    discover_extra_tools

    local name path found
    local -A seen=()
    # shellcheck disable=SC2086  # intentional word split: space-separated names
    for name in $selection; do
        if ! is_valid_tool_name "$name"; then
            die "extra_tools: invalid tool name '$name' (expected [a-z0-9][a-z0-9_-]{0,63})."
        fi
        # Ignore duplicate names: the same script twice would be COPYed and
        # run twice for no benefit.
        if [ -n "${seen[$name]+x}" ]; then
            continue
        fi
        seen[$name]=1
        found=0
        for path in "${EXTRA_TOOLS_ALL[@]+"${EXTRA_TOOLS_ALL[@]}"}"; do
            [ "$path" = "$name" ] && found=1 && break
        done
        if [ "$found" -eq 0 ]; then
            die "extra_tools: unknown tool '$name'. Available: ${EXTRA_TOOLS_ALL[*]:-none} (add scripts to $SANDBOX_ROOT/base/tools/)"
        fi
        path="$SANDBOX_ROOT/base/tools/$name.sh"
        [ -f "$path" ] || die "extra_tools: script not found: $path"
        TOOLS_SEL+=("$name")
        TOOL_FILES+=("$path")
    done

    if [ "${#TOOL_FILES[@]}" -gt 0 ]; then
        # Hash sorted names + contents so script order doesn't change the tag.
        local hash_input="" n
        while IFS= read -r n; do
            hash_input+="$n"$'\n'
            hash_input+="$(cat "$SANDBOX_ROOT/base/tools/$n.sh")"
        done < <(printf '%s\n' "${TOOLS_SEL[@]}" | sort)
        # sha256sum is Linux/coreutils; shasum is the macOS fallback.
        # 12 hex chars — long enough to make accidental tag collisions unlikely.
        if command -v sha256sum >/dev/null 2>&1; then
            TOOLS_SUFFIX="$(printf '%s' "$hash_input" | sha256sum | cut -c1-12)"
        else
            TOOLS_SUFFIX="$(printf '%s' "$hash_input" | shasum -a 256 | cut -c1-12)"
        fi
    fi
}

# Build an extra-tools layer image on top of a parent image: COPY the
# selected scripts into the image and run them as root at build time.
# Requires resolve_extra_tools to have run (TOOL_FILES non-empty).
build_extra_tools_layer() {
    local parent_image="$1"
    local tag="$2"
    local context="${3:-$SANDBOX_ROOT/base}"

    [ "${#TOOL_FILES[@]}" -gt 0 ] ||
        die "build_extra_tools_layer called with no tools selected"

    # Skip if already built (REBUILD=1 forces it). image_exists prepends
    # IMAGE_PREFIX itself, so strip the prefix from the full tag first —
    # passing it through would double the prefix and the check always miss.
    if [[ "${REBUILD:-0}" != "1" ]]; then
        if [[ "$tag" == "$IMAGE_PREFIX:"* ]]; then
            image_exists "${tag#"$IMAGE_PREFIX:"}" && return 0
        else
            image_exists "$tag" && return 0
        fi
    fi

    # Generate the layer Containerfile inside a subshell with an immediate
    # EXIT trap: the temp file is removed even when the build aborts, and the
    # trap dies with the subshell instead of overriding the caller's trap.
    (
        tmpfile=$(mktemp "${TMPDIR:-/tmp}/agent-sandbox-extra-tools.XXXXXX")
        trap 'rm -f "$tmpfile"' EXIT

        # Generate the layer Containerfile: copy only the validated scripts and
        # run each one with bash -euo pipefail as root, then drop back to agent.
        # The for loop with || exit 1 fails fast — no ';' chaining between
        # scripts, so the first failing tool fails the build.
        local run_cmd f base
        run_cmd='set -euo pipefail; for f in'
        for f in "${TOOL_FILES[@]}"; do
            base="$(basename "$f")"
            run_cmd+=" /opt/agent-sandbox/extra-tools/$base"
        done
        run_cmd+='; do bash -euo pipefail "$f" || exit 1; done'

        {
            echo "FROM $parent_image"
            echo "USER root"
            printf 'COPY'
            for f in "${TOOL_FILES[@]}"; do
                printf ' tools/%s' "$(basename "$f")"
            done
            printf ' /opt/agent-sandbox/extra-tools/\n'
            echo "RUN bash -c '$run_cmd'"
            # Harness/stack installs may create root-owned dirs in $HOME; the
            # tools layer must not leave them (or /opt) root-owned.
            echo "RUN chown -R agent:agent /home/agent /opt/agent-sandbox"
            echo "USER agent"
        } > "$tmpfile"

        echo "Building $tag with $RUNTIME ..."
        if ! "$RUNTIME" build \
            -t "$tag" \
            -f "$tmpfile" \
            "$context"
        then
            die "Extra tools image build failed: $tag (check the selected base/tools/*.sh scripts)"
        fi
    )
}
