---
name: azure-devops-provider
description: Azure DevOps provider for spec-to-pr — work item→spec, PAT auth, PR create/threads/merge via az CLI and/or REST plus provider scripts. Use when providers.active or providers.scm is azure-devops, or when invoking /azure-devops-provider standalone.
upstream: jpolvora/workflow-skills — this skill is a spec-to-pr pipeline dependency. Improvements must be submitted upstream to https://github.com/jpolvora/workflow-skills
version: 1.0
disable-model-invocation: true
---

# azure-devops-provider

Owns all **Azure DevOps–specific** instructions and scripts for inbound work items (`fetch-to-spec`) and outbound SCM (`create-pr`, threads, merge). Pipeline skills (`spec-to-pr`, `spec-to-pr-lite`, `09-fix-pr`, `goal-fix-pr`, `08-ship-pr`) load this skill when `config.providers.active` or `config.providers.scm` is `azure-devops`; they must not embed raw `az` / REST happy-path recipes beyond linking here.

Resolve `org` / `project` from `.agents/skills/shared/config.json` (`issueTrackers.azureDevOps`). See [`config-resolution.md`](../shared/config-resolution.md). **Never** hardcode organization or project names in this skill or its scripts.

---

## Invocation

### Standalone Mode

```
/azure-devops-provider <intent> [args...]
```

Examples:

```
/azure-devops-provider fetch-to-spec ADO 2416
/azure-devops-provider fetch-to-spec {org}/{project}#2416
/azure-devops-provider validate-auth
/azure-devops-provider create-pr --head develop --base main
/azure-devops-provider list-threads 592
/azure-devops-provider resolve-thread 4001 --pr-id 592 "Fixed in commit …"
/azure-devops-provider merge-pr 592
```

### Workflow Mode

Dispatched by `spec-to-pr` (entry / Specification Protocol) when `providers.active` is `azure-devops`, and by `09-fix-pr` / `goal-fix-pr` / `08-ship-pr` when `providers.scm` is `azure-devops`. Receives intent name plus args from the caller; confirmation gates follow the parent skill.

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `<intent>` | String | (required) | One of the intents in the contract table below. |
| work item / PR / thread ids | String/Int | (per intent) | Tracker or SCM identifiers; never baked into config as literals for other orgs/projects. |
| `dry-run` | Flag | `false` | When supported by the caller, simulate without mutating remote state. |

---

## Prerequisites

- **CLI (preferred for PR create/merge):** Azure CLI (`az`) with Azure DevOps extension when using `az repos pr` flows.
- **Auth (`validate-auth`):** PAT from env — prefer `issueTrackers.azureDevOps.patEnvVar` (default `ADO_PAT`), then `ADO_PAT`, then `AZURE_DEVOPS_PAT`. Never commit tokens.
- **Config:** `issueTrackers.azureDevOps.enabled` with non-empty `org` / `project` (and optional `apiBase`), and/or `providers.active` / `providers.scm` set to `azure-devops` in `.agents/skills/shared/config.json`.
- **Legacy fallback only:** if `issueTrackers.azureDevOps` is missing fields, scripts may read `.agents/skills/azure-devops/azure-devops.config.json` (+ optional `.secret`) **when that path exists**. If it does not, soft-warn and use only `shared/config.json` + env PAT — **do not** recreate a separate `azure-devops` skill layout for new consumers.

On auth or config failure: **STOP** with fix instructions from `validate-auth`. Do not silently fall back to another provider.

---

## Shared contract — intents

| Intent | Input | Output | Implementation |
|--------|-------|--------|----------------|
| `fetch-to-spec` | `ADO {id}`, `WI {id}`, `{org}/{project}#{id}`, or ADO work-item URL | `{us-dir}/step-00-us-{id}.spec.md` + optional `*.issue.json` | `ado-workitem-to-spec.py` (live WIT REST or offline JSON) |
| `validate-auth` | none | Pass/fail + fix instructions | Org/project present + PAT env resolve; optional WIT smoke GET |
| `create-pr` | head, base, title/body | PR URL + id | `az repos pr create` and/or REST |
| `list-threads` | PR id | Structured thread list | `fix_pr_azure_context.py collect` |
| `resolve-thread` | thread id (+ PR id, comment) | Resolved on remote (or dry-run log) | `fix_pr_azure_context.py resolve-thread` |
| `merge-pr` | PR id | Merged | Wait policies/status then `az repos pr update --status completed` (or equivalent REST) |

**Branch deletion rule:** never delete the configured `project.workingBranch` (default `develop`) after merge. Keep the working branch for future delivery loops.

---

## Canonical scripts

Logic lives under this skill. Thin shims at orch paths (`spec-to-pr/scripts/ado-workitem-to-spec.py`, `09-fix-pr/scripts/fix_pr_azure_context.py`) forward the same CLI args here for install canonicity checks.

| Script | Path | Used by |
|--------|------|---------|
| Work item → spec converter | `.agents/skills/azure-devops-provider/scripts/ado-workitem-to-spec.py` | `fetch-to-spec` |
| PR/thread collect + resolve | `.agents/skills/azure-devops-provider/scripts/fix_pr_azure_context.py` | `list-threads`, `resolve-thread`, auth smoke |

