# Gabarito

Operational communication skill for agents: eleven directives plus style discipline.

## What it does

- Runs **every turn** (always-on) unless opted out
- Improves accountability, anti-sycophancy, clarification, verification, anti-regression memory consult, and prose quality
- First reply only: short signal line (*"Gabarito in use."*)

## Consumer projects

Listed in `shared/AGENTS.md` § Skill loading (autoload every prompt; or root `AGENTS.md` when authoring against the source repo). Works alongside `senior-developer` (global or local install), `karpathy-guidelines`, and **caveman full**; does not replace specs or engineering rules. See hub § Precedence and § Opt-out.

## Caveman

**caveman full** autoloaded with Gabarito unless `stop caveman` / `normal mode`. Level switches: `/caveman lite|ultra|…`. See `../caveman/SKILL.md`.

## Opt-out

`stop gabarito`, or `normal mode` (caveman off: `stop caveman`). Canonical table: [`shared/AGENTS.md`](../shared/AGENTS.md) § Opt-out (or root [`AGENTS.md`](../../../AGENTS.md) § Opt-out when authoring against the source repo).

## Files

| File | Purpose |
|------|---------|
| `SKILL.md` | Agent instructions (authoritative) |
| `README.md` | This summary |
