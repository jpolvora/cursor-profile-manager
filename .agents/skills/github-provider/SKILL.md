---
name: github-provider
description: GitHub provider for spec-to-pr — issue→spec, auth checks, PR create/threads/merge via gh CLI and provider scripts. Use when providers.active or providers.scm is github, or when invoking /github-provider standalone.
upstream: jpolvora/workflow-skills — this skill is a spec-to-pr pipeline dependency. Improvements must be submitted upstream to https://github.com/jpolvora/workflow-skills
version: 1.0
disable-model-invocation: true
---

# github-provider

Owns all **GitHub-specific** instructions and scripts for inbound issues (`fetch-to-spec`) and outbound SCM (`create-pr`, threads, merge). Pipeline skills (`spec-to-pr`, `spec-to-pr-lite`, `09-fix-pr`, `goal-fix-pr`, `08-ship-pr`) load this skill when `config.providers.active` or `config.providers.scm` is `github`; they must not embed raw `gh` happy-path recipes beyond linking here.

Resolve `owner` / `repo` from `.agents/skills/shared/config.json` (`issueTrackers.github`, `project.org` / repo name, or `project.repoUrl`). See [`config-resolution.md`](../shared/config-resolution.md). **Never** hardcode org or repo names in this skill or its scripts.

---

## Invocation

### Standalone Mode

```
/github-provider <intent> [args...]
```

Examples:

```
/github-provider fetch-to-spec 2416
/github-provider validate-auth
/github-provider create-pr --head develop --base main
/github-provider list-threads 42
/github-provider resolve-thread <thread-id> "Fixed in commit …"
/github-provider merge-pr 42
```

### Workflow Mode

Dispatched by orchestrators (`spec-to-pr`, `spec-to-pr-lite` entry / Specification Protocol) when `providers.active` is `github`, and by `09-fix-pr` / `goal-fix-pr` / `08-ship-pr` when `providers.scm` is `github`. Receives intent name plus args from the caller; confirmation gates follow the parent skill.

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `<intent>` | String | (required) | One of the intents in the contract table below. |
| issue / PR / thread ids | String/Int | (per intent) | Tracker or SCM identifiers; never baked into config as literals for other repos. |
| `dry-run` | Flag | `false` | When supported by the caller, simulate without mutating remote state. |

---

## Prerequisites

- **CLI:** `gh` installed and on `PATH`.
- **Auth (`validate-auth`):** `gh auth status` must succeed for issue/PR CLI flows.
- **GraphQL threads:** token from `AGENTIC_CODE_REVIEWERS_GITHUB_TOKEN` → `GITHUB_TOKEN` → `GH_TOKEN` (same precedence as thread scripts).
- **Config:** `issueTrackers.github.enabled` (legacy) and/or `providers.active` / `providers.scm` set to `github` in `.agents/skills/shared/config.json`.

On auth failure: **STOP** with fix instructions from `validate-auth`. Do not silently fall back to another provider.

---

## Shared contract — intents

| Intent | Input | Output | Implementation |
|--------|-------|--------|----------------|
| `fetch-to-spec` | Issue id (`{n}`, `US {n}`, or GitHub issue URL) | `{us-dir}/step-00-us-{n}.spec.md` + optional `*.issue.json` | `gh issue view` → converter script |
| `validate-auth` | none | Pass/fail + fix instructions | `gh auth status`; note GraphQL token for threads |
| `create-pr` | head, base, title/body | PR URL + id | `gh pr create` (reuse open PR head→base if present) |
| `list-threads` | PR id | Structured thread list | `fetch_threads.cjs` |
| `resolve-thread` | thread id (+ comment) | Resolved on remote (or dry-run log) | `resolve_thread.cjs` |
| `merge-pr` | PR id | Merged | `gh pr checks --watch` then `gh pr merge --merge` |

**Branch deletion rule:** never pass `--delete-branch` when merging if the PR head is the configured `project.workingBranch` (default `develop`). Keep the working branch for future delivery loops.

---

## Canonical scripts

