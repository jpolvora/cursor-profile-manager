---
name: ws-interview
description: Audits and interrogates an implementation plan to resolve ambiguities before task creation.
upstream: jpolvora/workflow-skills — this skill is a spec-to-pr pipeline dependency. Improvements must be submitted upstream to https://github.com/jpolvora/workflow-skills
version: 1.8
disable-model-invocation: true
invocation_names:
  - interview
  - ws-interview
  - 02-interview
---

# 02-interview

Audit and interrogate the draft plan (`step-01-{slug}.plan.md`) against acceptance criteria, codebase structure, tenancy rules, and invariants. Act as a Technical Lead / Senior Architect on a "grill-me" philosophy: resolve ambiguities and secure shared understanding before task decomposition.

**Canonical path:** writes `{us-dir}/step-02-{slug}.plan.refined.md`, leaving `step-01-{slug}.plan.md` untouched.

## Invocation

Standalone:

```
@[refine] <plan-path> [spec=<spec-path>]
```

Workflow (spec-to-pr Step 2): dispatched when the orchestrator does not skip interview (see [gates.md](../shared/gates.md) conditional interview). May be skipped entirely for simple plans.

| Parameter | Default | Notes |
|-----------|---------|-------|
| `<plan-path>` | required | Path to `step-01-{slug}.plan.md` |
| `spec` | inferred | Path to `step-00-{slug}.spec.md`, inferred from plan folder |
| `softSkipEligible` | false | Orch hint: Open Questions empty; prefer defaults and exit fast if no blocking gaps |

## Grilling Protocol (hard rules)

1. **Diligent exploration first** — search the codebase, ADRs, database schema, and `MEMORY.md` before asking. Resolve discoverable gaps automatically and record the evidence.
2. **Walk the design tree** — resolve foundational gaps (scope/schema) before details (UI/i18n).
3. **Surgical escalation** — ask exactly one question per round; include the recommended solution as the first choice.
4. **Escalation cap** — max 3 rounds of user questions; on the 4th, apply sensible defaults and exit.
5. **No code edits** — write only refined plans and metadata.

## Steps

1. **Audit** — Scan sections 0-8 of the plan, run scenario probes (soft-deletion, concurrency, list sizing, rate limits), and register each finding in a `gap_registry` (`id`, `class`, `section`, `gap`, `recommendation`, `status`, `dependsOn`). Classify each gap `blocking` (prevents development or changes AC) or `non-blocking` (quality/optimization, apply via defaults).
   - Done when: every section 0-8 has been scanned and every finding is registered.

2. **Resolve** — Resolve registered gaps by scanning code layers, specs, and `MEMORY.md`; append resolution evidence to the registry.
   - Done when: every non-blocking gap and every locally resolvable blocking gap has a resolution.

3. **Escalate** — For remaining blocking gaps: standalone, prompt via `user-gate`; workflow, return `status: needs_user` per the Grilling Protocol.
   - Done when: no blocking gap remains unresolved and unescalated, or the escalation cap was reached and defaults were applied.

4. **Confirm shared understanding** — Workflow: treat as confirmed when the orchestrator already auto-confirmed via "End refinement and advance" (do not re-prompt); otherwise return `shared_understanding: pending`. Standalone: prompt the user to confirm.
   - Done when: `shared_understanding` is `confirmed`, or `pending` was returned to the orchestrator.

**Fast exit:** when `softSkipEligible` and Step 1 finds `blocking_open == 0`, write the refined plan with defaults applied, set `shared_understanding: confirmed`, and return success without escalation.

## Outputs

- `step-02-{slug}.plan.refined.md` with frontmatter `status: "plan refined ok"` and an appended `## Interview registry` table.

### step-output (workflow mode)

```yaml
status: success | needs_user
refine:
  registry: [{id, class, section, gap, status, resolution, dependsOn?}]
  round: number
  blocking_open: number
  shared_understanding: pending | confirmed
needs_user:
  question: string              # ONE question only
  options: [{id, label}]        # recommended choice first
  context: string
  design_branch: string         # e.g., "Authorization / tenant"
```

Language: en-us only.
