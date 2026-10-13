# Claude Code: permissions, hooks, models, and subagents

Complements `AGENTS.md` (risk matrix in 16.2) and `CLAUDE.md`. Describes **what the machine enforces**, what depends only on behavior, what each role may do, and how to change the protections. No change is pending in `proposals/claude/`; a new proposal only takes effect once applied (section 5).

## 1. What is enforced and what is only behavioral

| Layer | Where | What it does | Known limit |
| --- | --- | --- | --- |
| Permission rules | `.claude/settings.json` → `permissions` | `deny` blocks, `ask` requests confirmation, `allow` permits. Order: deny, ask, allow. A hook does not override `deny` or `ask`. | `Bash` rules match the command **text**. `/usr/bin/git push`, `git -C . push`, `git 'push'`, and `bash -c '...'` get past them. `Read` deny covers the file tools and commands such as `cat`/`sed`/redirection, but not a script (`python`, `node`) that opens the file itself. |
| `PreToolUse` hook | `.claude/hooks/guard-paths.sh` | Applies `.claudeignore`; blocks reading a large file without `limit`; blocks secrets in written content; Blocks destructive `git` in any form and asks for confirmation on `git -C`/`-c`/`--git-dir`. Also applies inside subagents. | Token-based check, best effort: variable expansion, glob, and external script get past it. May produce false positives (e.g., the `.key` filter of a `jq` matches `*.key`). `onFailure: "block"` is set in `.claude/settings.json`, so a **hook that fails to start, times out, or errors blocks the action**. |
| `.claudeignore` | root | List of sensitive paths, read by the hook. Reduces context. | Not a security barrier. Duplicates the `Read(...)` in `deny`: when editing one, edit the other. |
| Sandbox | `/sandbox` (**off today**) | The only mechanism that blocks, at the operating system level, what a subprocess reads, writes, and accesses over the network. | Covers only shell commands; the file tools follow the permission rules. Linux needs `bubblewrap` and `socat`; on Ubuntu 24.04+ AppArmor requires adjustment. |
| `AGENTS.md`, `CLAUDE.md` | root | Guide judgment. | **Behavioral**: the model may err or ignore them. To really block, use a permission rule or a hook. |

## 2. Risk matrix (16.2) → configuration

| Level | Configuration | Who decides |
| --- | --- | --- |
| **A** local inspection | explicit `allow` for `git status/diff/log/show`, `git worktree list`; reading inside the project; the project's tests, lint, and typecheck | automatic |
| **B** reversible local change | editing inside the project, **except** `.claude/**`, `.claudeignore`, and user settings (`deny`) | the session's permission mode |
| **C** operational impact | `ask`: commit and other commands that change Git, dependency installation, `publish`/`deploy`, `ssh`/`scp`/`rsync`, `curl`/`wget`, `sudo`, `docker compose`/`run`/`build`/`rm`, database clients, `rm -r`, `chmod -R` | user confirms each time |
| **D** critical or destructive | `deny` when irreversible and rare: `push --force`/`--delete`/`+refspec`, `reset --hard`, `clean`, `stash drop`/`clear`, `docker system prune`, `docker volume rm`/`prune`. The user runs it, if they want, with `!` | user only, per operation |

Criterion: **`deny` for what cannot be undone and the agent almost never needs to do; `ask` for what is legitimate but shared.** `ask` and `deny` do not depend on the model.

## 3. What each role may and may not do

Applies to **all** roles and models: permissions and hooks are inherited by subagents; a smaller model does **not** gain extra permission; no one changes the protections (`.claude/**`, `.claudeignore`, user settings) or switches the session model (that is up to the user: `claude --model`, `--effort`, `/model`).

| Role | Model and effort | May | May not |
| --- | --- | --- | --- |
| Interview and creation of the change | Opus 5.5, `medium` (`high` only for an ambiguous or critical decision) | Read the repository, write the change, propose configuration changes in `proposals/` | Change protections; Level C/D without authorization |
| Implementation and fixes | Sonnet 5.5, `medium`; `low` for a simple adjustment. Escalate to Opus after 2 unsuccessful attempts, in a new session | Edit code and tests, run local checks (A and B) | Commit, push, install, migrate, deploy without authorization |
| Reading subagent | Haiku 5.5. `tools: Read, Grep, Glob` | Search, read, summarize | Edit, run commands, commit |
| Test-runner subagent | Haiku 5.5. `tools: Read, Grep, Glob, Bash` | Run tests, lint, and typecheck and return only the failures | Edit files |
| Reviewer (`/code-review`) | Opus, clean context | Read the diff and report findings | Apply fixes without a request |

Usage rules:
- Choose model and effort **when opening the session**. Switching models midway invalidates the cache of the entire conversation.
- `opusplan` does not fit the OpenSpec workflow: plan mode does not write files, and each toggle switches the model.
- What decides a subagent's model, in order: the call parameter, then the `model` in the `.claude/agents/*.md` file, then `CLAUDE_CODE_SUBAGENT_MODEL`, then the session model. To force all of them: `CLAUDE_CODE_SUBAGENT_MODEL` with `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`.
- A rule in `CLAUDE.md` **influences** delegation but does not guarantee it. What drives routing is the subagent's `description` field. The built-in `Explore` inherits the session model; a custom subagent named `Explore` with `model: haiku` replaces it.
- A skill with `model:` in the frontmatter switches the model only during that turn and reverts on the next prompt.

## 4. Limits that remain open

1. **Subprocesses** (`python`, `node`) can read what the `Read` deny and the hook do not see. Only the **sandbox** closes this.
2. **Grep/Glob** without `path` scan the current directory; the hook only sees the `path` provided. Outside a Git repository, `ripgrep` may not apply `.gitignore` (not verified).
3. **MCP and `WebFetch`** do not go through the file hook. Control them with permission rules (`mcp__server__tool`, `WebFetch(domain:...)`).
4. **Command prefixes** (`env`, `command`, `time`) are handled by the `git` hook, but other wrappers are not.
5. `onFailure: "block"` is already set. Without it, a hook that fails to start, times out, or fails **lets the action through**; keep it when copying the hook to another project. Requires Claude Code 2.1.295 or later.

To close item 1, turn on the sandbox (verify the result in `/sandbox`, Config tab):

```json
{
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false,
    "filesystem": { "denyRead": ["~/.ssh", "~/.aws", "~/.gnupg", "~/**/.env"] }
  }
}
```

Install `bubblewrap` and `socat` (packages of the same name on Ubuntu and Arch). With `allowUnsandboxedCommands: false`, a command that fails in the sandbox does not retry outside it.

## 5. How to change the protections

The agent does **not** edit `.claude/**`, `.claudeignore`, or user settings (`deny`), and does not work around this through Bash. When a protection needs to change, the agent writes the proposal in `proposals/claude/` and the user applies it:

```bash
cp proposals/claude/settings.json .claude/settings.json
cp proposals/claude/hooks/guard-paths.sh proposals/claude/hooks/test-guard.sh .claude/hooks/
cp proposals/claude/claudeignore .claudeignore
bash .claude/hooks/test-guard.sh
```

Then use `jq empty .claude/settings.json`, `/hooks`, and `/permissions` to check, and remove `proposals/`.
