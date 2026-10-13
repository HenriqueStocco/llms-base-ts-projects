#!/usr/bin/env bash
# Copies the agent kit from this repository into another project.
#
# Usage: scripts/install-project.sh [--dry-run] [--tooling] [--runtime bun|pnpm] <target-dir>
#
# With --tooling, the CI workflow and the Dependabot config depend on the
# project's runtime (Bun or pnpm; npm and Yarn are not supported by these
# templates). It comes from --runtime, or is detected in the target from the
# "packageManager" field of package.json and then from the lockfile.
#
# Never overwrites or deletes anything in the target: files that already exist
# and differ are kept and reported as DIFFERENT. There is no --force.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

DRY_RUN=0
TOOLING=0
RUNTIME=""
RUNTIME_SOURCE=""
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
Usage: scripts/install-project.sh [--dry-run] [--tooling] [--runtime bun|pnpm] <target-dir>

  --dry-run          print what would happen; write nothing
  --tooling          also install the Git hooks, Biome/Knip configs, Dependabot,
                     CI workflow and .gitignore templates
  --runtime bun|pnpm runtime of the target project, used to pick the CI and
                     Dependabot templates. Without it, --tooling detects it from
                     "packageManager" in the target's package.json, then from
                     its lockfile. npm and Yarn are not supported.

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
    add_mapping "templates/github/dependabot-$RUNTIME.yml" ".github/dependabot.yml"
    add_mapping "templates/github/workflows/ci-$RUNTIME.yml" ".github/workflows/ci.yml"
    add_mapping "templates/gitignore" ".gitignore"
  fi
}

set_runtime_option() {
  case "$1" in
    bun | pnpm)
      RUNTIME="$1"
      RUNTIME_SOURCE="--runtime"
      ;;
    *)
      die_usage "invalid --runtime value: $1 (expected bun or pnpm)"
      ;;
  esac
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
      --runtime)
        if [[ $# -lt 2 ]]; then
          die_usage "--runtime needs a value (bun or pnpm)"
        fi
        set_runtime_option "$2"
        shift
        ;;
      --runtime=*)
        set_runtime_option "${1#--runtime=}"
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

# Prints the value of "packageManager" in the target's package.json (nothing if
# absent). Text-based on purpose: the installer must not require jq.
read_target_package_manager_field() {
  local package_json="$TARGET/package.json"
  local output

  if [[ ! -f "$package_json" ]]; then
    return 0
  fi

  output="$(sed -n 's/.*"packageManager"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$package_json")"
  printf '%s\n' "${output%%$'\n'*}"
}

# Sets RUNTIME and RUNTIME_SOURCE from the target project, or exits 2.
detect_runtime() {
  local field
  local unsupported=""
  field="$(read_target_package_manager_field)"

  case "$field" in
    bun@*)
      RUNTIME="bun"
      RUNTIME_SOURCE="packageManager"
      return 0
      ;;
    pnpm@*)
      RUNTIME="pnpm"
      RUNTIME_SOURCE="packageManager"
      return 0
      ;;
    "") ;;
    *)
      {
        echo "install-project: unsupported \"packageManager\" in package.json: $field"
        echo "  npm and Yarn are not supported by these templates (Bun and pnpm only). Pass --runtime bun|pnpm to override."
      } >&2
      exit 2
      ;;
  esac

  if [[ -f "$TARGET/bun.lock" || -f "$TARGET/bun.lockb" ]]; then
    RUNTIME="bun"
    RUNTIME_SOURCE="lockfile"
    return 0
  fi

  if [[ -f "$TARGET/pnpm-lock.yaml" ]]; then
    RUNTIME="pnpm"
    RUNTIME_SOURCE="lockfile"
    return 0
  fi

  local lockfile
  for lockfile in package-lock.json npm-shrinkwrap.json yarn.lock; do
    if [[ -f "$TARGET/$lockfile" ]]; then
      unsupported="${unsupported:+$unsupported, }$lockfile"
    fi
  done

  {
    echo "install-project: cannot detect the runtime of the target project."
    if [[ -n "$unsupported" ]]; then
      echo "  found only npm/Yarn markers: $unsupported"
    else
      echo "  no \"packageManager\" field in package.json and no bun.lock, bun.lockb or pnpm-lock.yaml."
    fi
    echo "  Pass --runtime bun|pnpm. npm and Yarn are not supported by these templates."
  } >&2
  exit 2
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

  if [[ "$TOOLING" -eq 1 ]]; then
    if [[ -z "$RUNTIME" ]]; then
      detect_runtime
    fi
  elif [[ -n "$RUNTIME" ]]; then
    echo "install-project: warning: --runtime is ignored without --tooling." >&2
  fi

  build_mappings
  check_sources

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Dry run: nothing will be written. Target: $TARGET"
  else
    echo "Installing into: $TARGET"
  fi

  if [[ "$TOOLING" -eq 1 ]]; then
    echo "Runtime: $RUNTIME ($RUNTIME_SOURCE)"
  fi

  local index
  for index in "${!SOURCES[@]}"; do
    process_file "${SOURCES[$index]}" "${DESTINATIONS[$index]}"
  done

  print_summary
}

main "$@"
