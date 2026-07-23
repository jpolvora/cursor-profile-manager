---
name: ws-fix-pr
description: Cooperatively resolve active PR code review threads on GitHub or Azure DevOps with structured validation and reports.
upstream: jpolvora/workflow-skills — this skill is a spec-to-pr pipeline dependency. Improvements must be submitted upstream to https://github.com/jpolvora/workflow-skills
version: 1.3
disable-model-invocation: true
invocation_names:
  - fix-pr
  - ws-fix-pr
  - 09-fix-pr
---

# 09-fix-pr

Fetch, score, and systematically resolve active PR review threads on GitHub or Azure DevOps: local fixes, test validation, thread resolution, and push back to the remote branch.

Act as a **Senior Software Developer**: parse threads, run regression tests, and apply minimal surgical fixes that satisfy reviewers.

Platform I/O (`list-threads`, `resolve-thread`) is **delegated** to the skill selected by `providers.scm`: never hardcode a single-host happy path here. See [README.md](README.md) for platform support, flow summary, and fix checklist.

## Invocation

Standalone:

```
/fix-pr <PR-ID> [dry-run]
```

Workflow (called by [goal-fix-pr](../goal-fix-pr/SKILL.md)): all interactive gates are auto-approved by the goal loop; receives `PR-ID` and `dry-run` from the goal.

| Parameter | Default | Notes |
|-----------|---------|-------|
| `<PR-ID>` | required | Target Pull Request number |
| `dry-run` | false | Simulate fixes/resolutions; no commits, pushes, or remote thread mutations |

## Prerequisites

- Local branch checked out matches the PR source branch.
- `.agents/skills/shared/config.json` with resolvable `providers.scm` (`github` \| `azure-devops`, never `local`): see [config-resolution.md](../shared/config-resolution.md).
- Provider skill's `validate-auth` passes before mutating remote threads.

## SCM provider resolution

Resolve per [config-resolution.md](../shared/config-resolution.md): read `providers.active` / `providers.scm`; if absent, prefer an enabled GitHub tracker, else Azure DevOps; reject `scm: "local"`.

| `providers.scm` | Skill | Intents used here |
|-----------------|-------|-------------------|
| `github` | [github-provider](../github-provider/SKILL.md) | `list-threads`, `resolve-thread` |
| `azure-devops` | [azure-devops-provider](../azure-devops-provider/SKILL.md) | `list-threads`, `resolve-thread` |

## Steps

1. **Sync & CI check**: `git pull origin <sourceRefName>`; refuse dirty worktrees; recommend waiting if CI is active.
   - Done when: worktree is clean and current with the source branch.

2. **Fetch active threads**: resolve `providers.scm` and call `list-threads` for `<PR-ID>`. Parse `threadId`, `filePath`, `lineNumber`, `comments`. Use the payload's `activeThreads` count directly; do not re-filter raw statuses. If reading any collect `--output` file, open with UTF-8 explicitly (bare `open(path)` on Windows raises `UnicodeDecodeError` on review text).
   - Done when: every active thread has parsed file/line/comment context.

3. **Score & classify**: rate each thread 0–10.
   - Done when: every thread has a score and an action:

   | Score | Action |
   |-------|--------|
   | 0–5 | Resolve with a comment justifying no code change |
   | 6–10 | Apply a surgical code fix |

4. **Confirmation gate**: save the proposed fix checklist to `.agents/skills/09-fix-pr/runs/pr-<PR-ID>/plan-gate.md` (uncommitted) and ask: "Proceed with fixes for threads [ID1, ID2]?" Under [goal-fix-pr](../goal-fix-pr/SKILL.md), auto-yes (save gate file and proceed).
   - Done when: checklist confirmed by user, or auto-approved by the goal loop.

5. **Surgical fix**: for each blocking thread, analyze call sites and adjacent logic, then apply minimal edits (Karpathy guidelines) that fix the defect class, not just the reported instance.
   - Done when: all approved threads have code changes or a resolution comment drafted.

6. **Verify & push**: run `config.json.verification` commands; write the review report under `{reviewsDir}/PR-<PR-ID>-round-<N>.md` (`{reviewsDir}` ← `config.reviews.dir`); resolve each handled thread via `resolve-thread` (skip remote mutation when `dry-run`) with a `<!-- resolution-reply -->` marker in the comment body; stage, commit, and `git push origin HEAD` (skip push when `dry-run`).
   - Done when: verification passed, report exists, threads are resolved (or dry-run simulated), and the branch is pushed (unless `dry-run`).

Language: en-us only.
