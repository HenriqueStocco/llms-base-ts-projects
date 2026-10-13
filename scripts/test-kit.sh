#!/usr/bin/env bash
# Self-contained tests for scripts/install-project.sh and the templates/ hooks.
# Everything runs inside a temporary directory; the real repository is only read.
#
# Usage: scripts/test-kit.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
INSTALLER="$SOURCE_ROOT/scripts/install-project.sh"
HOOKS="$SOURCE_ROOT/templates/githooks"
SETUP_HOOKS="$SOURCE_ROOT/templates/scripts/setup-hooks.sh"

# Keep Git calls isolated from the user's and the system's configuration, and
# from any repository this script may have been started from (e.g. a hook).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
# Stop Git repository discovery from climbing out of the temporary directory.
export GIT_CEILING_DIRECTORIES="$TMP_ROOT"

PASSED=0
FAILED=0

# Filled by run(): exit code and combined stdout+stderr of the last command.
RC=0
OUT=""

pass() {
  PASSED=$((PASSED + 1))
  echo "ok   $1"
}

fail() {
  FAILED=$((FAILED + 1))
  echo "FAIL $1"
  if [[ -n "${2:-}" ]]; then
    echo "     $2"
  fi
}

run() {
  RC=0
  OUT="$("$@" 2>&1)" || RC=$?
}

# expect_rc <expected-code> <description>: checks the RC of the last run().
expect_rc() {
  if [[ "$RC" -eq "$1" ]]; then
    pass "$2"
  else
    fail "$2" "expected exit $1, got $RC; output: $OUT"
  fi
}

# expect_out <extended-regex> <description>: checks OUT of the last run().
expect_out() {
  if grep -Eq -- "$1" <<< "$OUT"; then
    pass "$2"
  else
    fail "$2" "output did not match /$1/: $OUT"
  fi
}

expect_no_out() {
  if grep -Eq -- "$1" <<< "$OUT"; then
    fail "$2" "output unexpectedly matched /$1/: $OUT"
  else
    pass "$2"
  fi
}

new_dir() {
  local dir="$TMP_ROOT/$1"
  mkdir -p "$dir"
  echo "$dir"
}

# Lists relative file paths and checksums of a directory tree, sorted.
snapshot() {
  (cd "$1" && find . -type f -exec cksum {} + | sort -k3)
}

