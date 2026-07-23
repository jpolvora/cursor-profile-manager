---
name: spec-to-pr
description: >-
  Spec-to-PR delivery orchestrator FSM (F0–F6, steps 0–9). Agent contract only — not human docs.
  Invoke: /spec-to-pr | @[spec-to-pr]. Entry: GitHub issue | Azure DevOps work item | *.spec.md | feature description.
  Flags: dry-run, auto, skip-testing, skip-tests, full, strict.
  Flags combine freely (e.g. full + auto + dry-run for automated end-to-end dry-run). Delegates via `dispatch-agent` (host subagent dispatch).
upstream: jpolvora/workflow-skills — this skill is a workflow owned by workflow-skills. Improvements must be submitted upstream to https://github.com/jpolvora/workflow-skills
---

## Audience & load

| Audience | Doc |
|----------|-----|
| **Orchestrator (this file)** | FSM + tool bindings + asserts |
| **Humans** | [`README.md`](README.md), [`docs/faq.md`](docs/faq.md), [`DIAGRAM.md`](DIAGRAM.md) |

**Load:** current step + linked protocols only. Setup → [`setup.md`](../shared/setup.md). Gates (dual-mode) → [`gates.md`](../shared/gates.md). Config/SCM → [`config-resolution.md`](../shared/config-resolution.md). Artifacts → [`ARTIFACTS.md`](ARTIFACTS.md). Dispatch → [`STEP-DISPATCH.md`](STEP-DISPATCH.md) (load only when advancing/dispatching). Protocols → [`protocols/`](protocols/) (on demand). Stack → `config.json.rules.stackFile` (auto-loaded steps 4, 6, 7). Hub → [`AGENTS.md`](../shared/AGENTS.md) (consumer shared hub; optional project root `AGENTS.md` when the host provides one). Step 2 → [`02-interview`](../02-interview/SKILL.md). Tools → [`tools.md`](../shared/tools.md). Dual-mode with [`spec-to-pr-lite`](../spec-to-pr-lite/SKILL.md): shared skills must stay interchangeable.

## Language

**All skill content and user-facing output: English.** No PT/PT-BR in instructions, gates, banners, Progress Board.

## Native tool contract

Canonical tool names from [`tools.md`](../shared/tools.md). Project params from [`config.json`](../shared/config.json) (repo-root path: `.agents/skills/shared/config.json`). Never narrate undone work.

| Intent | Tool alias | Native | Rule |
|--------|------------|--------|------|
| Step work | `dispatch-agent` | subagent dispatch (host-provided) | `subagent_type: generalPurpose\|shell`; `description: "STP step {N} — {Label}"`; `readonly: true` step 5 only; no resume across steps; step 4 DAG ≤3 parallel |
| User gate | `user-gate` / `user-gate-auto` | `user-gate` | Prefer when available; markdown fallback per [`gates.md`](../shared/gates.md); ≥2 options; recommended first; cancelled → HS-1; auto → auto-gate |
| Build/test | `build-backend`, `test-backend`, etc. | `Shell` | values from `config.json.verification` |
| Source control | `commit-code`, `push-branch`, etc. | `Shell` | `gh`, `git`; cite real output |
| State | `read-state` / `write-state` | `Read` + `Write`/`StrReplace` | truth source; hygiene before board |
| Search | `search-code` | `Grep`/`Glob` | MEMORY.md index; `{plansDir}/*/*.state.md` resume |
| Browser (step 7) | `browser-mcp` | `CallMcpTool` | normal mode only, non-dry-run, non-skip, gated |
| State check | `run-script validate_state` | `Shell` | optional |
| Code edits | `dispatch-agent` Coder | subagent dispatch (host-provided) | orch never edits — hard stop |

Subagents: native tools for evidence; end with parseable `step-output` block.

User output: post-tool summaries + Progress Board + banners.

### User gates (user-gate)

Prefer native structured choice UI (`user-gate`) for normal-mode decisions; if unavailable, same options as markdown list (Recommended first). Full contract: [`gates.md`](../shared/gates.md) — slim transitions, combined delivery+ship at Step 8, Fix-PR at Step 9. Applies to transitions, entry/resume/config, refinement 2c (2e only if needed), G2-code, Step 8 delivery+ship, Step 9 fix-pr. Cancelled → **HS-1**. `autoMode` → auto-gate index 0.

