---
name: ws-write-spec
description: Drafts a canonical step-00-{slug}.spec.md from a free-text feature description (spec-to-pr Step 0 brainstorm).
upstream: jpolvora/workflow-skills — this skill is a spec-to-pr pipeline dependency. Improvements must be submitted upstream to https://github.com/jpolvora/workflow-skills
version: 3.4
disable-model-invocation: true
invocation_names:
  - write-spec
  - ws-write-spec
  - 00-write-spec
---

# 00-write-spec

Draft a **canonical** local spec from free-text. Act as a Product Manager: clear scope, testable acceptance criteria.

**Canonical path:** `{us-dir}/step-00-{slug}.spec.md` (`{us-dir}` = `{plansDir}/{slug}/`). Human-browsable mirrors under `plans.specsDir` are owned by [local-spec-provider](../local-spec-provider/SKILL.md) — never copy them yourself.

**Format:** load [spec-format](../spec-format/SKILL.md) and follow it. Set `source: local` and `id: null`.

## Invocation

Standalone:

```
/write-spec "<description>" [slug=<slug>] [output-dir=<path>] [--mirror]
```

Workflow (spec-to-pr / lite Step 0): orchestrator passes `description` and optional `slug`; optional mirror when requested or when mirroring is policy for local brainstorms.

| Parameter | Default | Notes |
|-----------|---------|-------|
| `<description>` | required | Raw feature / business text |
| `slug` | inferred | URL-safe id from title/description |
| `output-dir` | `{us-dir}` | Optional override for destination `{us-dir}` (`{plansDir}/{slug}/`) |
| `--mirror` | false | After write, register via local-spec-provider |

## Steps

1. **Parse** — Infer title and url-safe `slug` from the description (or use provided `slug`).
   - Done when: title and `slug` are set.

2. **Draft** — Build the spec per [spec-format](../spec-format/SKILL.md).
   - Done when: frontmatter has `source: local`, `id: null`, `slug`, `title`, `specDate`; body has Description, Acceptance Criteria (each AC specific and testable), and Notes as needed; every stated requirement maps to ≥1 AC or an explicit out-of-scope note in Notes.

3. **Write** — Save `{us-dir}/step-00-{slug}.spec.md`.
   - Done when: that file exists on disk.

4. **Optional mirror** — Only if `--mirror` or the orchestrator requests a human-browsable copy. Delegate; do not copy files yourself:

   ```bash
   python .agents/skills/local-spec-provider/scripts/register_local_spec.py \
     --input "{us-dir}/step-00-{slug}.spec.md" \
     --mirror
   ```

   That script normalizes `source: local` (in-place when input is already the canonical `step-00-` file) and writes `{plans.specsDir}/{slug}.spec.md` (default `specs/`). Use `--force` only when overwriting an existing mirror that differs.
   - Done when: command succeeded, or this step was skipped.

5. **Handoff** — Return the canonical `{us-dir}/step-00-{slug}.spec.md` path for [01-write-plan](../01-write-plan/SKILL.md). Mention the mirror path only if one was written. In workflow mode the orchestrator records `specPath` at that file and `specSource: local`.
   - Done when: caller has the canonical `step-00-` path.

Language: en-us only.
