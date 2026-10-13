# ai-dev-core-configs

Guidance base for AI coding agents (Claude Code first). It is **not a software project**: there is no application code here, only the instructions, protections, and templates that you copy into your own TypeScript projects (Bun or Node.js).

## What is in it

| Path            | Purpose                                                                                                                                                                                      |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AGENTS.md`     | Core engineering contract, loaded in every session. Rules only, no examples.                                                                                                                 |
| `CLAUDE.md`     | Claude Code entry point: imports `AGENTS.md` and adds the Claude-specific rules.                                                                                                             |
| `docs/agents/`  | Detail with examples and procedures, read on demand when a task touches the topic.                                                                                                           |
| `.claude/`      | Enforcement layer: `settings.json` (permissions) and `hooks/` (a `PreToolUse` guard that applies `.claudeignore` and blocks risky commands).                                                 |
| `.claudeignore` | Sensitive paths the agent must not read. Not a security barrier.                                                                                                                             |
| `templates/`    | Optional project tooling: Git hooks, Biome and Knip configs, Dependabot, CI workflow, `.gitignore`.                                                                                          |
| `scripts/`      | `bootstrap.sh` clones the kit and installs it in one step (also usable through `curl`); `install-project.sh` copies the kit into a project; `test-kit.sh` tests both and the hook templates. |

## How to use it

### Without cloning (`curl` or `wget`)

`scripts/bootstrap.sh` shallow-clones the kit into a temporary directory, drops its `.git`, runs the installer below against the target, and removes the temporary directory. It needs `git`. The target defaults to the current directory and is created if missing; it takes the same options as the installer, plus `--repo <git-url>` and `--ref <branch-or-tag>`.

```bash
# New project (a new project has no package.json, so pass --runtime with --tooling).
curl -fsSL https://raw.githubusercontent.com/HenriqueStocco/llms-base-ts-projects/main/scripts/bootstrap.sh \
  | bash -s -- --tooling --runtime bun my-app

# Same with wget, previewing only.
wget -qO- https://raw.githubusercontent.com/HenriqueStocco/llms-base-ts-projects/main/scripts/bootstrap.sh \
  | bash -s -- --dry-run --tooling --runtime pnpm my-app
```

Piping a download into `bash` runs it unread. To read it first: `curl -fsSLO <url>`, read `bootstrap.sh`, then `bash bootstrap.sh ...`. When files already exist and differ, the temporary copy is kept so the printed `diff -u` commands still work; its path is printed.

### From a local clone

```bash
# 1. Preview. Writes nothing.
scripts/install-project.sh --dry-run --tooling /path/to/project

# 2. Install. Add --tooling for the templates, omit it for the core kit only.
#    The runtime (bun or pnpm) is detected from package.json "packageManager",
#    then from the lockfile; pass --runtime bun|pnpm when it cannot be detected.
scripts/install-project.sh --tooling /path/to/project

# 3. In the target project, if the Git hooks were installed:
scripts/setup-hooks.sh
```

- The installer never overwrites or deletes anything in the target. Files that already exist and differ are reported as `DIFFERENT`, kept as they are, and come with a `diff -u` command so you can merge by hand. There is no `--force`.
- The installer does not run `git` in the target and does not install dependencies.
- The kit's hook (`.claude/hooks/guard-paths.sh`) needs `jq`.
- Scripts target Linux (Ubuntu and Arch) and use only Bash and tools both ship by default.
- Run `scripts/test-kit.sh` to check the bootstrap, the installer, and the hook templates (it works in a temporary directory).

## Changing the protections

The agent does not edit `.claude/**`, `.claudeignore`, or the user's settings, and does not work around this through Bash. When a protection needs to change, the agent writes the proposal in `proposals/claude/` and the user applies it. See `docs/agents/claude-code.md`.

## Limits

- Rules guide; hooks and permissions enforce. The model can still err or ignore a behavioral rule.
- `git commit --no-verify` and `git push --no-verify` bypass local hooks, so CI must repeat the same checks (`templates/github/workflows/ci.yml`).
- GitHub secret scanning and branch protection are not available on private repositories on the Free plan. Local hooks are the main guard there, and CI is the reproducible backup.
- The templates support Bun and pnpm only. npm and Yarn are not covered; a target whose `packageManager` is npm or Yarn is refused.
- CI installs with a frozen lockfile, so the lockfile (`bun.lock` or `pnpm-lock.yaml`) must be committed. A project without one fails the `quality` job until it is generated and committed.
- The CI workflow has a `quality` job (Biome, Knip, `tsc --noEmit`) and an `audit` job, with dependency caching. Biome, Knip, and TypeScript must be devDependencies of the project.
- The templates are starting points: adapt `knip.json` (`entry` and `project`; with workspaces the root ones are ignored) and the `tsc` step (project references, monorepos) to the project.
