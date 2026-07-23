---
name: ws-code-review
description: Senior code reviewer — two-phase triage and investigation with defect class generalization. Standalone or workflow Step 6.
upstream: jpolvora/workflow-skills — this skill is a spec-to-pr pipeline dependency. Improvements must be submitted upstream to https://github.com/jpolvora/workflow-skills
version: 3.4
disable-model-invocation: true
invocation_names:
  - code-review
  - ws-code-review
  - 06-code-review
---

# 06-code-review

Perform a comprehensive local code review of all modified files, relative to the base branch, before a PR is raised. Act as a **Senior Code Reviewer** conducting static and logical analysis for style, security, tenancy, performance, correctness, and architectural invariants.

**Canonical output:** `{us-dir}/step-06-{slug}.review.md`. Optional fix summary: `{us-dir}/step-06-{slug}.fix.report.md`.

## Invocation

Standalone:

```
/code-review [base=<ref>] [plan=<plan-path>]
```

Workflow (spec-to-pr Step 6): dispatched automatically, receives `base` and `planPath` from orchestrator state.

| Parameter | Default | Notes |
|-----------|---------|-------|
| `base` | `origin/main`/`origin/master` (auto-detected) | Git ref to diff against |
| `plan` | (optional) | `step-02-*.plan.refined.md` or `step-01-*.plan.md` to cross-reference planned changes |

## Conditional fix substep (workflow)

Fix is not its own workflow step. After this skill returns:

| Case | Orchestrator behavior |
|------|----------------------|
| Clean (no Critical/Warning) | Completes Step 6; advances to Step 7 |
| Critical or Warning findings | Dispatches [04-implement-tasks](../04-implement-tasks/SKILL.md) `mode=fix`, optional targeted re-review, then completes Step 6 |
| User declines fix | Logs skip; advances with findings (or pauses) |

Log `review-fix` in gate history; do not add a separate `completedSteps` entry for the fix substep. Standalone `/code-review`: apply fixes inline after user confirms (Step 8 below).

## Steps

1. **Detect stack & diff**: read `config.json.stack` to scope backend/frontend layers; exclude `bin/`, `obj/`, `dist/`, `node_modules/`, CI YAML, translations. Run `git diff --name-status {base}...HEAD` over in-scope paths.
   - Done when: the in-scope modified file list is known.

2. **Triage**: flag lines with real defect potential; discard cosmetic nits, untouched pre-existing code, and low-risk TSX without security surface.
   - Done when: a hypothesis list of candidate findings exists.

3. **Investigate**: for each hypothesis, complete all four proof steps: Evidence Read, Failure Scenario, Missing Protection, Discards. Drop any hypothesis that cannot complete all four.
   - Done when: every retained finding has all four proof steps documented.

4. **Generalize defect class**: for each proven finding, search the full diff for sibling occurrences of the same pattern and report them together.
   - Done when: sibling occurrences are searched and reported (or none found).

5. **Sweep known patterns**: grep each ID in `MEMORY.md → ## Review Patterns` against the modified file set; report confirmed violations.
   - Done when: the pattern sweep ran and results are reported.

6. **Check invariants**: cross-check `config.json.invariants` / `config.json.rules`: tenancy filters, DB-migrations-CLI-only, domain rules, React hook cleanup/dependency arrays, and i18n keys present in every locale from `config.json.stack.frontend.i18n.locales[]`.
   - Done when: each applicable checklist item is checked.

7. **Write report**: save `step-06-{slug}.review.md`. No findings: write `No feedback` and stop. Findings: use severity sections Critical / Warning / Suggestion, each with `path:L#`, description, score `/10`, sibling occurrences, and a `suggestion` block; end with **Apply fixes?**.
   - Done when: the report file matches the format described above.

8. **Apply fixes (standalone only)**: after the user answers YES, apply surgical fixes, run `build-backend`, `test-backend`, `build-frontend` (+ `test-frontend` if UI logic touched), and report the outcome in `step-06-{slug}.fix.report.md` when a plan directory exists. Under workflow, the orchestrator owns this via `04-implement-tasks` instead.
   - Done when: fixes are applied and verification commands ran, or this step was skipped under workflow.

## Rules of engagement

- Precision before volume: include only findings with complete evidence, no speculative comments.
- Convergence goal: one report round covering all issues; avoid review loops.
- Do not commit: changes stay in the working tree for the orchestrator or developer to stage.

Language: en-us only.
