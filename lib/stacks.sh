#!/usr/bin/env bash
# Stack registry and image building. Stacks are auto-discovered from the
# filesystem: any subdirectory of stacks/ with a Containerfile is a stack.
# The parent stack is parsed from the Containerfile's FROM line
# (e.g. "FROM agent-sandbox:clojure" -> parent is "clojure").
#
# Expects: SANDBOX_ROOT, REBUILD (optional), die() from common.sh,
#          build_image/image_exists from runtime.sh
# Provides: STACKS (array), STACK_PARENT (assoc array), context_for, ensure_image

declare -A STACK_PARENT=()
STACKS=()

# Discover stacks from stacks/*/Containerfile and parse parent from FROM line.
discover_stacks() {
    STACK_PARENT=([base]="")
    STACKS=(base)

    local dir name containerfile parent
    for dir in "$SANDBOX_ROOT"/stacks/*/; do
        [ -d "$dir" ] || continue
        name="$(basename "$dir")"
        containerfile="$dir/Containerfile"
        [ -f "$containerfile" ] || continue

        # Parse parent from: FROM agent-sandbox:<parent>
        parent=""
        if grep -q '^FROM agent-sandbox:' "$containerfile" 2>/dev/null; then
            parent="$(grep -m1 '^FROM agent-sandbox:' "$containerfile" |
                      sed 's/^FROM agent-sandbox://' | awk '{print $1}')"
        fi

        STACK_PARENT[$name]="$parent"
        STACKS+=("$name")
    done

    # Topological sort: parents before children (for menu display order).
    local -a sorted=()
    local -A added=([base]=1)
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

ensure_image() {
    local name="$1" parent="${STACK_PARENT[$1]}"
    [[ -z "$parent" ]] || ensure_image "$parent"
    if [[ "${REBUILD:-0}" == "1" ]] || ! image_exists "$name"; then
        [[ -f "$(context_for "$name")/Containerfile" ]] || {
            die "No Containerfile for stack '$name' in $(context_for "$name")."
        }
        build_image "$name" "$(context_for "$name")"
    fi
}

# Initialize on source
discover_stacks
