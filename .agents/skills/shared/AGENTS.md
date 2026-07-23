# Shared — Workflow Config & Consumer Data Hub

**Audience: agents** (config resolution, gates, skill loading, consumer-owned paths). Humans: install narrative in the project README or upstream [workflow-skills](https://github.com/jpolvora/workflow-skills) README.

> **Config, gates, bootstrap docs, skill loading, and consumer-owned project data** for [`spec-to-pr`](../spec-to-pr/SKILL.md) and [`spec-to-pr-lite`](../spec-to-pr-lite/SKILL.md).
>
> This folder is **not** an installable skill package. The installer copies hub templates here when a workflow or Full package is selected.
>
> Promoted utilities and harness skills live as **top-level** installable skills under `.agents/skills/<skill>/`.
>
> **Consumer-owned** (preserved on update; never overwritten by upstream):
> `config.json`, `STACK.md`, `MEMORY.md`, `memory/*`, `installed-skills.json`, and `CHANGELOG.md` (when `rules.changelogFile` points under `shared/`).
> Fresh install seeds `config.json` from `config.json.example`, empty `MEMORY.md` / `CHANGELOG.md` from templates, and `STACK.md` from `STACK.md.example`. Prefer [`configure-project`](../configure-project/SKILL.md) to fill placeholders. The installer writes `installed-skills.json` for update/uninstall tracking.
>
> **Installer scope:** only `.agents/skills/` (skill folders + this `shared/` hub). Never creates or overwrites consumer repo-root files (root `AGENTS.md`, host pointers). Optional root/host pointers stay consumer-owned; check-harness may suggest them.

**Language:** en-us only for skill bodies, gates, banners, and harness docs.

---

## Config & Tools

| File | Purpose |
|------|---------|
| [`config.json.example`](config.json.example) | Project config template — seeded to `config.json` on fresh install; fill via [`configure-project`](../configure-project/SKILL.md); never commit |
| [`config.schema.json`](config.schema.json) | JSON Schema for `config.json` validation |
| [`config-resolution.md`](config-resolution.md) | Canonical config path + SCM resolution (dual-mode) |
| [`gates.md`](gates.md) | Shared user-gate / delivery / ship / session-model banner (dual-mode) |
| [`tools.md`](tools.md) | Canonical agent tool vocabulary (aliases → config keys), **Path tokens** (`{skillsRoot}` / `{sharedDir}` / `{plansDir}`), script launchers (`python` / `node` / `bash`). Load with `config.json` before tool calls. |
| [`STACK.md.example`](STACK.md.example) | Template for human-readable stack companion — seeds `STACK.md` |
| [`setup.md`](setup.md) | Bootstrap & entry logic shared by `spec-to-pr` and `spec-to-pr-lite` |
| [`MEMORY.md.template`](MEMORY.md.template) | Empty memory index template — seeds `MEMORY.md` |
| [`CHANGELOG.md.template`](CHANGELOG.md.template) | Empty changelog stub — seeds `CHANGELOG.md` |

## Consumer-owned (local only)

| File | Purpose |
|------|---------|
| `config.json` | Project identity, stack, verification, providers (seeded; gitignored) |
| `STACK.md` | Human-readable companion to `config.json` (edit freely) |
| `MEMORY.md` | Compiled anti-regression index (`self-learning` skill) |
| `memory/*.md` | Individual memory entries (compile into `MEMORY.md`) |
| `CHANGELOG.md` | Append-only history (`changelog` skill; default `rules.changelogFile`) |
| `installed-skills.json` | Managed skill list for `update` / `uninstall` (installer-written) |

---

## Skill loading (mandatory)

| Skill | Path | Trigger |
|-------|------|---------|
| `caveman` | [`../caveman/SKILL.md`](../caveman/SKILL.md) | Every prompt — compression |
| `gabarito` | [`../gabarito/SKILL.md`](../gabarito/SKILL.md) | Every prompt — operational guidelines |
| `karpathy-guidelines` | [`../karpathy-guidelines/SKILL.md`](../karpathy-guidelines/SKILL.md) | Every prompt — surgical scope |
| `changelog` | [`../changelog/SKILL.md`](../changelog/SKILL.md) | Every task completion |
| `self-learning` | [`../self-learning/SKILL.md`](../self-learning/SKILL.md) | Before plan/code/fix: consult `{sharedDir}/MEMORY.md`; on completion: write traps → compile |

### Precedence (highest first)

1. Explicit user instructions (current turn)
2. Design / spec / architecture constraints
3. `karpathy-guidelines`
4. `gabarito`
5. `caveman` (compression only; keep technical accuracy)

### Opt-out

| Phrase | Effect |
|--------|--------|
| `stop caveman` / `normal mode` | Disable caveman |
| `stop gabarito` / `sem gabarito` | Disable gabarito |
| `/caveman lite\|full\|ultra\|…` | Intensity |

---

## Promoted skills (top-level installables)

### Utilities (Workflows package)

| Skill | Path |
|-------|------|
| `caveman` | [`../caveman/SKILL.md`](../caveman/SKILL.md) |
| `gabarito` | [`../gabarito/SKILL.md`](../gabarito/SKILL.md) |
| `karpathy-guidelines` | [`../karpathy-guidelines/SKILL.md`](../karpathy-guidelines/SKILL.md) |
| `spec-format` | [`../spec-format/SKILL.md`](../spec-format/SKILL.md) |
| `configure-project` | [`../configure-project/SKILL.md`](../configure-project/SKILL.md) |
| `goal-loop` | [`../goal-loop/SKILL.md`](../goal-loop/SKILL.md) |
| `self-learning` | [`../self-learning/SKILL.md`](../self-learning/SKILL.md) |
| `changelog` | [`../changelog/SKILL.md`](../changelog/SKILL.md) |

### Harness & review (Workflows package)

| Skill | Path |
|-------|------|
| `check-harness` | [`../check-harness/SKILL.md`](../check-harness/SKILL.md) |
| `check-workflows` | [`../check-workflows/SKILL.md`](../check-workflows/SKILL.md) |
| `secrets-leak-review` | [`../secrets-leak-review/SKILL.md`](../secrets-leak-review/SKILL.md) |

### Extra package (optional)

Present only after Extra or Full install. If a path is missing, treat as intentional omission (not a broken route).

| Skill | Path |
|-------|------|
| `write-a-skill` | [`../write-a-skill/SKILL.md`](../write-a-skill/SKILL.md) |
| `show-harness` | [`../show-harness/SKILL.md`](../show-harness/SKILL.md) |

### Intentionally orch-only (not duplicated here)

Pipeline folders `00`–`09`, `goal-fix-pr`, `update-plan-implementation`, orchestrators (`spec-to-pr`, `spec-to-pr-lite`), and providers are discovered via host invoke / orch dispatch — not listed as promoted utilities.

Install packages and dependency map: upstream `bin/skill-dependencies.json` in [workflow-skills](https://github.com/jpolvora/workflow-skills) (not vendored in consumer clones).

---

## Task router (consumer)

| Intent | Load |
|--------|------|
| Spec → PR E2E | `spec-to-pr` |
| Spec → PR lite | `spec-to-pr-lite` |
| Fill / update `config.json` | `configure-project` |
| Audit harness | `check-harness` |
| Check workflows | `check-workflows` |
| Secrets / leaks | `secrets-leak-review` |
| Format/review spec | `spec-format` |
| Record learning | `self-learning` |
| Record changelog | `changelog` |
| Create / rewrite a skill | `write-a-skill` (Extra) |
| Show active harness | `show-harness` (Extra) |

Pipeline steps 0–9: use orchestrator dispatch (do not invent alternate folder ids).

---

## Managed skills — no silent local refactors

Skills under `.agents/skills/` (except consumer-owned `shared/` data) are **managed upstream copies**. `update` overwrites them.

| Context | Do | Do not |
|---------|----|--------|
| **Consumer repo / CI / Actions** | Verify a real runtime bug with evidence. If a lasting skill/script fix is needed, **tell the user to fix upstream** ([workflow-skills](https://github.com/jpolvora/workflow-skills) PR) or open that PR; local experiments are temporary only. | Autonomously reorder, “hygiene-refactor,” or rewrite managed skill scripts from a false positive (e.g. Python same-module call-before-`def` is not a `NameError`). |
| **Managed script calls** | Invoke with explicit launchers (`python` / `node` / `bash`) per [`tools.md`](tools.md) § Script launchers. On failure: report and stop. | Rewrite managed scripts for shell quirks, or invent temp scanners/bridges when a recipe fails. |
| **Agent shell scans** | Prefer `python -m py_compile` on real `*.py` paths, or a short **uncommitted** temp script if a one-liner heredoc breaks on quoting. Delete temps when done. | Commit throwaway scanners into the consumer tree, or treat shell `SyntaxError` in an embedded heredoc as a skill-script bug. |

False positives that look like “forward reference” bugs are almost always safe at Python call time. Prefer reporting + upstream suggestion over silent local churn.

---

## Recommended Feature Delivery Checklist (before push / ship)

### Consumer Projects

Run this checklist prior to triggering `/ship-pr` or shipping features in a consumer project:

- [ ] **1. Run Tests & Verification**: Execute local test commands (`verification.backendTest` / `verification.frontendTest` or project test scripts).
- [ ] **2. Harness & Workflow Audit**: Run `check-harness` / `check-workflows` to ensure 0 critical findings.
- [ ] **3. Configure & Verify Project**: Verify `.agents/skills/shared/config.json` settings and stack definitions.
- [ ] **4. Clean Docs & Artifacts**: Ensure documentation files have no merge conflict markers or uncommitted scratch files.
- [ ] **5. Ship via `ship-pr`**: Execute `/ship-pr` (runs Prepare Board, commits, pushes, creates PR).

### Upstream Maintainers (`jpolvora/workflow-skills` source repo only)

Additional obligations when maintaining and releasing the upstream skills package:

- [ ] **1. Run Package Tests**: Execute `npm run test` (runs installer, integrity checks, and tree verification).
- [ ] **2. Single Version Bump**: Increment package version once per release PR and stamp site footer (`npm run build-site:bump`).
- [ ] **3. Regenerate Integrity Manifest**: Run `npm run generate-integrity` and `npm run verify-integrity`.
- [ ] **4. Harness Audit**: Run `check-harness` to ensure 0 critical findings.
- [ ] **5. Hub Sync**: Keep `AGENTS.md` and `.agents/AGENTS.md` in sync before shipping PR.

---

## Skill discovery (consumers)

Installed skills live at `.agents/skills/<name>/SKILL.md`. Load on demand from orchestrator dispatch, task intent, or host skill discovery. There is **no** packaged `.agents/AGENTS.md` in consumer projects; **this file** is the consumer-facing hub. A thin root `AGENTS.md` (when the consumer adds one) should point here — installer never writes it.

---

## External dependencies

Not shipped in the hub package (except where noted). Resolve each dependency in **order** (first match wins). Read paths from `config.json` when present. Do **not** assume host-private rule folders.

| Dependency | Resolve (first match) |
|------------|------------------------|
| `senior-developer` | `config.json` → `rules.seniorDeveloper` → local skill (`senior-developer/SKILL.md`) → global/user skill |
| `karpathy-guidelines` | `config.json` → `rules.karpathyGuidelines` → shipped `../karpathy-guidelines/SKILL.md` → global skill |
| Stack companion | `config.json` → `rules.stackFile` (default `.agents/skills/shared/STACK.md`) — consumer-owned under `shared/` |
| Changelog file | `config.json` → `rules.changelogFile` (default `.agents/skills/shared/CHANGELOG.md`) |
| Domain glossary | `config.json` → `domain.glossaryFile` (often `CONTEXT.md`) — consumer root, optional |
| Optional consumer rules | Other `config.json` `rules.*` paths when set — do not invent filenames |
| Workflow artifacts | `config.json` → `plans.dir` (token `{plansDir}`; default `.agents/plans`) · `plans.specsDir` (default `.agents/specs`) · optional `reviews.dir` (default `.agents/codereviews`) |

Bootstrap notes: [`setup.md`](setup.md). Config resolution: [`config-resolution.md`](config-resolution.md).

### Code review proof

When skills ask for **Code review proof**, use the checklist from the **resolved** `rules.seniorDeveloper` skill. Do **not** paste or duplicate that checklist here.
