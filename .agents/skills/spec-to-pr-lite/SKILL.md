---
name: spec-to-pr-lite
description: >-
  Spec-to-PR lite delivery orchestrator FSM. Fast sequential spec → plan → implement → review → ship → fix-pr.
  Invoke: /spec-to-pr-lite | @[spec-to-pr-lite]. Entry: GitHub issue | Azure DevOps work item | *.spec.md | plain text.
  Flags: dry-run, auto, skip-tests, full. Flags combine freely (e.g. full + auto + dry-run).
  Inline execution in main session. Dual-mode compatible with spec-to-pr (shared skills, shared/config.json, shared/gates.md).
upstream: jpolvora/workflow-skills — this skill is a workflow owned by workflow-skills. Improvements must be submitted upstream to https://github.com/jpolvora/workflow-skills
---

# Spec-to-PR Lite — Orchestrator

Deterministic FSM for sequential spec-to-ship delivery. Reuses the **same** pipeline skills as [`spec-to-pr`](../spec-to-pr/SKILL.md). Dual-mode contract: [`gates.md`](../shared/gates.md), [`config-resolution.md`](../shared/config-resolution.md), [`setup.md`](../shared/setup.md). Do **not** load [`spec-to-pr/STEP-DISPATCH.md`](../spec-to-pr/STEP-DISPATCH.md) for lite step numbers — that file is standard-orch only (0–9).

## Core Goals

1. **Faster Turnaround:** Skip interview, DAG, check-implementation, and Testing steps.
2. **Same entry as standard:** SCM, `*.spec.md`, draft spec, or plain-text via `ws-write-spec` ([`setup.md`](../shared/setup.md) § Shared entry).
3. **Compatible gates:** Universal step controls, combined delivery+ship at Step 4, fix-pr at Step 5.
4. **Portability:** Config only from `.agents/skills/shared/config.json`.

## Invariants

- **Entry:** Same matrix as standard — GitHub, ADO, local-spec, free-text (`setup.md`). No “existing spec only” restriction.
- **`workflowType: lite`** in state — resume never cross-mixes with `standard`.
- **Inline execution:** Orchestrator executes steps inline in the main session (no subagent dispatch).
- **State hygiene:** `python .agents/skills/spec-to-pr-lite/scripts/update_state.py` after every step. Pass measured `--elapsed` (required for completed/failed). Upserts `## Telemetry log`. Missing telemetry → treat as hygiene fail.
- **Artifacts:** Spec `step-00-{slug}.spec.md`; plan `step-01-{slug}.plan.md`; result `step-08-{slug}.result.md` (shared with standard).
- **Commits:** Code during implement/review fix substep. Plan + result at Step 4 combined ship gate (G2-delivery).
- **Ship:** Combined delivery+ship gate at Step 4; `08-ship-pr` with `workflowMode: true`, `stopBeforeFixPr: true`.
- **Fix-PR:** Step 5 first-class (`ws-goal-fix-pr` / `ws-fix-pr`).
- **Branch-direct** default; worktree when `plans.useWorktrees=true`.

---

## Steps 0–5 Index

| Step | Label | Inline? | Skill | Notes |
|------|-------|---------|-------|-------|
| 0 | Spec | ✓ | providers / `ws-write-spec` | Shared entry matrix |
| 1 | Planning | ✓ | `ws-write-plan` | No interview / DAG |
| 2 | Implementation | ✓ | `ws-implement-tasks` build | Build/tests unless `skipTests` |
| 3 | Code Review | ✓ | `ws-code-review` (+ conditional fix substep) | Fix only when Critical/Warning |
| 4 | Ship | ✓ | orch + `ws-ship-pr` | Combined delivery + ship gate |
| 5 | Fix-PR | ✓ | `ws-goal-fix-pr` / `ws-fix-pr` | After PR exists |

---

## Transition menu (every step boundary)

Per [`gates.md`](../shared/gates.md) **universal step controls**:

**Banner:** Current model + Pause → switch in IDE/agent host → resume.

1. **Advance** (Recommended)
2. **More options…** → Previous / Repeat / Refine→Replay / Commit / Undo commit / Pause / Cancel

Lite has **Previous (Go back)** — same as standard. No phase soft tips.

---

## FSM Step Instructions

### Step 0: Spec