Logic lives under this skill. Legacy callers may still hit thin forwarder shims under `spec-to-pr/scripts/` and `09-fix-pr/scripts/`. **Prefer these canonical paths:**

| Script | Path | Used by |
|--------|------|---------|
| Issue → spec converter | `.agents/skills/github-provider/scripts/github-issue-to-spec.py` | `fetch-to-spec` |
| List review threads | `.agents/skills/github-provider/scripts/fetch_threads.cjs` | `list-threads` |
| Resolve review thread | `.agents/skills/github-provider/scripts/resolve_thread.cjs` | `resolve-thread` |

Optional override: `issueTrackers.github.issueToSpecScript` in config, when set, must still resolve to the converter (canonical or shim).

---

## Intent procedures

### `validate-auth`

```bash
gh auth status
```

- Exit 0 → pass for CLI issue/PR flows.
- Non-zero → instruct user to run `gh auth login` (or fix `GH_TOKEN` / host config); **STOP**.
- For `list-threads` / `resolve-thread`, also require a token in `AGENTIC_CODE_REVIEWERS_GITHUB_TOKEN`, `GITHUB_TOKEN`, or `GH_TOKEN`. If missing, print the same token hint the scripts emit and **STOP**.

### `fetch-to-spec`

Entry patterns: `{n}`, `US {n}`, GitHub issue URL → slug `us-{n}`.

```bash
mkdir -p {plansDir}/us-{n}
gh issue view {n} --json number,title,body,state,labels,assignees,comments,url \
  > {plansDir}/us-{n}/step-00-us-{n}.issue.json
python .agents/skills/github-provider/scripts/github-issue-to-spec.py \
  --input {plansDir}/us-{n}/step-00-us-{n}.issue.json \
  --output {plansDir}/us-{n}/step-00-us-{n}.spec.md \
  --repo {owner}/{repo}
```

`{owner}/{repo}` from config (`issueTrackers.github` or `project`), never literals in skill text for a specific consumer.

Plans dir may follow `config.plans.dir` (default `.agents/plans`).

### `create-pr`

```bash
gh pr create --head {head} --base {base} --title "{title}" --body "{body}"
```

Reuse an existing open PR for the same head→base when present (`gh pr list` / `gh pr view`). Capture PR number and URL for the caller (`08-ship-pr`).

### `list-threads`

```bash
node .agents/skills/github-provider/scripts/fetch_threads.cjs {PR_ID} [--json]
```

Return structured threads (`threadId`, path, line, comments) to `09-fix-pr` / `goal-fix-pr`.

### `resolve-thread`

```bash
node .agents/skills/github-provider/scripts/resolve_thread.cjs {THREAD_ID} "{resolution note}"
```

Skip remote mutation when the parent skill is in `dry-run`.

### `merge-pr`

```bash
gh pr checks {PR_ID} --watch
gh pr merge {PR_ID} --merge
```

Do **not** add `--delete-branch` for the configured working branch.

---

## Config keys

| Key | Role |
|-----|------|
| `providers.active` | `github` → this skill owns `fetch-to-spec` / entry registration |
| `providers.scm` | `github` → this skill owns PR/thread/merge intents |
| `issueTrackers.github` | enabled flag, org/repo fields, optional `issueToSpecScript` |
| `project.workingBranch` / `project.baseBranch` / `project.gitRemote` | defaults for create/merge when flags omit them |
| `plans.dir` | root for `{us-dir}` (`us-{n}`) |

Legacy: if `providers.*` is absent, GitHub remains the default when `issueTrackers.github.enabled` (orchestrator inference).

---

## Dependencies

- **Orchestrator:** [spec-to-pr](../spec-to-pr/SKILL.md)
- **Ship:** [08-ship-pr](../08-ship-pr/SKILL.md)
- **Fix / converge:** [09-fix-pr](../09-fix-pr/SKILL.md), [goal-fix-pr](../goal-fix-pr/SKILL.md)
- **Spec format:** [spec-format](../spec-format/SKILL.md)
