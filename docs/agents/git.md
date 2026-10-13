# Git

Detail for section 17 of `AGENTS.md`, with examples and procedures. It does not contradict the core; on divergence, the core prevails. The original numbering is kept.

## 17. Git

Git operations follow the risk matrix (16.2).

### 17.1 Scope and inspection

- Restrict changes to the necessary scope.
- Do not assume the working tree is clean. Before any relevant operation, check `git status` and identify: current branch, staged and unstaged changes, relevant untracked files, and the necessary history and references.
- Determine whether the existing changes belong to the user, to another task, or to the task in progress.
- Preserve the user's preexisting changes. Do not discard, overwrite, or revert someone else's work without authorization, not even to simplify an operation.
- Do not edit generated files by hand; change the source and regenerate.
- Do not modify configuration files merely to work around a failure.
- Inspect the final diff and remove unexpected changes: out-of-scope files, accidental reformatting, debug code, temporary artifacts.
- Keep compatibility with existing consumers, unless a breaking change was requested and handled explicitly (version, migration, communication).

### 17.2 Commits

- Do not create commits without an instruction or authorized workflow that requests them.
- Prepare small, coherent commits related to the task.
- Add files by explicit path. Avoid adding everything at once when there are other people's changes in the working tree.
- Review the staged content before creating the commit: what matters is what will be recorded, not the overall state of the directory.
- Do not include sensitive files, unnecessary artifacts, or other people's changes.
- Do not use `--no-verify`, `--no-gpg-sign`, or an equivalent bypass without explicit authorization and justification. If a hook fails, fix the cause.

```bash
git status --short
git add src/users/service.ts src/users/tests/service.test.ts
git diff --staged
```

### 17.3 Commit messages

Follow the pattern configured in the project. In the absence of another explicit contract, use Conventional Commits:

```text
<type>(<scope>): <description>
```

```text
feat(auth): add token refresh
fix(users): prevent duplicate registration
test(api): cover invalid request payloads
refactor(core): simplify error handling
docs(core): clarify setup instructions
chore(deps): synchronize package versions
```

- Short, specific description, in the language and verb form adopted by the project.
- Do not invent types, scopes, or exceptions that contradict the existing configuration. Check the validation configuration and the recent history.

### 17.4 Push

A request to implement or commit does not authorize publishing.

- Do not push automatically after a commit.
- Confirm remote, branch, and destination before publishing.
- Assess whether the push updates a shared branch.
- Do not publish sensitive files or changes that have not been reviewed.
- Do not use force push as an automatic attempt to resolve divergence.
- Respect branch protections and review policies.

### 17.5 Pull, merge, and rebase

- Inspect the local state before integrating remote changes.
- Preserve uncommitted work.
- Assess conflicts and effects on the history.
- Do not resolve a conflict by automatically choosing one version: understand the intent of both sides.
- Do not rebase a shared branch without authorization.
- Do not change remote history to simplify an integration.
- Prefer explicit, verifiable operations.

### 17.6 Operations that discard or hide work

These require special care, among others: `git reset --hard`, `git clean -fd`, `git clean -fdx`, `git checkout -- <path>`, `git restore`, `git stash`, `git stash drop`, `git stash clear`, `git rebase`, `git branch -D`, `git push --force`.

Before using any of them:

1. Examine the Git state.
2. Identify exactly which changes will be affected.
3. Determine whether they belong to the user or to another task.
4. Prefer a reversible alternative.
5. Obtain authorization when there is a risk of discarding, overwriting, or altering history.

Rules:

- Do not use `git stash` to work around a dirty working tree. Stash hides relevant changes and makes them harder to recover.
- Do not use `git reset --hard`, `git clean -fdx`, or equivalent without understanding the discard and having explicit authorization for it. `git clean` with `-x` also deletes ignored files, such as `.env` and installed dependencies.
- Discarded changes that were never committed are, in general, not recoverable through Git.

### 17.7 Worktrees

Useful for parallel features, hotfixes, and isolated tasks. Do not create a worktree for a simple task when the existing workflow is enough.

Before creating, changing, or removing:

- Check `git worktree list`.
- Verify branch and destination directory. By default, Git refuses to use in another worktree a branch already linked to one; do not force it.
- Preserve local changes and untracked files.
- Check whether there are processes or tasks in progress in the directory.
- Do not remove a worktree because it looks old: verify its state first. Do not force the removal of a worktree that has changes.

### 17.8 Tags, releases, and shared history

- Do not create a release tag, publish a version, or modify a release without authorization.
- Do not rewrite shared history or force-update a remote branch to resolve a conflict.
- Before any authorized change to shared history, assess the impact on collaborators and pipelines.

