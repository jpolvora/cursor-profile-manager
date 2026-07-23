---
name: ws-ship-pr
description: End-to-end delivery — prepare-to-PR checklist (including discover+wait for local consumer prepare/before-push rules), push/create PR, wait 30 seconds for code-review action to start on GitHub infrastructure, run goal-fix-pr (default 300s) until no open issues, then merge (unless stopBeforeFixPr / no-merge).
upstream: jpolvora/workflow-skills — this skill is a spec-to-pr pipeline dependency. Improvements must be submitted upstream to https://github.com/jpolvora/workflow-skills
version: 1.10
disable-model-invocation: true
invocation_names:
  - ship-pr
  - ws-ship-pr
  - 08-ship-pr
---

# ship-pr

Ship from `config.project.workingBranch` (default `develop`) to `config.project.baseBranch`. Act as a **DevOps Engineer / Release Manager**: drive the **prepare-to-PR** goal checklist (verify + **discover and wait** for local consumer prepare / before-push / before-publish harness steps), then push/create PR via configured SCM, wait 30 seconds for code-review action to start on GitHub infrastructure, run `goal-fix-pr` (default 300 seconds heartbeats), and merge only when clean.

Prepare board (mandatory): [PREPARE-CHECKLIST.md](PREPARE-CHECKLIST.md). Wait/converge timing: [GOAL-OVERRIDES.md](GOAL-OVERRIDES.md). Examples: [examples.md](examples.md).

## Invocation

Standalone:

```
/ship-pr [commit-title] [base=<branch>] [head=<branch>] [dry-run] [no-merge] [max <n>]
```

Workflow: `spec-to-pr` Step 8 or `spec-to-pr-lite` Step 4. Dispatched with `workflowMode: true`, `shipAction`, and typically `stopBeforeFixPr: true`: create/push PR and STOP; orch Step 9 runs `goal-fix-pr`/`fix-pr`.

| Parameter | Default | Notes |
|-----------|---------|-------|
| `commit-title` | (optional) | Message for any uncommitted changes |
| `base` | `config.project.baseBranch` | Auto-detect `main`/`master` if unset |
| `head` | `config.project.workingBranch` (`develop`) | Branch to push and use as PR head |
| `dry-run` | `false` | Simulate; no commits/push/real PR API calls |
| `no-merge` | `false` | Create PR and run checks; stop before merge |
| `max <n>` | `10` | `goal-fix-pr` iteration cap (ignored when `stopBeforeFixPr`) |
| `workflowMode` | `false` | Orchestrator-set: execute `shipAction` without re-asking |
| `shipAction` | (orchestrator-selected) | `create-pr` \| `push-only` \| `skip` |
| `stopBeforeFixPr` | `false` | Skip Step 6; orchestrator owns fix-PR at Step 9 |

Before executing, restate commit title, head/base, SCM provider, mode, `stopBeforeFixPr`, max, and `shipAction`. Resolve branches and provider from `.agents/skills/shared/config.json` only.

## Steps

1. **Preflight**: resolve `workingBranch`/`baseBranch`/`gitRemote`; confirm active branch is `workingBranch`; check `git status` and tracking drift; `git pull {gitRemote} {workingBranch}`; auto-detect base via `bash .agents/skills/08-ship-pr/scripts/detect-base-branch.sh` if unset; stop on unexpected dirty files outside delivery scope.
   - Done when: branches resolved; working tree clean enough to ship and pulled.

2. **Prepare to PR (goal)**: load [PREPARE-CHECKLIST.md](PREPARE-CHECKLIST.md). Drive coverage → build → tests → security → **consumer prepare discovery** (scan local `AGENTS.md` / `{sharedDir}/AGENTS.md` / `rules.*` / ship docs for prepare or before-push/publish/deliver steps; **wait** until those obligations complete) until every required row is ✅/⏭. Show the board to the user after each item and before shipping. Credit orch Steps 6–7 only with cited evidence for the **current** tree. STOP on any ❌ — including unfinished discovered local prepare steps.
   - Done when: board shown; scan evidence recorded for row 5; all required rows ✅/⏭.

3. **Code-review loop**: skip if already reviewed under `spec-to-pr` Step 6 or `spec-to-pr-lite` Step 3 (record on board). Otherwise load [06-code-review](../06-code-review/SKILL.md) against `base` and auto-fix Critical/Warning findings, up to 3 iterations.
   - Done when: review clean, 3-iteration cap reached, or skipped with evidence.

4. **Commit & push**: only after Step 2 is green. Commit remaining ship-scope changes (delivery commit may already exist under `workflowMode`); `git push -u {gitRemote} {workingBranch}`. Skip push when `shipAction: skip` or `dry-run`.
   - Done when: branch pushed with no uncommitted ship-scope changes, or ship explicitly skipped.

5. **Create PR**: only when Step 2 is green and `shipAction: create-pr` (or standalone default). Resolve `providers.scm` per [`config-resolution.md`](../shared/config-resolution.md) (reject `local`; STOP if unresolved — do not invent a client). Load matching provider ([github-provider](../github-provider/SKILL.md) or [azure-devops-provider](../azure-devops-provider/SKILL.md)), `validate-auth` (STOP on failure), then `create-pr --head {workingBranch} --base {baseBranch}` (reuse open PR for same head→base when present). Capture PR id and URL.
   - Done when: PR id/URL captured or reused. If `stopBeforeFixPr` and `shipAction: create-pr`: print URL and STOP (success).

6. **Monitor reviews & converge**: skip if `stopBeforeFixPr` (orch Step 9 owns [goal-fix-pr](../goal-fix-pr/SKILL.md)). Otherwise, after pushing and creating PR, wait **30 seconds** (wait for code-review action to start on GitHub infrastructure), then start [goal-fix-pr](../goal-fix-pr/SKILL.md) (default **300 seconds** heartbeat/settle loop, [GOAL-OVERRIDES.md](GOAL-OVERRIDES.md)), poll required checks and `list-threads`, and dispatch `goal-fix-pr` until `activeThreads == 0` or `max`. Never merge while threads remain, checks are red, or on escalate-stop. Prepare the handoff prompt/state for `goal-fix-pr` even when stopping early so Step 9 can resume cleanly.
   - Done when: `activeThreads == 0` and required checks green, or run stopped with PR URL reported.

7. **Merge**: only when Step 6 converged and checks green. Provider intent `merge-pr`; skip when `no-merge` or `stopBeforeFixPr`. Never delete `{workingBranch}`.
   - Done when: merged or explicitly skipped; `{workingBranch}` intact.

## Output

```markdown
**PR:** {provider-returned-url}
```

In `dry-run`, `push-only`, `skip`, or early `stopBeforeFixPr` stop, state the outcome clearly (no placeholder URL). Always include the final Prepare to PR board in the closing summary.

## Dependencies

- Prepare board: [PREPARE-CHECKLIST.md](PREPARE-CHECKLIST.md) · Verify helper: `bash .agents/skills/08-ship-pr/scripts/verify.sh`
- SCM: [github-provider](../github-provider/SKILL.md) · [azure-devops-provider](../azure-devops-provider/SKILL.md)
- Security: [secrets-leak-review](../secrets-leak-review/SKILL.md)
- Review: [06-code-review](../06-code-review/SKILL.md) · Convergence: [goal-fix-pr](../goal-fix-pr/SKILL.md) · Fixer: [09-fix-pr](../09-fix-pr/SKILL.md)
- Base detection: `bash .agents/skills/08-ship-pr/scripts/detect-base-branch.sh` · Artifacts: [ARTIFACTS.md](../spec-to-pr/ARTIFACTS.md)

Language: en-us only.
