---
slug: github-pages-site
title: "GitHub Pages site: hero, how-to, deploy on merge"
status: "plan refined ok"
refinedFrom: step-01-github-pages-site.plan.md
refinedAt: "2026-07-23T17:32:00Z"
shared_understanding: confirmed
---

## 0. Summary & Business Rules

### Objectives

Ship a **lightweight static marketing site** for [jpolvora/cursor-profile-manager](https://github.com/jpolvora/cursor-profile-manager) on **GitHub Pages** so visitors immediately understand:

> Run **multiple isolated Cursor IDE instances/profiles** on one machine/codebase, each with its **own Cursor account** (login, extensions, settings, AI chat history).

The page has three jobs only:

1. **Hero (first viewport)** — Brand + goal message + full-bleed anonymized product screenshot + CTA(s).
2. **Basic how-to** — Short numbered Windows path: obtain/run → add profile → Start → second profile / second account.
3. **CI deploy** — On merge/push to default branch (`master`), GitHub Actions rebuilds/deploys the site to Pages (no manual `gh-pages` push).

### Business rules

| Rule | Detail |
|------|--------|
| Scope | Marketing + getting-started landing only. README remains primary in-repo docs. |
| Platform | Windows-only messaging; no macOS/Linux install as supported. |
| Feature honesty | Do not invent features; align how-to with README Quick start / Usage (GUI, `--user-data-dir`, no CLI-launcher requirement on the site). |
| Privacy | Hero imagery must use anonymized `screenshots/main-window-hero.png` (fake names/paths only). |
| Language | English (en-us) only. |
| Non-goals | No change to PowerShell GUI core; no custom domain required; no full docs portal, blog, i18n, or Agent Story deep-dive section. |

### Security / privacy mitigations

- Commit only the scrubbed hero PNG (`screenshots/main-window-hero.png` and site-bundled copy). Never swap in personal captures showing real usernames, home paths, or private project dirs.
- Site is public static HTML; no secrets, tokens, or user profile data.
- Workflow uses official `actions/configure-pages`, `upload-pages-artifact`, `deploy-pages` with least privilege (`pages: write`, `id-token: write`).

---

## 1. Definition of Ready & Scope

### Resolved assumptions (interview-locked)

| Assumption | Resolution | Evidence |
|------------|------------|----------|
| Default branch | `master` | `project.baseBranch` in config.json; `origin/HEAD` → `origin/master` |
| Stack for this feature | **Static HTML + CSS** (± minimal JS). Not Agent Story React/Vite; not PowerShell GUI. | Spec + STACK.md (site is parallel surface) |
| Site root | **`site/`** at repo root | Open Q1 default; `docs/` only holds `superpowers/` (internal specs); avoid Pages/docs mix |
| Rebuild | Pure static: upload `site/` as Pages artifact (no generator) | Spec “rebuild may be no-op” |
| Published URL (expected) | `https://jpolvora.github.io/cursor-profile-manager/` | org/repo from config.json |
| Hero asset | Source: `screenshots/main-window-hero.png` → bundle `site/assets/main-window-hero.png` | Both plan copy and screenshots PNG present (same size) |
| Asset URLs | **Relative** paths only (`styles.css`, `assets/...`) so project Pages base path works | Project site is not domain root |
| Path filters | `site/**` + `.github/workflows/pages.yml` | Open Q2 default |
| Fonts | One intentional CSS font pair; CDN OK | Open Q3 default |
| Pages enablement | README documents Settings → Pages → GitHub Actions | Open Q4; satisfies AC6/AC10 without blocking impl |
| README badge | **Skip** status badge; plain Website link is enough | Open Q5 default |

### Acceptance Criteria (measurable)

| ID | Criterion |
|----|-----------|
| AC1 | Repo contains static site source (HTML + CSS min) under documented path (`site/`). |
| AC2 | First viewport hero primary message = multi-profile / multi-account Cursor goal (not generic OSS filler). |
| AC3 | Hero has brand **Cursor Profile Manager**, one short supporting sentence (AC2-aligned), ≥1 clear CTA (Get started / How to use and/or GitHub). |
| AC12 | Hero (or adjacent first-viewport block) shows `main-window-hero.png` (or site copy) with meaningful `alt` about multiple profiles/accounts. |
| AC13 | Published hero imagery has no real personal usernames/home paths/private project dirs (anonymized asset only). |
| AC4 | Below hero: numbered how-to — obtain/run on Windows, add profile, Start, second profile for different account. |
| AC5 | How-to matches README behavior (Windows GUI, `--user-data-dir`, no CLI-launcher requirement on site). |
| AC6 | Pages configured or maintainer-documented so URL serves this site. |
| AC7 | `.github/workflows/` contains a workflow that deploys (rebuild then deploy) to GitHub Pages. |
| AC8 | Workflow triggers on push/merge to default branch `master`. |
| AC9 | Merging site/workflow changes to `master` yields green Pages deploy without manual FTP/`gh-pages` push. |
| AC10 | README links to Pages URL once known, or documents enablement + site path until confirmed. |
| AC11 | Copy en-us; no out-of-scope platform/feature invention. |

### Out of scope

- PowerShell GUI / launch-contract changes.
- Replacing README as primary documentation.
- Custom domain.
- Full docs portal, blog, i18n, auth, download CDN beyond GitHub links.
- Agent Story as a required marketing section.
- Committing `.agents/plans/` as delivery product (planning artifacts only until Step 8 policy).
- README Pages status badge (explicitly skipped).

### Definition of Ready

- Spec canonical at `step-00-github-pages-site.spec.md` (done).
- Hero PNG present at `screenshots/main-window-hero.png` (done).
- Open Questions Q1–Q5 closed via autoMode defaults (this refined plan).
- Implementer may start Step 3/4 with no further product decisions.

---

## 2. Technical Design & Architecture

### Layer model (this feature vs config.json)

`config.json` layers describe Manager GUI / Agent Story. **This work adds a parallel static “Marketing site” surface** that does not mutate those layers:

| Layer | Path | Role |
|-------|------|------|
| Marketing site (new) | `site/` | Static HTML/CSS (± minimal JS), assets |
| CI / Pages (new) | `.github/workflows/pages.yml` | Deploy on push to `master` (path-filtered) |
| User docs (touch) | `README.md` | Website section: URL + enablement + `site/` path |
| Product changelog (touch) | `CHANGELOG.md` | Added entry for public site |
| Agent guide (optional touch) | `AGENTS.md` | One-line file-map row for `site/` if useful |
| **Do not touch** | `cursor-profile-manager.ps1`, `tests/`, `agent-story/**` | Core app / Pester / Agent Story unchanged |

### Recommended file tree

```text
site/
  index.html          # Single landing page
  styles.css          # Layout, hero, how-to, tokens
  assets/
    main-window-hero.png   # Copy of screenshots/main-window-hero.png
.github/workflows/
  pages.yml           # GitHub Pages deploy
README.md             # Website section (link; no badge)
CHANGELOG.md          # Added: public GitHub Pages site
```

Optional later (not required): `site/robots.txt`, favicon. Skip unless needed for polish.

### Frontend design (hard rules)

| Rule | Application |
|------|-------------|
| One composition | First viewport = brand + one headline + one support line + CTA group + dominant product image. No stats strips or secondary marketing clutter in viewport 1. |
| Brand first | **Cursor Profile Manager** is hero-level (not nav-only). |
| Full-bleed hero visual | `main-window-hero.png` as edge-to-edge / dominant plane, not inset card / floating collage. |
| No hero overlays | No badges/chips/stickers on the screenshot. |
| No card clutter | How-to = simple numbered list/section, not card grid. |
| Avoid design biases | No purple-on-white / indigo gradient; no cream+serif+terracotta; no broadsheet dense columns. Cool-neutral or charcoal + single accent (cyan/blue aligned with README badges). |
| Fonts (locked) | One intentional font pair via CSS `@import` or `<link>` to a CDN (Google Fonts or similar). Do not use Inter/Roboto/Arial as identity fonts. |
| Motion | 2–3 subtle motions (hero fade/rise, CTA hover, soft image reveal). Prefer CSS. |
| Responsive | Desktop + mobile: stack copy above image on narrow viewports; image remains large. |
| Paths | Relative URLs only (project Pages serves under `/cursor-profile-manager/`). |

### Hero content contract

| Element | Content guidance |
|---------|------------------|
| Brand | Cursor Profile Manager |
| Headline | Goal-forward (multi-instance / multi-account isolation), not “welcome to our repo”. |
| Support | One sentence: separate login, extensions, settings, AI chat per profile on the same codebase. |
| CTA | Primary: in-page `#how-to` (“Get started”); Secondary: GitHub repo link. |
| Image | `site/assets/main-window-hero.png`; `alt` e.g. “Cursor Profile Manager main window showing multiple isolated profiles, some Running and some Idle, with per-row Start Focus Close actions”. |

### How-to content contract (AC4–AC5)

Numbered steps aligned with README Quick start / Usage (verified in-repo):

1. **Obtain / run on Windows** — Clone repo; run `.\cursor-profile-manager.ps1` or double-click `cursor-profile-manager.bat`; optional `install-desktop-shortcut.ps1`.
2. **Add a profile** — Toolbar **Add Profile**; isolated folder under `%USERPROFILE%\.cursor-profiles\`.
3. **Start** — **Start ▶** / double-click row → Cursor with `--user-data-dir` for that profile.
4. **Second profile / account** — Add another profile; Start it; sign in to a different Cursor account on first launch for that profile.

Mention isolation via `--user-data-dir` in plain language. **Do not** require CLI launchers on the site. Agent Story optional one-liner max (link to README), not a required how-to step.

### CI / Pages architecture (locked)

```text
push to master (paths: site/** OR .github/workflows/pages.yml)
  → jobs.build: checkout → configure-pages → upload-pages-artifact (path: site)
  → jobs.deploy: environment github-pages → deploy-pages
```

- Permissions: `contents: read`, `pages: write`, `id-token: write`.
- Concurrency: one Pages deploy at a time; `cancel-in-progress: false`.
- Trigger: `on.push.branches: [master]` plus `workflow_dispatch` for maintainer re-run.
- Path filters: `paths: ['site/**', '.github/workflows/pages.yml']`. Document in README that README-only changes do not redeploy (acceptable).
- No `.github/` exists yet in repo; create workflow directory as part of Step E.

### Maintainer Pages enablement (AC6 / AC10)

Document in README **Website** subsection:

1. Repo **Settings → Pages → Build and deployment → Source: GitHub Actions**.
2. After first green workflow, site at `https://jpolvora.github.io/cursor-profile-manager/`.
3. Site source lives in `site/`.
4. No Pages status badge required.

### Invariant checks (`config.json.invariants`)

| Invariant | Impact on this plan |
|-----------|---------------------|
| `powershell51Baseline` | N/A for site HTML; do not change PS scripts. |
| `noHardcodedWindowTitle` | N/A (no GUI edits). |
| `profilesJsonNeverCommitted` | Do not commit profile data; hero uses fake paths only. |
| `commitPlanFilesOnlyAtStep8` | Do not stage `.agents/plans/` in delivery commits before Step 8 policy. |
| EF/tenancy invariants | N/A. |

---

## 3. Step-by-Step Plan

Dependency order: site shell → content/design → asset → workflow → docs → verify.

### Step A — Scaffold static site (`site/`)

**Action:** Create `site/index.html` + `site/styles.css` with semantic structure: header/brand, hero, how-to section (`id="how-to"`), footer (repo link, Windows-only note). Use relative asset/CSS links.

**Files:** `site/index.html`, `site/styles.css`

**Checks:** Valid HTML5; `lang="en"`; no build tooling; opens via file:// or static server.

**ACs:** AC1 (partial), AC11.

### Step B — Hero composition (brand, copy, CTA, layout)

**Action:** First-viewport hero per design rules: brand-level name, goal headline, one support sentence, CTA group. Full-bleed / dominant image region. CSS variables; intentional CDN font pair; avoid banned aesthetics.

**Files:** `site/index.html`, `site/styles.css`

**Checks:** Removing nav still leaves unmistakable branding; viewport 1 has no card grid / stat strip / overlay badges.

**ACs:** AC2, AC3.

### Step C — Bundle & display hero screenshot

**Action:** Copy `screenshots/main-window-hero.png` → `site/assets/main-window-hero.png` (same bytes). Reference with relative `src` and meaningful `alt`. Spot-check anonymized demo names/paths only.

**Files:** `site/assets/main-window-hero.png`, `site/index.html`

**Checks:** Image loads under project Pages base; alt describes multi-profile UI; no real PII.

**ACs:** AC12, AC13.

### Step D — How-to section

**Action:** Numbered how-to below hero matching README Quick start / Usage (four topics above). English only; no macOS/Linux support claims; no invented features.

**Files:** `site/index.html`, `site/styles.css` (section spacing only)

**Checks:** Four required topics present; content consistent with README.

**ACs:** AC4, AC5, AC11.

### Step E — GitHub Actions Pages workflow

**Action:** Add `.github/workflows/pages.yml` using official Pages actions; trigger on push to `master` with path filters + `workflow_dispatch`; upload `site/` artifact; deploy job with `github-pages` environment.

**Files:** `.github/workflows/pages.yml`

**Checks:** YAML valid; branch `master`; path filters present; permissions correct; no manual `gh-pages` push step.

**ACs:** AC7, AC8, AC9 (AC9 fully proven after merge + Pages source enabled).

### Step F — README + CHANGELOG (+ optional AGENTS file map)

**Action:**

- README: **Website** subsection linking `https://jpolvora.github.io/cursor-profile-manager/`, documenting `site/`, path-filter redeploy note, and Settings → Pages → GitHub Actions. **No** status badge.
- CHANGELOG: **Added** public GitHub Pages marketing site + deploy workflow.
- Optional: AGENTS.md file-map row for `site/`.

**Files:** `README.md`, `CHANGELOG.md`, optionally `AGENTS.md`

**Checks:** Link/path/enablement documented; changelog has Added entry.

**ACs:** AC6, AC10.

### Step G — Local + CI verification

**Action:** Open `site/index.html` in browser (or `npx serve site`); run section 5 checklist; after merge to `master` (and Pages source enabled), confirm green workflow and live URL. Do **not** use Pester as proof of site; optional `run-tests.ps1` only if shared/core files were accidentally touched.

**Files:** none (verification only)

**ACs:** AC1–AC13 via section 5 matrix.

---

## 4. Permissions, Tenancy & i18n

| Area | Plan |
|------|------|
| RBAC / tenancy | N/A — public static site; no user data, no multi-tenant app surface. |
| GitHub Actions permissions | Workflow: `pages: write`, `id-token: write`, `contents: read`. Deploy environment: `github-pages`. |
| Repo settings | Maintainer enables Pages source = GitHub Actions (one-time; documented). |
| i18n | Single locale **en-us**. `html lang="en"`. |
| Accessibility | Meaningful image `alt`; sufficient contrast; keyboard-focusable CTAs/links. |

Scenario probes (N/A for this surface): soft-deletion, list sizing, app rate limits. Workflow concurrency covered in §2.

---

## 5. Test Coverage

No unit-test harness for static HTML in this repo. Verification = **manual / checklist** (+ Actions run).

| AC | Test ID | Method / procedure | Pass criteria |
|----|---------|-------------------|---------------|
| AC1 | `T-AC1-site-source` | Inspect repo: `site/index.html` + `site/styles.css` exist; README documents `site/`. | Files present; path documented. |
| AC2 | `T-AC2-hero-goal` | Open `site/index.html`; read first-viewport headline + support. | Copy states multi-profile / separate accounts. |
| AC3 | `T-AC3-brand-cta` | Same viewport check. | Brand hero-level; one support sentence; ≥1 CTA. |
| AC12 | `T-AC12-hero-image` | Inspect `img` src + visual. | Site-bundled hero; `alt` mentions multiple profiles/accounts. |
| AC13 | `T-AC13-privacy` | Visually inspect hero PNG. | Only demo data; no real personal paths. |
| AC4 | `T-AC4-howto-steps` | Scroll to `#how-to`. | Covers obtain/run, add profile, Start, second profile/account. |
| AC5 | `T-AC5-readme-parity` | Compare to README Quick start / Usage. | Windows GUI; `--user-data-dir`; no CLI-launcher requirement. |
| AC6 | `T-AC6-pages-docs` | Read README Website section. | URL and enablement steps + `site/` path. |
| AC7 | `T-AC7-workflow-exists` | Open `.github/workflows/pages.yml`. | Uses Pages deploy actions. |
| AC8 | `T-AC8-branch-trigger` | Read `on:` in workflow. | Push to `master` (+ optional `workflow_dispatch`). |
| AC9 | `T-AC9-deploy-green` | After merge to `master` with Pages source enabled. | Deploy job green; no human FTP/`gh-pages` push. |
| AC10 | `T-AC10-readme-link` | README Website section. | URL + enablement; no badge required. |
| AC11 | `T-AC11-scope-lang` | Review visible site copy. | English; Windows-only; no invented features. |

**Regression:** If any product script accidentally edited, run `powershell -NoProfile -File .\run-tests.ps1`. Expected: no Pester changes for this feature.

---

## 6. Invariants (Do Not Violate)

1. **No PowerShell GUI / launch-contract changes** unless a separate spec says so.
2. **`powershell51Baseline`** — prefer zero script touches.
3. **`profilesJsonNeverCommitted`** — hero stays anonymized.
4. **`commitPlanFilesOnlyAtStep8`** — do not `git add` `.agents/plans/` for ordinary delivery commits.
5. **README remains source of truth** — site summarizes; do not fork divergent feature claims.
6. **Do not publish `docs/superpowers/`** as the Pages root.
7. **Do not use purple-on-white / cream-serif-terracotta / broadsheet** as the default look.
8. **English only** on the site.
9. **Relative asset paths only** under `site/` (project Pages base path).

---

## 7. Pre-PR Checklist

- [ ] Layer boundaries respected (only `site/`, workflow, README/CHANGELOG ± AGENTS; no GUI/Agent Story churn).
- [ ] Domain entities / EF mappings — N/A.
- [ ] Schema migrations — N/A.
- [ ] Authorization — N/A (public site); workflow permissions minimal.
- [ ] i18n keys — N/A; `lang="en"` set.
- [ ] Test cases cover all ACs (section 5; AC9 post-merge).
- [ ] Hero asset anonymized and bundled under `site/assets/`.
- [ ] Design: brand-first, full-bleed product visual, no card clutter in hero; intentional CDN font pair.
- [ ] Workflow triggers on `master` with path filters; `workflow_dispatch` present; Pages source documented.
- [ ] README Website section (link + enablement; **no** badge); CHANGELOG **Added** entry present.
- [ ] No `.agents/plans/` staged for delivery commit.

---

## 8. Open Questions

All closed under autoMode (softSkipEligible). No remaining product decisions.

| # | Question | Locked answer |
|---|----------|---------------|
| Q1 | Site folder `site/` vs `docs/site/`? | **`site/`** at repo root. |
| Q2 | Path-filter workflow? | **Yes** — `site/**` + `.github/workflows/pages.yml`; README notes README-only skips redeploy. |
| Q3 | Web fonts CDN vs system fonts? | **One intentional font pair via CSS/CDN**; avoid Inter/Roboto/Arial-as-identity. |
| Q4 | First-deploy Pages enablement? | Document in README; AC6/AC10 via docs + URL; AC9 when Actions + Settings enabled. |
| Q5 | Pages status badge? | **Skip**; link text is enough for AC10. |

---

## Interview registry

| id | class | section | gap | recommendation | status | resolution | dependsOn |
|----|-------|---------|-----|----------------|--------|------------|-----------|
| G1 | non-blocking | 8 / Q1 | Site path ambiguous in spec (`docs/site/` or `site/`) | Prefer `site/` at repo root | resolved | Locked `site/`. Evidence: `docs/` only has `superpowers/`; avoids mixing marketing Pages with internal design specs. | — |
| G2 | non-blocking | 8 / Q2 | Whether to path-filter workflow | Filter `site/**` + workflow file | resolved | Locked path filters; README documents README-only skip. | — |
| G3 | non-blocking | 8 / Q3 | Font strategy undecided | Intentional CSS font pair; CDN OK | resolved | Locked CDN font pair; banned Inter/Roboto/Arial-as-identity. | — |
| G4 | non-blocking | 8 / Q4 | AC6 needs maintainer Settings click | Document enablement in README | resolved | AC6/AC10 satisfied by docs + expected URL; AC9 proven post-enable. Does not block implementation. | — |
| G5 | non-blocking | 8 / Q5 | Optional Pages badge | Skip badge; text link only | resolved | Badge skipped per autoMode default. | — |
| G6 | non-blocking | 2 | No `.github/` directory exists yet | Create `.github/workflows/pages.yml` from scratch | resolved | Confirmed via repo listing (`no .github dir`). Step E creates it. | — |
| G7 | non-blocking | 2 | Project Pages base path can break root-absolute URLs | Use relative asset/CSS/href paths only | resolved | Locked in §2 design + invariant #9. URL `https://jpolvora.github.io/cursor-profile-manager/`. | — |
| G8 | non-blocking | 2 / CI | Optional `workflow_dispatch` | Include for maintainer re-run | resolved | Include `workflow_dispatch` alongside push to `master`. | — |
| G9 | non-blocking | 5 / AC9 | Full deploy proof only after merge + Pages source | Keep AC9 as post-merge check; do not block plan | resolved | Already in Step G / T-AC9; Q4 docs cover enablement. | — |
| G10 | non-blocking | 3 / D | How-to must match live README | Align four steps to Quick start / Usage | resolved | README verified: `.ps1`/`.bat`, Add Profile, Start ▶, `--user-data-dir`, second profile for second account. | — |
| G11 | non-blocking | 1 | MEMORY.md empty for Pages keywords | Proceed with spec/README evidence | resolved | MEMORY consult: no matching traps for github-pages/site/workflow. | — |

**Audit summary:** Sections 0–8 scanned. Scenario probes (soft-delete, concurrency, list size, rate limits): N/A or covered by workflow concurrency. **blocking_open: 0**. Fast exit applied (`softSkipEligible` + `autoMode`).
)
