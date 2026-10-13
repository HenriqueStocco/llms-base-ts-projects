# Quality tooling, hooks, and CI

Detail for section 15 of `AGENTS.md`, with examples and procedures. It does not contradict the core; on divergence, the core prevails. The original numbering is kept.

## 15. Quality tooling, hooks, and CI

**Behavioral** rules (this document) guide the agent's judgment. **Automated** checks enforce what a machine can verify. One does not replace the other.

### 15.1 Controls and policy

Controls proportional to the project:

- Formatter and lint.
- Typecheck.
- Targeted tests and full suite.
- Build.
- Detection of unused code and dependencies.
- Dependency version consistency.
- Secret scanner.
- Dependency and vulnerability checks.
- Git hooks.
- Agent hooks, when the platform offers them.
- Mandatory CI on protected branches.
- Safeguards for destructive commands and sensitive operations.

None of these controls is a universal capability. Verify what the project and the platform actually offer; do not assume a hook or a check exists.

Policy:

- Do not silently skip an essential check.
- Do not use a bypass mechanism (skipping hooks, disabling a rule, marking a test as ignored) to get around a failure without authorization and a recorded justification.
- Do not declare a check passed without evidence: the command executed and the result obtained. Do not pretend a tool is installed.
- During development, prefer targeted, fast checks. Do not run a very slow suite at every step when a more efficient check is adequate. Run the applicable full checks before concluding, or record why it was not possible.
- Treat CI as the source of reproducible validation.
- Treat local hooks as complementary protection, not as a substitute for CI. Every critical validation also exists in CI.

### 15.2 Default tools

Preferred default for the projects covered by this document, unless there is proven technical incompatibility or an explicit project decision:

| Tool | Role |
| --- | --- |
| **Biome** | Formatting and lint. |
| **Knip** | Unused files, exports, and dependencies. |
| **Syncpack** | Dependency version consistency across manifests (monorepos or several manifests). |
| **Bash scripts + Git hooks** | Automated validations and commit message standardization, versioned in `.githooks/` (15.7). |
| **Dependabot** | Dependency updates and security alerts on GitHub (15.12). One update bot per repository. |

This default does not authorize ignoring the existing stack. Before installing or configuring any tool:

1. Check whether it is already installed.
2. Examine existing versions, scripts, and configuration.
3. Consult the documentation compatible with the installed version. Commands, flags, and options change between major versions.
4. Check compatibility with Bun, Node.js, the package manager, and the repository layout.
5. Reuse and complete the existing configuration when appropriate.
6. Do not duplicate functionality without concrete benefit.
7. Do not silently replace another established tool.
8. Record every relevant technical exception.

Rules:

- Do not invent option, script, flag, or command names. Use the manifest scripts and the help of the installed version.
- If a tool is incompatible with the project, document the reason and propose the minimum necessary alternative.
- The absence of a default tool is a finding of class **Attention** (4.3). Installing or configuring tooling is its own task: do not do it as a side effect of another task.

### 15.3 Biome

Default formatting and lint tool, when the installed version supports the project's languages.

- Configure rules that are consistent and compatible with the project.
- Use check mode, without writing, in CI.
- Apply automatic fixes only to files in the intended scope, and review the result.
- Do not ignore a rule without a written justification next to the suppression.
- Do not disable a rule globally to solve a localized problem.
- Do not run competing formatters on the same files.
- Do not claim the project is formatted without running the corresponding check.
- The visual separation in section 9 remains mandatory where the formatter does not enforce it.
- Locally use `biome check --staged --files-ignore-unknown=true --no-errors-on-unmatched`; in CI use `biome ci`. `--staged` is for local use and `--changed` is for CI.
- Enable `vcs` (`enabled`, `clientKind`, `useIgnoreFile`, `defaultBranch`): they default to off, and `--changed` fails without `defaultBranch`.
- Monorepo: one root `biome.json`; nested configs use `"extends": "//"`. Keep `$schema` matching the installed version.

### 15.4 Knip

Configure it respecting the project's entry points, plugins, and particularities.

