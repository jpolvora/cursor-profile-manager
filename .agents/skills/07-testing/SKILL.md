---
name: ws-testing
description: Plans and executes pre-PR testing — unit tests, integration/E2E, coverage, testing quality, and feature quality.
upstream: jpolvora/workflow-skills — this skill is a spec-to-pr pipeline dependency. Improvements must be submitted upstream to https://github.com/jpolvora/workflow-skills
version: 2.5
disable-model-invocation: true
invocation_names:
  - testing
  - ws-testing
  - 07-testing
---

# 07-testing

Plan and execute the pre-PR **testing** battery: unit tests, integration/E2E flows, coverage signals, testing quality (assertions, fixtures, flakiness), and feature quality against acceptance criteria. Act as a **Release Engineer / QA Lead** who verifies end-to-end flows, RBAC, and database schema stability.

**Canonical outputs:** `step-07-{slug}.testing.plan.md`, `step-07-{slug}.testing.report.md`. Do not write retired artifact names (`step-11-*.integration-test.*`).

## Invocation

Standalone:

```
/testing <plan-path> [spec=<spec-path>] [skip-browser]
```

Workflow (spec-to-pr Step 7): dispatched with `planPath` and `specPath` from orchestrator state. The orchestrator, not this skill, decides skip when `skipTesting` is set or when there is no meaningful test surface and unit tests are already green. UI browser testing requires explicit authorization.

| Parameter | Default | Notes |
|-----------|---------|-------|
| `<plan-path>` | required | `step-02-*.plan.refined.md` or `step-01-*.plan.md` |
| `spec=<spec-path>` | inferred from folder | `step-00-*.spec.md` |
| `skip-browser` | `false` | Skip browser-agent/UI testing; backend/API only |

## Prerequisites

- `config.json` resolves local dev server URLs (`apiHost`, `devHost`), locales, and DB seed keys.
- Codebase builds cleanly (backend + frontend); DB migrations are applied.

## Steps

1. **Plan**: write `step-07-{slug}.testing.plan.md` covering unit & coverage commands (from `config.json.verification`) and gaps vs changed files; target hosts/ports and credentials; DB seed datasets and rollback per AC; API contracts (status codes, Bearer JWT, error shapes); RBAC and tenancy isolation checks; integration/E2E paths (cross-service, UI routes, translations); a feature-quality AC checklist mapped to observable outcomes (not just happy-path 200s); and defect-threshold pass/fail metrics.
   - Done when: the plan file exists covering all areas above.

2. **Verify base build**: run build and core test commands from `config.json.verification`.
   - Done when: the commands ran and results are recorded.

3. **Run unit tests**: execute project unit test suites; note failures and missing coverage on touched code.
   - Done when: unit suite results are recorded.

4. **Apply DB seeds**: apply and verify seed constraints and cleanups.
   - Done when: seed state is verified or reported as unnecessary.

5. **Run API/integration checks**: probe endpoints via `curl` or script runners.
   - Done when: every planned API contract check ran.

6. **Run UI/E2E validation**: run browser automation or visual checks unless `skip-browser` is set.
   - Done when: UI/E2E checks ran or were explicitly skipped.

7. **Report**: write `step-07-{slug}.testing.report.md` with results from Steps 2-6, including an accessibility/contrast check on form validation errors and alert indicators.
   - Done when: the report file exists with results for every planned area.

## Rules of engagement

- No code fixes: report gaps and hand off to [04-implement-tasks (fix mode)](../04-implement-tasks/SKILL.md) rather than editing code.

Language: en-us only.