Resolve input via [`setup.md`](../shared/setup.md) § Shared entry (GitHub / ADO / local-spec / free-text).

- Output: `step-00-{slug}.spec.md`
- Optional soft clarify if AC empty (not a full interview)
- Gate: Advance → Step 1

### Step 1: Planning

- Execute `ws-write-plan` inline using `step-00-{slug}.spec.md`.
- Output: `step-01-{slug}.plan.md`.
- Gate: Advance → Step 2.

### Step 2: Implementation

- Execute `ws-implement-tasks` `mode=build` inline with `step-01-{slug}.plan.md`.
- Run verification (build + tests unless `skipTests`).
- Gate: Advance → Step 3.

### Step 3: Code Review (+ conditional fix)

- Execute `ws-code-review` inline vs base branch.
- Output: `step-06-{slug}.review.md` (shared artifact name with standard).
- **Fix substep** (only when Critical/Warning):
  - `ws-implement-tasks` `mode=fix` → optional `step-06-{slug}.fix.report.md`
  - User may decline → log skip and Advance
- Clean review → Advance → Step 4.

### Step 4: Ship (delivery + push/PR)

1. Mark checklists in `step-01-{slug}.plan.md` `[x]` where done.
2. Write `step-08-{slug}.result.md` (summary, files, **Benchmark with Total wall-clock time** from `telemetry.totalElapsedSec`). Show final-board Telemetry (Total time) even in `autoMode`/`fullMode`.
3. **Combined delivery + ship gate** ([`gates.md`](../shared/gates.md)):
   - Commit plan + result, then create PR (Recommended when `fullMode`)
   - Commit plan + result, push only
   - Commit plan + result, skip PR
   - Skip delivery commit and skip shipping
   - Pause
4. On delivery commit: `docs({slug}): delivery plan and result`; MEMORY sweep.
5. Execute `ws-ship-pr` inline with `workflowMode: true`, `shipAction`, `stopBeforeFixPr: true`, `workflowType: lite`.
6. Advance → Step 5 when PR created (or skip path complete).

### Step 5: Fix-PR

- **Wait for code-review / CI** (≥300s settle + poll checks/threads) — do not merge yet.
- Dispatch `ws-goal-fix-pr` (default) or `ws-fix-pr` (one-shot) until **no open issues** (`activeThreads == 0`).
- **Merge** via SCM `merge-pr` only after convergence and required checks are green.
- Never delete `project.workingBranch` after merge.

---

## user-gate / Auto-gate defaults

Prefer `user-gate` when available; markdown fallback per [`gates.md`](../shared/gates.md). `autoMode` uses index 0 below.

| Context | Index 0 |
|---------|---------|
| Transitions | Advance |
| Step 3 fix substep | Apply fixes (if findings) |
| Step 4 combined ship (`fullMode`) | Commit plan + result, then create PR |
| Step 4 combined ship (not `fullMode`) | Skip delivery commit and skip shipping |
| Step 5 | Run goal-fix-pr loop |

---

## State & execution

### Base Prompt Prefix (Inline execution instructions)

```markdown
# Inline — Step {STEP} — {Label}
Read state: `{us-dir}/{workflow-id}.state.md`
Skill: {SKILL.md path} — read full.
Orch: spec-to-pr-lite · model {currentModel} · {modeFlags} · workflowType: lite · workflowMode: true
Enhancing skills (mandatory): karpathy-guidelines, caveman, self-learning, gabarito
Read: state workflow memory + decisions; MEMORY.md index; `config.json.rules.stackFile`.
Config/SCM: `.agents/skills/shared/config-resolution.md`
Anchor: uswf/{workflow-id}/before-step-{STEP} @ {sha} · CWD: {repo-root}
Role: fresh; no resume. files_touched required. model: {currentModel}.
Rules: no `{plansDir}/` in git-add except Step 4 G2-delivery; needs_user: ≥2 choices, recommended first.
End with ```step-output(...)```
```

---

## Triggers

```
@[spec-to-pr-lite] [auto|dry-run|skip-tests|full] [US {issue_id} | {org}/{project}#{id} | {name}.spec.md | "feature description"]
/spec-to-pr-lite [flags] [US {issue_id} | {org}/{project}#{id} | {name}.spec.md | "feature description"]
```

For interview, DAG, check-implementation, or Testing: use `/spec-to-pr` instead.