- Run it after relevant changes to files, exports, scripts, or dependencies.
- Investigate every result before removing anything. The absence of a static reference does not prove something is unnecessary.
- Check entry points, dynamic imports, framework conventions and plugins, manifest scripts, CI configuration, and indirectly referenced files.
- Do not remove a file or export merely because the analysis did not detect usage.
- Do not do mass removal without reviewing the impact.
- Do not ignore false positives globally. Prefer localized, documented, and justified exceptions. First fix entry patterns, plugins, and generated files; `ignore*` options are a last resort.
- Reassess the ignore rules when the code changes.
- Needs Node.js >= 20.19 or Bun. With workspaces, configure each workspace (root `"."` included): the root `entry`/`project` are ignored. Exit codes: 0 clean, 1 issues, 2 error.
- Do not use `--fix` or `--allow-remove-files` in hooks or CI: they delete code and files.

### 15.5 Syncpack

Keep versions and manifests consistent. It is relevant only with more than one manifest (monorepo); do not add it to a single-package project. The goal is compatible consistency, not artificial uniformity.

- Check the existing configuration, version policies, internal dependencies, and necessary exceptions.
- Commands of the current major (v14 and later): `syncpack lint`, `syncpack fix`, `syncpack format --check`. The v13 names (`list-mismatches`, `fix-mismatches`) no longer exist; `lint` does not check formatting.
- Run the consistency check after dependency changes, and refresh the lockfile with the package manager after `fix`.
- Fix divergences intentionally, assessing compatibility before synchronizing.
- Do not blindly align incompatible versions.
- Do not update a dependency just to eliminate a numeric difference.
- Do not change the lockfile without understanding the cause and reviewing the result.
- Preserve justified exceptions for tools, runtimes, or packages that require distinct versions.

### 15.6 Bash scripts

Centralize validations and commit rules in versioned Bash scripts, when the environment is compatible. Hooks call the scripts; they do not duplicate long commands.

Each script:

- Has a clear name and responsibility.
- Fails with a nonzero exit code and propagates errors from the commands it runs.
- Emits clear messages, on the error output, saying what failed and how to fix it.
- Does not print secrets.
- Does not run a destructive command as a side effect of a validation.
- Is predictable and reproducible: same input, same result.
- Checks that the commands it depends on exist and reports when they are missing.
- Does not depend on the working directory: it resolves paths from the repository root.
- Uses consistent quoting and handles paths with spaces.
- Has a test when it contains relevant logic.

Reference platform: Linux, across more than one distribution. Scripts work without changes on different distributions (for example, Ubuntu and Arch):

- Declare `#!/usr/bin/env bash` and run with Bash. Do not depend on `/bin/sh`: on some distributions it is Bash, on others it is a more restricted shell.
- Do not assume the same version of Bash, utilities, or installed tools: rolling-release and fixed-release distributions diverge.
- Do not call the system package manager (`apt`, `pacman`, etc.) or depend on distribution-specific paths. Check whether the command exists and report what is missing.
- macOS and Windows become a requirement only when the project declares support; in that case, declare the requirements and avoid extensions exclusive to the GNU utilities.

