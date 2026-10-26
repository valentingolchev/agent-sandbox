#!/usr/bin/env bash
# Interactive pickers. AGENT_IMAGE/HARNESS skip a prompt; the config value
# preselects the default answer. Expects: CONFIG, STACK_PARENT, STACKS,
# IMAGE (for the harness status line).
#
# Uses fzf for a nice fuzzy-search TUI when available (and a TTY is present),
# falls back to a numbered menu otherwise.

# All supported harnesses. Keep in sync with resolve_harness and the
# harness install scripts (base/harness/*.sh).
HARNESSES=(claude opencode vibe pi manual)

has_fzf() {
    command -v fzf >/dev/null 2>&1
}

has_tty() {
    # Check for a controlling terminal. /dev/tty works inside command
    # substitution $(...), where fd 1 is a pipe but /dev/tty is still the
    # controlling terminal. fzf opens /dev/tty directly for its TUI.
    [[ -r /dev/tty && -w /dev/tty ]]
}

# pick_one TITLE DEFAULT ITEM... : print the chosen ITEM on stdout.
# Accepts a menu number, an item name, or empty/EOF for DEFAULT (fallback mode).
# With fzf: fuzzy search, default item pre-selected, Escape returns default.
pick_one() {
    local title="$1" default="$2" choice i item
    shift 2
    local items=("$@")

    # --- fzf mode ---
    if has_fzf && has_tty; then
        # Put default first so it's the initial highlight
        local -a ordered=("$default")
        for item in "${items[@]}"; do
            [[ "$item" == "$default" ]] || ordered+=("$item")
        done

        local selected
        selected="$(printf '%s\n' "${ordered[@]}" | fzf \
            --prompt="❯ " \
            --header="$title" \
            --header-first \
            --height=50% \
            --layout=reverse \
            --border=rounded \
            --pointer="►" \
            --marker="✓ " \
            --color='header:#7aa2f7,prompt:#7aa2f7,pointer:#7aa2f7,marker:#9ece6a' \
            --info=inline \
            2>/dev/null)" || true

        # Escape or fzf failure -> default
        echo "${selected:-$default}"
        return 0
    fi

    # --- numbered menu fallback ---
    echo "$title" >&2
    i=1
    for choice in "${items[@]}"; do
        if [[ "$choice" == "$default" ]]; then
            echo "  $i) $choice (default)" >&2
        else
            echo "  $i) $choice" >&2
        fi
        i=$((i + 1))
    done
    while :; do
        printf "Choice [1-%d, Enter for %s]: " "${#items[@]}" "$default" >&2
        read -r choice || choice=""   # EOF: accept the default
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#items[@]} )); then
            echo "${items[$((choice - 1))]}"
            return 0
        fi
        case "$choice" in
            "") echo "$default"; return 0 ;;
        esac
        for item in "${items[@]}"; do
            if [[ "$choice" == "$item" ]]; then
                echo "$item"
                return 0
            fi
        done
        echo "Invalid choice, try again." >&2
    done
}

resolve_harness() {
    case "$1" in
        claude|opencode|vibe|pi) echo "$1" ;;
        *) echo "/bin/bash" ;;
    esac
}

is_valid_harness() {
    case "$1" in
        claude|opencode|vibe|pi|manual) return 0 ;;
        *) return 1 ;;
    esac
}

choose_stack() {
    local requested="${AGENT_IMAGE:-}" choice
    if [[ -n "$requested" ]]; then
        choice="${requested#agent-sandbox:}"
        choice="${choice%%:*}"
        # Strip harness suffix if present (e.g., python-claude → python).
        # Only strip if the result is a known stack (safe for lua-nvim, web-cljs, etc.)
        local h stripped
        for h in claude opencode vibe pi; do
            stripped="${choice%-${h}}"
            if [[ -n "${STACK_PARENT[$stripped]+x}" ]]; then
                choice="$stripped"
                break
            fi
        done
        [[ -n "${STACK_PARENT[$choice]+x}" ]] ||
            die "Unknown stack '$requested'. Known: ${STACKS[*]}"
        echo "$choice"
        return 0
    fi

    local default="${CONFIG[stack]:-base}"
    [[ -n "${STACK_PARENT[$default]+x}" ]] ||
        die "Unknown stack '$default' (in $CONFIG_FILE). Known: ${STACKS[*]}"
    pick_one "Select stack:" "$default" "${STACKS[@]}"
}

choose_harness() {
    local requested="${HARNESS:-}"
    if [[ -n "$requested" ]]; then
        # Normalize legacy aliases
        case "$requested" in
            bash|shell) requested="manual" ;;
        esac
        is_valid_harness "$requested" ||
            die "Unknown harness '$requested' (${HARNESSES[*]})."
        echo "$requested"
        return 0
    fi

    local default="${CONFIG[harness]:-manual}"
    is_valid_harness "$default" ||
        die "Unknown harness '$default' (in $CONFIG_FILE) (${HARNESSES[*]})."

    pick_one "Select harness:" "$default" "${HARNESSES[@]}"
}
