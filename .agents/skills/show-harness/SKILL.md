---
name: show-harness
description: >
  Snapshot the harness active in this session — skills, rules, instructions, precedence,
  and can/cannot — as short bullets. Invoke anytime with /show-harness or @show-harness.
upstream: jpolvora/workflow-skills
version: 1.0
disable-model-invocation: true
invocation_names:
  - show-harness
---

# show-harness

**Leading word:** *snapshot* — what is active **now**, not a disk audit.

Read-only. Emit one report, then **stop**. For integrity/routing audits use [`check-harness`](../check-harness/SKILL.md).

## Steps

1. **Collect** — From this turn's context only, list what is loaded:
   - Entry: root `AGENTS.md` when authoring upstream; after install load `skills/shared/AGENTS.md` (optional project root `AGENTS.md` when the host provides one)
   - Autoload / always-on skills and opt-outs (caveman, gabarito, karpathy, hooks, etc.)
   - Session-loaded skills (attached, routed, or already Read this turn)
   - Workspace rules + user rules that bind this agent
   - Config / external deps only if already known or a one-line path check (`skills/shared/config.json`)
   - Done when: each category is marked present, absent, or unknown (no invented files).

2. **Summarize** — Emit the report below. Bullet facts only; no skill-body dumps; no fixes.
   - Done when: every section is filled or explicitly `none` / `unknown`, and Can / Cannot has ≥1 bullet each.

## Report format

```markdown
# Harness snapshot

## Entry / hubs
- …

## Precedence (highest first)
- …

## Always-on / autoload
- … (note opt-outs if any)

## Session-loaded skills
- `name` — one-line role

## Rules active
- **Enforce:** …
- **Allow:** …
- **Forbid / guardrails:** …

## Config / external deps
- … or `unknown`

## Can / Cannot
- **Can:** …
- **Cannot:** …
```

## Boundaries

- Prefer context already in the session; light hub reads only to name precedence / autoload tables.
- Do not run check-harness phases, edit files, or propose corrections.
- Do not list every skill on disk — only what is active this moment.
