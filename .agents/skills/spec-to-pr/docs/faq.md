# FAQ — Spec-to-PR

This FAQ documents the canonical behavior of the modern **Spec-to-PR** (Steps 0–9) and **Spec-to-PR Lite** (Steps 0–5) orchestrated workflows.

> **Architecture:**
> - Shared config: [`.agents/skills/shared/config.json`](../../shared/config.json) (see [`config-resolution.md`](../../shared/config-resolution.md))
> - Shared gates: [`gates.md`](../../shared/gates.md)
> - Dynamic paths: [Path tokens](../../shared/tools.md#path-tokens) (`{plansDir}`, `{sharedDir}`, etc.)
> - Model Selection: Switch model only via **Pause → IDE/Agent model picker → Resume** (no in-gate model picker or CLI flags).

---

## Quick Index

| Section | Topic |
| :--- | :--- |
| 1. [Overview](#1-overview) | Core goals, Roles, standard vs. lite differences |
| 2. [Execution Timeline](#2-execution-timeline) | Standard (0–9) and Lite (0–5) step breakdown |
| 3. [Start Options & Modes](#3-start-options--modes) | Command triggers, free-text vs. tracker IDs, dry-run, auto-mode |
| 4. [FSM Steps 0–9 Breakdown](#4-fsm-steps-09-breakdown) | Deep-dive into each individual step of the standard workflow |
| 5. [Gates & Universal Controls](#5-gates--universal-controls) | G0-G3 Authorization ladder, HS-1 to HS-5 Hard Stops |
| 6. [Artifacts & State Lifecycle](#6-artifacts--state-lifecycle) | state.md structure, plansDir artifacts, git checkpoints |
| 7. [Troubleshooting](#7-troubleshooting) | Handling HS pauses, worktree issues, and retry loops |

---

## 1. Overview

### What is Spec-to-PR?
Spec-to-PR is a deterministic **orchestrated software delivery pipeline** designed to automate the entire lifecycle of a User Story or feature request: from initial spec bootstrap, through plan formulation, implementation, check-implementation verification, local code review, testing, shipping (commits/PR), and resolving PR threads.

### Standard vs. Lite Modes
The hub supports two workflows depending on target speed and project complexity:
*   **Standard (`spec-to-pr`)**: Detailed 10-step lifecycle (0 to 9) containing plan refinement interviews, sequential or parallel DAG execution, read-only verify gates, separate code reviews, and testing batteries.
*   **Lite (`spec-to-pr-lite`)**: Fast-track 6-step lifecycle (0 to 5) skipping Plan Refinement interviews, DAG creation, verify gates, and step-7 testing. Steps are executed inline in a single session.

### Who is responsible for what?
*   **Orchestrator Agent**: Manages FSM state, checkpoints, user gates, state hygiene, and dispatches. It **never** writes or edits code directly.
*   **Subagents (`dispatch-agent`)**: Spun up with fresh, clean context to implement specific tasks (e.g. planner, coder, verifier, reviewer). No session memory leaks between steps.
*   **User**: Provides steering decisions at transition gates and approves PR shipping.

---

## 2. Execution Timeline

### Standard FSM Timeline (Steps 0–9)

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

### Lite FSM Timeline (Steps 0–5)

```mermaid
flowchart TD
  L0[0 Spec] --> L1[1 Plan]
  L1 --> L2[2 Implement]
  L2 --> L3[3 Review]
  L3 --> L4[4 Ship]
  L4 --> L5[5 Fix-PR]
```

---

## 3. Start Options & Modes

### Invocation Examples
```bash
# Standard interactive start
/spec-to-pr US 1234
@[spec-to-pr] specs/feature.spec.md

# Non-interactive automated dry-run
/spec-to-pr auto dry-run US 1234

# Skip integration testing
/spec-to-pr skip-testing "Add real-time alerts to the feed"

# Lite workflow trigger
/spec-to-pr-lite US 5678
```

### Modes & Flags
*   `dry-run` (`dryRun: true`): Simulates all operations. Prevents source edits, git commits, remote pushes, browser automation, and memory updates.
*   `auto` (`autoMode: true`): Disables interactive menus. Auto-selects options (index 0). Workflow pauses only on hard stops or if a verify score falls below 7.
*   `skip-testing`: Skips standard Step 7 Testing entirely, moving directly to Step 8 Ship.
*   `skip-tests`: Skips the execution of testing suites (e.g. `npm run test` or `pytest`) in STACK.md. Build checks are still enforced.

---

## 4. FSM Steps 0–9 Breakdown

### Step 0: Spec Creation
*   **Executor**: Orchestrator (dispatches provider skill or `00-write-spec`).
*   **Role**: Resolves the input description or ticket ID into a canonical spec:
    *   **GitHub ID**: Dispatches [`github-provider`](../../github-provider/SKILL.md) to fetch issue and write `step-00-{slug}.spec.md`.
    *   **Azure DevOps ID**: Dispatches [`azure-devops-provider`](../../azure-devops-provider/SKILL.md) to fetch work item and write `step-00-{slug}.spec.md`.
    *   **Local Spec**: Normalizes spec format using [`local-spec-provider`](../../local-spec-provider/SKILL.md).
    *   **Free-text**: Invokes `00-write-spec` to brainstorm and draft the spec.

### Step 1: Planning and Brainstorm
*   **Executor**: Planner subagent (`ws-write-plan` / `01-write-plan`).
*   **Role**: Analyzes the spec and codebase to write a plan file: `step-01-{slug}.plan.md`. This plan covers design, files to modify/create, and acceptance criteria checks.

### Step 2: Plan Refinement (Interview)
*   **Executor**: Planner subagent (`ws-interview` / `02-interview`).
*   **Role**: Audits the plan against the spec and codebase. If there are ambiguities, escalates to the user for confirmation (max 3 rounds) and outputs `step-02-{slug}.plan.refined.md`.
*   **Conditional Skip**: Skipped automatically if complexity is simple, no open questions exist in the plan, and no blocking gaps are detected.

### Step 3: Execution Plan and DAG
*   **Executor**: Planner subagent (`ws-plan-to-tasks` / `03-plan-to-tasks`).
*   **Role**: Parses the plan and splits it into atomic implementation tasks:
    *   **Small plan**: flat list of sequential tasks (`execMode: sequential`).
    *   **Large plan**: directed acyclic graph (`execMode: parallel`), outputting `step-03-{slug}.exec.dag.json`.

### Step 4: Implementation
*   **Executor**: Coder subagent (`ws-implement-tasks` / `04-implement-tasks`).
*   **Role**: Writes code to target paths inside a git worktree (if enabled) or directly on the branch. If parallel, spins up up to 3 parallel subagents per DAG level. No commits are made yet.

### Step 5: Check-implementation
*   **Executor**: Verifier subagent (read-only) (`ws-verify-plan` / `05-verify-plan`).
*   **Role**: Evaluates the written code against the spec/plan and publishes an integer score (0–10).
    *   **Score ≥ 7**: Passes gate.
    *   **Score < 7**: Halts. Requires manual repair, replanning, or explicit override.

### Step 6: Code Review
*   **Executor**: Reviewer subagent (`ws-code-review` / `06-code-review`).
*   **Role**: Runs local static analysis on changed code compared to the base branch.
    *   **Fix Substep**: If Critical or Warning findings are present, runs a coder subagent in `mode: fix` to address the findings before moving forward.

### Step 7: Testing
*   **Executor**: Verifier subagent (`ws-testing` / `07-testing`).
*   **Role**: Writes a test plan and executes unit, integration, and optionally browser verification.

### Step 8: Ship
*   **Executor**: Orchestrator + ship subagent (`ws-ship-pr` / `08-ship-pr`).
*   **Role**: Compiles the delivery summary in `step-08-{slug}.result.md` (including benchmark telemetry) and presents the **Combined Ship Gate**:
    1.  Commit plan + result, then create PR
    2.  Commit plan + result, push only
    3.  Commit plan + result, skip PR
    4.  Skip delivery commit and skip shipping
    5.  Pause
*   **Artifact commits**: Only `step-01-*.plan.md` (or `step-02-*.refined.md`) and `step-08-*.result.md` are added to the delivery commit. Mid-workflow plan files are ignored.

### Step 9: Fix-PR
*   **Executor**: PR fixing subagent (`ws-fix-pr` / `ws-goal-fix-pr`).
*   **Role**: Triggered if a PR is created. Polls the remote PR for comments, runs code fixes iteratively, commits, and pushes until all review threads are resolved.

---

## 5. Gates & Universal Controls

### Authorization Ladder (G0–G3)
| Level | Allowed Operations | Trigger Phase |
| :--- | :--- | :--- |
| **G0** | Read codebase, fetch issue metadata, output reports | Steps 0, 1, 2, 3, 5, 6, 7 (plan) |
| **G1** | Modify workspace files, update state files, draft plans | Step 4, Step 6 (fix), Step 7 (fix) |
| **G2-code** | Commit code changes only under `src/`, `web/`, `tests/` | Step 4, 6 fix, 7 fix boundary |
| **G2-delivery** | Commit plan and result summary files only | Step 8 delivery checkpoint |
| **G3** | Run `git push`, create remote PR, merge PR | Step 8 ship action / Step 9 |

### Hard Stops (HS-1 to HS-5)
If any of these conditions are met, the workflow immediately pauses and exits:
*   **HS-1**: User cancelled or closed the interactive menu. Re-presents menu on resume.
*   **HS-2**: Rogue commit detected (a git commit executed without going through the gate menu).
*   **HS-2a**: Accidental staging/commit of files inside `{plansDir}/` during Steps 0–7.
*   **HS-3**: A mutating code step succeeded but `files_touched` was reported empty.
*   **HS-4**: Touched files reported by the subagent are missing or deleted on the active branch.
*   **HS-5**: State hygiene validation failed (corrupt YAML schema in `state.md`).

### Universal Step Controls (Transition Gate)
Every step transition exposes:
*   **Next (Advance)**: Advance to the next step.
*   **Previous**: Rollback state to an earlier step (restores matching checkpoint).
*   **Replay / Refine**: Re-dispatch the current step.
*   **Commit**: G2-code commit menu for code changes.
*   **Undo**: Revert to the checkpoint taken before the current step started.
*   **Pause**: Saves workspace state and pauses.

---

## 6. Artifacts & State Lifecycle

### Path Tokens
All file references in workflow logs use bracketed path tokens which are resolved against `.agents/skills/shared/config.json`:
*   `{skillsRoot}`: Path to installation folder (default `.agents/skills`).
*   `{sharedDir}`: Path to shared seeds (default `.agents/skills/shared`).
*   `{plansDir}`: Path to plans workspace (default `.agents/plans`).
*   `{reviewsDir}`: Path to review summaries (default `.agents/codereviews`).
*   `{us-dir}`: Path to specific US folder `{plansDir}/us-{id}`.

### Git Checkpoints
At the beginning of every step (e.g. before Step 4 starts mutating), the orchestrator tags the HEAD commit with:
`uswf/{workflow-id}/before-step-{N}`
If you rollback, Nav Backward, or Undo, the orchestrator resets the working tree back to this tag. Checkpoint tags are strictly local and are never pushed to remote.

---

## 7. Troubleshooting

### My workflow paused with HS-5. What do I do?
An HS-5 indicates that `state.md` YAML parsing or schema validation failed.
1.  Open the state file in your editor: `{plansDir}/us-{id}/{workflow-id}.state.md`.
2.  Fix any malformed YAML characters (e.g. unquoted colons, unresolved strings, or syntax errors).
3.  Type `/spec-to-pr US {id}` to resume.

### Step 4/6/7 failed to write files (HS-4)
If the subagent claims to have written files but they are not present:
*   Check if you are running in worktree mode (`plans.useWorktrees: true`). If worktree creation failed, the system reverted to branch-direct mode.
*   Verify your workspace path length. Windows has a 260-character limit. Retrying the step in branch-direct mode (by updating config to `useWorktrees: false`) usually resolves path limits.

### How do I change models mid-workflow?
Workflows do not provide an in-gate model selector.
1.  Select **Pause workflow** at the transition gate.
2.  Switch your model in the IDE / Agent host panel.
3.  Resume the workflow: `/spec-to-pr US {id}`.
4.  The orchestrator detects the new session model, updates `currentModel` in state, and logs the transition.
