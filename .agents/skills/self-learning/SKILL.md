---
name: self-learning
description: >
  Consult anti-regression MEMORY before planning or writing code, and record new traps
  into the shared memory hub after implementation. Use at session/task start (read)
  and task completion (write + compile). Prevents repeating known mistakes.
---

# Self-Learning

**Bidirectional gate** — MEMORY is both input (avoid known traps) and output (record new ones).

Expand path tokens first ([`tools.md`](../shared/tools.md) § Path tokens): `{sharedDir}` → `.agents/skills/shared`, `{skillsRoot}` → `.agents/skills`.

Consumer-owned memory lives in the shared hub (never overwritten by install/update):

- Entries: `{sharedDir}/memory/YYYY-MM-DD-[slug].md`
- Compiled index: `{sharedDir}/MEMORY.md`

## When to run

| Moment | Action |
|--------|--------|
| **Before plan / before code / before fix** | **Consult:** `Grep` / `Read` `{sharedDir}/MEMORY.md` for keywords of the task (shell, script, encoding, skill path, module). Apply matching **Solution** lines. Skip only for pure Q&A with no repo edits. |
| Implementation hit a trap/pitfall/race | **Write:** new file in `{sharedDir}/memory/`, then `python {skillsRoot}/self-learning/self_learning.py --compile` (expand tokens before shell) |
| Standard feature/bug fix, no new trap | Proof line: `Learning: N/A (standard implementation)` after confirming no new pitfall |
| Pure Q&A, no durable insight | Proof line: `Learning: N/A (no new project knowledge)` |

Task is **not done** until the completion side runs (write or explicit `Learning: N/A`) and proof includes a **`Learning:`** line. Prefer consulting MEMORY **before** inventing a new approach when the domain already has High/Critical entries.

## Pre-work consult (mandatory for mutating work)

1. Identify 3–8 keywords from the task (e.g. `bash`, `CRLF`, `launcher`, `verify.sh`, `managed skill`, `encoding`).
2. `Grep` those terms in `{sharedDir}/MEMORY.md` (tool alias `read-memory`).
3. If a hit is Severity Medium+, fold its **Solution** into the plan or first edit. Do not re-discover the same failure mode.
4. For scripts/skills specifically, also apply the preflight in memory entry **Script/skill authoring preflight** (launchers, LF, Windows Python `\r\n`, no shell bridges).

## Process (write after)

1. **Analyze context** — What did we try that failed? What non-obvious constraint or pitfall did we hit?
2. **Write to `{sharedDir}/memory/`** — New file `{sharedDir}/memory/YYYY-MM-DD-[slug].md`. **ONLY** traps/pitfalls. **DO NOT** use as a changelog or to record patterns an LLM already knows.
3. **Compile `MEMORY.md`** — Expand tokens, then run:
   ```bash
   python .agents/skills/self-learning/self_learning.py --compile
   ```
4. **Proof + chat** — Set `**Learning:** [entry title]` or `N/A` in the final proof; one-line summary in the reply.

## Conflict Resolution

If `MEMORY.md` merge-conflicts on pull/merge, **do not** resolve by hand. Run:
```bash
python .agents/skills/self-learning/self_learning.py --compile
```
This rebuilds a clean index from `{sharedDir}/memory/` (per-file entries do not conflict).

## Individual Memory File Template

```markdown
### [YYYY-MM-DD] [Topic/Component]
- **Layer**: [e.g. Core, Infrastructure, Api, Web, Tests, or N/A]
- **Module**: [e.g. Auth, Wallet, Users, or N/A]
- **Severity**: [Low, Medium, High, Critical]
- **Trap Avoided**: [What approach failed, what non-obvious constraint was hit, or what standard LLM assumption was wrong]
- **Solution**: [How to do it correctly to avoid the trap]
```

Path tokens: [`tools.md`](../shared/tools.md) § Path tokens.
