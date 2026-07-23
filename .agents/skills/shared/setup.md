# Setup & Bootstrap — Shared Workflow Entry

Initialization, configuration bootstrap, flags, resume logic, and first-run setup.
Shared by [`spec-to-pr`](../spec-to-pr/SKILL.md) and [`spec-to-pr-lite`](../spec-to-pr-lite/SKILL.md).

Artifact paths: [`../spec-to-pr/ARTIFACTS.md`](../spec-to-pr/ARTIFACTS.md). Resume rules in this file are canonical; FAQ/DIAGRAM must link here.

---

## External dependencies (guardrails)

Resolve `config.json` `rules.*` before assuming a skill or rule file exists. Full portable contract (same meaning): [`AGENTS.md`](AGENTS.md) § External dependencies in this folder · upstream root [`../../../AGENTS.md`](../../../AGENTS.md)#external-dependencies when authoring against the source repo.

| Key | Role | Resolve (first match) |
|-----|------|------------------------|
| `rules.seniorDeveloper` | Engineering guardrails; **Code review proof** source | config path → local `senior-developer` skill → global/user skill |
| `rules.karpathyGuidelines` | Surgical-change guidelines | config path → shipped `../karpathy-guidelines/SKILL.md` → global skill |
| `rules.stackFile` | Human-readable stack companion | config path (default `.agents/skills/shared/STACK.md`); bootstrap may create under `shared/` if missing (see 1b below) — never require repo-root files |
| Other `rules.*` | Optional consumer rules (e.g. `efMigrations`, `viewPatterns`) | Use path from config when set; do not invent filenames |

**Code review proof:** When pipeline / utility skills ask for proof, load the checklist from the **resolved** `rules.seniorDeveloper` skill. Do not paste that checklist into hub docs.

---

## Bootstrap & Entry

> **[spec-to-pr]** — Before Step 0.
> **[spec-to-pr-lite]** — Before Step 0.

### Entry matrix (both orchestrators)

Same entry paths for **standard** and **lite**. Resolve provider from `config.json` `providers.active` (or legacy `issueTrackers.*.enabled` inference). Canonical spec write: `{us-dir}/step-00-{slug}.spec.md`.

| Input | Provider / skill | Step 0 action |
|-------|------------------|---------------|
| GitHub `{n}` / `US {n}` | [`github-provider`](../github-provider/SKILL.md) `fetch-to-spec` | Fetch issue → spec; `slug: us-{n}` |
| ADO `{org}/{project}#{id}` / `ADO {id}` / `WI {id}` | [`azure-devops-provider`](../azure-devops-provider/SKILL.md) `fetch-to-spec` | Fetch WI → spec |
| Hand-written `*.spec.md` (any path) | [`local-spec-provider`](../local-spec-provider/SKILL.md) `fetch-to-spec` | Register / normalize → canonical spec |
| Free-text feature description (no spec) | `ws-write-spec` (standard or lite) | Brainstorm → `step-00-{slug}.spec.md` |
| Plain text in invocation (no issue id, no `*.spec.md` path) | `ws-write-spec` | Same as free-text row |

Optional mirror: `{specs-dir}/{slug}.spec.md` for human browsing. Downstream skills **always** read `step-00-{slug}.spec.md` under `{us-dir}`.

1. **Config check**: Check if `.agents/skills/shared/config.json` exists (fresh install normally seeds it from `config.json.example`).
   - If missing: `cp .agents/skills/shared/config.json.example .agents/skills/shared/config.json`.
   - Load path tokens early ([`tools.md`](tools.md) § Path tokens): `pathTokens.skillsRoot` / `sharedDir` (defaults `.agents/skills` / `.agents/skills/shared`) plus `{plansDir}` ← `plans.dir`. Expand braces before Read/Grep/Shell.
   - User-gate: **Configure now (Recommended)** / **Skip**.
   - If **Configure now** (or config exists but required fields are placeholders/`<…>` / empty): load and run [`configure-project`](../configure-project/SKILL.md) (same session). Pass `--section` only when fixing one area mid-workflow.
   - If **Skip**: continue with example defaults; warn that providers/verification may be wrong until configure-project runs.
