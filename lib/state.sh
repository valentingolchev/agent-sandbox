#!/usr/bin/env bash
# Harness state snapshot management.
#
# Strategy: Copy-on-write with host-wins config sync.
#   - Host state is NEVER modified (no sync-back)
#   - Snapshot accumulates chat history, session data
#   - On [K]eep: host configs overwrite snapshot configs (host wins)
#   - On [R]eset: wipe snapshot, copy fresh configs from host
#   - On [D]iscard: wipe snapshot, start empty
#
# Per-harness mapping: config files (synced from host) vs state dirs (snapshot only).
# Usage: source this file, then call setup_harness_state <harness> <snapshot-dir>

# Harness → config files (synced from host, host wins on conflict)
# Format: "config_path:container_path" (relative to $HOME and /home/agent)
declare -A HARNESS_CONFIG=(
    [claude]=".claude.json:.claude.json"
    [opencode]=".config/opencode/config.json:.config/opencode/config.json"
    [vibe]=".vibe/config.json:.vibe/config.json"
    [pi]=".config/pi/settings.json:.config/pi/settings.json"
)

# Harness → state directories (snapshot only, NOT synced from host, NOT synced back)
# These accumulate chat history, sessions, caches across runs.
declare -A HARNESS_STATE_DIRS=(
    [claude]=".claude:.claude"
    [opencode]=".config/opencode/state:.config/opencode/state .local/share/opencode:.local/share/opencode"
    [vibe]=".vibe/sessions:.vibe/sessions"
    [pi]=".pi/sessions:.pi/sessions .config/pi/cache:.config/pi/cache"
)

# Copy config files from host to snapshot (host wins — overwrites).
# Only copies files that exist on the host.
sync_configs_from_host() {
    local harness="$1"
    local snapshot_dir="$2"
    local configs="${HARNESS_CONFIG[$harness]:-}"
    [ -n "$configs" ] || return 0

    local entry host_rel container_rel src dest
    for entry in $configs; do
        host_rel="${entry%%:*}"
        container_rel="${entry#*:}"
        src="$HOME/$host_rel"
        dest="$snapshot_dir/$host_rel"

        if [ -f "$src" ]; then
            mkdir -p "$(dirname "$dest")"
            cp "$src" "$dest"
        fi
    done
}

# Initialize state directories in snapshot (empty on reset/discard).
init_state_dirs() {
    local harness="$1"
    local snapshot_dir="$2"
    local state_dirs="${HARNESS_STATE_DIRS[$harness]:-}"
    [ -n "$state_dirs" ] || return 0

    local entry host_rel container_rel dest
    for entry in $state_dirs; do
        host_rel="${entry%%:*}"
        dest="$snapshot_dir/$host_rel"
        mkdir -p "$dest"
    done
}

# Build mount arguments for the snapshot.
# Outputs: STATE_ARGS array with -v mounts.
build_state_mounts() {
    local harness="$1"
    local snapshot_dir="$2"
    local configs="${HARNESS_CONFIG[$harness]:-}"
    local state_dirs="${HARNESS_STATE_DIRS[$harness]:-}"

    STATE_ARGS=()

    # Mount config files
    local entry host_rel container_rel src dest
    for entry in $configs; do
        host_rel="${entry%%:*}"
        container_rel="${entry#*:}"
        dest="$snapshot_dir/$host_rel"

        if [ -f "$dest" ]; then
            STATE_ARGS+=(-v "$dest:/home/agent/$container_rel:rw")
        fi
    done

    # Mount state directories
    for entry in $state_dirs; do
        host_rel="${entry%%:*}"
        container_rel="${entry#*:}"
        dest="$snapshot_dir/$host_rel"

        if [ -d "$dest" ]; then
            STATE_ARGS+=(-v "$dest:/home/agent/$container_rel:rw")
        fi
    done
}

# Check if snapshot has any content.
snapshot_exists() {
    local snapshot_dir="$1"
    [ -d "$snapshot_dir" ] && [ -n "$(ls -A "$snapshot_dir" 2>/dev/null)" ]
}

# Main entry: setup harness state snapshot.
# Args: harness, snapshot_dir, action (keep|reset|discard|prompt)
# Sets: STATE_ARGS array for container mounts.
setup_harness_state() {
    local harness="$1"
    local snapshot_dir="$2"
    local action="${3:-prompt}"

    # No state mapping for this harness (e.g., manual)
    [ -n "${HARNESS_CONFIG[$harness]:-}" ] || [ -n "${HARNESS_STATE_DIRS[$harness]:-}" ] || return 0

    mkdir -p "$snapshot_dir"

    # Determine action
    if [ "$action" = "prompt" ] && snapshot_exists "$snapshot_dir"; then
        echo
        echo "Previous $harness state found in snapshot."
        read -r -p "  [K]eep (sync configs from host) / [R]eset (fresh from host) / [D]iscard (empty)? [K] " choice
        case "${choice:-K}" in
            [Rr]*) action="reset" ;;
            [Dd]*) action="discard" ;;
            *)     action="keep" ;;
        esac
    elif [ "$action" = "prompt" ]; then
        action="reset"  # First run
    fi

    case "$action" in
        keep)
            # Sync configs from host (host wins), preserve state dirs
            sync_configs_from_host "$harness" "$snapshot_dir"
            ;;
        reset)
            # Wipe and start fresh
            rm -rf "$snapshot_dir"
            mkdir -p "$snapshot_dir"
            sync_configs_from_host "$harness" "$snapshot_dir"
            init_state_dirs "$harness" "$snapshot_dir"
            ;;
        discard)
            # Wipe and start empty (no host configs)
            rm -rf "$snapshot_dir"
            mkdir -p "$snapshot_dir"
            init_state_dirs "$harness" "$snapshot_dir"
            ;;
    esac

    # Build mount arguments
    build_state_mounts "$harness" "$snapshot_dir"
}