# Lists the kit's files that the installer is expected to create.
expected_core_files() {
  local path
  echo "AGENTS.md"
  echo "CLAUDE.md"
  echo ".claudeignore"
  echo ".claude/settings.json"
  echo ".claude/hooks/guard-paths.sh"
  echo ".claude/hooks/test-guard.sh"
  for path in "$SOURCE_ROOT"/docs/agents/*.md; do
    echo "docs/agents/$(basename "$path")"
  done
}

expected_tooling_files() {
  local path
  for path in "$HOOKS"/*; do
    echo ".githooks/$(basename "$path")"
  done
  echo "scripts/setup-hooks.sh"
  echo "biome.json"
  echo "knip.json"
  echo ".github/dependabot.yml"
  echo ".github/workflows/ci.yml"
  echo ".gitignore"
}

# Source path (relative to the source root) of an installed file.
source_of() {
  case "$1" in
    .githooks/*) echo "templates/githooks/${1#.githooks/}" ;;
    scripts/setup-hooks.sh) echo "templates/scripts/setup-hooks.sh" ;;
    biome.json) echo "templates/biome.json" ;;
    knip.json) echo "templates/knip.json" ;;
    .github/dependabot.yml) echo "templates/github/dependabot.yml" ;;
    .github/workflows/ci.yml) echo "templates/github/workflows/ci.yml" ;;
    .gitignore) echo "templates/gitignore" ;;
    *) echo "$1" ;;
  esac
}

init_repo() {
  git -c init.defaultBranch=main init -q "$1"
}

test_dry_run() {
  echo "-- install: dry run"
  local target
  target="$(new_dir dry-run)"

  run "$INSTALLER" --dry-run --tooling "$target"
  expect_rc 0 "dry-run exits 0"
  expect_out '^WOULD-COPY +AGENTS\.md$' "dry-run prints WOULD-COPY"
  expect_no_out '^NEW ' "dry-run prints no NEW line"

  if [[ -z "$(ls -A "$target")" ]]; then
    pass "dry-run creates nothing"
  else
    fail "dry-run creates nothing" "target is not empty"
  fi
}

test_real_install() {
  echo "-- install: real run with --tooling"
  local target path source_path
  target="$(new_dir install)"

  run "$INSTALLER" --tooling "$target"
  expect_rc 0 "install exits 0"

  local missing=0
  while IFS= read -r path; do
    if [[ ! -f "$target/$path" ]]; then
      fail "installed $path" "missing"
      missing=1
      continue
    fi

    source_path="$SOURCE_ROOT/$(source_of "$path")"

    if ! cmp -s "$source_path" "$target/$path"; then
      fail "installed $path" "content differs from source"
      missing=1
    elif [[ -x "$source_path" && ! -x "$target/$path" ]]; then
      fail "installed $path" "lost the executable bit"
      missing=1
    elif [[ ! -x "$source_path" && -x "$target/$path" ]]; then
      fail "installed $path" "gained an executable bit"
      missing=1
    fi
  done < <(expected_core_files; expected_tooling_files)

  if [[ "$missing" -eq 0 ]]; then
    pass "every expected file exists, matches the source and keeps its exec bit"
  fi

  local hook
  for hook in commit-msg pre-commit pre-push; do
    if [[ -x "$target/.githooks/$hook" ]]; then
      pass "hook .githooks/$hook is executable"
    else
      fail "hook .githooks/$hook is executable"
    fi
  done

  expect_out 'scripts/setup-hooks\.sh' "install points to scripts/setup-hooks.sh"
  expect_out 'jq' "install reminds about jq"
}

test_idempotent() {
  echo "-- install: second run"
  local target before after
  target="$(new_dir install)"
  before="$(snapshot "$target")"

  run "$INSTALLER" --tooling "$target"
  expect_rc 0 "second run exits 0"
  expect_out '^SAME +AGENTS\.md$' "second run reports SAME"
  expect_no_out '^(NEW|DIFFERENT|WOULD-COPY) ' "second run reports only SAME"

  after="$(snapshot "$target")"
  if [[ "$before" == "$after" ]]; then
    pass "second run changes nothing"
  else
    fail "second run changes nothing" "snapshot changed"
  fi
}

test_existing_file_kept() {
  echo "-- install: existing differing file"
  local target saved
  target="$(new_dir differing)"
  saved="$TMP_ROOT/differing-original"

  mkdir -p "$target/.githooks"
  printf 'my own rules\n' > "$target/AGENTS.md"
  printf '#!/bin/sh\necho custom\n' > "$target/.githooks/pre-commit"
  cp "$target/AGENTS.md" "$saved"

  run "$INSTALLER" --tooling "$target"
  expect_rc 0 "exits 0 even with DIFFERENT files"
  expect_out '^DIFFERENT +AGENTS\.md$' "reports DIFFERENT for AGENTS.md"
  expect_out 'diff -u' "prints a diff -u command"
  expect_out '^NEW +CLAUDE\.md$' "still copies the missing files"

  if cmp -s "$saved" "$target/AGENTS.md"; then
    pass "differing AGENTS.md is byte-identical to the original"
  else
    fail "differing AGENTS.md is byte-identical to the original"
  fi

  if [[ "$(cat "$target/.githooks/pre-commit")" == $'#!/bin/sh\necho custom' ]]; then
    pass "differing .githooks/pre-commit is kept"
  else
    fail "differing .githooks/pre-commit is kept"
  fi
}

test_refusals() {
  echo "-- install: argument and target validation"
  local before after

  before="$(cd "$SOURCE_ROOT" && find . -path ./.git -prune -o -type f -print | sort | cksum)"

  run "$INSTALLER" "$SOURCE_ROOT"
  expect_rc 2 "refuses target == source root"

  run "$INSTALLER" --tooling "$SOURCE_ROOT/."
  expect_rc 2 "refuses target == source root via a dot path"

  after="$(cd "$SOURCE_ROOT" && find . -path ./.git -prune -o -type f -print | sort | cksum)"
  if [[ "$before" == "$after" ]]; then
    pass "refused runs left the source root untouched"
  else
    fail "refused runs left the source root untouched" "file listing changed"
  fi

  run "$INSTALLER" "$TMP_ROOT/does-not-exist"
  expect_rc 2 "refuses a nonexistent target"

  printf 'x\n' > "$TMP_ROOT/plain-file"
  run "$INSTALLER" "$TMP_ROOT/plain-file"
  expect_rc 2 "refuses a target that is a file"

  run "$INSTALLER"
  expect_rc 2 "no arguments exits 2"

  run "$INSTALLER" --bogus "$TMP_ROOT"
  expect_rc 2 "unknown option exits 2"
}

# Writes a message file and runs the commit-msg hook on it.
commit_msg_run() {
  local file="$TMP_ROOT/commit-msg.txt"
  printf '%b' "$1" > "$file"
  run "$HOOKS/commit-msg" "$file"
}

expect_message_accepted() {
  commit_msg_run "$1"
  expect_rc 0 "commit-msg accepts: $2"
}

expect_message_rejected() {
  commit_msg_run "$1"
  expect_rc 1 "commit-msg rejects: $2"
}

test_commit_msg() {
  echo "-- commit-msg"
  expect_message_accepted 'feat: add x\n' "feat: add x"
  expect_message_accepted 'fix(api): y\n' "fix(api): y"
  expect_message_accepted 'feat!: z\n' "feat!: z"
  expect_message_accepted 'feat(scope-x)!: z\n' "feat(scope-x)!: z"
  expect_message_accepted "Merge branch 'a'\n" "Merge branch 'a'"
  expect_message_accepted 'Revert "feat: x"\n' 'Revert "feat: x"'
  expect_message_accepted 'Reapply "feat: x"\n' 'Reapply "feat: x"'
  expect_message_accepted 'fixup! feat: x\n' "fixup! feat: x"
  expect_message_accepted 'squash! feat: x\n' "squash! feat: x"
  expect_message_accepted 'amend! feat: x\n' "amend! feat: x"
  expect_message_accepted '\n# a comment\n\nfeat: after blanks\n# trailing\n' "blank and comment lines before the subject"
  expect_message_accepted 'feat: no trailing newline' "subject without trailing newline"
  expect_message_accepted 'docs: x\n\nBody with: colons.\n' "subject followed by a body"

  expect_message_rejected 'bad message\n' "bad message"
  expect_message_rejected 'Feat: x\n' "Feat: x"
  expect_message_rejected 'feat:\n' "feat:"
  expect_message_rejected 'feat x\n' "feat x"
  expect_message_rejected 'feat: \n' "feat: (empty description)"
  expect_message_rejected 'feat():x\n' "feat():x"
  expect_message_rejected 'feat(a b): x\n' "feat(a b): x"
  expect_message_rejected 'oops: x\n' "unknown type"
  expect_message_rejected '' "empty file"
  expect_message_rejected '\n# only a comment\n' "only blank and comment lines"
  expect_out 'expected: <type>\(<scope>\): <description>' "failure prints the expected format"
  expect_out 'build chore ci docs feat fix perf refactor revert style test' "failure lists the allowed types"
}

test_pre_commit() {
  echo "-- pre-commit"
  local repo
  repo="$(new_dir pre-commit-repo)"
  init_repo "$repo"

  run bash -c 'cd "$1" && "$2"' _ "$repo" "$HOOKS/pre-commit"
  expect_rc 0 "no Biome config exits 0"
  expect_out 'pre-commit: no Biome config, skipped' "no Biome config prints the notice"

  printf '{}\n' > "$repo/biome.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$HOOKS/pre-commit"
  expect_rc 1 "biome.json without node_modules/.bin/biome exits 1"
  expect_out 'Install the dependencies' "missing biome binary explains how to fix it"

  mkdir -p "$repo/node_modules/.bin" "$repo/sub"
  printf '#!/usr/bin/env bash\necho "biome $*"\nexit 3\n' > "$repo/node_modules/.bin/biome"
  chmod +x "$repo/node_modules/.bin/biome"
  run bash -c 'cd "$1" && "$2"' _ "$repo/sub" "$HOOKS/pre-commit"
  expect_rc 3 "propagates the Biome exit code (run from a subdirectory)"
  expect_out 'biome check --staged --files-ignore-unknown=true --no-errors-on-unmatched' "passes the expected Biome arguments"

  rm "$repo/biome.json"
  printf '{}\n' > "$repo/biome.jsonc"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$HOOKS/pre-commit"
  expect_rc 3 "biome.jsonc is recognized"
}

# Runs pre-push in <repo> with the fake package managers first in PATH.
pre_push_run() {
  run bash -c 'cd "$1" && PATH="$2:$PATH" "$3"' _ "$1" "$TMP_ROOT/fake-bin" "$HOOKS/pre-push"
}

reset_push_repo() {
  find "$1" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
}

test_pre_push() {
  echo "-- pre-push"
  local repo manager lockfile
  repo="$(new_dir pre-push-repo)"
  init_repo "$repo"

  # Fake package managers: they only echo their arguments and never touch anything.
  mkdir -p "$TMP_ROOT/fake-bin"
  for manager in bun npm pnpm yarn; do
    printf '#!/usr/bin/env bash\necho "FAKE %s $*"\n' "$manager" > "$TMP_ROOT/fake-bin/$manager"
    chmod +x "$TMP_ROOT/fake-bin/$manager"
  done

  pre_push_run "$repo"
  expect_rc 0 "no package.json exits 0"

  printf '{\n  "scripts": {\n    "test": "x"\n  }\n}\n' > "$repo/package.json"
  touch "$repo/bun.lock"
  pre_push_run "$repo"
  expect_rc 0 "no verify script exits 0"
  expect_out 'no "verify" script' "no verify script prints a notice"
  expect_no_out 'FAKE' "no verify script runs nothing"

  printf '{\n  "scripts": {\n    "test": "x"\n  },\n  "dependencies": {\n    "verify": "1.0.0"\n  }\n}\n' > "$repo/package.json"
  pre_push_run "$repo"
  expect_no_out 'FAKE' "a dependency named verify is not a verify script"

  local entry
  for entry in "bun:bun.lock" "bun:bun.lockb" "npm:package-lock.json" "pnpm:pnpm-lock.yaml" "yarn:yarn.lock"; do
    manager="${entry%%:*}"
    lockfile="${entry#*:}"

    reset_push_repo "$repo"
    printf '{\n  "scripts": {\n    "test": "x",\n    "verify": "y"\n  }\n}\n' > "$repo/package.json"
    touch "$repo/$lockfile"

    pre_push_run "$repo"
    expect_rc 0 "$lockfile: exits 0"
    expect_out "^FAKE $manager run verify\$" "$lockfile: runs '$manager run verify'"
  done

  reset_push_repo "$repo"
  printf '{\n  "scripts": {\n    "verify": "y"\n  }\n}\n' > "$repo/package.json"
  pre_push_run "$repo"
  expect_rc 1 "verify script without a lockfile exits 1"
  expect_no_out 'FAKE' "verify script without a lockfile runs nothing"
}

test_setup_hooks() {
  echo "-- setup-hooks"
  local repo hook
  repo="$(new_dir setup-hooks-repo)"
  init_repo "$repo"

  run bash -c 'cd "$1" && "$2"' _ "$repo" "$SETUP_HOOKS"
  expect_rc 1 "fails without .githooks/"

  mkdir -p "$repo/.githooks" "$repo/deep/dir"
  cp "$HOOKS"/* "$repo/.githooks/"
  chmod -x "$repo/.githooks/"*

  run bash -c 'cd "$1" && "$2"' _ "$repo/deep/dir" "$SETUP_HOOKS"
  expect_rc 0 "runs from a subdirectory"

  if [[ "$(git -C "$repo" config --local --get core.hooksPath)" == ".githooks" ]]; then
    pass "core.hooksPath is .githooks"
  else
    fail "core.hooksPath is .githooks"
  fi

  for hook in "$repo"/.githooks/*; do
    if [[ -x "$hook" ]]; then
      pass "made $(basename "$hook") executable"
    else
      fail "made $(basename "$hook") executable"
    fi
  done

  expect_out 'update-index --chmod=\+x' "prints the exec-bit note"
  expect_out '\-\-no-verify' "prints the --no-verify note"

  run bash -c 'cd "$1" && "$2"' _ "$TMP_ROOT" "$SETUP_HOOKS"
  expect_rc 1 "fails outside a Git repository"
}

main() {
  test_dry_run
  test_real_install
  test_idempotent
  test_existing_file_kept
  test_refusals
  test_commit_msg
  test_pre_commit
  test_pre_push
  test_setup_hooks

  echo
  echo "Summary: $PASSED passed, $FAILED failed."

  if [[ "$FAILED" -ne 0 ]]; then
    exit 1
  fi
}

main "$@"
