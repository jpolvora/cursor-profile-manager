# Tools — Standard Agent Vocabulary

Canonical tool names every agent uses. Project-specific parameters from `config.json`. Do not hardcode build/test commands in skills — use these aliases.

## Path tokens (load first)

**Before** any `Read` / `Grep` / `Glob` / `Shell` that uses a brace path, expand tokens from this table (same idea as `{plansDir}` ← `plans.dir`). Prefer `config.json` → `pathTokens.*` when present; otherwise use the **Default** column.

| Token | Resolve | Default (install contract) |
|-------|---------|----------------------------|
| `{skillsRoot}` | `pathTokens.skillsRoot` | `.agents/skills` |
| `{sharedDir}` | `pathTokens.sharedDir` | `{skillsRoot}/shared` → `.agents/skills/shared` |
| `{plansDir}` | `plans.dir` | `.agents/plans` |
| `{reviewsDir}` | `reviews.dir` | `.agents/codereviews` |
| `{us-dir}` | `{plansDir}/{slug}/` | (slug from workflow) |

**Agent contract:**

1. Load `config.json` (`read-config`) then this file (`toolsFile`, default `tools.md`) early in the session.
2. Expand tokens **before** tool calls. Example: `{sharedDir}/MEMORY.md` → `.agents/skills/shared/MEMORY.md`.
3. **Forbidden:** bare `shared/MEMORY.md` or other undeclared shorthands (do not Grep those literals).
4. **Shell recipes:** expand tokens before paste, or write the Default path literally (copy-paste safe).
5. **Markdown links** in skill files: use real relative paths (`../shared/…`), never brace tokens (GitHub/check-harness cannot expand them).
6. **Hub routing tables** that inventory disk paths: keep full `.agents/skills/…` literals so audits stay filesystem-true.
7. `{skillsRoot}` / `{sharedDir}` are **fixed install layout**, not relocatable consumer knobs (unlike `plans.dir`).

## Core tools

| Tool | Action | Native | Source from config |
|------|--------|--------|--------------------|
| `build-backend` | Compile backend | `Shell` | `verification.backendBuild` |
| `test-backend` | Run backend tests | `Shell` | `verification.backendTest` |
| `lint-backend` | Check code style | `Shell` | `verification.backendFormat` |
| `build-frontend` | Compile frontend | `Shell` | `verification.frontendBuild` |
| `test-frontend` | Run frontend tests | `Shell` | `verification.frontendTest` |
| `build-all` | Build both stacks | `Shell` | chain `backendBuild` + `frontendBuild` |
| `migrations-add` | Add EF migration | `Shell` | `verification.migrationsAdd` |
| `migrations-apply` | Apply EF migrations | `Shell` | `verification.migrationsApply` |
| `seed-db` | Seed demo data | `Shell` | `database.seedScript` |
| `start-stack` | Start full stack | `Shell` | `orchestration.startCommand` |
| `stop-stack` | Stop API + Vite | `Shell` | `orchestration.stopCommand` |
| `compose-up` | Docker full stack | `Shell` | `orchestration.composeCommand` |

## State & workflow tools