Optional override: `issueTrackers.azureDevOps.workItemToSpecScript` in config, when set, must still resolve to the converter (canonical or shim).

---

## Intent procedures

### `validate-auth`

1. Read `org`, `project`, `apiBase`, `patEnvVar` from `issueTrackers.azureDevOps` in `.agents/skills/shared/config.json`.
2. Resolve PAT: env var named by `patEnvVar` → `ADO_PAT` → `AZURE_DEVOPS_PAT` (legacy file secret only if env empty and legacy config path exists).
3. If org/project missing or PAT empty → print fix instructions (enable tracker, fill org/project, export PAT); **STOP**.
4. Optional smoke: GET `{apiBase}/{org}/{project}/_apis/wit/fields/System.State?api-version=7.1` with Basic auth (empty user + PAT), or rely on `fix_pr_azure_context.py` smoke when available.

### `fetch-to-spec`

Entry patterns:

| Input | Org/project source | Slug |
|-------|--------------------|------|
| `ADO {id}` / `WI {id}` | `issueTrackers.azureDevOps` | `us-{id}` |
| `{org}/{project}#{id}` | parsed from input (must match enabled tracker context) | `us-{id}` |
| ADO work-item URL | parsed from URL | `us-{id}` |

```bash
mkdir -p {plansDir}/us-{id}
python .agents/skills/azure-devops-provider/scripts/ado-workitem-to-spec.py \
  --org {org} --project {project} --id {id} \
  --api-base {apiBase} --pat-env {patEnvVar} \
  --snapshot {plansDir}/us-{id}/step-00-us-{id}.issue.json \
  --output {plansDir}/us-{id}/step-00-us-{id}.spec.md
```

`{org}`, `{project}`, `{apiBase}`, `{patEnvVar}` from config — never consumer-specific literals in skill text.

Plans dir may follow `config.plans.dir` (default `.agents/plans`).

### `create-pr`

Prefer Azure CLI when installed:

```bash
az repos pr create \
  --organization "https://dev.azure.com/{org}" \
  --project "{project}" \
  --repository "{repository}" \
  --source-branch {head} \
  --target-branch {base} \
  --title "{title}" \
  --description "{body}"
```

`{repository}` from remote / `project` config — not hardcoded. Reuse an existing open PR for the same source→target when present. Capture PR id and URL for the caller (`08-ship-pr`). REST equivalent is acceptable when `az` is unavailable (same PAT + org/project).

### `list-threads`

```bash
python .agents/skills/azure-devops-provider/scripts/fix_pr_azure_context.py collect \
  --pr-id {PR_ID} \
  --output .agents/skills/09-fix-pr/runs/pr-{PR_ID}/context.json
```

Return structured threads (`threadId`, path, line, comments, status) to `09-fix-pr` / `goal-fix-pr`. Active-thread count for goal-loop = `len(activeThreads)` from the payload (status in active/pending per script normalization). Collect also prints `collect-summary:` on stderr (`threads`, `activeThreads`, `statuses`).

`context.json` is UTF-8. On Windows, re-reading it requires `encoding="utf-8"` — never bare `open(path)` / locale `cp1252`.

### `resolve-thread`

```bash
python .agents/skills/azure-devops-provider/scripts/fix_pr_azure_context.py resolve-thread \
  --pr-id {PR_ID} \
  --thread-id {THREAD_ID} \
  --model {model} \
  --comment "{resolution note}"
```

Pass `--dry-run` when the parent skill is in `dry-run`. Skip remote mutation in that case.

### `merge-pr`

1. Wait for required policies / PR status (mirror GitHub `checks --watch`): e.g. `az repos pr show` / policy evaluation until green, or documented REST wait.
2. Complete the PR:

```bash
az repos pr update --id {PR_ID} --status completed \
  --organization "https://dev.azure.com/{org}" \
  --project "{project}"
```

Do **not** delete the configured working branch after completion.

---

## Config keys

| Key | Role |
|-----|------|
| `providers.active` | `azure-devops` → this skill owns `fetch-to-spec` / entry registration |
| `providers.scm` | `azure-devops` → this skill owns PR/thread/merge intents |
| `issueTrackers.azureDevOps` | enabled, `org`, `project`, `patEnvVar`, `apiBase`, optional `workItemToSpecScript` |
| `project.workingBranch` / `project.baseBranch` / `project.gitRemote` | defaults for create/merge when flags omit them |
| `plans.dir` | root for `{us-dir}` (`us-{id}`) |

**PAT preference order:** `patEnvVar` from config → `ADO_PAT` → `AZURE_DEVOPS_PAT` → legacy `.secret` file only as fallback.

Legacy: if `providers.*` is absent, orchestrator may select this skill when only `issueTrackers.azureDevOps.enabled` is true (or when entry is explicitly `ADO {id}` / `{org}/{project}#{id}`).

---

## Dependencies

- **Orchestrator:** [spec-to-pr](../spec-to-pr/SKILL.md)
- **Ship:** [08-ship-pr](../08-ship-pr/SKILL.md)
- **Fix / converge:** [09-fix-pr](../09-fix-pr/SKILL.md), [goal-fix-pr](../goal-fix-pr/SKILL.md)
- **Spec format:** [spec-format](../spec-format/SKILL.md)
