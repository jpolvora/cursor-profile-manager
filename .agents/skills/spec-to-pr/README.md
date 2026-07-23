# Spec-to-PR

> **Human audience.** Orchestrator FSM lives in [`SKILL.md`](SKILL.md) — English agent contract. Use this README + [`DIAGRAM.md`](DIAGRAM.md) for onboarding. FAQ sections that still mention steps 11–13 are **legacy**; trust [`SKILL.md`](SKILL.md) / this README for steps **0–9**.
>
> **Current:** Standard FSM steps **0–9** (F0–F6). Pipeline skill folders `00`–`09` (+ unprefixed `goal-fix-pr`, `update-plan-implementation`). Dual-mode with [`spec-to-pr-lite`](../spec-to-pr-lite/SKILL.md) (steps 0–5). Tools via [`tools.md`](../shared/tools.md). Config: `.agents/skills/shared/config.json`.
>
> **Identity:** `/spec-to-pr` / `@[spec-to-pr]`. Runtime tags: `uswf/`; plan slugs: `us-{id}`.

End-to-end Spec → PR pipeline using **orchestrator + sub-agents**, shared state, and confirmation gates (session model on each transition; switch via Pause → IDE/agent host → Resume).

## Core Goals

1. **End-to-End Delivery:** Spec → plan → interview → implement → check → review → testing → ship → fix-pr (steps **0–9**).
2. **Context Isolation:** Fresh `dispatch-agent` per step where practical; shared `state.md` + `MEMORY.md`.
3. **Safety & Gates:** Explicit transitions; combined delivery+ship at Step 8; Fix-PR at Step 9.
4. **Portability:** Stack-agnostic; metadata from `config.json` / `STACK.md`.

| Document | Audience | Content |
|----------|----------|---------|
| **This README** | Humans + agents | Overview, phases, steps, flags |
| [`docs/faq.md`](docs/faq.md) | Humans | FAQ (partially legacy numbering — prefer SKILL for FSM) |
| [`SKILL.md`](SKILL.md) | **Agent (FSM)** | Contract, invariants, dispatch |
| [`DIAGRAM.md`](DIAGRAM.md) | Visual | Mermaid 0–9 / lite 0–5 |
| [`ARTIFACTS.md`](ARTIFACTS.md) | Both | Canonical filenames |

**Project entry:** [`shared/AGENTS.md`](../shared/AGENTS.md) (or root [`AGENTS.md`](../../../AGENTS.md) when authoring against the source repo).

---

## Phases (standard)

| Phase | Name | Steps | Notes |
|-------|------|-------|-------|
| **F0** | Bootstrap | 0 | Spec / providers / free-text |
| **F1** | Planning | 1–3 | Plan → interview → plan-to-tasks |
| **F2** | Implement | 4 | `ws-implement-tasks` build |
| **F3** | Check | 5 | Score 0–10 vs refined ‖ spec; &lt;7 gate |
| **F4** | Review | 6 | Code-review + **conditional fix** substep |
| **F5** | Testing | 7 | `ws-testing` (skippable) |
| **F6** | Ship + Fix-PR | 8–9 | Combined delivery+ship; then fix-pr |

Lite: 0 Spec → 1 Plan → 2 Implement → 3 Review → 4 Ship → 5 Fix-PR (no Testing / interview / DAG / check).

### Happy path

```text
/spec-to-pr 2416
  → 0 Spec → 1 Plan → 2 Interview → 3 Tasks
  → 4 Implement → 5 Check (≥7 or approve-below-7)
  → 6 Review (+ fix if Critical/Warning) → 7 Testing
  → 8 Ship (delivery commit + push/PR) → 9 Fix-PR
```

Flags combinable, e.g. `full auto dry-run` — see [`setup.md`](../shared/setup.md).

---

## How to start

```text
@[spec-to-pr] 2338
@[spec-to-pr] contoso/MyProject#2338
@[spec-to-pr] ADO 2338
@[spec-to-pr] specs/my-feature.spec.md
@[spec-to-pr] dry-run 2338
@[spec-to-pr] auto 2338
@[spec-to-pr] auto dry-run full 2338
@[spec-to-pr] auto skip-testing 2338
@[spec-to-pr] auto skip-tests skip-testing 2338
@[spec-to-pr] soft-delete for suppliers
```

State: `{plansDir}/us-{id}/{workflow-id}.state.md` (`dryRun`, `autoMode`, `skipTesting`, `skipTests`, `fullMode`).

### Flags

| Flag | Effect |
|------|--------|
| `auto` | Recommended option at every gate; no interactive menus |
| `dry-run` | Simulate; no commits/push/code edits/browser/`MEMORY` writes |
| `skip-testing` | Skip Step 7 Testing |
| `skip-tests` | Skip implement-time test suite runs (build still runs) |
| `full` | Step 8 Recommended = commit plan+result then create PR |
| `strict` | Full verification matrix at Step 5 |

**Combined switches:** any mix supported (e.g. `full` + `auto` + `dry-run` for automated end-to-end dry-run). Documented in [`setup.md`](../shared/setup.md).

### Model selection

Session model only. Pause → switch in IDE/agent host → Resume. No `--model` / `--model-chain`.

---

## Steps (standard)

| # | Name | Skill / action | Objective |
|---|------|----------------|-----------|
| **0** | Spec | providers / `ws-write-spec` | `step-00-{slug}.spec.md` |
| **1** | Plan | `ws-write-plan` | `step-01-{slug}.plan.md` |
| **2** | Interview | `ws-interview` | `step-02-{slug}.plan.refined.md` |
| **3** | Plan-to-tasks | `ws-plan-to-tasks` | exec + DAG |
| **4** | Implement | `ws-implement-tasks` | Code |
| **5** | Check-implementation | `ws-verify-plan` | Score 0–10; &lt;7 gate |
| **6** | Code-review | `ws-code-review` (+ fix substep) | `step-06-{slug}.review.md` |
| **7** | Testing | `ws-testing` | `step-07-{slug}.testing.*` |
| **8** | Ship | `ws-ship-pr` | Delivery + push/PR → `step-08-{slug}.result.md` |
| **9** | Fix-PR | `ws-fix-pr` / `ws-goal-fix-pr` | Threads → merge policy |

Post-workflow QA deltas: `ws-update-plan-implementation` (`update-plan-implementation`).

### Step 7 — Testing (summary)

Unit + integration/E2E + coverage + feature-quality checks. Auto-skip when `skipTesting` or no meaningful test surface and unit suite already green. Browser gated; skipped in auto/dry-run.

### Golden rule

After Transition Gate **Next**, dispatch the next step in the **same turn**. Universal controls: Next / Previous / Replay / Refine→Replay / Commit / Undo ([`gates.md`](../shared/gates.md)).

---

## Git checkpoints

Local tags **never pushed**: `uswf/{workflow-id}/before-step-{N}`.

---

## Dual-mode

Same skills, `shared/config.json`, `gates.md`. `workflowType`: `standard` | `lite` — no cross-resume. Lite has **no** Testing step.

---

## Related

- Lite orchestrator: [`spec-to-pr-lite/SKILL.md`](../spec-to-pr-lite/SKILL.md)
- Shared bootstrap: [`setup.md`](../shared/setup.md)
- Step dispatch (standard only): [`STEP-DISPATCH.md`](STEP-DISPATCH.md)
- Dry-run FSM test runbook: [`spec-to-pr-run-test.md`](spec-to-pr-run-test.md)
