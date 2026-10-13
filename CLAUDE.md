@AGENTS.md

## Files ignored by the agent (.claudeignore)

- Every path listed in `.claudeignore` (`.gitignore` syntax) **must not be read, modified, or used** by the agent, not for inspection, not for debugging, not as an example.
- Before reading, editing, or quoting a sensitive file, check whether it matches `.claudeignore`.
- If the task requires an ignored path, stop and ask the user. Do not work around it with `cat`, `grep`, `sed`, scripts, or any other tool.
- Do not copy the content of ignored paths into answers, commits, logs, or tests.
- This rule is behavioral. Technical enforcement is done by `.claude/hooks/guard-paths.sh` and by the `permissions.deny` rules in `.claude/settings.json`.

## Protections, models, and delegation

Detail and role table: `docs/agents/claude-code.md` (read before changing permissions, hooks, or subagents).

- Do not edit `.claude/**`, `.claudeignore`, or the user's settings, and do not work around this through Bash. If a protection needs to change: write the proposal in `proposals/claude/` and ask the user to apply it.
- Permission denied or a hook blocked the action: adjust the approach; never repeat the same command or look for another path to the same effect.
- The session's model and effort are the user's choice; do not try to change them. If the task calls for another one (e.g., a hard bug the current model did not solve in 2 attempts), suggest it.
- Delegate to a subagent broad repository reads, test execution, and log analysis, to keep the main context small. Diff review goes to a subagent with a clean context.
- Subagents inherit the same permissions and prohibitions; a smaller model does not widen what can be done.
