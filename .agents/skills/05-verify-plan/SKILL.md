---
name: ws-verify-plan
description: Compares implementation quality and code deliverables against the spec (or plan when no spec) and acceptance criteria. Publishes a 0–10 score.
upstream: jpolvora/workflow-skills — this skill is a spec-to-pr pipeline dependency. Improvements must be submitted upstream to https://github.com/jpolvora/workflow-skills
version: 2.4
disable-model-invocation: true
invocation_names:
  - verify-plan
  - ws-verify-plan
  - 05-verify-plan
---

# 05-verify-plan

Audit implementation deliverables against the specification and plan. Act as a **Senior QA Engineer / SDET** who checks acceptance criteria, code quality, and test coverage, then publishes a **0–10 score**.

Runs in two modes: **Quick Score** (code quality vs plan, no spec required) or **US Verification** (feature-by-feature match between spec, plan, and code).

**Canonical output:** `{us-dir}/step-05-{slug}.plan.report.md`. Optional Quick Score report shape: [`TEMPLATE.md`](TEMPLATE.md).

## Invocation

Standalone:

```
/verify-plan [spec-input] [plan-dir=<path>]
```

Workflow (spec-to-pr Step 5): orchestrator passes `specPath`, `planDir`, optional `mode=quick|full`. Default `mode=quick`; escalate to `full` when quick score < 7, orchestrator passes `mode=full`, or user passed `--strict`.

| Parameter | Default | Notes |
|-----------|---------|-------|
| `spec-input` | (optional) | Path to `step-00-*.spec.md`, US number, or omit for Quick Score |
| `plan-dir` | `{us-dir}` | Optional override for `{us-dir}` (`{plansDir}/{slug}/`) |
| `mode` | `quick` (workflow) / `full` (standalone with spec) | Verification depth |

## Steps

1. **Resolve source**: search `{us-dir}` in order for `step-02-{slug}.plan.refined.md` (refined, primary), then `step-01-{slug}.plan.md` (fallback). In full mode, also resolve the primary evaluation source: the refined plan when present, else `step-00-{slug}.spec.md`.
   - Done when: the resolved plan (and, in full mode, spec) path is known.

2. **Evaluate**: Quick Score scores Completeness (40%), Correctness & Style (35%), Tests (25%), each 0-10. US Verification maps every plan feature and acceptance criterion to **Implemented**, **Not implemented**, or **Implemented differently**, each with file:line evidence.
   - Done when: every planned feature/AC has a situation and evidence, and Quick Score's three metrics are each scored.

3. **Score**: compute the integer **0-10** score (weighted average for Quick Score; overall adherence for US Verification).
   - Done when: an integer score 0-10 is set.

4. **Write report**: save `{us-dir}/step-05-{slug}.plan.report.md` matching this format exactly:

   ```markdown
   ---
   us: "{slug}"
   reportDate: YYYY-MM-DD
   score: N
   sourcePlans: ["step-02-{slug}.plan.refined.md"]
   evalSource: step-02-{slug}.plan.refined.md | step-00-{slug}.spec.md
   githubSource: gh | none
   ---

   # Implementation Report - {slug}

   **Generated on:** YYYY-MM-DD
   **Score:** N/10
   **Evaluation source:** step-02-{slug}.plan.refined.md (or step-00-{slug}.spec.md)
   **Reference Plan:** step-02-{slug}.plan.refined.md (or step-01-{slug}.plan.md)

   ## Result by Feature (Plan & ACs)

   | Feature | Situation | Detail / Evidence |
   |---------|-----------|-------------------|
   | CRUD Accounts | **Implemented** | `AccountService.cs:L20-L45` |

   ## Additional Features Beyond Original Plan

   | Feature / Extra Behavior | Location in Code | Note |
   |--------------------------|------------------|------|

   ## Gaps and Next Steps
   - (List missing or incomplete tasks to resolve before PR approval)
   ```

   Do not edit the reference plan/spec files. Write only the canonical `step-05-{slug}.plan.report.md` name.
   - Done when: the report file exists with `Score: N/10` near the top and every required section populated.

5. **Handoff**: return the score and report path.
   - Workflow: the orchestrator owns the gate after reading the report: score `>= 7` advances to Step 6; score `< 7` triggers user-gate (Refine / Replan / Respec / Approve-and-continue) and must not auto-approve below 7.
   - Standalone: apply the same `>= 7` / `< 7` threshold; recommend re-implementation or a full matrix when below 7.
   - Done when: the caller has the score and report path.

Language: en-us only.