Example — message validation for the `commit-msg` hook, with Conventional Commits 1.0.0 types as the default pattern (adapt it to the project's convention). Git passes the path of the file containing the message as the first argument, and the hook also runs on `git merge`:

```bash
#!/usr/bin/env bash
set -euo pipefail

message_file="${1:?usage: commit-msg <message-file>}"
types='build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test'
pattern="^(${types})(\([^()[:space:]]+\))?!?: .+"
skip='^(Merge |Revert "|Reapply "|fixup! |squash! |amend! )'

subject=""
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  subject="$line"
  break
done < "$message_file"

if [[ "$subject" =~ $skip ]]; then
  exit 0
fi

if [[ ! "$subject" =~ $pattern ]]; then
  echo "Invalid commit message: \"$subject\"" >&2
  echo "Expected format: <type>(<scope>): <description>" >&2
  exit 1
fi
```

Types, scopes, and exceptions follow the project's convention (17.3). The specification calls the scope a noun, so the pattern accepts any scope without spaces or parentheses; tighten it only by project decision. Regex validation is the default; commitlint is justified only for richer rules (it needs Node.js >= 22.12).

### 15.7 Git hooks

When the project adopts local hooks, use them for the events below; verify what exists first (15.1). Check the real semantics of each hook in the documentation of Git and of the hook manager in use before configuring it.

| Hook | When | Responsibility |
| --- | --- | --- |
| `commit-msg` | After the message is written, before the commit is created. | Validate the message. |
| `pre-commit` | Before the commit is created. | Fast checks on the staged content. |
| `pre-push` | Before the push transfers data to the remote. | Additional checks before publishing. |

**`commit-msg`**

- Validate the actual message received from Git, with no fixed text in the script.
- Apply the project's commit convention (17.3).
- Reject an empty or non-conforming message, with a clear and actionable error.

**`pre-commit`**

- Check the files that will be committed, not the entire repository.
- Check or apply formatting and lint, according to the project's policy.
- Detect forbidden files, improper artifacts, and secrets, when a tool is available.
- Do not run the E2E suite or slow checks on every commit.
- If the formatter modifies files, ensure the commit contains the formatted result **without** including changes the user had not staged. Partially staged files require care: adding the whole file back would include what was deliberately left out.

**`pre-push`**

- Run typecheck, targeted tests, and other checks relevant to the project.
- Identify the destination (Git passes the remote and the refs to the hook) and block publications that violate the project's rules.
- Do not deploy or perform additional unexpected operations.
- Do not repeat slow checks that CI already runs in full.

**`push`**

Git **does not have** a client hook called `push`, and `pre-push` is not equivalent to it. On the client, the hook for the publishing stage is `pre-push`. Hooks that run after the data is received (`pre-receive`, `update`, `post-receive`) run on the server and depend on the hosting provider.

- If the project's hook manager or platform offers its own event for this stage, document its purpose and do not duplicate what `pre-push` already covers.
- If it does not, do not invent the hook. Put the safeguard in `pre-push` and in CI, and report the limitation.

**Installation and maintenance**

- Check how hooks are installed and activated. Git only runs hooks in the effective hooks directory: the default one, inside the `.git` directory and not versioned, or the one set by `core.hooksPath`.
- A versioned hooks directory has no effect until it is activated, by the hook manager or by `core.hooksPath`.
- Default without a runtime dependency: versioned Bash hooks in `.githooks/`, activated with `git config core.hooksPath .githooks`. That setting is local to each clone, so provide a setup script (or call it from a `prepare` script when there is a `package.json`) and document it. Commit the executable bit (`git update-index --chmod=+x`): a hook without it is ignored.
- `core.hooksPath` replaces `.git/hooks`, and it conflicts with managers that set it (Husky, for example). Do not mix two mechanisms.
- Hooks are bypassable with `--no-verify`, so every critical check also runs in CI (15.1).
- Ensure reproducible installation for new collaborators and document how to reinstall and validate.
- Do not bypass hooks to finish a task faster (15.1).

### 15.8 Hook security

Hooks execute arbitrary code on each collaborator's machine and are part of the attack surface.

- Inspect the scripts and tools executed by hooks.
- Do not introduce unverified remote download or installation during a commit or push.
- Do not store credentials in scripts.
- Do not use `eval` or dynamic execution of untrusted content.
- Avoid excessive permissions.
- Do not change files outside the scope of the commit.
- Do not mask errors or return artificial success.
- Avoid loops, recursive installations, and duplicate execution of the same checks.
- Emit a clear message when a dependency is missing.
- Do not disable hooks as a permanent solution to a configuration error: fix the configuration.

### 15.9 Essential repository files

Assess presence and adequacy. Create or update only what is applicable and necessary.

**`.gitignore`**

- Ignore installed dependencies, generated artifacts, caches, logs, and local files that must not be versioned.
- Ignore `.env` and other credential files, keeping an explicit exception for safe templates, such as `.env.example`.
- Do not ignore files needed for build or development. Avoid broad patterns that hide important files.
- Adding a rule does not remove an already tracked file from the index: that requires specific handling.
- Do not remove tracked files without understanding the impact. A secret that has already been committed remains in the history and must be treated as compromised.

**`.gitattributes`**

- Define consistent line-ending normalization when necessary (for example, `text=auto`) and mark binary formats.
- Avoid spurious diffs across operating systems. Preserve binaries and special formats.
- Assess the impact before applying mass normalization to existing files: it changes many files at once.
- Do not impose indiscriminate rules on all files.

**`.claudeignore` and agent context exclusion files**

- Check, in the documentation of the tool and version in use, whether the file is recognized and what its semantics are. Do not assume support.
- It is not a universal mechanism or a security barrier. Never rely on it to protect secrets.
- When recognized, use it to reduce irrelevant context: artifacts, generated files, caches, and local data.
- Do not exclude files essential to understanding the project.
- Distinguish three things: a file ignored by Git, a file omitted from the agent's context, and a file protected by access control.
- If the tool does not recognize the file, report the limitation and use the mechanism officially supported by it (read-deny or permission rules, for example).

**Other files**

Inspect, according to the stack: manifest (`package.json`), lockfile of the package manager in use, `tsconfig.json`, Biome, Knip, and Syncpack configurations, validation scripts, hook configuration and installation, CI configuration.

### 15.10 Tooling implementation order

When adopting or updating tooling in an existing project:

1. Inspect existing tools, versions, scripts, and hooks.
2. Identify what already works and what is missing.
3. Define the necessary checks and contracts.
4. Reuse the valid configurations.
5. Implement the minimum changes.
6. Validate scripts and configurations.
7. Run the local checks.
8. Inspect the diff and the Git state.
9. Document exceptions, limitations, and relevant commands.

Do not replace the project's entire configuration to get a visually uniform standard.

When the task is only to create or update instructions for agents, do not install dependencies, do not configure real hooks, and do not modify the other files of the project.

### 15.11 Rules verifiable by tool

When the project has the corresponding control, use it as evidence. When configuring a new project, prefer to automate:

| Rule | Possible check |
| --- | --- |
| Strict typing (6) | Compiler `strict` mode; additional strictness options per project. |
| Explicit `any`, non-null assertion, suppressions (6.1, 6.4) | Lint rules (Biome). |
| Empty `catch`, unhandled promises (11) | Lint rules, depending on installed version support. |
| Formatting (9) | Formatter in check mode (Biome). |
| File names (8.1) | Naming lint rule, if available. |
| Unused code, exports, and dependencies (8.4, 14) | Knip. |
| Divergent versions across manifests (7.1, 14) | Syncpack. |
| Circular dependencies and boundaries between packages (7) | Dependency graph analysis or lint rules. |
| Commit message (17.3) | `commit-msg` hook. |
| Secrets in commits (5.2) | Secret scanner, in `pre-commit` and in CI. GitHub secret scanning is not available on user-owned private repositories (Free/Pro) and is paid on organization private repositories: do not rely on it. |
| Vulnerable dependencies (14) | `bun audit --audit-level=high` or `npm audit --audit-level=high` in CI; Dependabot alerts on GitHub (15.12). |
| Behavior (12) | Tests in `pre-push` (targeted) and in CI (full). |

The rest depends on diff review.

### 15.12 Dependency updates and supply chain

- **One update bot per repository.** Default on GitHub: Dependabot (`.github/dependabot.yml`, `version: 2`, ecosystems `bun` or `npm`, plus `github-actions`), with a `cooldown`. Renovate is the alternative when grouping, automerge, or action pinning is needed; never run both for version updates. Bun support requires the text `bun.lock` (not `bun.lockb`). Dependabot alerts are free on private repositories; keep them on.
- **Single lockfile**, committed. CI installs with the lockfile frozen: `bun ci` / `bun install --frozen-lockfile`, or `npm ci`. Bun does not enable frozen mode automatically in CI.
- **Install scripts policy:** Bun does not run dependency lifecycle scripts by default except a curated list; use `trustedDependencies` to control it. npm 10/11 (bundled with Node.js 22/24/26) runs them by default, so set `ignore-scripts=true`; npm 12 blocks them unless the root `allowScripts` policy allows. Prefer an age gate on new releases (`minimumReleaseAge` in Bun, `cooldown` in Dependabot).
- **Pin the toolchain:** `packageManager` (for example `"bun@<version>"`) and, for Node.js, `.nvmrc` or `.node-version` or `engines`. Corepack is not bundled with Node.js 25 and later. Use a supported Node.js line (Node.js 20 reached end of life on 2026-04-30; 24 is LTS).
- Update this section when a tool's major version changes: versions and flags were verified on 2026-10-13.

