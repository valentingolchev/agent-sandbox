#!/usr/bin/env bash
# validate.sh — validate agent-sandbox config file.
# Provides: validate_config() — call after sourcing common.sh, config.sh, stacks.sh, prompts.sh

err()  { echo "  ✗ $*" >&2; VALIDATE_ERRORS=$((VALIDATE_ERRORS+1)); }
warn() { echo "  ! $*" >&2; VALIDATE_WARNINGS=$((VALIDATE_WARNINGS+1)); }
ok()   { echo "  ✓ $*"; }

# Valid keys
VALID_KEYS="stack harness memory cpus no_network persist_caches env_keys harness_state harness_state_action runtime init_script session_log"

# Valid harness_state_action values
VALID_ACTIONS="keep reset discard prompt"

validate_config() {
    local config_file="${1:-$CONFIG_FILE}"
    VALIDATE_ERRORS=0
    VALIDATE_WARNINGS=0

    echo "Validating: $config_file"
    echo

    # File exists and is readable
    if [ ! -f "$config_file" ]; then
        warn "Config file not found: $config_file (using defaults)"
        return 0
    fi
    if [ ! -r "$config_file" ]; then
        err "Config file not readable: $config_file"
        return 1
    fi

    # Parse and validate line by line
    local line_num=0
    local in_section=0
    local section_path=""
    local -A seen_keys=()

    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        line="$(trim "${line%$'\r'}")"

        # Skip empty lines and comments
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue

        # Section header
        if [[ "$line" == \[*\] ]]; then
            local sec="${line#\[}"
            sec="${sec%\]}"
            section_path="${sec/#\~/$HOME}"
            section_path="${section_path%/}"
            in_section=1

            # Validate section path
            if [ ! -d "$section_path" ]; then
                warn "Section path does not exist: $section_path (line $line_num)"
            fi
            continue
        fi

        # Key = value
        if [[ "$line" != *=* ]]; then
            err "Invalid syntax (expected key = value): $line (line $line_num)"
            continue
        fi

        local key value
        key="$(trim "${line%%=*}")"
        value="$(trim "${line#*=}")"

        # Check for duplicate keys
        local key_id="${in_section}:${section_path}:${key}"
        if [ -n "${seen_keys[$key_id]+x}" ]; then
            warn "Duplicate key '$key' (line $line_num)"
        fi
        seen_keys[$key_id]=1

        # Validate key name
        local valid_key=0
        for vk in $VALID_KEYS; do
            [ "$key" = "$vk" ] && valid_key=1 && break
        done
        if [ "$valid_key" -eq 0 ]; then
            err "Unknown key '$key' (line $line_num)"
            continue
        fi

        # Validate value per key
        case "$key" in
            stack)
                if [ -z "$value" ]; then
                    err "stack: empty value (line $line_num)"
                elif [ -z "${STACK_PARENT[$value]+x}" ]; then
                    err "stack: unknown stack '$value' (line $line_num). Known: ${STACKS[*]}"
                fi
                ;;
            harness)
                if ! is_valid_harness "$value"; then
                    err "harness: unknown harness '$value' (line $line_num). Known: ${HARNESSES[*]}"
                fi
                ;;
            memory)
                if ! [[ "$value" =~ ^[0-9]+[kmgt]?$ ]]; then
                    err "memory: invalid format '$value' (line $line_num). Expected: 8g, 512m, etc."
                fi
                ;;
            cpus)
                if ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    err "cpus: invalid format '$value' (line $line_num). Expected: 4, 2.5, etc."
                fi
                ;;
            no_network|persist_caches|harness_state)
                case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
                    ""|1|0|true|false|yes|no|on|off) ;;
                    *) err "$key: invalid boolean '$value' (line $line_num). Expected: true/false/1/0" ;;
                esac
                ;;
            harness_state_action)
                local valid_action=0
                for va in $VALID_ACTIONS; do
                    [ "$value" = "$va" ] && valid_action=1 && break
                done
                if [ "$valid_action" -eq 0 ]; then
                    err "harness_state_action: invalid value '$value' (line $line_num). Known: $VALID_ACTIONS"
                fi
                ;;
            runtime)
                if [ "$value" != "podman" ] && [ "$value" != "docker" ]; then
                    err "runtime: invalid value '$value' (line $line_num). Expected: podman or docker"
                fi
                ;;
            init_script)
                local init_path="${value/#\~/$HOME}"
                if [ -n "$value" ] && [ ! -f "$init_path" ]; then
                    err "init_script: file not found: $init_path (line $line_num)"
                fi
                ;;
            session_log)
                # Just check the directory is writable (or creatable)
                local log_path log_dir
                log_path="${value/#\~/$HOME}"
                log_dir="$(dirname "$log_path")"
                if [ -n "$value" ] && [ ! -d "$log_dir" ]; then
                    warn "session_log: directory does not exist: $log_dir (line $line_num)"
                fi
                ;;
            env_keys)
                # Space-separated list, just check it's not empty if set
                ;;
        esac
    done < "$config_file"

    # Summary
    echo
    if [ "$VALIDATE_ERRORS" -eq 0 ]; then
        if [ "$VALIDATE_WARNINGS" -gt 0 ]; then
            ok "Config valid (with $VALIDATE_WARNINGS warning(s)): $config_file"
        else
            ok "Config valid: $config_file"
        fi
        return 0
    else
        echo "  Found $VALIDATE_ERRORS error(s), $VALIDATE_WARNINGS warning(s)"
        return 1
    fi
}
