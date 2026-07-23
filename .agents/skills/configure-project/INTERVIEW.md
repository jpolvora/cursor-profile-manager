# configure-project — Interview reference

Disclosed detail for [`SKILL.md`](SKILL.md). Load when detecting or interviewing sections.

## Required (must resolve before workflows)

| Section | Keys | Notes |
|---------|------|-------|
| `project` | `name`, `baseBranch` | `workingBranch` default `develop`; `gitRemote` default `origin`; `repoUrl` / `org` strongly recommended |
| `providers` | `active`, `scm` | Or legacy `issueTrackers.*.enabled` inference — prefer explicit `providers` |
| `verification` | at least one build or test command used by the stack | Empty strings OK only if that stack side is absent |
| `plans` | `dir` | Default `.agents/plans` |

## Optional (offer once, skippable)

`stack`, `domain`, `reviews`, `rules` (non-empty paths only), `defaults`, `dagThresholds`, `issueTrackers` details, `orchestration` / DB fields under `stack`.

## Detection heuristics

Scan consumer **repo root** (not this skill package alone):

| Signal | Suggest |
|--------|---------|
| `package.json` | Node stack; read `scripts.build` / `test` / `lint` / `dev` → `verification.*` / `orchestration.*` |
| `*.sln` / `*.slnx` / `*.csproj` | .NET; `dotnet build` / `dotnet test` |
| `pyproject.toml` / `requirements.txt` | Python; pytest/uvicorn hints when present |
| `go.mod` / `Cargo.toml` | Go / Rust verification commands |
| `.git` + `git remote get-url origin` | `project.repoUrl`, `org`, host → `providers.scm` (`github.com` → github; `dev.azure.com` / `visualstudio.com` → azure-devops) |
| `gh` auth / GitHub remote | `providers.active=github`, enable `issueTrackers.github` |
| ADO remote only | `providers.active=azure-devops` |
| No tracker remote / `specs/**/*.spec.md` | Suggest `active=local` + set `scm` from remote host or ask |
| No app stack detected + `.agents/skills/` present | Suggest `verification.backendTest: "python .agents/skills/check-workflows/scripts/check_workflows.py"` for harness validation |
| `prisma/` / `drizzle` / `Migrations/` / compose DB services | `stack.database.*` hints |
| Top-level `src/`, `web/`, `tests/` | `stack.backend.srcDir` / frontend `sourceDir` / test paths |
| `.agents/skills/shared/STACK.md` (preferred) | `rules.stackFile` → that path |
| Root `STACK.md` / `stack.md` (legacy optional) | Keep only if user already uses it; do not create or require |
| `.agents/skills/shared/CHANGELOG.md` (preferred) | `rules.changelogFile` → that path |
| Repo-root `CHANGELOG.md` | Only if user sets `rules.changelogFile: "CHANGELOG.md"` |
| Existing repo-root `specs/` | Keep `plans.specsDir: "specs"` |
| No specs dir yet | Suggest `plans.specsDir: ".agents/specs"` |
| Existing `config.json` placeholders `<…>` | Treat as gaps |

## Interview order

1. `project` (name, org, repoUrl, baseBranch, workingBranch)
2. `providers` + matching `issueTrackers` slice
3. `plans.dir` / `plans.specsDir` / optional `reviews.dir`
4. `verification` (+ `orchestration` if detected)
5. `stack` summary (id, description, key paths) — or defer to STACK.md generation
6. `domain` / `rules` / `defaults` — optional

Each user-gate: **Accept suggestion (Recommended)** / **Keep current** / **Edit…** / **Skip**.

## Write rules

- Merge into existing JSON; do not delete unknown keys.
- Preserve `_comment*` keys from the example when present.
- After write: show path `.agents/skills/shared/config.json` and remind it is gitignored.