---

# Spec-to-PR — Orchestrator

Deterministic FSM; step content delegated to skills via **`dispatch-agent`**.

## Core Goals
1. **End-to-End Delivery:** Automate the entire feature/US lifecycle from specification bootstrap through PR creation and thread resolution (steps 0 to 9).
2. **Context Isolation & State Hygiene:** Run each step in a clean, isolated subagent (`dispatch-agent`) with optional step worktrees, while keeping state sync (`state.md` + `MEMORY.md`) strictly valid.
3. **Safety & Gates:** Enforce transition gates and explicit authorization before coding, review fixes, testing, and shipping.
4. **Portability:** Keep the orchestrator FSM stack-agnostic and configuration-driven, resolving all project metadata and commands dynamically from `config.json` and `STACK.md`.

## Invariants

| Topic | Rule |
|-------|------|
| Scope | Steps 0–7 deliver locally (code + plan/report artifacts). Step 8 = delivery commit + push/PR (combined gate). Step 9 = fix-pr / goal-fix-pr after PR exists. No push before Step 8 ship action. |
| Auth | G1+ needs gate. user-gate cancelled → HS-1. Commit → G2 + explicit menu (HS-2). |
| Isolation | Fresh `dispatch-agent`/step; `Shell` tag `uswf/{id}/before-step-{N}`; **branch-direct default**; worktree when `config.plans.useWorktrees=true` (code steps 4, 6-fix, 7 preferred). |
| State | Hygiene `Write`/`StrReplace` → asserts → board. Fail → HS-5. |
| Memory | `state.md` short-term (`## Workflow memory`, `## Accumulated decisions`, `## Doc consolidation log`). Root `MEMORY.md` = generalizable patterns. |
| Dual-mode | Shared skills interchangeable with `spec-to-pr-lite`. Config/gates: [`config-resolution.md`](../shared/config-resolution.md), [`gates.md`](../shared/gates.md). `workflowType: standard`. |
| `dryRun` | No `Write` `src/`/`web/`, no commit/push/worktree/browser/MEMORY `Shell`/`Write`. Prefix `[DRY-RUN]`. |
| `autoMode` | No user-gate; auto-gate option 0. Prefix `[AUTO]`. HS-3/4/5 pause. No browser MCP. Telemetry/`--elapsed` + Step 8 Benchmark/final-board Total time still mandatory. |
| `skipTesting` | Skip Step 7 → `skippedSteps`+`completedSteps`, log, Step 8. Prefer when no API/UI surface and unit tests green. |
| `skipTests` | Skip test suites in STACK.md; build required. `verification.tests: skipped`. |
| `fullMode` | Step 8 combined gate Recommended = commit plan+result then create PR. Default: off (Recommended = commit + skip PR). |
| Banners | `autoMode` or `dryRun` → Step Output Banner every step. |
| Revert | Workflow manifest + checkpoint only — no global `reset --hard` / `restore .`. |
| Checkpoints | Local tag `uswf/{workflow-id}/before-step-{N}` every boundary. |
| **Workflow artifacts** | **Never `git commit` `{plansDir}/` files during Steps 0–7.** Code commits (4 / 6-fix / 7 fix) stage `src/`/`web/`/`tests/` only. Delivery commit at Step 8: plan + `step-08-{slug}.result.md` only. |
| **Pause** | **Pause workflow** keeps **all** artifacts on disk — no cleanup, no delete. `status: active`. |
| Session model | `currentModel` = executing session model. Switch via Pause → IDE/agent host → Resume ([`gates.md`](../shared/gates.md)). |
| Portability | Keep spec-to-pr fully generic and portable. No hardcoded project-specific metadata, paths, solution names, or commands. All dynamic options and metadata must be resolved from `config.json` or `STACK.md`. |

**Runtime tokens:** git tags/worktrees use prefix `uswf/`; plan slugs use `us-{id}`.

## Allowed deps