1b. **Stack file bootstrap**: Read `config.json.rules.stackFile` (default: `.agents/skills/shared/STACK.md`). Prefer configure-project step 5 when that skill just ran. If config still points at a missing root `STACK.md`/`stack.md` while `.agents/skills/shared/STACK.md` exists, set `rules.stackFile` to the shared path (no root file required). Else `Shell` `test -f {stackFile}`. If missing:
   - Auto-detect the project stack by scanning the repository:
     - **Language/Framework**: Look for `package.json` (Node/React/Next), `*.csproj`/`*.sln`/`*.slnx` (.NET), `pyproject.toml`/`requirements.txt` (Python), `go.mod` (Go), `Cargo.toml` (Rust), `pom.xml`/`build.gradle` (Java), `Gemfile` (Ruby), etc.
     - **Frontend framework**: Check `package.json` `dependencies` for `next`, `react`, `vue`, `angular`, `svelte`, `vite`, `tailwindcss`, etc.
     - **Backend framework**: Check for `express`, `fastify`, `nest`, `django`, `flask`, `fastapi` in matching config files.
     - **Database**: Check for `prisma/schema.prisma`, `drizzle.config.*`, `Migrations/`, `alembic/ini`, EF Core migrations, `docker-compose.yml` (PostgreSQL, MySQL, MongoDB images).
     - **Project structure**: List top-level directories (`src/`, `web/`, `tests/`, `app/`, `lib/`, `cmd/`, etc.) and infer conventional layers.
     - **Tool versions**: `node --version`, `dotnet --version`, `python --version`, `go version` (if installed).
     - **Build/test commands**: Check `package.json` `scripts` (`build`, `test`, `lint`, `dev`), `Makefile` targets, existing CI configs (`.github/workflows/`, `.gitlab-ci.yml`).
   - Generate companion from the detected information using [`STACK.md.example`](STACK.md.example) as format reference.
   - Write to `.agents/skills/shared/STACK.md` (or the resolved `rules.stackFile` when it already lives under `.agents/skills/shared/`). Do **not** create a repo-root stack file.
   - If auto-detection is incomplete or ambiguous (multiple possible stacks), present findings to the user and ask for clarification on uncertain items.
   - Log: `stack companion created → {path}` in step output.
2. **Parse flags**: `auto`, `dry-run`, `skip-testing`, `skip-tests`, `full`, `strict`.
   - **Combined Switches:** These switches can be used individually or combined in any configuration (e.g. `full` + `auto` + `dry-run` to run a fully automated dry-run simulation of the entire workflow for testing).
   - Map: `skip-testing` → `skipTesting: true`; `skip-tests` → `skipTests: true`.
   - Set `currentModel` from the **executing session model** (agent identity / runtime). If unknown → `unknown`.
   - Do **not** accept `--model` or `--model-chain` (removed). If the raw invocation still contains them, ignore and note once in the init banner: `model flags ignored — use Pause → switch model in IDE/agent host → Resume`.
   - Do **not** store or apply `modelChain`.
   - `strict` → full US verification at Step 5 (standard orch only).
