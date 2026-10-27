#!/usr/bin/env bash
# Machine defaults from ~/.config/agent-sandbox/config.
# "key = value" lines; a [path] section overrides the globals for workspaces
# under that path (longest matching prefix wins, ~ = $HOME).
# Expects: WORKSPACE_DIR. Provides: CONFIG (after load_config), CONFIG_FILE.

CONFIG_FILE="${AGENT_SANDBOX_CONFIG:-$HOME/.config/agent-sandbox/config}"
declare -A CONFIG=()

load_config() {
    local line key value sec current="" best=""
    local -a sections=()
    local -A global=() pairs=()

    CONFIG=()
    [[ -r "$CONFIG_FILE" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(trim "${line%$'\r'}")"
        [[ -z "$line" || "$line" == \#* ]] && continue
        if [[ "$line" == \[*\] ]]; then
            sec="$(trim "${line#\[}")"
            sec="$(trim "${sec%\]}")"
            current="${sec/#\~/$HOME}"
            current="${current%/}"
            sections+=("$current")
            continue
        fi
        [[ "$line" != *=* ]] && continue
        key="$(trim "${line%%=*}")"
        value="$(trim "${line#*=}")"
        case "$key" in
            stack|harness|memory|cpus|no_network|persist_caches|env_keys|harness_state|runtime|init_script) ;;
            *) continue ;;
        esac
        if [[ -z "$current" ]]; then
            global[$key]="$value"
        else
            pairs["$current|$key"]="$value"
        fi
    done < "$CONFIG_FILE"

    for key in "${!global[@]}"; do
        CONFIG[$key]="${global[$key]}"
    done

    # Longest section path that is a prefix of the workspace dir wins.
    for sec in "${sections[@]}"; do
        if [[ "$WORKSPACE_DIR" == "$sec" || "$WORKSPACE_DIR" == "$sec"/* ]] &&
           (( ${#sec} > ${#best} )); then
            best="$sec"
        fi
    done
    for key in "${!pairs[@]}"; do
        if [[ "$key" == "$best|"* ]]; then
            # shellcheck disable=SC2034  # CONFIG is used by main script via sourcing
            CONFIG["${key##*|}"]="${pairs[$key]}"
        fi
    done
}
