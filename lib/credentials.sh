#!/usr/bin/env bash
# Credentials into the container: env vars passed by name (values never
# touch the image) and provider API keys from the OS keyring.
# Expects: CONFIG, ENV_KEYS (optional), HARNESS_CMD (set by main script).
# Provides: ENV_ARGS (via build_env_args), KEYRING_ENV_FILE (via
#           retrieve_keyring_secrets).
#
# Only API keys for the ACTIVE harness are forwarded — not all provider keys.

# Map harness → required API keys. Only these are forwarded by default.
# Users can add extra keys via ENV_KEYS env var or config env_keys.
declare -A HARNESS_ENV_KEYS=(
    [claude]="ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN"
    [vibe]="MISTRAL_API_KEY"
    [opencode]="OPENAI_API_KEY ANTHROPIC_API_KEY MISTRAL_API_KEY GEMINI_API_KEY GOOGLE_API_KEY"
    [pi]="OPENAI_API_KEY ANTHROPIC_API_KEY MISTRAL_API_KEY GEMINI_API_KEY GOOGLE_API_KEY GROQ_API_KEY OPENROUTER_API_KEY"
    [manual]=""
)

declare -A PASSED_ENV=()
ENV_ARGS=()

# Pass one env var by name. Second arg "warn" reports unset vars (only
# explicitly requested ones may be typos). PASSED_ENV deduplicates.
pass_env() {
    local key="$1"
    if [[ -z "${!key:-}" ]]; then
        [[ "${2:-}" == "warn" ]] && echo "Warning: env var $key not set, skipping" >&2
        return 0
    fi
    [[ -n "${PASSED_ENV[$key]+x}" ]] && return 0
    PASSED_ENV[$key]=1
    ENV_ARGS+=(-e "$key")
}

# Forward only the active harness's keys, then ENV_KEYS / env_keys extras.
build_env_args() {
    local key
    local harness_keys="${HARNESS_ENV_KEYS[${HARNESS_CMD:-manual}]:-}"

    for key in $harness_keys; do
        pass_env "$key"
    done
    for key in ${ENV_KEYS:-${CONFIG[env_keys]:-}}; do
        pass_env "$key" warn
    done
}

# API keys retrieved from the OS keyring: "env_var:service:harness" tuples.
# Only retrieved for the active harness.
#   vibe owns its key under "ai.mistral.vibe"
#   claude's key lives under the "agent-sandbox" service
# Store one with:
#   secret-tool store --label=<ENV_VAR> service agent-sandbox username <ENV_VAR>
declare -A HARNESS_KEYRING=(
    [claude]="ANTHROPIC_API_KEY:agent-sandbox"
    [vibe]="MISTRAL_API_KEY:ai.mistral.vibe"
    [opencode]=""
    [pi]=""
    [manual]=""
)
KEYRING_ENV_FILE=""

# Forward keyring-held keys for the active harness only, without exposing
# values on any command line: secret-tool -> mode-600 tmpfs file ->
# podman --env-file, removed on exit by the entry script. Skipped silently
# when secret-tool or the keyring is unavailable (headless hosts).
# Env vars already passed win.
retrieve_keyring_secrets() {
    local entry key service secret f
    command -v secret-tool >/dev/null 2>&1 || return 0
    [ -d "/run/user/$(id -u)" ] || return 0
    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "/run/user/$(id -u)/bus" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
    fi

    local harness_entry="${HARNESS_KEYRING[${HARNESS_CMD:-manual}]:-}"
    [ -n "$harness_entry" ] || return 0

    key="${harness_entry%%:*}"
    service="${harness_entry#*:}"

    # Skip if already passed via env var
    if [ -n "${!key:-}" ] || [ -n "${PASSED_ENV[$key]+x}" ]; then
        return 0
    fi

    secret="$(secret-tool lookup service "$service" username "$key" 2>/dev/null || true)"
    [ -n "$secret" ] || return 0

    f="$(mktemp "/run/user/$(id -u)/agent-sandbox-env.XXXXXX")" || return 0
    chmod 600 "$f"
    KEYRING_ENV_FILE="$f"
    printf '%s=%s\n' "$key" "$secret" >> "$f"
    PASSED_ENV[$key]=1
}