2a. **Gate contract**: Load [`gates.md`](gates.md) — universal step controls, combined delivery + ship gate at standard Step 8 / lite Step 4, separate fix-PR at standard Step 9 / lite Step 5. Config/SCM: [`config-resolution.md`](config-resolution.md).
2b. **Mode hint (new workflow only):** If user did not pass density flags and invoked full `spec-to-pr` without `--full`/`auto`, optionally offer once: **Full pipeline** (rec) / **Use lite instead** (`/spec-to-pr-lite`) — see gates.md Mode selection. Skip when already on lite.
3. **Log parsed args and switch states**: Write a banner to step output showing all switches and their resolved values:
   ```markdown
   ### Init — Parsed args
   Raw invocation: `{raw args from user}`
   
   | Switch | Resolved |
   |--------|----------|
   | `autoMode` | `{true/false}` |
   | `dryRun` | `{true/false}` |
   | `fullMode` | `{true/false}` |
   | `skipTesting` | `{true/false}` |
   | `skipTests` | `{true/false}` |
   | `currentModel` | `{session model}` |
   | `slug` | `{slug}` |
   | `workflowId` | `{workflow-id}` |
   | `branch` | `{branch}` |
   | `baseBranch` | `{baseBranch}` |
   ```
   Write this block immediately after flag parsing, before auto-resume. Applies in all modes (normal, auto, dry-run). In `dryRun`, prefix with `[DRY-RUN]`.
4. **Auto resume** or **Active Resume** (see [Resume / reset](#resume--reset)).
5. **Identity**: `workflow-id`, `slug`, `us-dir`.
   - **[spec-to-pr]**: Inject `workflowType: standard` into the initialized frontmatter of `{us-dir}/{workflow-id}.state.md`.
   - **[spec-to-pr-lite]**: Inject `workflowType: lite`.
6. **Baseline**: `git status --porcelain` → `preExistingDirty[]`; `git rev-parse HEAD` → `baselineCommit`.
7. **LOC baseline**: `Shell` capture → `telemetry.loc.baseline`. Store ISO → `telemetry.workflowStartedAt`.
8. **Checkpoint**: tag `uswf/{workflow-id}/before-step-0`.
9. **Progress Board** render.
10. **Step Entry Gate** → dispatch.

---

## Resume / Reset

**Auto:** skip Active Resume; use auto resume policy. If existing `active`/`paused` workflow matches same US/slug + `autoMode` + matching `workflowType`, auto-resume.

**Normal — workflow discovery (mandatory before any new workflow):**

1. `Glob` `{plansDir}/**/*.state.md` (`{plansDir}` ← `config.plans.dir`) → list all state files.
2. For each, `Read` frontmatter YAML: `status`, `workflowId`, `slug`, `us`, `currentStep`, `startedAt`, `autoMode`, `workflowType`.
3. **[spec-to-pr]** Filter: (`status: active` or `status: paused`) and `workflowType` is `standard` or absent.
   **[spec-to-pr-lite]** Filter: (`status: active` or `status: paused`) and `workflowType` is exactly `lite`.
4. Present as **selectable list** via user-gate:

```text
Found {N} unfinished workflow(s):

1. US {us} — {slug} — Step {currentStep} — started {startedAt} — [{autoMode ? 'AUTO' : 'normal'}] (Recommended)
2. US {us} — {slug} — Step {currentStep} — started {startedAt} — [{autoMode ? 'AUTO' : 'normal'}]

Options:
- Resume workflow #1 (Recommended)
- Resume workflow #2
- Start new workflow (ignore existing)
- Cancel for now
```

5. Resume: load state, `status: active`, skip bootstrap, jump to `currentStep` gate.
5a. **Session model refresh (mandatory on every resume):** Re-read the executing session model → update `currentModel`. If changed vs prior frontmatter value, log `model-change | step {currentStep} | {old} → {new} | ISO` in ## Gate history. Ignore leftover `modelChain` keys in old state files.
6. Paused: resume at same step (checkpoint revert M=currentStep → hygiene → board → gate).
7. No unfinished workflows: skip list, proceed to bootstrap.

**Full reset:** Checkpoint Revert M=1 → gate **Start again** (new workflow-id) / **Exit**.

**Stale state cleanup** (new workflow start or explicit):
- Starting new while old exist → offer: **Archive old workflows** (move to `{workflow-id}.archive/`) / **Delete** / **Keep both**.
- Stale = `status: active|paused` and `startedAt` older than 7 days → flag `[STALE]`.
