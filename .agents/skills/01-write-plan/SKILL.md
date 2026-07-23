---
name: ws-write-plan
description: Generates the implementation plan (step-01-{slug}.plan.md) from the specification.
upstream: jpolvora/workflow-skills — this skill is a spec-to-pr pipeline dependency. Improvements must be submitted upstream to https://github.com/jpolvora/workflow-skills
version: 3.4
disable-model-invocation: true
invocation_names:
  - write-plan
  - ws-write-plan
  - 01-write-plan
---

# 01-write-plan

Draft an implementation blueprint from the spec. Act as a Senior Software Engineer / Technical Architect: stack-aware, modular, testable, with mapped database and API layers.

**Canonical path:** `{us-dir}/step-01-{slug}.plan.md` (`{us-dir}` = `{plansDir}/{slug}/`).

**Reads:** `config.json` (stack, layers, invariants), `tools.md` / `STACK.md`, `MEMORY.md`.

## Invocation

Standalone:

```
/write-plan <spec-input> [slug=<slug>] [output-dir=<path>]
```

Workflow (spec-to-pr Step 1): orchestrator passes `specInput` (path to `step-00-*.spec.md`, GitHub issue id, or Azure DevOps id) from state.

| Parameter | Default | Notes |
|-----------|---------|-------|
| `<spec-input>` | required | Local spec path, `GH <id>`, or `US <id>` |
| `slug` | inferred | From spec when omitted |
| `output-dir` | `{us-dir}` | Optional override for destination (`{plansDir}/{slug}/`) |

## Steps

1. **Load spec and stack context** — Read the spec input and `config.json` layers/invariants.
   - Done when: stack (layers, db/ORM, frontend framework) is identified, or the step stops to ask for clarification when undetectable.

2. **Draft plan** — Write `{us-dir}/step-01-{slug}.plan.md` following the template below.
   - Done when: every section 0-8 is filled, each stated requirement maps to an entry in the Step-by-Step Plan, and every AC maps to a test case in section 5.

3. **Handoff** — Return the plan path for [02-interview](../02-interview/SKILL.md) (or [03-plan-to-tasks](../03-plan-to-tasks/SKILL.md) when interview is skipped).
   - Done when: caller has the `step-01-` path.

## Plan Template

```markdown
---
slug: {slug}
title: "{title}"
status: "plan to be refined"
---

## 0. Summary & Business Rules
Feature objectives, target business rules, security mitigations.

## 1. Definition of Ready & Scope
Resolved assumptions, measurable Acceptance Criteria (ACs), out-of-scope boundaries.

## 2. Technical Design & Architecture
Layer edits (per config.json layers): backend files, db schema, entity mappings. Frontend edits: pages, routes, API endpoints, styling, i18n keys. Invariant checks from config.json.invariants.

## 3. Step-by-Step Plan
Steps ordered by dependency, e.g.: Domain & Database → Application Core → Backend Unit Tests → Frontend & UI → Frontend Tests. For each step: action details, affected files, engineering checks.

## 4. Permissions, Tenancy & i18n
RBAC permissions, tenant data leakage isolation checks, dynamic i18n strings.

## 5. Test Coverage
Map each AC (AC1, AC2, ...) to specific test cases and method names.

## 6. Invariants (Do Not Violate)
Reiterate strict architectural invariants from config.json.invariants.

## 7. Pre-PR Checklist
- [ ] Layer boundaries respected.
- [ ] Domain entities and mappings encapsulated.
- [ ] Schema migrations created.
- [ ] Authorization checks applied.
- [ ] i18n keys declared.
- [ ] Test cases cover all ACs.

## 8. Open Questions
Ambiguities, blocked tasks, or architectural decisions requiring reviewer input.
```

## Rules of Engagement

- The plan must contain sufficient detail for direct coding task generation.
- Do not write product code: this skill is strictly for planning and documentation.
- If the project stack cannot be detected from `config.json`, stop and ask for clarification.

Language: en-us only.
