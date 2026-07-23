---
name: local-spec-provider
description: >
  Local markdown spec provider for spec-to-pr — detect/configure specsDir, register/normalize/mirror
  hand-written *.spec.md into canonical step-00 artifacts (source: local). PR intents delegate to
  providers.scm. Use when /local-spec-provider, active provider is local, or registering a local
  *.spec.md path.
upstream: jpolvora/workflow-skills — this skill is a spec-to-pr pipeline dependency. Improvements must be submitted upstream to https://github.com/jpolvora/workflow-skills
version: 1.0
disable-model-invocation: true
---

# local-spec-provider

Owns **filesystem** local-spec entry for `spec-to-pr`: detect/configure `plans.specsDir` (default **`.agents/specs`**; prefer existing repo-root `specs/` when present), register/normalize hand-written `*.spec.md` into `{us-dir}/step-00-{slug}.spec.md` with `source: local`, and optional human-browsable mirrors. Does **not** call remote trackers.

**PR / thread / merge intents** are **hybrid**: this skill does not implement SCM APIs. Load the skill selected by `providers.scm` (`github-provider` or `azure-devops-provider`) and run those intents there. Never no-op silently.

---

## Invocation

### Standalone Mode

```
/local-spec-provider <intent> [args...]
```

Examples:

```
/local-spec-provider validate-auth
/local-spec-provider fetch-to-spec specs/my-feature.spec.md
/local-spec-provider fetch-to-spec my-feature --mirror
```

### Workflow Mode

Dispatched by `spec-to-pr` (entry / Specification Protocol) when `providers.active` resolves to `local`, or when the trigger input is an existing `*.spec.md` path. Receives intent + path/slug from the orchestrator. Also used by `00-write-spec` for optional post-draft mirror under `specsDir`.

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `<intent>` | String | (required) | One of the intents in the contract table below. |
| path / slug | String | (intent-dependent) | Local `*.spec.md` path or slug under `specsDir`. |
| `--mirror` | Flag | `false` | Also write flat mirror `{specs-dir}/{slug}.spec.md`. |

---

## Configuration

Read [`.agents/skills/shared/config.json`](../shared/config.json):

| Key | Role |
|-----|------|
| `plans.specsDir` | Local specs root (default **`.agents/specs`**; if repo-root `specs/` already exists and config omits the key, prefer `specs`). |
| `plans.dir` | Plans root; `{us-dir}` = `{plansDir}/{slug}/`. |
| `providers.active` | When `local`, entry uses this skill for `fetch-to-spec`. |
| `providers.scm` | Host for PR intents (`github` \| `azure-devops`). Required when shipping from local specs. **Never** `local`. |

If `plans.specsDir` is missing: prefer existing repo-root `specs/`; otherwise use `.agents/specs`. Create the directory and write `plans.specsDir` into local `config.json` (gitignored — never commit). Do **not** create a new repo-root `specs/` unless the consumer explicitly chose that path.

### Specs layout (flat + one-level nested)

| Layout | Path |
|--------|------|
| Flat | `{specs-dir}/{slug}.spec.md` |
| Nested | `{specs-dir}/{slug}/README.spec.md` |
| Nested | `{specs-dir}/{slug}/{slug}.spec.md` |

Canonical workflow copy is always `{us-dir}/step-00-{slug}.spec.md`. `{specs-dir}` is a human mirror / intake root only.

---

## Intent contract

| Intent | Behavior |
|--------|----------|
| `fetch-to-spec` | Register/normalize input path or slug → `{us-dir}/step-00-{slug}.spec.md` with `source: local`. Optional `--mirror`. Skip Step 0 (local entry). |
| `validate-auth` | Ensure `specsDir` exists or is creatable; when configuring, `config.json` must be writable. No remote auth. |
| `create-pr` | **Delegate** to skill for `providers.scm` — do not implement here. |
| `list-threads` | **Delegate** to `providers.scm`. |
| `resolve-thread` | **Delegate** to `providers.scm`. |
| `merge-pr` | **Delegate** to `providers.scm` (never delete working branch by default). |

### Provider resolution (same algorithm as orchestrator)

1. Read `providers.active` / `providers.scm` from `config.json`.
2. If `providers` absent: enabled GitHub → `github`; else enabled ADO → `azure-devops`; else `local`. Prefer GitHub if both enabled.
3. If `scm` absent: if active is `github`\|`azure-devops` → scm=active; if active=`local` → parse `project.repoUrl` host (`github.com` → github; `dev.azure.com` / `visualstudio.com` → azure-devops); else STOP and require explicit `providers.scm`.
4. Reject `scm: "local"`.

---

## Scripts

Canonical paths (Python 3; **no PowerShell**):

| Script | Purpose |
|--------|---------|
| [`.agents/skills/local-spec-provider/scripts/detect_specs_dir.py`](scripts/detect_specs_dir.py) | Detect / ensure / configure `plans.specsDir`; `--validate` for `validate-auth`. |
| [`.agents/skills/local-spec-provider/scripts/register_local_spec.py`](scripts/register_local_spec.py) | Register/normalize/mirror into `{us-dir}/step-00-{slug}.spec.md`. |

### `validate-auth`

```bash
python .agents/skills/local-spec-provider/scripts/detect_specs_dir.py --validate
# optional machine output:
python .agents/skills/local-spec-provider/scripts/detect_specs_dir.py --validate --json
```

### Detect / configure `specsDir`

```bash
python .agents/skills/local-spec-provider/scripts/detect_specs_dir.py --detect
python .agents/skills/local-spec-provider/scripts/detect_specs_dir.py --detect --ensure
python .agents/skills/local-spec-provider/scripts/detect_specs_dir.py --configure specs
```

### `fetch-to-spec` (register / normalize / mirror)

```bash
mkdir -p "{plansDir}/{slug}"   # script also creates us-dir
python .agents/skills/local-spec-provider/scripts/register_local_spec.py \
  --input path/to/feature.spec.md \
  [--slug feature] \
  [--mirror] \
  [--force]
```

Slug resolution: frontmatter `slug:` if present; else basename without `.spec.md` (strip leading `step-00-`); for nested `README.spec.md` / twin file, use parent directory name.

Normalization always sets `source: local` and ensures `slug` + `title` (+ `specDate` if missing). Overwrite existing canonical file only if identical or `--force` / user confirms.

Do **not** call tracker APIs. Validate required sections per [`spec-format`](../spec-format/SKILL.md) after registration when running as an agent.

### PR intents → scm provider

When the caller needs `create-pr` / `list-threads` / `resolve-thread` / `merge-pr` and this skill is the active *spec* provider:

1. Resolve `providers.scm` (algorithm above).
2. Load [github-provider](../github-provider/SKILL.md) or [azure-devops-provider](../azure-devops-provider/SKILL.md).
3. Execute the intent on that skill. Specs remain `source: local`.

---

## Entry patterns

| Input | Action |
|-------|--------|
| `*.spec.md` path (any) | `fetch-to-spec` → register under `{us-dir}` |
| Slug under `specsDir` (flat or nested) | Resolve file → `fetch-to-spec` |
| Already `{us-dir}/step-00-{slug}.spec.md` | Re-normalize `source: local` if needed; skip Step 0 |

---

## Dual-mode notes

- **Standalone:** run intents directly; print `specPath` / `specsDir` for the user.
- **Workflow:** orchestrator records `specPath`, `specSource: local`, skips Step 0, advances to Step 1 gate.
- **Language:** en-us only (skill body, scripts, user-facing script messages).
- **Portability:** no hardcoded org/repo/project; paths from `config.json`.
