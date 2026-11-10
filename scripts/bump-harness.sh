#!/usr/bin/env bash
# Bump or check pinned harness versions in base/harness/*.sh
# Usage: ./scripts/bump-harness.sh [--check|<harness>|all [<version>]]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_DIR="$ROOT/base/harness"

# Simple die for standalone script
die() { echo "ERROR: $*" >&2; exit 1; }

# Validate version format (also blocks sed injection)
validate_version() {
  local v="$1"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+[0-9A-Za-z.+-]*$ ]] || die "Invalid version format: $v"
}

# Extract pinned version from harness file
pinned_version() {
  local file="$1"
  sed -n 's/^# Version pinned: \([^ ]*\).*/\1/p' "$file"
}

# Fetch latest version for a harness
get_latest_version() {
  local harness="$1"
  local url
  case "$harness" in
    claude) url="https://registry.npmjs.org/@anthropic-ai/claude-code/latest" ;;
    opencode) url="https://registry.npmjs.org/@opencode/cli/latest" ;;
    pi) url="https://registry.npmjs.org/@earendil-works/pi-coding-agent/latest" ;;
    vibe) url="https://pypi.org/pypi/mistral-vibe/json" ;;
    *)
      die "Unknown harness: $harness. Valid: claude opencode pi vibe"
      ;;
  esac
  curl -fsSL --max-time 30 "$url" | \
    sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | \
    head -n 1
}

# Bump a single harness file to new version
bump_harness_file() {
  local file="$1"
  local new="$2"
  local old
  old="$(pinned_version "$file")"
  validate_version "$old"
  validate_version "$new"

  # Escape only . and + for sed BRE
  local old_esc
  old_esc="$(printf '%s' "$old" | sed 's/[.+]/\\&/g')"

  # Rewrite file with portable sed (GNU/BSD)
  sed -i \
    -e "s/pinned: ${old_esc}\([^0-9A-Za-z.+-]\)/pinned: ${new}\1/g" \
    -e "s/pinned: ${old_esc}$/pinned: ${new}/g" \
    -e "s/@${old_esc}\([^0-9A-Za-z.+-]\)/@${new}\1/g" \
    -e "s/@${old_esc}$/@${new}/g" \
    -e "s/==${old_esc}\([^0-9A-Za-z.+-]\)/==${new}\1/g" \
    -e "s/==${old_esc}$/==${new}/g" \
    "$file"
}

# Print usage
usage() {
  cat <<'EOF'
Usage:
  ./scripts/bump-harness.sh [--check|<harness>|all [<version>]]

Commands:
  --check               Check all harnesses against latest upstream
  <harness>             Bump single harness to latest
  all                   Bump all harnesses to latest
  <harness> <version>   Bump to explicit version (e.g., 9.9.9)

Examples:
  ./scripts/bump-harness.sh --check
  ./scripts/bump-harness.sh claude
  ./scripts/bump-harness.sh all
  ./scripts/bump-harness.sh vibe 4.0.0

After a successful bump, rebuild with: REINSTALL_HARNESS=1 agent-sandbox
EOF
}

# Parse args
MODE="check"
HARNESS_ARG=""
VERSION_ARG=""

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--check" ]]; then
  MODE="check"
  shift
elif [[ "${#}" -ge 1 ]]; then
  HARNESS_ARG="$1"
  shift
  if [[ "${#}" -ge 1 ]]; then
    VERSION_ARG="$1"
    MODE="explicit"
    shift
  elif [[ "$HARNESS_ARG" == "all" ]]; then
    MODE="all"
  else
    MODE="latest"
  fi
fi

if [[ "${#}" -gt 0 ]]; then
  usage
  exit 1
fi

# Discover harnesses
declare -a harnesses=() files=()
for f in "$HARNESS_DIR"/*.sh; do
  [[ -f "$f" ]] || continue
  bn="$(basename "$f" .sh)"
  harnesses+=("$bn")
  files+=("$f")
done

# Check or bump
if [[ "$MODE" == "check" ]]; then
  outdated=0
  for i in "${!harnesses[@]}"; do
    hn="${harnesses[$i]}"
    fn="${files[$i]}"
    old="$(pinned_version "$fn")"
    latest="$(get_latest_version "$hn")"
    if [[ "$old" != "$latest" ]]; then
      echo "$hn: $old -> $latest (outdated)"
      outdated=1
    else
      echo "$hn: $old (current)"
    fi
  done
  if [[ $outdated -ne 0 ]]; then
    exit 1
  fi
export -f validate_version bump_harness_file pinned_version get_latest_version
else
  # Bump one or all
  if [[ "$MODE" == "explicit" ]]; then
    validate_version "$VERSION_ARG"
    for i in "${!harnesses[@]}"; do
      if [[ "${harnesses[$i]}" == "$HARNESS_ARG" ]]; then
        bump_harness_file "${files[$i]}" "$VERSION_ARG"
        echo "Bumped ${harnesses[$i]} to $VERSION_ARG"
        break
      fi
    done
  elif [[ "$MODE" == "latest" ]]; then
    latest="$(get_latest_version "$HARNESS_ARG")"
    bump_harness_file "$HARNESS_DIR/${HARNESS_ARG}.sh" "$latest"
    echo "Bumped ${HARNESS_ARG} to $latest"
  elif [[ "$MODE" == "all" ]]; then
    for hn in "${harnesses[@]}"; do
      latest="$(get_latest_version "$hn")"
      bump_harness_file "$HARNESS_DIR/${hn}.sh" "$latest"
      echo "Bumped $hn to $latest"
    done
  fi
  echo "Rebuild images: REINSTALL_HARNESS=1 agent-sandbox"
fi

# Validate script syntax
if ! bash -n "$0"; then
  die "bash -n failed on $0"
fi

if command -v shellcheck >/dev/null 2>&1; then
  if ! shellcheck --severity=warning "$0"; then
    die "shellcheck failed on $0"
  fi
fi
