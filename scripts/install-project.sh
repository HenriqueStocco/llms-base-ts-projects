#!/usr/bin/env bash
# Copies the agent kit from this repository into another project.
#
# Usage: scripts/install-project.sh [--dry-run] [--tooling] <target-dir>
#
# Never overwrites or deletes anything in the target: files that already exist
# and differ are kept and reported as DIFFERENT. There is no --force.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

DRY_RUN=0
TOOLING=0
TARGET=""

COUNT_NEW=0
COUNT_SAME=0
COUNT_DIFFERENT=0
COPIED_HOOKS=0

# Parallel arrays: SOURCES[i] (relative to the source root) -> DESTINATIONS[i]
# (relative to the target).
SOURCES=()
DESTINATIONS=()

usage() {
  cat >&2 << 'EOF'
Usage: scripts/install-project.sh [--dry-run] [--tooling] <target-dir>

  --dry-run   print what would happen; write nothing
  --tooling   also install the Git hooks, Biome/Knip configs, Dependabot,
              CI workflow and .gitignore templates

Existing files in the target are never overwritten or deleted.
EOF
}

die_usage() {
  echo "install-project: $1" >&2
  usage
  exit 2
}

add_mapping() {
  SOURCES+=("$1")
  DESTINATIONS+=("$2")
}

add_directory_files() {
  local source_dir="$1"
  local destination_dir="$2"
  local pattern="$3"
  local path

  for path in "$SOURCE_ROOT/$source_dir"/$pattern; do
    if [[ -f "$path" ]]; then
      add_mapping "$source_dir/$(basename "$path")" "$destination_dir/$(basename "$path")"
    fi
  done
}

build_mappings() {
  add_mapping "AGENTS.md" "AGENTS.md"
  add_mapping "CLAUDE.md" "CLAUDE.md"
  add_mapping ".claudeignore" ".claudeignore"
  add_mapping ".claude/settings.json" ".claude/settings.json"
  add_mapping ".claude/hooks/guard-paths.sh" ".claude/hooks/guard-paths.sh"
  add_mapping ".claude/hooks/test-guard.sh" ".claude/hooks/test-guard.sh"
  add_directory_files "docs/agents" "docs/agents" "*.md"

  if [[ "$TOOLING" -eq 1 ]]; then
    add_directory_files "templates/githooks" ".githooks" "*"
    add_mapping "templates/scripts/setup-hooks.sh" "scripts/setup-hooks.sh"
    add_mapping "templates/biome.json" "biome.json"
    add_mapping "templates/knip.json" "knip.json"
    add_mapping "templates/github/dependabot.yml" ".github/dependabot.yml"
    add_mapping "templates/github/workflows/ci.yml" ".github/workflows/ci.yml"
    add_mapping "templates/gitignore" ".gitignore"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --tooling)
        TOOLING=1
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        die_usage "unknown option: $1"
        ;;
      *)
        if [[ -n "$TARGET" ]]; then
          die_usage "only one target directory is allowed"
        fi
        TARGET="$1"
        ;;
    esac
    shift
  done

  if [[ $# -gt 0 ]]; then
    if [[ -n "$TARGET" || $# -gt 1 ]]; then
      die_usage "only one target directory is allowed"
    fi
    TARGET="$1"
  fi

  if [[ -z "$TARGET" ]]; then
    die_usage "missing <target-dir>"
  fi
}

resolve_target() {
  if [[ ! -d "$TARGET" ]]; then
    echo "install-project: target is not an existing directory: $TARGET" >&2
    exit 2
  fi

  TARGET="$(cd -P "$TARGET" && pwd -P)"

  if [[ "$TARGET" == "$SOURCE_ROOT" ]]; then
    echo "install-project: refusing to install into the source repository itself." >&2
    exit 2
  fi
}

check_sources() {
  local index
  local missing=0

  for index in "${!SOURCES[@]}"; do
    if [[ ! -f "$SOURCE_ROOT/${SOURCES[$index]}" ]]; then
      echo "install-project: source file missing: ${SOURCES[$index]}" >&2
      missing=1
    fi
  done

  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi
}

report() {
  printf '%-10s %s\n' "$1" "$2"
}

process_file() {
  local relative_source="$1"
  local relative_destination="$2"
  local source_path="$SOURCE_ROOT/$relative_source"
  local destination_path="$TARGET/$relative_destination"

  if [[ ! -e "$destination_path" && ! -L "$destination_path" ]]; then
    COUNT_NEW=$((COUNT_NEW + 1))

    if [[ "$relative_destination" == .githooks/* ]]; then
      COPIED_HOOKS=1
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
      report "WOULD-COPY" "$relative_destination"
      return 0
    fi

    mkdir -p "$(dirname "$destination_path")"
    cp -p "$source_path" "$destination_path"
    report "NEW" "$relative_destination"
    return 0
  fi

  if [[ -f "$destination_path" ]] && cmp -s "$source_path" "$destination_path"; then
    COUNT_SAME=$((COUNT_SAME + 1))
    report "SAME" "$relative_destination"
    return 0
  fi

  COUNT_DIFFERENT=$((COUNT_DIFFERENT + 1))
  report "DIFFERENT" "$relative_destination"
  printf '           kept as is; inspect with: diff -u %q %q\n' "$destination_path" "$source_path"
}

print_summary() {
  local new_label="new"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    new_label="would be copied"
  fi

  echo
  echo "Summary: $COUNT_NEW $new_label, $COUNT_SAME same, $COUNT_DIFFERENT different (kept untouched)."

  if [[ "$COPIED_HOOKS" -eq 1 ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "After a real install, run in the target: scripts/setup-hooks.sh"
    else
      echo "Run in the target to activate the Git hooks: scripts/setup-hooks.sh"
    fi
  fi

  echo "Reminder: the kit's .claude/hooks/guard-paths.sh needs jq installed."
}

main() {
  parse_args "$@"
  resolve_target
  build_mappings
  check_sources

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Dry run: nothing will be written. Target: $TARGET"
  else
    echo "Installing into: $TARGET"
  fi

  local index
  for index in "${!SOURCES[@]}"; do
    process_file "${SOURCES[$index]}" "${DESTINATIONS[$index]}"
  done

  print_summary
}

main "$@"
