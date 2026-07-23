---
name: goal-loop
description: >-
  Generic goal/loop pattern for convergence-driven loops. Provides sentinel
  management, heartbeat/sleeper, re-collect -> check -> continue/done loop,
  stop conditions, verify framework, and report format. Consumed by
  goal-orchestrator skills (e.g., goal-fix-pr). Not invocable standalone.
upstream: jpolvora/workflow-skills — this skill is a spec-to-pr pipeline dependency. Improvements must be submitted upstream to https://github.com/jpolvora/workflow-skills
version: 1.1
disable-model-invocation: true
---

# goal-loop — Generic Goal/Loop Pattern

Convergence-driven loop skeleton. A **goal-orchestrator skill** loads this skill and instantiates the loop with concrete success criteria, collect action, and act action.

## Loop skeleton

```
Goal: <description>
Success: <checkable criterion>
Iteration: <n>/<max>
- [ ] collect + evaluate
- [ ] act round (if criterion not met)
- [ ] verify
- [ ] report
- [ ] wait + re-collect (if not converged)
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `PR_NUMBER` | int | Target PR number |
| `SUCCESS_CRITERION` | expression | `activeThreads == 0`, `len(failures) == 0`, etc. |
| `MAX_ITERATIONS` | int | Hard stop (default **20**) |
| `WAIT_SECONDS` | int | Post-push wait before re-collect (default **300**) |
| `COLLECT_CMD` | string | Shell command to collect state (must produce parsable output) |
| `ACT_CMD` | string | Shell command or skill load to perform one fix round |
| `VERIFY_CMD` | string | Shell command(s) to verify correctness post-act |
| `DRY_RUN` | bool | Skip push, resolve, and destructive actions |
| `RUNTIME_DIR` | path | Sentinel/runtime dir (default `{us-dir}/.runtime` or goal-loop runs dir) |

## Sentinel management

A **sentinel** is a singleton background timer that wakes the agent after `WAIT_SECONDS` to re-evaluate convergence.

**Portability:** never write sentinel files under OS temp (`TMPDIR` / Windows `%TEMP%`). Use a project-local runtime directory:

```bash
# Prefer spec-to-pr runtime when available:
#   {plansDir}/{slug}/.runtime/
# Fallback:
#   .agents/skills/goal-loop/runs/<ID>/

RUNTIME_DIR="<resolved runtime dir>"
mkdir -p "$RUNTIME_DIR"
echo "goal_loop_wake_<ID>" > "$RUNTIME_DIR/sentinel.pid"
echo $! >> "$RUNTIME_DIR/sentinel.pid"

# Sleep and emit wake signal
sleep <WAIT_SECONDS> && echo 'GOAL_LOOP_WAKE_<ID> {"reason":"post-push","id":"<ID>","iteration":<N>}'
```

### Rules

- **One sentinel per session.** If a sentinel PID file exists, kill the old process before starting a new one.
- **Track PID** at `$RUNTIME_DIR/sentinel.pid`.
- **On stop/abort**, kill sentinel and remove PID file.
- **Wake message** must match a `notify_on_output` regex: `^GOAL_LOOP_WAKE_<ID>`.

## Convergence loop

### 1. Collect + evaluate

Run `COLLECT_CMD` and parse output against `SUCCESS_CRITERION`.

- **Criterion met** -> emit final report, kill sentinel, stop.
- **Criterion not met** -> proceed to act round.
- **Collect failure** -> stop; do not improvise API calls.

### 2. Act round

Execute `ACT_CMD`. One round = sync state -> investigate -> fix -> validate -> commit -> resolve -> push (or dry-run simulation).

### 3. Verify (mandatory)

No claim of progress without fresh evidence:

| Check | Evidence |
|-------|----------|
| Build/tests | Output from `VERIFY_CMD` |
| Auto-review | Status from code-review skill (or equivalent) |
| Publication | Commit hash + push confirmation (or dry-run log) |
| Resolution | Resolve exit code 0 (or documented skip in dry-run) |

**3x identical failure** on the same check -> stop and escalate.

### 4. Report

Per-iteration report at `$RUNTIME_DIR/round-<N>.md`:

```markdown
# Goal Loop Round <N>

| Field | Value |
|-------|-------|
| ID | <ID> |
| Iteration | <N>/<MAX_ITERATIONS> |
| Mode | drive / watch |
| Success criterion | <SUCCESS_CRITERION> |
| Criterion met | yes / no |
| Actions taken | <summary> |
| Build/tests | <pass/fail> |
| Commit | <hash> |
| Push | <yes/no> |
```

### 5. Post-push heartbeat

After commit/push (or resolve-only round):

1. Schedule next collect after `WAIT_SECONDS` via sentinel.
2. On wake, re-run **step 1** (collect + evaluate).
3. **0 active** -> convergence -> done.
4. **> 0** and `n < MAX_ITERATIONS` -> iteration `n+1` (back to step 2).
5. **n >= MAX_ITERATIONS** -> stop, report remaining items, ask for human intervention.

### 6. Convergence

The loop exits when:

- `SUCCESS_CRITERION` evaluates to true.
- `MAX_ITERATIONS` reached without convergence.
- User says stop.
- Escalation (ambiguity requiring human decision).
- Collect failure.

## Stop conditions

| Condition | Action |
|-----------|--------|
| Criterion met | Final report + kill sentinel |
| User says stop | Kill sentinel, summarize progress |
| Escalation | Stop, list blockers |
| `n >= MAX_ITERATIONS` | Stop, list unconverged items |
| Collect fails | Stop; do not improvise |

## Final report

```markdown
# Goal Loop Result — <ID>

| Field | Value |
|-------|-------|
| ID | <ID> |
| Iterations executed | <N> |
| Stop reason | convergence / max iterations / user / escalate / error |
| Criterion met | yes / no |
| Rounds | <summary per round> |
| Final state | <evidence of last collect> |
| URL | <resource URL> |
```

## Dry-run mode

When `DRY_RUN=true`:

- **Do not** push, resolve threads, or execute destructive commands.
- **Do** simulate: log what would be done, write reports, run verify.
- **Do not** arm sentinel; re-collect immediately instead of waiting.

## Dependencies

| Resource | Path |
|----------|------|
| Run artifacts | `$RUNTIME_DIR/` or `.agents/skills/goal-loop/runs/<ID>/` |
| Sentinel tracking | `$RUNTIME_DIR/sentinel.pid` |
| Artifact registry | [ARTIFACTS.md](../spec-to-pr/ARTIFACTS.md) |
