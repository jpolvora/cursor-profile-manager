---
name: changelog
description: >
  Write a summarized historical record of the task into the configured changelog file
  (default `.agents/skills/shared/CHANGELOG.md`). Use at the very end of every implementation task.
---

# Changelog

**Mandatory completion gate** — run after [self-learning](../self-learning/SKILL.md) at the end of implementation tasks.

## When to run

Run at the end of every implementation task to maintain a historical record of what was actually built, fixed, or modified.

**Important:** This file is strictly for historical tracking and auditing. It is an append-only file and should NOT be used for reading context or preventing regressions (use `MEMORY.md` for that). Do not re-read or rewrite past entries.

## Path resolution

Resolve the target file from `.agents/skills/shared/config.json`:

| Source | Path |
|--------|------|
| `rules.changelogFile` when set | that path (repo-relative) |
| Default | `.agents/skills/shared/CHANGELOG.md` |

Do **not** create or require a repo-root `CHANGELOG.md` unless the consumer explicitly set `rules.changelogFile` to that path (e.g. `"CHANGELOG.md"`).

## Process

1. **Analyze context** — What was the prompt? What did the agent (you) actually do? What was the final result?
2. **Update the resolved changelog file** — Append a new entry using the template below. Create the file (and parent dirs) if it does not exist.

## CHANGELOG.md Template

Insert the following exact format at the top of the file, directly under the main '# Changelog' header:

```markdown
### [YYYY-MM-DD HH:MM] Agent: {agent/runtime}
- **Prompt**: [Brief summarized intent of the user's request]
- **Done**: [What was actually implemented, changed, or fixed]
- **Result**: [Final outcome, status, or any immediate next steps]
```
