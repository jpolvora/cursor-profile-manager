# Spec-to-PR — Diagrams (FSM 0–9)

> **Architecture:** Steps 0–9. Pipeline skills live under `.agents/skills/00`–`09` (+ unprefixed `goal-fix-pr`, `update-plan-implementation`). Dual-mode with [`spec-to-pr-lite`](../spec-to-pr-lite/SKILL.md) (lite steps 0–5). Canonical artifacts: [`ARTIFACTS.md`](ARTIFACTS.md). Gates/config: [`gates.md`](../shared/gates.md), [`config-resolution.md`](../shared/config-resolution.md). Agent contract: [`SKILL.md`](SKILL.md).

---

## 0. Phases (standard)

```mermaid
flowchart LR
  F0[F0 Bootstrap<br/>step 0] --> F1[F1 Planning<br/>steps 1–3]
  F1 --> F2[F2 Implement<br/>step 4]
  F2 --> F3[F3 Check<br/>step 5]
  F3 --> F4[F4 Review<br/>step 6 + fix substep]
  F4 --> F5[F5 Testing<br/>step 7]
  F5 --> F6[F6 Ship + Fix-PR<br/>steps 8–9]
```

Lite: F0=0 · F1=1 · F2=2 · F3=3 · F4=4 · F5=5 (no Testing / interview / DAG / check).

---

## 1. Standard pipeline (steps 0–9)

```mermaid
flowchart TD
  S0[0 Spec] --> S1[1 Plan]
  S1 --> S2[2 Interview]
  S2 --> S3[3 Plan-to-tasks]
  S3 --> S4[4 Implement]
  S4 --> S5[5 Check-implementation]
  S5 -->|score ≥ 7| S6[6 Code-review]
  S5 -->|score < 7| G5{Refine / Replan / Respec / Approve}
  G5 --> S4
  G5 -->|approve| S6
  S6 -->|findings| Fix[Fix substep<br/>ws-implement-tasks]
  Fix --> S7[7 Testing]
  S6 -->|clean| S7
  S7 --> S8[8 Ship<br/>delivery + push/PR]
  S8 --> S9[9 Fix-PR]
```

---

## 2. Lite pipeline (steps 0–5)

```mermaid
flowchart TD
  L0[0 Spec — same entry as standard] --> L1[1 Plan]
  L1 --> L2[2 Implement]
  L2 --> L3[3 Review + conditional fix]
  L3 --> L4[4 Ship]
  L4 --> L5[5 Fix-PR]
```

---

## 3. Skill folder map (filesystem)

| Step (standard) | Skill `name:` | Folder |
|-----------------|---------------|--------|
| 0 | `ws-write-spec` | `00-write-spec` |
| 1 | `ws-write-plan` | `01-write-plan` |
| 2 | `ws-interview` | `02-interview` |
| 3 | `ws-plan-to-tasks` | `03-plan-to-tasks` |
| 4 / 6-fix | `ws-implement-tasks` | `04-implement-tasks` |
| 5 | `ws-verify-plan` | `05-verify-plan` |
| 6 | `ws-code-review` | `06-code-review` |
| 7 | `ws-testing` | `07-testing` |
| 8 | `ws-ship-pr` | `08-ship-pr` |
| 9 | `ws-fix-pr` / `ws-goal-fix-pr` | `09-fix-pr` / `goal-fix-pr` |
| Post | `ws-update-plan-implementation` | `update-plan-implementation` |

---

## 4. Dispatch cycle (per step)

```mermaid
flowchart LR
  Gate[Post-step gate] --> Advance[Next / Advance]
  Advance --> Tip[Optional soft tip]
  Tip --> Disp[dispatch-agent / inline]
  Disp --> Ingest[Ingest step-output]
  Ingest --> State[Update state.md]
  State --> Gate
```

Universal controls ([`gates.md`](../shared/gates.md)): **Next**, **Previous**, **Replay**, **Refine→Replay**, **Commit**, **Undo**.

---

## 5. Step 7 — Testing

```mermaid
flowchart TD
  Start[Step 7] --> Skip{skipTesting / no test surface?}
  Skip -->|yes| Ship[Advance Step 8]
  Skip -->|no| Plan[testing.plan.md]
  Plan --> Run[Unit + integration/E2E + coverage + feature quality]
  Run --> Report[testing.report.md]
  Report --> Ship
```

Artifacts: `step-07-{slug}.testing.plan.md`, `step-07-{slug}.testing.report.md`.

---

## 6. Ship + Fix-PR split

```mermaid
flowchart LR
  S8[Step 8 Ship] -->|create PR| PR[prUrl / prId]
  PR --> S9[Step 9 Fix-PR]
  S9 --> Loop[ws-goal-fix-pr or ws-fix-pr]
  Loop --> Merge[Merge policy]
```

`ws-ship-pr` with `stopBeforeFixPr: true` in orch mode — no goal-fix loop inside ship.

---

## Legend

| Symbol | Meaning |
|--------|---------|
| Dispatch | Subagent via `dispatch-agent` (host-provided) |
| Inline | Same session (lite) |
| Gate | user-gate / markdown fallback |

## Triggers

`/spec-to-pr` · `@[spec-to-pr]`.
