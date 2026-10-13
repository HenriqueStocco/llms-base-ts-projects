#!/usr/bin/env bash
# Downloads the agent kit and installs it into a project, in one step.
#
# Usage:
#   scripts/bootstrap.sh [--repo <git-url>] [--ref <branch-or-tag>]
#                        [--dry-run] [--tooling] [--runtime bun|pnpm] [<target-dir>]
#
# Without a local clone (NvChad style):
#   curl -fsSL https://raw.githubusercontent.com/HenriqueStocco/my-claude-utils/main/scripts/bootstrap.sh \
#     | bash -s -- --tooling --runtime bun my-app
#
# Shallow-clones the kit into a temporary directory, drops its .git, runs the
# kit's own scripts/install-project.sh against the target, and removes the
# temporary directory. <target-dir> defaults to the current directory and is
# created when missing. Every installer rule applies: nothing in the target is
# overwritten or deleted. Requires git.
set -euo pipefail

DEFAULT_REPO="https://github.com/HenriqueStocco/llms-base-ts-projects.git"

REPO="$DEFAULT_REPO"
REF=""
TARGET="."
TARGET_GIVEN=0
DRY_RUN=0
CREATED_TARGET=0
KEEP_WORK=0
WORK=""

# Options this script does not own, in order, for install-project.sh.
INSTALLER_ARGS=()

usage() {
  cat >&2 << 'EOF'
Usage: bootstrap.sh [options] [<target-dir>]

  --repo <git-url>   kit repository (default: HenriqueStocco/my-claude-utils)
  --ref <name>       branch or tag to install from (default: the default branch)
  --dry-run          print what would happen; write nothing
  --tooling          also install Git hooks, Biome/Knip configs, Dependabot, CI
  --runtime bun|pnpm runtime of the target (needed with --tooling in a new
                     project; otherwise detected from package.json or lockfile)

<target-dir> defaults to the current directory and is created if missing.
Existing files in the target are never overwritten or deleted.
EOF
}

die() {
  echo "bootstrap: $1" >&2
  exit "${2:-1}"
}

need_value() {
  if [[ $# -lt 2 ]]; then
    usage
    die "$1 needs a value" 2
  fi
}

cleanup() {
  if [[ -n "$WORK" && "$KEEP_WORK" -eq 0 ]]; then
    rm -rf "$WORK"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        need_value "$@"
        REPO="$2"
        shift
        ;;
      --repo=*)
        REPO="${1#--repo=}"
        ;;
      --ref)
        need_value "$@"
        REF="$2"
        shift
        ;;
      --ref=*)
        REF="${1#--ref=}"
        ;;
      --runtime)
        need_value "$@"
        INSTALLER_ARGS+=("--runtime" "$2")
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        INSTALLER_ARGS+=("--dry-run")
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -*)
        # --tooling, --runtime=*, and unknown options: the installer decides.
        INSTALLER_ARGS+=("$1")
        ;;
      *)
        if [[ "$TARGET_GIVEN" -eq 1 ]]; then
          usage
          die "only one target directory is allowed" 2
        fi
        TARGET="$1"
        TARGET_GIVEN=1
        ;;
    esac
    shift
  done
}

clone_kit() {
  local clone_args=(--quiet --depth 1)

  if [[ -n "$REF" ]]; then
    clone_args+=(--branch "$REF")
  fi

  echo "Cloning $REPO${REF:+ ($REF)} ..."

  # GIT_TERMINAL_PROMPT=0: fail instead of waiting for credentials.
  if ! GIT_TERMINAL_PROMPT=0 git clone "${clone_args[@]}" -- "$REPO" "$WORK/kit"; then
    die "could not clone $REPO${REF:+ at $REF}"
  fi

  # Only kit files are ever copied, but no history should outlive this script.
  rm -rf "$WORK/kit/.git"

  if [[ ! -f "$WORK/kit/scripts/install-project.sh" ]]; then
    die "$REPO is not the agent kit (scripts/install-project.sh is missing)"
  fi
}

prepare_target() {
  if [[ -d "$TARGET" ]]; then
    return 0
  fi

  if [[ -e "$TARGET" ]]; then
    die "target exists and is not a directory: $TARGET" 2
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Target does not exist yet; previewing against an empty directory."
    TARGET="$WORK/empty"
    mkdir "$TARGET"
    return 0
  fi

  mkdir -p "$TARGET"
  CREATED_TARGET=1
}

run_installer() {
  local rc=0

  # Only stdout goes through tee; errors stay on stderr.
  bash "$WORK/kit/scripts/install-project.sh" "${INSTALLER_ARGS[@]}" "$TARGET" \
    | tee "$WORK/installer.log" || rc=$?

  if [[ "$rc" -ne 0 && "$CREATED_TARGET" -eq 1 ]]; then
    # Do not leave an empty directory behind after a refused install.
    rmdir "$TARGET" 2> /dev/null || true
  fi

  # The diff commands the installer printed point into the temporary copy, so
  # keep it when there is something to compare.
  if grep -q '^DIFFERENT ' "$WORK/installer.log"; then
    KEEP_WORK=1
    echo
    echo "Kept the kit copy so the diff commands above still work: $WORK/kit"
    echo "Remove it when done: rm -rf $WORK"
  fi

  return "$rc"
}

main() {
  parse_args "$@"

  if ! command -v git > /dev/null 2>&1; then
    die "git is required but was not found"
  fi

  WORK="$(mktemp -d)"
  trap cleanup EXIT

  clone_kit
  prepare_target
  run_installer
}

main "$@"