| Resource | Path |
|----------|------|
| Orchestrator | `SKILL.md` |
| **Artifacts** | [`ARTIFACTS.md`](ARTIFACTS.md) — canonical filenames + path resolution |
| **Setup** | `setup.md` — initialization, config bootstrap, flags, resume, stack file generation |
| **Config** | `.agents/skills/shared/config.json` — project identity, stack, issue trackers, verification commands, invariants |
| **Tools** | `tools.md` — canonical tool aliases |
| Stack | `config.json.rules.stackFile` — project-specific stack reference; derived from config.json and auto-loaded for code review & optimization |
| Scripts | Orchestrator: `check_memory_conflict.py`, `validate_state.py` under `spec-to-pr/scripts/`. Converters + thread helpers: **canonical** under `github-provider/scripts/` and `azure-devops-provider/scripts/` (thin shims remain at `spec-to-pr/scripts/` and `09-fix-pr/scripts/` for canonicity). Local register/mirror: `local-spec-provider/scripts/`. |
| Providers | [`github-provider`](../github-provider/SKILL.md) · [`azure-devops-provider`](../azure-devops-provider/SKILL.md) · [`local-spec-provider`](../local-spec-provider/SKILL.md) — `providers.active` owns `fetch-to-spec`; `providers.scm` owns PR/thread/merge intents |
| SCM CLIs | Via provider skills only (`gh` / `az`); orchestrator does not embed platform CLI recipes |
| State | `{plansDir}/{slug}/{workflow-id}.state.md` |
| Skills | `ws-write-spec`→0 · `ws-write-plan`→1 · `ws-interview`→2 · `ws-plan-to-tasks`→3 · `ws-implement-tasks`→4 build, 6 fix · `ws-verify-plan`→5 · `ws-code-review`→6 · `ws-testing`→7 · `ws-ship-pr`→8 · `ws-fix-pr`/`ws-goal-fix-pr`→9 · `spec-format` |

Filesystem paths: FSM steps `00`–`09` use numeric prefixes; `goal-fix-pr` / `update-plan-implementation` are unprefixed. Skill `name:` uses `ws-` prefix. Post-8 PR threads: [`ws-fix-pr`](../09-fix-pr/SKILL.md) / [`ws-goal-fix-pr`](../goal-fix-pr/SKILL.md).

### Work dir `{us-dir}` = `{plansDir}/{slug}/` (`{plansDir}` ← `config.plans.dir`)

| Entry | `slug` |
|-------|--------|
| Issue `{id}` | `us-{id}` |
| `*.spec.md` | basename or frontmatter `slug:` |

State: `{us-dir}/{workflow-id}.state.md` · Canonical spec: `{us-dir}/step-00-{slug}.spec.md`.

Artifacts: `step-00-{slug}.issue.json`, `step-00-{slug}.spec.md`, `step-01-{slug}.plan.md`, `step-02-{slug}.plan.refined.md`, `step-03-{slug}.plan.exec.md`, `step-03-{slug}.exec.dag.json`, `step-05-{slug}.plan.report.md`, `step-06-{slug}.review.md`, `step-06-{slug}.fix.report.md`, `step-07-{slug}.testing.plan.md`, `step-07-{slug}.testing.report.md`, `step-08-{slug}.result.md` (Step 8 delivery summary — committable).

**Committable (Step 8 only):** `step-01-{slug}.plan.md` (or `step-02-{slug}.plan.refined.md` if generated), `step-08-{slug}.result.md`. Other plan-dir files stay uncommitted unless user explicitly asks.

Git-ignored: `worktrees/step-{N}/`, `{workflow-id}.baseline/`, `{workflow-id}.archive/`. Never write state under `.agents/`.

---

## Phases F0–F6 ↔ steps 0–9

```mermaid
flowchart LR
  F0[F0 Bootstrap] --> F1[F1 Planning]
  F1 --> F2[F2 Implementation]
  F2 --> F3[F3 Check-implementation]
  F3 --> F4[F4 Review + Fix]
  F4 --> F5[F5 Testing]
  F5 --> F6[F6 Ship + Fix-PR]
```

| Phase | Steps | Executor |
|-------|-------|----------|
| F0 | 0 | Orchestrator + spec subagent |
| F1 | 1, 2, 3 | Planner subagent |
| F2 | 4 | Coder subagent |
| F3 | 5 | Verifier (readonly) |
| F4 | 6 (+ fix substep) | Reviewer + Coder |
| F5 | 7 | Verifier + optional browser |
| F6 | 8, 9 | Orchestrator + shell (+ fix-pr subagent when PR exists) |

| `completedSteps` | Phase done |
|------------------|------------|
| 0 | F0 |
| 1–3 | F1 |
| 4 | F2 |
| 5 | F3 |
| 6 | F4 |
| 7 | F5 |
| 8 | F6 (may continue to 9) |
| 9 | F6 fix-pr complete |

