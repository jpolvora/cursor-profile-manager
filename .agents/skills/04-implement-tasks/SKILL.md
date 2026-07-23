---
name: ws-implement-tasks
description: Executes code implementations or fixes defects following a plan, DAG, or review findings.
upstream: jpolvora/workflow-skills — this skill is a spec-to-pr pipeline dependency. Improvements must be submitted upstream to https://github.com/jpolvora/workflow-skills
version: 2.4
disable-model-invocation: true
invocation_names:
  - implement-tasks
  - ws-implement-tasks
  - 04-implement-tasks
---

# 04-implement-tasks

Execute the coding and testing steps from the plan (build mode) or correct defects from a review or test report (fix mode). Act as a Senior Software Developer: clean code, SOLID, surgical edits, stack-consistent, no duplication.

**Reads:** execution plan (`step-03-*.plan.exec.md`), refined plan (`step-02-*.plan.refined.md`), or draft plan (`step-01-*.plan.md`); `config.json` for layer patterns; `{sharedDir}/MEMORY.md` (Grep task keywords before coding — expand per [`tools.md`](../shared/tools.md) § Path tokens; [`self-learning`](../self-learning/SKILL.md) § Pre-work consult).

## Invocation

Standalone:

```
/implement-tasks <plan-path> [mode=build|fix] [findings=<path>]
```

Workflow (spec-to-pr Step 4 build; conditional fix substep under Step 6 review findings / Step 7 test failures; lite Step 2 build / Step 3 review-fix): orchestrator passes `planPath`, `mode`, and optional `findings` path.

| Parameter | Default | Notes |
|-----------|---------|-------|
| `<plan-path>` | required | Execution, refined, or draft plan path |
| `mode` | `build` | `build` or `fix` |
| `findings` | (optional) | Findings report or review comments path |

## Build mode

1. **Load plan** — Parse execution tasks or plan steps; identify files to create/modify and their acceptance criteria.
   - Done when: every task/step has an identified file list and AC.

2. **Consult MEMORY** — Grep `{sharedDir}/MEMORY.md` for modules/paths/keywords in the plan; apply Medium+ Solutions before editing.
   - Done when: relevant entries noted or none found.

3. **Scan codebase** — Locate similar patterns in the project layers (`config.json`) for style consistency.
   - Done when: a matching pattern is found, or none exists and this is noted.

4. **Implement** — Write minimal, clean, modular code matching the requirements without scope creep.
   - Done when: every planned file is created or modified per its AC.

5. **Validate** — Run the build and unit tests for modified layers (backend/frontend).
   - Done when: build/test results are captured (pass or fail).

6. **Report** — Return the modified/created file lists and test output details.
   - Done when: the step-output below is populated.

## Fix mode

1. **Intake gaps** — Load findings from `step-06-*.review.md` / `step-06-*.fix.report.md`, `step-07-*.testing.report.md`, or review comment threads.
   - Done when: every finding is enumerated.

2. **Consult MEMORY** — Grep `{sharedDir}/MEMORY.md` for the defect class / paths; reuse known Solutions before inventing fixes.
   - Done when: relevant entries noted or none found.

3. **Correct** — Apply minimal, targeted fixes per [karpathy-guidelines](../karpathy-guidelines/SKILL.md).
   - Done when: every enumerated finding has a corresponding edit.

4. **Sweep siblings** — Search modified directories for the same defect class and fix simultaneously.
   - Done when: no sibling occurrence of the fixed defect class remains in modified directories.

5. **Anti-regression test** — Write a unit test covering the corrected defect scenario.
   - Done when: each fixed finding has a covering test.

6. **Validate** — Run the project build and test suites to confirm no regressions were introduced.
   - Done when: build/test results are captured (pass or fail).

## Output (both modes)

Modify the working tree directly; never commit or push.

### step-output (workflow mode)

```yaml
status: success | partial | failed | needs_user
files_touched:
  created: []
  modified: []
  deleted: []
verification:
  files_on_disk: pass | fail
  build: pass | fail | skipped
  tests: pass | fail | skipped
summary: |
  (Summary text of changes and verifications)
```

## Rules of Engagement

- No auto-commits: never commit or push code; let the orchestrator or user handle branch staging and commits.
- Strict scope isolation: do not refactor adjacent files or expand feature scope.
- Migration safety: never hand-write schema migration files; always use project CLI tools.

Language: en-us only.
