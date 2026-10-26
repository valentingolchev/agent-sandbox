#!/usr/bin/env bash
# Shared helpers: string trimming, boolean parsing, error exit.

trim() {
    local v="$1"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    printf '%s' "$v"
}

is_true() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

# A typo in a boolean must fail loudly, not silently mean "false".
validate_bool() {
    case "$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" in
        ""|1|0|true|false|yes|no|on|off) ;;
        *) die "Invalid $1 value '$2' (expected true/false/1/0)." ;;
    esac
}

die() {
    echo "$*" >&2
    exit 1
}
