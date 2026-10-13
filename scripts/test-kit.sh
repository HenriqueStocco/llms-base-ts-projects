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

# Source path (relative to the source root) of an installed file, for the
# runtime given as $2 (bun or pnpm).
source_of() {
  case "$1" in
    .githooks/*) echo "templates/githooks/${1#.githooks/}" ;;
    scripts/setup-hooks.sh) echo "templates/scripts/setup-hooks.sh" ;;
    biome.json) echo "templates/biome.json" ;;
    knip.json) echo "templates/knip.json" ;;
    .github/dependabot.yml) echo "templates/github/dependabot-$2.yml" ;;
    .github/workflows/ci.yml) echo "templates/github/workflows/ci-$2.yml" ;;
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

  run "$INSTALLER" --dry-run --tooling --runtime bun "$target"
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

  run "$INSTALLER" --tooling --runtime bun "$target"
  expect_rc 0 "install exits 0"
  expect_out '^Runtime: bun \(--runtime\)$' "install prints the runtime and its source"

  local missing=0
  while IFS= read -r path; do
    if [[ ! -f "$target/$path" ]]; then
      fail "installed $path" "missing"
      missing=1
      continue
    fi

    source_path="$SOURCE_ROOT/$(source_of "$path" bun)"

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

  run "$INSTALLER" --tooling --runtime bun "$target"
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

  run "$INSTALLER" --tooling --runtime bun "$target"
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

  run "$INSTALLER" --tooling --runtime bun "$SOURCE_ROOT/."
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

# push_case <description> <expected-exit> <expected-manager|none> <packageManager|-> [lockfile...]
# Builds a package.json with a verify script, runs pre-push and checks that only
# the expected package manager was executed.
push_case() {
  local description="$1"
  local expected_rc="$2"
  local expected_manager="$3"
  local field="$4"
  shift 4

  local repo="$TMP_ROOT/pre-push-repo"
  local field_line=""
  local lockfile other

  if [[ "$field" != "-" ]]; then
    field_line=$'  "packageManager": "'"$field"$'",\n'
  fi

  reset_push_repo "$repo"
  printf '{\n  "name": "x",\n%s  "scripts": {\n    "test": "x",\n    "verify": "y"\n  }\n}\n' "$field_line" > "$repo/package.json"

  for lockfile in "$@"; do
    touch "$repo/$lockfile"
  done

  pre_push_run "$repo"
  expect_rc "$expected_rc" "pre-push, $description: exits $expected_rc"

  if [[ "$expected_manager" == "none" ]]; then
    expect_no_out 'FAKE' "pre-push, $description: runs no package manager"
    return 0
  fi

  expect_out "^FAKE $expected_manager run verify\$" "pre-push, $description: runs '$expected_manager run verify'"

  for other in bun pnpm npm yarn; do
    if [[ "$other" != "$expected_manager" ]]; then
      expect_no_out "FAKE $other( |\$)" "pre-push, $description: does not run $other"
    fi
  done
}

test_pre_push() {
  echo "-- pre-push"
  local repo manager
  repo="$(new_dir pre-push-repo)"
  init_repo "$repo"

  # Fake package managers: they only echo their arguments and never touch anything.
  mkdir -p "$TMP_ROOT/fake-bin"
  for manager in bun pnpm npm yarn; do
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

  # Detection from the "packageManager" field, without any lockfile.
  push_case "packageManager bun@, no lockfile" 0 bun "bun@1.2.3"
  push_case "packageManager pnpm@, no lockfile" 0 pnpm "pnpm@10.22.0"

  # Detection from the lockfile.
  push_case "bun.lock" 0 bun - bun.lock
  push_case "bun.lockb" 0 bun - bun.lockb
  push_case "pnpm-lock.yaml" 0 pnpm - pnpm-lock.yaml

  # The packageManager field wins over a conflicting lockfile.
  push_case "packageManager pnpm@ over bun.lock" 0 pnpm "pnpm@10.22.0" bun.lock
  push_case "packageManager bun@ over pnpm-lock.yaml" 0 bun "bun@1.2.3" pnpm-lock.yaml

  # Unsupported markers.
  push_case "packageManager npm@" 1 none "npm@10.9.0"
  expect_out 'unsupported package manager \(this kit supports Bun and pnpm\)' "pre-push, packageManager npm@: prints the unsupported message"
  push_case "packageManager yarn@" 1 none "yarn@4.5.0"
  push_case "packageManager npm@ over bun.lock" 1 none "npm@10.9.0" bun.lock
  push_case "package-lock.json" 1 none - package-lock.json
  expect_out 'unsupported package manager \(this kit supports Bun and pnpm\)' "pre-push, package-lock.json: prints the unsupported message"
  push_case "npm-shrinkwrap.json" 1 none - npm-shrinkwrap.json
  push_case "yarn.lock" 1 none - yarn.lock
  expect_out 'unsupported package manager \(this kit supports Bun and pnpm\)' "pre-push, yarn.lock: prints the unsupported message"

  # Verify script but nothing to detect.
  push_case "no packageManager and no lockfile" 1 none -
  expect_out 'no package manager was detected' "pre-push, nothing detectable: prints the detection error"

  # Minified package.json.
  reset_push_repo "$repo"
  printf '{"packageManager":"pnpm@10.22.0","scripts":{"verify":"y"}}\n' > "$repo/package.json"
  pre_push_run "$repo"
  expect_rc 0 "pre-push, minified package.json: exits 0"
  expect_out '^FAKE pnpm run verify$' "pre-push, minified package.json: runs 'pnpm run verify'"
}

# runtime_target <name> <package.json content|-> [file...]
# Creates a fresh target directory with the given package.json and empty files.
runtime_target() {
  local dir="$TMP_ROOT/runtime-$1"
  local content="$2"
  local file
  shift 2

  rm -rf "$dir"
  mkdir -p "$dir"

  if [[ "$content" != "-" ]]; then
    printf '%s\n' "$content" > "$dir/package.json"
  fi

  for file in "$@"; do
    touch "$dir/$file"
  done

  echo "$dir"
}

# expect_runtime_files <target> <runtime> <description>
expect_runtime_files() {
  local target="$1"
  local runtime="$2"
  local description="$3"

  if cmp -s "$SOURCE_ROOT/templates/github/workflows/ci-$runtime.yml" "$target/.github/workflows/ci.yml" &&
    cmp -s "$SOURCE_ROOT/templates/github/dependabot-$runtime.yml" "$target/.github/dependabot.yml"; then
    pass "$description: installs the $runtime CI and Dependabot templates"
  else
    fail "$description: installs the $runtime CI and Dependabot templates"
  fi
}

# expect_target_unchanged <target> <description>
expect_target_unchanged() {
  if [[ -z "$(ls -A "$1")" ]]; then
    pass "$2: wrote nothing"
  else
    fail "$2: wrote nothing" "target is not empty"
  fi
}

test_runtime_detection() {
  echo "-- install: runtime selection"
  local target

  target="$(runtime_target pm-bun '{"packageManager": "bun@1.2.3"}')"
  run "$INSTALLER" --tooling "$target"
  expect_rc 0 "packageManager bun@: exits 0"
  expect_out '^Runtime: bun \(packageManager\)$' "packageManager bun@: detected as bun"
  expect_runtime_files "$target" bun "packageManager bun@"

  target="$(runtime_target pm-pnpm '{"name":"x","packageManager":"pnpm@10.22.0"}')"
  run "$INSTALLER" --tooling "$target"
  expect_rc 0 "packageManager pnpm@ (minified): exits 0"
  expect_out '^Runtime: pnpm \(packageManager\)$' "packageManager pnpm@: detected as pnpm"
  expect_runtime_files "$target" pnpm "packageManager pnpm@"

  target="$(runtime_target lock-bun '-' bun.lock)"
  run "$INSTALLER" --tooling "$target"
  expect_rc 0 "bun.lock: exits 0"
  expect_out '^Runtime: bun \(lockfile\)$' "bun.lock: detected as bun"
  expect_runtime_files "$target" bun "bun.lock"

  target="$(runtime_target lock-bunb '{"name":"x"}' bun.lockb)"
  run "$INSTALLER" --tooling "$target"
  expect_out '^Runtime: bun \(lockfile\)$' "bun.lockb: detected as bun"
  expect_runtime_files "$target" bun "bun.lockb"

  target="$(runtime_target lock-pnpm '{"name":"x"}' pnpm-lock.yaml)"
  run "$INSTALLER" --tooling "$target"
  expect_out '^Runtime: pnpm \(lockfile\)$' "pnpm-lock.yaml: detected as pnpm"
  expect_runtime_files "$target" pnpm "pnpm-lock.yaml"

  target="$(runtime_target override '{"packageManager": "bun@1.2.3"}' bun.lock)"
  run "$INSTALLER" --tooling --runtime pnpm "$target"
  expect_rc 0 "--runtime override: exits 0"
  expect_out '^Runtime: pnpm \(--runtime\)$' "--runtime overrides the detection"
  expect_runtime_files "$target" pnpm "--runtime override"

  target="$(runtime_target equals '-')"
  run "$INSTALLER" --tooling --runtime=bun "$target"
  expect_out '^Runtime: bun \(--runtime\)$' "--runtime=bun form is accepted"

  target="$(runtime_target dry '{"packageManager": "pnpm@10.22.0"}')"
  run "$INSTALLER" --dry-run --tooling "$target"
  expect_rc 0 "dry-run with detection: exits 0"
  expect_out '^Runtime: pnpm \(packageManager\)$' "dry-run prints the detected runtime"
  expect_out '^WOULD-COPY +\.github/workflows/ci\.yml$' "dry-run lists the CI workflow"

  # Undetectable or unsupported: exit 2 and write nothing.
  target="$(runtime_target none '-')"
  run "$INSTALLER" --tooling "$target"
  expect_rc 2 "undetectable runtime exits 2"
  expect_out '--runtime bun\|pnpm' "undetectable runtime asks for --runtime bun|pnpm"
  expect_out 'npm and Yarn are not supported' "undetectable runtime says npm and Yarn are unsupported"
  expect_target_unchanged "$target" "undetectable runtime"

  target="$(runtime_target npm-pm '{"packageManager": "npm@10.9.0"}')"
  run "$INSTALLER" --tooling "$target"
  expect_rc 2 "packageManager npm@ only: exits 2"
  expect_out 'npm and Yarn are not supported' "packageManager npm@ only: explains the limitation"

  # Same strictness as the pre-push hook: an unsupported packageManager wins
  # over a lockfile that would otherwise select Bun.
  target="$(runtime_target npm-pm-bun-lock '{"packageManager": "npm@10.9.0"}' bun.lock)"
  run "$INSTALLER" --tooling "$target"
  expect_rc 2 "packageManager npm@ over bun.lock: exits 2"
  expect_no_out '^(NEW|WOULD-COPY) ' "packageManager npm@ over bun.lock: copies nothing"

  target="$(runtime_target npm-lock '-' package-lock.json)"
  run "$INSTALLER" --tooling "$target"
  expect_rc 2 "package-lock.json only: exits 2"

  target="$(runtime_target yarn-lock '-' yarn.lock)"
  run "$INSTALLER" --tooling "$target"
  expect_rc 2 "yarn.lock only: exits 2"

  target="$(runtime_target yarn-pm '{"packageManager": "yarn@4.5.0"}' yarn.lock)"
  run "$INSTALLER" --tooling "$target"
  expect_rc 2 "packageManager yarn@ with yarn.lock: exits 2"
  expect_no_out '^(NEW|WOULD-COPY) ' "packageManager yarn@ with yarn.lock: copies nothing"

  target="$(runtime_target invalid '-')"
  run "$INSTALLER" --tooling --runtime npm "$target"
  expect_rc 2 "--runtime npm exits 2"

  run "$INSTALLER" --tooling --runtime yarn "$target"
  expect_rc 2 "--runtime yarn exits 2"

  run "$INSTALLER" --tooling --runtime "" "$target"
  expect_rc 2 "--runtime with an empty value exits 2"

  run "$INSTALLER" --tooling --runtime
  expect_rc 2 "--runtime without a value exits 2"
  expect_target_unchanged "$target" "invalid --runtime"

  # --runtime without --tooling is accepted and ignored with a warning.
  target="$(runtime_target no-tooling '-')"
  run "$INSTALLER" --runtime bun "$target"
  expect_rc 0 "--runtime without --tooling: exits 0"
  expect_out 'warning: --runtime is ignored without --tooling' "--runtime without --tooling: warns"
  expect_no_out '^Runtime:' "--runtime without --tooling: prints no Runtime line"

  if [[ -e "$target/.github" || -e "$target/.githooks" ]]; then
    fail "--runtime without --tooling: installs no tooling files"
  else
    pass "--runtime without --tooling: installs no tooling files"
  fi

  # Core kit only: no runtime needed.
  target="$(runtime_target core-only '-')"
  run "$INSTALLER" "$target"
  expect_rc 0 "core kit without --tooling needs no runtime"
}

# file_has <file> <fixed-string> <description>
file_has() {
  if grep -qF -- "$2" "$1"; then
    pass "$(basename "$1") contains $3"
  else
    fail "$(basename "$1") contains $3" "missing: $2"
  fi
}

# file_lacks <file> <fixed-string> <description>
file_lacks() {
  if grep -qF -- "$2" "$1"; then
    fail "$(basename "$1") does not contain $3" "found: $2"
  else
    pass "$(basename "$1") does not contain $3"
  fi
}

test_templates() {
  echo "-- templates"
  local github="$SOURCE_ROOT/templates/github"
  local workflow

  for workflow in "$github/workflows/ci-bun.yml" "$github/workflows/ci-pnpm.yml"; do
    file_has "$workflow" "biome ci" "biome ci"
    file_has "$workflow" "knip" "knip"
    file_has "$workflow" "tsc --noEmit" "tsc --noEmit"
    file_has "$workflow" "concurrency:" "concurrency"
    file_has "$workflow" "--frozen-lockfile" "--frozen-lockfile"
    file_has "$workflow" "permissions:" "permissions"
    file_has "$workflow" "actions/checkout@v7" "actions/checkout@v7"
    file_has "$workflow" "name: ci" "workflow name ci"
    file_has "$workflow" "quality:" "quality job"
    file_has "$workflow" "audit:" "audit job"

    # "pnpm" contains "npm", so match npm, npx and yarn only as whole words.
    if grep -Eq '(^|[^[:alnum:]_-])(npm|npx|yarn)([^[:alnum:]_-]|$)|package-lock' "$workflow"; then
      fail "$(basename "$workflow") has no npm, npx, yarn or package-lock"
    else
      pass "$(basename "$workflow") has no npm, npx, yarn or package-lock"
    fi
  done

  file_has "$github/workflows/ci-bun.yml" "actions/cache@v6" "actions/cache@v6"
  file_has "$github/workflows/ci-bun.yml" "~/.bun/install/cache" "the Bun cache path"
  file_has "$github/workflows/ci-pnpm.yml" "cache: pnpm" "cache: pnpm"
  file_has "$github/workflows/ci-pnpm.yml" "pnpm/action-setup@v6" "pnpm/action-setup@v6"

  file_has "$github/dependabot-bun.yml" 'package-ecosystem: "bun"' "the bun ecosystem"
  file_lacks "$github/dependabot-bun.yml" 'package-ecosystem: "npm"' "the npm ecosystem"
  file_has "$github/dependabot-pnpm.yml" 'package-ecosystem: "npm"' "the npm ecosystem"
  file_lacks "$github/dependabot-pnpm.yml" 'package-ecosystem: "bun"' "the bun ecosystem"

  local old
  for old in "$github/dependabot.yml" "$github/workflows/ci.yml"; do
    if [[ -e "$old" ]]; then
      fail "old template ${old#"$SOURCE_ROOT"/} no longer exists"
    else
      pass "old template ${old#"$SOURCE_ROOT"/} no longer exists"
    fi
  done
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
  test_runtime_detection
  test_templates

  echo
  echo "Summary: $PASSED passed, $FAILED failed."

  if [[ "$FAILED" -ne 0 ]]; then
    exit 1
  fi
}

main "$@"