Path tokens: [Path tokens (load first)](#path-tokens-load-first). Artifact names: [`ARTIFACTS.md`](../spec-to-pr/ARTIFACTS.md).

| Tool | Action | Native |
|------|--------|--------|
| `read-state` | Read workflow state | `Read` `{us-dir}/{workflow-id}.state.md` |
| `write-state` | Write/append state | `Write` / `StrReplace` (hygiene before board) |
| `read-config` | Load project config | `Read` `{sharedDir}/config.json` |
| `read-artifacts-registry` | Canonical artifact names | `Read` `{skillsRoot}/spec-to-pr/ARTIFACTS.md` |
| `read-stack` | Load stack reference | `Read` `config.json.rules.stackFile` (default `{sharedDir}/STACK.md`) |
| `read-memory` | Load learned knowledge **before** plan/code/fix | `Grep` / `Read` `{sharedDir}/MEMORY.md` (keywords from the task). Mandatory for mutating work — see [`self-learning`](../self-learning/SKILL.md) § Pre-work consult |
| `search-code` | Find patterns in code | `Grep` / `Glob` |
| `run-script` | Run workflow / provider script | `Shell` with **explicit launcher** (see [Script launchers](#script-launchers)): `python` / `node` / `bash` + path. Orchestrator helpers: `python {skillsRoot}/spec-to-pr/scripts/{name}.py`. Converters/thread helpers: prefer `{skillsRoot}/{github,azure-devops,local-spec}-provider/scripts/` (shims may still live under `spec-to-pr/scripts/` / `09-fix-pr/scripts/`) |

## Source control tools

| Tool | Action | Native |
|------|--------|--------|
| `commit-code` | Commit src/web/tests only | `Shell` `git add src/ web/ tests/ && git commit -m "..."` |
| `commit-delivery` | Commit plan + result (Step 8) | `Shell` stage `step-02-{slug}.plan.refined.md` **or** `step-01-{slug}.plan.md`, plus `step-08-{slug}.result.md` |
| `push-branch` | Push working branch | `Shell` `git push {gitRemote} {workingBranch}` — from `config.project` |
| `create-pr` | Create PR via SCM provider | Resolve `providers.scm` → [`github-provider`](../github-provider/SKILL.md) or [`azure-devops-provider`](../azure-devops-provider/SKILL.md) `create-pr` (not raw `gh`/`az` alone) |
| `list-threads` / `resolve-thread` / `merge-pr` | PR review + merge intents | Same SCM provider skill as `create-pr` |
| `create-checkpoint` | Tag before step N | `Shell` `git tag uswf/{id}/before-step-{N}` |
| `revert-to-checkpoint` | Revert to tag M | `Shell` `git reset --mixed {tag}` + per-path restore |

Entry / fetch: resolve `providers.active` → [`github-provider`](../github-provider/SKILL.md) · [`azure-devops-provider`](../azure-devops-provider/SKILL.md) · [`local-spec-provider`](../local-spec-provider/SKILL.md) `fetch-to-spec`. Consumers who already installed `spec-to-pr` before these folders existed: `npx github:jpolvora/workflow-skills update --include-new`.

## Agent dispatch tools

| Tool | Action | Native |
|------|--------|--------|
| `dispatch-agent` | Spawn subagent for step | Subagent dispatch (host-provided); prefer `subagent_type: generalPurpose\|shell`; `description: "STP step {N} — {Label}"` |
| `dispatch-parallel` | Spawn ≤3 concurrent DAG tasks | Subagent dispatch (host-provided) — same worktree, no file overlap |
| `user-gate` | Ask question | Prefer native structured choice UI when available; ≥2 options, recommended first; cancelled → HS-1. Markdown fallback with same options when unavailable (see [`gates.md`](gates.md)); log `user-gate-fallback` |
| `user-gate-auto` | Auto-select first option | auto-gate table — no user-gate prompt |
| `browser-mcp` | Browser integration test | Host browser MCP when available (only normal mode, non-dry-run, gated) |

## Knowledge tools

| Tool | Action | Native |
|------|--------|--------|
| `update-memory` | Write learned pattern | Create unique file in `{sharedDir}/memory/` and run `python {skillsRoot}/self-learning/self_learning.py --compile` |
| `update-changelog` | Append historical log | `Write`/`StrReplace` `config.json.rules.changelogFile` (default `{sharedDir}/CHANGELOG.md`) |

## Script launchers

Managed skill scripts are upstream-owned. Invoke with an **explicit launcher**; never rely on shebang alone or the host default shell.

| Extension | Launcher | Example |
|-----------|----------|---------|
| `*.py` | `python` | `python {skillsRoot}/.../scripts/foo.py` (expand token first) |
| `*.cjs` / `*.js` | `node` | `node {skillsRoot}/.../scripts/foo.cjs` (expand token first) |
| `*.sh` | `bash` | `bash {skillsRoot}/.../scripts/foo.sh` (expand token first) |

**Contract (agents):**

1. Prefix every recipe/script call with the launcher above (`python …`, `node …`, `bash …`).
2. Do **not** rewrite managed scripts for shell quirks (no pwsh/cmd translations, no in-place dialect patches).
3. Do **not** invent temp scanners/bridges when a recipe fails — report the failure (missing launcher, non-zero exit) and stop; lasting fixes go upstream.
4. Consumer `verification.*` (and other config command strings): run **unchanged**. If they assume `pwsh` and the host is bash (or the reverse), that is a **consumer config** problem, not a skill-script problem.

Skill `.sh` dialect: Git Bash–compatible bash. Prefer Node/Python for new logic; keep shell as thin glue.

## Rules

1. **No hardcoded commands** in skills — use tool aliases. Config.json holds project-specific values.
2. **Shell only for git/build/scripts** — never use bash where `Read`/`Write`/`Grep`/`Glob` suffice.
3. **Explicit launchers** — every managed script call uses `python` / `node` / `bash` per [Script launchers](#script-launchers).
4. **Consult MEMORY before mutating** — `read-memory` (`Grep` / `Read` `{sharedDir}/MEMORY.md`) before plan, code, skill edits, or script fixes; apply known Solutions. Write new traps via `update-memory` after.
5. **One worktree max** — step 4 worktrees are exclusive under `{worktrees-dir}` when `config.plans.useWorktrees` is true.
6. **No commit of `{plansDir}/`** — except Step 8 delivery per [`ARTIFACTS.md`](../spec-to-pr/ARTIFACTS.md).
7. **Subagents: fresh per step** — never resume a subagent across steps.
8. **Orch never edits code** — hard stop. Code changes spawn via `dispatch-agent`.
9. **Paths via tokens** — expand [Path tokens](#path-tokens-load-first) before tool calls; never invent undeclared shorthands. `{plansDir}` / `{reviewsDir}` / `workingBranch` / `baseBranch` come from config; `{skillsRoot}` / `{sharedDir}` from `pathTokens` or defaults.