## Step index

| N | Label | Dispatch? | `subagent_type` | Worktree | RO |
|---|-------|-------|-----------------|----------|-----|
| 0 | Spec Creation | ✓ | GP | opt‡ | — |
| 1 | Planning and Brainstorm | ✓ | GP | opt‡ | — |
| 2 | Plan Refinement (conditional) | ✓ | GP | opt‡ | — |
| 3 | Execution Plan and DAG | ✓ | GP | opt‡ | — |
| 4 | Implementation (DAG) | ✓ | GP | step-4‡ | — |
| 5 | Check-implementation | ✓ | GP | opt‡ | ✓ |
| 6 | Code Review (+ fix substep) | ✓ | GP+shell | step-6‡ | — |
| 7 | Testing | ✓ | GP+shell | step-7‡ | — |
| 8 | Ship (delivery + push/PR) | ✓ | shell+GP | cleanup | — |
| 9 | Fix-PR | ✓ | GP+shell | — | — |

‡ [Worktree policy](#worktree-policy). GP = `generalPurpose`. Fixed labels for board/banners. Steps 1–3 conditional per [Complexity / Dynamic Execution](#complexity--dynamic-execution).

---

## Protocols

### Authorization Ladder

| Level | Ops | Gate |
|-------|-----|------|
| G0 | Read, RO reports | — |
| G1 | Edit WT, plans, impl (no commit) | Transition gate |
| G2-code | `git commit` **code only** (`src/`, `web/`, `tests/`) | Step 4 / 6 fix substep / 7 fix |
| G2-delivery | `git commit` **plan + `step-08-{slug}.result.md` only** | Step 8 combined delivery+ship gate |
| G3 | `git push`, PR create/merge | Step 8 **ship action** (within combined gate) |

```text
HS-1: user-gate cancelled → STOP; re-present gate. Never infer "yes".
HS-2: Commit without explicit gate menu selection → STOP.
HS-2a: `git add` or commit any `{plansDir}/` path during Steps 0–7 → STOP (workflow artifacts forbidden until Step 8 delivery commit).
HS-3: Mutating step success + empty files_touched → FAILED.
HS-4: Step 4/6-fix/7 success without expected files on state.branch → FAILED.
HS-5: State Hygiene failed → STOP before Progress Board.
```
Auto: HS-3/4/5 apply; HS-1/2 N/A.

### Transition Discipline

**Normal:** N done → Hygiene → checkpoint `before-step-{N+1}` → Board → summary → Transition Gate → dispatch N+1.

**Auto:** auto-gate + dispatch N+1 same turn.

**Forbidden:** mutating step or commit without gate.

### Universal step controls (every boundary)

Available at **every** transition gate (normal mode; under **More options…** when not primary):

| Control | Action |
|---------|--------|
| **Next** | Advance to Step N+1 (default Recommended) |
| **Previous** | Go back to an earlier completed step (backward nav) |
| **Replay** | Re-dispatch current step from checkpoint |
| **Refine** | Replay with refinement intent (maps to Replay + log `refine-replay`) |
| **Commit** | When step produced uncommitted code changes — explicit G2-code menu (never implicit) |
| **Undo** | Revert to checkpoint before current step (manifest algorithm) |

`autoMode`: only **Next** (auto-gate index 0). Backward/Replay/Refine/Commit/Undo disabled.

### Refinement FSM (Step 2)

2a/2b/2d → `02-interview`. Orch: 2c Escalate, 2e Shared Understanding, redispatch.

| State | Owner | Output |
|-------|-------|--------|
| 2a Audit | refine | `gap_registry[]` by design-tree |
| 2b Resolve | refine | Close with evidence; codebase before escalate |
| 2c Escalate | orch | user-gate — **one** question; max 3 rounds; always **End refinement and advance** |
| 2d Exit | refine | §8 empty or `assumed-default`; `shared_understanding: pending` |
| 2e Shared Understanding | orch | Only if 2c did **not** exit via End refinement. Else auto-confirm. |

Rules: multiple `needs_user` → one by design-tree priority. **End refinement and advance** → log `assumed-default`, set `shared_understanding: confirmed`, skip 2e. Block Step 3 only if interview ran and `refine.shared_understanding !== confirmed`.

**Conditional skip:** See [`gates.md`](../shared/gates.md) § Conditional interview. Step 2 grills the **plan**, not the spec.

### Complexity / Dynamic Execution

Before Step 1, classify per [`gates.md`](../shared/gates.md) § Complexity gate. User may override when ambiguous: **Simple path** / **Standard path** (rec) / **Full grill**.

**Simple path:** stub `step-01-{slug}.plan.md`, `execMode: sequential`, skip Steps 1–2–3, jump to Step 4.

### Worktree policy

```text
dryRun → no worktree
default → branch-direct (preferred on win32 and most consumers)
worktree when config.plans.useWorktrees=true AND path≤180 AND git worktree add succeeds
```

Any step **may** use a worktree when `useWorktrees=true`. **Preferred** for code-mutating steps 4, 6-fix, 7. branch-direct: edits on `state.branch`; subagent `wip(us-{id}): step-{N}` or dirty WT. Post-step: files exist, expected diff, build/tests per STACK.md.

### State Hygiene

→ [`protocols/state-hygiene.md`](protocols/state-hygiene.md)

Every completed/failed step: pass measured `--elapsed` into `update_state.py` (required; script rejects omit). Upserts `## Telemetry log`. Missing step-output telemetry or hygiene fail → **HS-5**.

### Model readiness

No in-gate model picker. At every transition, show the gates.md banner (`Current model` + Pause → IDE/agent host → Resume).

When Advance crosses **F1→F2** (after Step 3, before Step 4) or **F3→F4** (after Step 5, before Step 6), add the soft hint from [`gates.md`](../shared/gates.md) (Coder / Reviewer class). Log `model-hint | F1→F2|F3→F4 | current={currentModel} | ISO`. Tags `before-step-4`, `before-step-6` remain for telemetry only.

### Step Dispatch & Isolation

Orch calls **`dispatch-agent`** — never inline step impl.

```yaml
dispatch-agent:
  subagent_type: generalPurpose | shell
  description: "STP step {N} — {Label}"
  readonly: true   # step 5 only
  run_in_background: false   # step 4 parallel (DAG): ≤3 parallel, same worktree, no file overlap
```

Anchor (`Shell` tag): `uswf/{workflow-id}/before-step-{N} @ {sha}`. Worktree via `Shell`: `worktree add` → merge → `worktree remove` → `branch -d`. Max 1 active. Audit: `Write` `stepDispatches[]`. No per-DAG-task worktree.

**Step 4 dispatch:**
- `execMode: sequential` → single `dispatch-agent` `04-implement-tasks` mode `build` with `step-01-*.plan.md` directly (no DAG).
- `execMode: parallel` → DAG: `dispatch-agent` per level, ≤3 concurrent, no file overlap within level.

### Check-implementation score gate (Step 5)

Eval implemented code vs **refined spec when present, else `step-00-{slug}.spec.md`**. Publish integer **score 0–10** in Progress Board + `step-05-{slug}.plan.report.md`.

| Score | Behavior |
|-------|----------|
| ≥ 7 | Complete step 5; Advance to 6 |
| < 7 | User-gate: **Refine** (replay implement + re-check) / **Replan** (back to 1) / **Respec** (back to 0) / **Approve and continue** (log `check-approve-below-7`) |

`--strict`: always run full verification matrix regardless of score. `autoMode`: do **not** auto-approve below 7 — Pause with score (fail closed).

### Code review + conditional fix (Step 6)

| Case | Behavior |
|------|----------|
| Clean (no Critical/Warning) | Complete step 6; Advance to 7 |
| Fixable findings | **Fix substep:** `ws-implement-tasks` mode fix → optional re-review slice → complete step 6 |
| User declines fix | Log skip; Advance with findings (or Pause) |

Fix substep is **not** its own `completedSteps` entry — log `review-fix` in `## Gate history`. Artifacts: `step-06-{slug}.review.md`, optional `step-06-{slug}.fix.report.md`.

### Learning & Memory Protocol

At step start, subagent reads `state.md` (`## Workflow memory`, `## Accumulated decisions`, `## Step outputs`) and `.agents/skills/shared/MEMORY.md` index. After step, record `step-output.learning` → orchestrator appends to `## Workflow memory`.

**Step 8 sweep:** Promote generalizable patterns to `shared/memory/*.md` + run `self_learning.py --compile`. Criteria: technical, generalizable, non-duplicate, concise. `dryRun`: log in `## Doc consolidation log` only.

### Specification Protocol

[`spec-format`](../spec-format/SKILL.md). Canonical spec: `{us-dir}/step-00-{slug}.spec.md` — never live tracker APIs and never `*.issue.json` after Step 0.

| Input | Tracker / provider | Action | Uses Step 0? |
|-------|--------------------|--------|--------------|
| `{n}` or `US {n}` | `providers.active` | `fetch-to-spec` → `{us-dir}/step-00-us-{n}.spec.md` | No — skip to Step 1 |
| `{org}/{project}#{id}` / `ADO {id}` / `WI {id}` | `azure-devops-provider` | `fetch-to-spec` | No — skip to Step 1 |
| `*.spec.md` | `local-spec-provider` | `fetch-to-spec` | No — skip to Step 1 |
| free-text / no args | none | `00-write-spec` → spec file | Yes — `dispatch-agent` `00-write-spec` |

Provider resolution and `fetch-to-spec` dispatch: load active provider skill; auth failure → STOP (no silent fallback). Details in each provider `SKILL.md`.

### Step 0 Entry Gate

1. **Tracker id** → provider `fetch-to-spec` → skip Step 0 → Step 1 gate.
2. **Local `*.spec.md`** → `local-spec-provider` → skip Step 0 → Step 1 gate.
3. **No args / free-text** → Entry menu: issue/spec path / brainstorm (`00-write-spec` only path).

Store `specPath` in state `## Artifacts`.

### Build & Test Validation (4, 6-fix, 7)

Before G2-code commit: `config.json.rules.stackFile` → build (+ tests unless `skipTests`) → Coder fix loop. Stage **only** `src/`, `web/`, `tests/` — never `{plansDir}/`. `skipTests`: `verification.tests: skipped`.

### Testing (Step 7)

`07-testing` via **`dispatch-agent`** (label **Testing** — broader than integration-only). `skipTesting` → skip to Step 8. `autoMode`/`dryRun` → `dispatch-agent` without browser.

Gates (normal): **Approve and run test battery** (rec) / **Run without browser** / **Adjust test plan** / **Skip validation** / **Pause workflow**.

Failure (max 3): **Apply fixes and revalidate** (rec) / **Accept with reservations** / **Re-run without fixes** / **Pause**. Fix: G2-code commit only.

### Workflow Artifact Commit Protocol

| When | Allowed |
|------|---------|
| Steps 0–7 | **Code only** under `src/`, `web/`, `tests/` at Steps 4, 6 fix, 7 fix |
| Steps 0–7 | **Forbidden:** `{plansDir}/**`, exec/dag/report/state/issue files |
| Step 8 | Plan + `step-08-{slug}.result.md` — delivery commit via G2-delivery gate |
| Pause | No commit; no delete |

Orch `git add` must be path-scoped — never `git add .` on code-commit steps.

### Ship — delivery + push/PR (Step 8)

→ [`protocols/delivery-result.md`](protocols/delivery-result.md) (writes `step-08-{slug}.result.md`)

**Order:** delivery result → **combined delivery + ship user-gate** → on delivery commit: MEMORY sweep → optional temp delete per [`protocols/artifact-cleanup.md`](protocols/artifact-cleanup.md).

**Combined gate** ([`gates.md`](../shared/gates.md) + [`STEP-DISPATCH.md`](STEP-DISPATCH.md)):

1. **Commit plan + result, then create PR** (Recommended when `fullMode`)
2. **Commit plan + result, push only**
3. **Commit plan + result, skip PR**
4. **Skip delivery commit and skip shipping**
5. **Pause**

Dispatch `ws-ship-pr` with `workflowMode: true`, `shipAction`, `stopBeforeFixPr: true` — **no goal-fix loop inside ship**. Advance to Step 9 when PR created and `fullMode` / user chose create-pr.

### Fix-PR (Step 9)

First-class step after Step 8 when `shipAction: create-pr` and PR exists (canonical detail: [`STEP-DISPATCH.md`](STEP-DISPATCH.md) § Step 9):

1. **Wait for code-review / CI** (≥300s settle + poll checks/threads) — do not merge yet.
2. Dispatch `ws-goal-fix-pr` (default loop) or `ws-fix-pr` (one-shot) until **no open issues** (`activeThreads == 0`).
3. **Merge** via SCM `merge-pr` only after convergence and required checks are green.

Stop: max exhausted · escalate · merge blocked · cancelled · PR closed · checks red.

### Progress Board & banners

→ [`protocols/progress-board.md`](protocols/progress-board.md)

### Automatic Mode

Parse: `auto` + combinable `dry-run`, `skip-testing`, `skip-tests`, US/spec entry.

Resume: active `autoMode` same US → continue `currentStep`; else new `workflow-id`.

| Context | Auto choice (index 0) |
|---------|----------------------|
| Step 0 entry gate | **I have a US/issue number** (user must provide in invocation) |
| Complexity ambiguous | **Standard path** |
| Transition 0–6, 9 | **Advance to Step N+1** |
| Transition / phase model | **Advance** with session `currentModel` (no `--model-chain`) |
| Step 2 needs_user | first option; early → **End refinement and advance** (auto-confirms 2e) |
| Step 2e (only if shown) | **I confirm shared understanding — advance to Step 3** |
| Step 5 score < 7 | Pause (fail closed — no auto-approve) |
| Step 7 skipTesting / no API-UI | skip step |
| Step 7 plan | **Approve and run test battery without browser** |
| Step 7 failure | **Apply fixes and revalidate** |
| Step 8 combined gate (`fullMode`) | **Commit plan + result, then create PR** |
| Step 8 combined gate (not `fullMode`) | **Commit plan + result, skip PR** |
| Step 9 fix-pr | **Run goal-fix-pr loop** |

Shared defaults: [`gates.md`](../shared/gates.md) § Auto-gate defaults. Log `auto-gate | step {N} | {choice} | ISO`. Disabled: backward/repeat/pause menus; Step 3 without shared understanding.

### Checkpoints

Tag `uswf/{workflow-id}/before-step-{N}` = HEAD before step N first mutation. `before-step-1` = `baselineCommit`. Mirror in `checkpoints[]`. Delete on Step 8 completion/reset. Dry-run: log only.

### Safe Revert & Backward Navigation

**Revert** = manifest to checkpoint M. Scope: `reset --mixed` → per-path restore from `## Step file log` → remove worktrees ≥M → truncate state <M. Verify `preExistingDirty`. Forbidden: global `reset --hard`, `checkout -- .`, `restore .`, `clean -fd`, stash, push `uswf/*` tags.

**Bootstrap revert data:** `baselineCommit`, `preExistingDirty[]`, backup `{workflow-id}.baseline/`. Full reset: M=1 + new workflow-id.

**Backward nav** (normal only): Gate **Go back** / **Previous** or Step 5→4 shortcut. Targets: 0–7 in `completedSteps`. Sub-menu: Planning/Implementation/Review/Testing/Ship → confirm → checkpoint revert → redispatch M. Log `backward-nav | from | to | ISO`.

---

## State & dispatch

### `state.md` YAML

```yaml
workflowId, slug, us, specSource, specPath
startedAt, endedAt, status: active|completed|cancelled|failed
currentStep, dryRun, autoMode, skipTesting, skipTests, fullMode
execMode: sequential|parallel|null  # set after Step 3
branch, baselineCommit, preExistingDirty: []
checkpoints, workflowManifest, commits: [{sha, step, message}]
completedSteps, stepStatus, skippedSteps, completedTasks, stepDispatches
refineRound, currentModel  # session-derived; refresh on resume
stepModels: [{step: N, model: "name", dispatched: ISO}]
# modelChain removed — ignore if present in old state files
telemetry:
  workflowStartedAt: ISO
  workflowEndedAt: null
  totalElapsedSec: null
  loc: { baseline, final, added, removed, netDelta }
  totalTokens: int|null
  steps: [{ N, label, dispatchedAt, finishedAt, elapsedSec, promptTokens, completionTokens, estimated, model, filesTouched }]
```

Sections: Workflow baseline, manifest, Step file log, Refinement registry, Context, Artifacts, Step outputs, Step model log, Workflow memory, Accumulated decisions, Doc consolidation log, Open items, Gate history.

### Resume / reset

→ [`setup.md`](../shared/setup.md) § Resume / reset

### Base Prompt Prefix (`dispatch-agent` body)

```markdown
# Subagent — Step {STEP} — {Label}
Read state: `{us-dir}/{workflow-id}.state.md`
Skill: {SKILL.md path} — read full.
Orch: SKILL.md § Step {STEP} · model {currentModel} · {modeFlags}
Enhancing skills (mandatory): karpathy-guidelines, caveman, self-learning, gabarito
Read: state workflow memory + decisions + doc log; MEMORY.md index; `config.json.rules.stackFile`.
Anchor: uswf/{workflow-id}/before-step-{STEP} @ {sha} · CWD: {repo-root | worktree}
Role: fresh; no resume. files_touched required (revert). model: {currentModel}.
Rules: no `{plansDir}/` in git-add except Step 8 G2-delivery; needs_user: ≥2 choices, recommended first.
Learning: read ## Workflow memory + ## Step outputs (all prior steps) for traps/errors. Do NOT repeat broken approaches. Record own mistakes in step-output.learning.
Telemetry required: elapsedSec, promptTokens + completionTokens (from LLM metadata if available, else estimate chars/3.5 with estimated: true).
End with ```step-output(status, step, artifacts, files_touched, verification, refine, summary, evidence, decisions, doc_consolidation, needs_user, errors, retry_hint, learning, model, telemetry{elapsedSec, promptTokens|null, completionTokens|null, estimated})
```
```

### Transition Gates

Post-step: hygiene → checkpoint (`Shell` tag) → short summary → gate. Board at phase boundaries.

| Mode | Tool |
|------|------|
| auto | auto-gate table → immediate `dispatch-agent`/`Shell` |
| normal | Prefer `user-gate`; slim menu per [`gates.md`](../shared/gates.md) |

Shows gates.md banner (`Current model` + Pause → IDE/agent host → Resume) and `**Next step:** {N+1} — {Label}`. Primary: **Advance** (Recommended) / **More options…** (universal controls). Soft tips at F1→F2 / F3→F4 only.

---

## Bootstrap & Entry

→ [`setup.md`](../shared/setup.md) § Bootstrap & Entry

## Step instructions

→ [`STEP-DISPATCH.md`](STEP-DISPATCH.md) (load when advancing/dispatching)

## Error policy

Retry: max 3; backoff 0s→30s→60s. Revert: Checkpoint Algorithm only. Conduct: orch never implements code; fresh `dispatch-agent`/step; branch-direct default; G2-code steps 4/6-fix/7; G2-delivery step 8; G3 step 8 push/PR; HS-2a blocks plan-dir commits mid-workflow.

## Post-workflow (outside this agent)

Manual QA after workflow completion (or pause before Step 8) not resumed here. Use [`update-plan-implementation`](../update-plan-implementation/SKILL.md) — append plan §9, implement delta, update `step-08-{slug}.result.md`, certify for PR. Distinct from Step 6 fix substep (in-pipeline review fixes).

## Triggers

```
@[spec-to-pr] [auto|dry-run|skip-testing|skip-tests|full|strict] [US {issue_id} | {org}/{project}#{id} | {name}.spec.md | "feature description"]
/spec-to-pr [flags] [US {issue_id} | {org}/{project}#{id} | {name}.spec.md | "feature description"]
/status | progress | where am I? → Progress Board only
go back | change plan | back to step X → Backward Nav (not in auto)
switch model | change model → Pause workflow, switch in IDE/agent host, resume (no in-gate picker)
```

**Flags:** `auto`, `dry-run`, `skip-testing`, `skip-tests`, `full`, `strict` (full US verification at Step 5). Model = session; switch via Pause → IDE/agent host → Resume ([`gates.md`](../shared/gates.md)).

Gates: [`gates.md`](../shared/gates.md). Config: [`config-resolution.md`](../shared/config-resolution.md).

If invoked **without** US number, spec path, or description:
> **Give me a GitHub issue id, an Azure DevOps work item (`ADO {id}` or `{org}/{project}#{id}`), a path to a hand-written `*.spec.md`, or a free-text feature description to start.**

Examples:
- `/spec-to-pr auto skip-tests skip-testing US 1234`
- `/spec-to-pr "Implement a product analytics dashboard with real-time charts"`
- `/spec-to-pr auto contoso/project#5678`
- `/spec-to-pr ADO 2416`
- `/spec-to-pr specs/my-feature.spec.md`
- `/spec-to-pr full US 99`
- `/spec-to-pr auto skip-tests US 567`
