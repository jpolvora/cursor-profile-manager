---
slug: profile-window-mode
title: "Profile Window Mode (Classic IDE vs Agents Window)"
status: "plan to be refined"
---

## 0. Summary & Business Rules

### Objectives

Add a per-profile **Window Mode** preference so Start can force Cursor’s classic IDE (`--classic`), Agents Window (`--glass`), or leave the choice to Cursor (`default` / no flag). Preference is stored on the profile object, edited in Add/Edit Profile, and merged into every Start argument list.

### Business rules

| Rule | Detail |
|------|--------|
| Storage | `WindowMode` string: `default` \| `classic` \| `glass` |
| Default | Missing or invalid → `default` (load + helpers); new profiles → `default` |
| UI | DropDownList in Add/Edit only; labels map to the three values |
| Launch | Append at most one of `--classic` / `--glass`; never both; `default` adds neither |
| Grid | No WindowMode column |
| Baseline | Windows PowerShell **5.1** only (no PS 7 syntax) |
| Docs | README + AGENTS.md launch contract + CHANGELOG **Added** + App-Version bump |

### Security / compatibility mitigations

- Flags are fixed literals from a normalized enum — never free-form user strings on the CLI.
- Older Cursor builds that ignore unknown flags remain usable; document that `--classic` / `--glass` need a recent Cursor 3.x desktop build.
- Do not write Cursor settings for “Open Agents Window on startup”; CLI flags only.

---

## 1. Definition of Ready & Scope

### Resolved assumptions

| Assumption | Resolution |
|------------|------------|
| Helper shape | Mirror `ProxyType` helpers (`Get-ProfileProxyType*` / `Get-CursorProxyLaunchArgs`) |
| Combo placement | Near proxy controls in `Show-ProfileDialog`; bump FixedDialog height if needed |
| Theme | Same input colors as `cmbProxyType` |
| Soft profile reset | **Out of scope** (separate design/workflow) |
| Agent Story / proxy | Unchanged; window-mode args merge with existing `$extraArgs` |
| Grid model | Unchanged; no new grid fields or columns |
| Version | Bump from current `2.0.21` → `2.0.22` (patch) when shipping script behavior |

### Acceptance Criteria (measurable)

| ID | Criterion |
|----|-----------|
| AC1 | Profile objects persist `WindowMode` as `default` \| `classic` \| `glass`; missing/invalid normalize to `default` on load and in helpers. |
| AC2 | Add/Edit Profile exposes DropDownList Default / Classic IDE / Agents Window; new profiles default to `default`. |
| AC3 | Start appends `--classic` or `--glass` (never both) when mode is classic/glass; `default` adds neither; applies to all Start arg paths (`--new-window`, `--add`, proxy extras). |
| AC4 | No grid column for WindowMode. |
| AC5 | Unit tests cover normalize, index round-trip, launch-args helper, and Load-Profiles backfill; `.\run-tests.ps1` passes. |
| AC6 | README, AGENTS.md launch contract, CHANGELOG, and app version updated. |

### Out of scope

- Soft profile data reset (`2026-07-23-profile-data-reset-design.md`)
- Remote SSH / remote-cli quirks
- `--chat` standalone chat window
- Writing Cursor settings “Open Agents Window on startup”
- Grid column or Instances/Status coupling for WindowMode
- Agent Story server/UI changes

### Definition of Ready

- Canonical spec at `step-00-profile-window-mode.spec.md` (done).
- ProxyType patterns identified in `cursor-profile-manager.ps1` (done).
- This plan maps every AC → steps + section 5 tests.
- Implementer can start without further product decisions (section 8 defaults apply).

---

## 2. Technical Design & Architecture

### Layer edits (config.json)

| Layer | Path | Change |
|-------|------|--------|
| Manager GUI | `cursor-profile-manager.ps1` | WindowMode helpers, storage, dialog, launch merge, version bump |
| Tests | `tests/` | Pester coverage for helpers + Load-Profiles backfill |
| Docs | `README.md`, `AGENTS.md`, `CHANGELOG.md` | User docs, launch contract, changelog |

**No changes** to Agent Story server/UI, database, or EF/migrations (N/A).

### Storage (`profiles.json` profile object)

Add field alongside existing proxy fields:

```json
"WindowMode": "default"
```

- `Load-Profiles`: if property missing, `Add-Member` `WindowMode = 'default'`; if present, assign normalized value via `Get-ProfileWindowModeFromValue` so invalid strings become `default` (AC1).
- `New-ProfileObject`: add `[AllowEmptyString()][string]$WindowMode = 'default'`; store normalized value.
- `Edit-Profile` / Add handler: persist `WindowMode` from dialog result (same Add-Member-or-assign pattern as `ProxyType`).

### Helpers (place near ProxyType block ~line 1801)

| Function | Contract |
|----------|----------|
| `Get-ProfileWindowModeFromValue` | Input string → `default` \| `classic` \| `glass` (anything else → `default`) |
| `Get-ProfileWindowMode` | Profile → normalized mode (`default` if null/missing) |
| `Get-ProfileWindowModeIndex` | Mode string → `0` / `1` / `2` |
| `Get-ProfileWindowModeFromIndex` | Index → mode (`default` for out-of-range) |
| `Get-CursorWindowModeLaunchArgs` | Mode → `, @()` / `, @('--classic')` / `, @('--glass')` — use unary comma on return so single-element arrays stay arrays (AGENTS.md learning) |

**Index / label map (DropDownList order):**

| Index | Label | Value |
|-------|-------|-------|
| 0 | `Default (Cursor decides)` | `default` |
| 1 | `Classic IDE (--classic)` | `classic` |
| 2 | `Agents Window (--glass)` | `glass` |

### UI (`Show-ProfileDialog`)

- Add label + `ComboBox` `cmbWindowMode` (`DropDownStyle = DropDownList`) after proxy controls.
- Seed items with the three labels above; `SelectedIndex` from `Get-ProfileWindowModeIndex` when editing, else `0`.
- Theme: `$script:UiInputBackColor` / `$script:UiInputForeColor` like `cmbProxyType`.
- Increase `$dlg.Size` height (currently `500×448`) by ~38–48 px so Save/Cancel/hints are not clipped.
- Dialog result hashtable includes `WindowMode = Get-ProfileWindowModeFromIndex -Index $cmbWindowMode.SelectedIndex`.
- Wire Add (`New-ProfileObject ... -WindowMode $result.WindowMode`) and `Edit-Profile` persistence.

### Launch (`Start-CursorProfileInstance`)

After proxy `$extraArgs` is computed (or remains `@()` when not proxied):

```powershell
$windowMode = Get-ProfileWindowMode -Profile $Profile
$windowModeArgs = Get-CursorWindowModeLaunchArgs -WindowMode $windowMode
$extraArgs = @($extraArgs) + @($windowModeArgs)
```

Ensure **all three** argument constructions include `$extraArgs`:

1. Empty `--new-window` then `--add` reuse path
2. Standard `--new-window` [+ project] path
3. Any path that already concatenates proxy extras

Include `windowMode` in launch-log Details for diagnostics.

### Grid (AC4)

- **Do not** add a DataGridView column, Build-GridModel field, or Sync-GridRowToView cell for WindowMode.
- Existing columns stay: Name, UserDataDir, Instances, Status, Proxy, Notes, Actions.

### Invariant checks (`config.json.invariants`)

| Invariant | Plan compliance |
|-----------|-----------------|
| `powershell51Baseline` | No `??`, ternary, `-AsHashtable`, etc. |
| `noHardcodedWindowTitle` | Version bump only via `# App-Version` + `$script:AppVersionId`; do not hardcode title strings |
| `profilesJsonNeverCommitted` | Tests use temp `CURSOR_PROFILES_DIR` only |
| `commitPlanFilesOnlyAtStep8` | This plan artifact is not committed until delivery |

---

## 3. Step-by-Step Plan

### Step A — Domain helpers + storage (AC1)

**Actions**

1. Add `Get-ProfileWindowModeFromValue`, `Get-ProfileWindowMode`, `Get-ProfileWindowModeIndex`, `Get-ProfileWindowModeFromIndex`, `Get-CursorWindowModeLaunchArgs` next to ProxyType helpers.
2. Extend `New-ProfileObject` with `-WindowMode` (default `default`, normalized).
3. In `Load-Profiles`, backfill missing `WindowMode` and normalize invalid existing values.
4. Optionally extend `New-TestProfile` with `-WindowMode` passthrough for tests.

**Files:** `cursor-profile-manager.ps1`, optionally `tests/TestHelpers.ps1`

**Engineering checks**

- `[AllowEmptyString()]` on string params that may be `''`.
- Return arrays with `, @(...)` where a single flag must remain a one-element array.
- Invalid inputs (`''`, `'foo'`, `$null` via FromValue) → `default`.

**Maps to:** AC1 (helpers + load normalize); foundation for AC3/AC5.

---

### Step B — Dialog + persist (AC2)

**Actions**

1. Add `cmbWindowMode` + label in `Show-ProfileDialog`; bump dialog height.
2. Return `WindowMode` from Save.
3. Persist on Add (`New-ProfileObject -WindowMode ...`) and `Edit-Profile` (Add-Member-or-assign).

**Files:** `cursor-profile-manager.ps1`

**Engineering checks**

- DropDownList only (not editable ComboBox).
- New profile path without Existing → index 0 / `default`.
- Theme colors match proxy combo; no layout clip of Save/Cancel.

**Maps to:** AC2.

---

### Step C — Launch merge (AC3)

**Actions**

1. In `Start-CursorProfileInstance`, resolve mode and append `Get-CursorWindowModeLaunchArgs` into `$extraArgs` before both reuse-window and standard launches.
2. Confirm never both flags (helper returns one array only).
3. Log `windowMode` in launch configuration details.

**Files:** `cursor-profile-manager.ps1`

**Engineering checks**

- Works with `$extraArgs` empty (non-proxied) and with proxy Chromium flags present.
- Both `--new-window` and `--add` paths receive the same window-mode args.

**Maps to:** AC3.

---

### Step D — Guard no grid column (AC4)

**Actions**

1. Explicit non-change: leave grid column setup untouched.
2. During implement/review, grep confirm no `WindowMode` / `cmbWindowMode` in grid builders.

**Files:** none (verification only) / review of `cursor-profile-manager.ps1` grid section

**Maps to:** AC4.

---

### Step E — Unit tests (AC5)

**Actions**

1. Add `tests/WindowMode.Tests.ps1` (preferred) covering normalize, index round-trip, launch-args arrays.
2. Extend `tests/Storage.Tests.ps1` with Load-Profiles missing-`WindowMode` backfill (mirror ProxyType test) and optionally invalid-value normalize.
3. Assert `New-ProfileObject` default / explicit `WindowMode`.
4. Run `.\run-tests.ps1` until green.

**Files:** `tests/WindowMode.Tests.ps1` (new), `tests/Storage.Tests.ps1`, optionally `tests/TestHelpers.ps1`

**Maps to:** AC5 (and regression for AC1).

---

### Step F — Docs + version (AC6)

**Actions**

1. **README.md** — Document Window Mode in profile settings / Start behavior; note Cursor 3.x requirement for flags.
2. **AGENTS.md** — Extend Launch contract: Start may append `--classic` or `--glass` from profile `WindowMode`; list helpers in architecture table if helpful.
3. **CHANGELOG.md** — Dated **Added** entry for per-profile Window Mode.
4. Bump `# App-Version:` and `$script:AppVersionId` (`2.0.21` → `2.0.22`).

**Files:** `README.md`, `AGENTS.md`, `CHANGELOG.md`, `cursor-profile-manager.ps1`

**Maps to:** AC6.

---

### Suggested implementation order

```
A (helpers + storage) → E tests (red/green for helpers/load)
  → B (dialog) → C (launch) → D (grid verify) → F (docs/version)
  → full .\run-tests.ps1 → manual smoke (spec §7)
```

**Expected files touched (product):** ≤6 primary paths — `cursor-profile-manager.ps1`, `tests/WindowMode.Tests.ps1`, `tests/Storage.Tests.ps1`, `README.md`, `CHANGELOG.md`, `AGENTS.md` (+ optional `TestHelpers.ps1`).

---

## 4. Permissions, Tenancy & i18n

| Area | Applicability |
|------|----------------|
| RBAC / permissions | N/A — local desktop GUI, no multi-user auth |
| Tenancy isolation | N/A — profiles are local filesystem dirs; no tenant filters |
| i18n | N/A — English UI strings only (`config.frontend.i18n.framework: none`) |

No new permissions, tenant checks, or locale keys.

---

## 5. Test Coverage

Map every AC to concrete Pester cases. Prefer pure helpers over WinForms automation.

| AC | Test file / area | Test case (method name sketch) | Assertion |
|----|------------------|--------------------------------|-----------|
| AC1 | `WindowMode.Tests.ps1` | `Get-ProfileWindowModeFromValue defaults empty/invalid to default` | `''`, `'foo'` → `default` |
| AC1 | `WindowMode.Tests.ps1` | `Get-ProfileWindowModeFromValue accepts classic and glass` | `classic` / `glass` unchanged |
| AC1 | `WindowMode.Tests.ps1` | `Get-ProfileWindowMode defaults missing property` | Profile without property → `default` |
| AC1 | `Storage.Tests.ps1` | `adds missing WindowMode property on load` | Load JSON without field → `WindowMode -eq 'default'` |
| AC1 | `Storage.Tests.ps1` | `normalizes invalid WindowMode on load` (optional but recommended) | `"WindowMode":"nope"` → `default` |
| AC2 | `Storage.Tests.ps1` / `WindowMode.Tests.ps1` | `New-ProfileObject defaults WindowMode to default` | New object `.WindowMode -eq 'default'` |
| AC2 | `WindowMode.Tests.ps1` | `Get-ProfileWindowModeIndex / FromIndex round-trip` | 0↔default, 1↔classic, 2↔glass; bad index → default |
| AC2 | Manual smoke | Add/Edit dialog shows DropDownList; new profile Save stores `default` | Visual + `profiles.json` |
| AC3 | `WindowMode.Tests.ps1` | `Get-CursorWindowModeLaunchArgs default returns empty` | Count 0; no classic/glass |
| AC3 | `WindowMode.Tests.ps1` | `Get-CursorWindowModeLaunchArgs classic returns --classic only` | Exactly `@('--classic')` |
| AC3 | `WindowMode.Tests.ps1` | `Get-CursorWindowModeLaunchArgs glass returns --glass only` | Exactly `@('--glass')` |
| AC3 | Manual smoke | Start with each mode; inspect Cursor command line | Flags match mode; never both |
| AC4 | Review / grep gate | No WindowMode grid column | Grid column list unchanged |
| AC5 | Runner | `.\run-tests.ps1` | Full suite passes |
| AC6 | Review | Docs + version markers | README/AGENTS/CHANGELOG updated; App-Version bumped |

**Verification command:** `powershell -NoProfile -File .\run-tests.ps1` (`verification.backendTest`).

**Manual smoke (from spec):**

1. Default → neither `--classic` nor `--glass` on process command line.
2. Classic → `--classic` present; classic IDE window (Cursor 3.x).
3. Agents Window → `--glass` present; Agents Window (Cursor 3.x).

---

## 6. Invariants (Do Not Violate)

1. **PowerShell 5.1 baseline** — no PS 7-only operators/cmdlets; `#Requires -Version 5.1` remains.
2. **No hardcoded window title** — bump version markers only; titles via `Get-AppWindowTitle`.
3. **Never commit user `profiles.json` / profile data dirs**.
4. **Plan artifacts commit at Step 8 only** (`commitPlanFilesOnlyAtStep8`).
5. **Surgical scope** — mirror ProxyType; do not refactor unrelated launch/proxy/grid code.
6. **No soft reset** in this feature.
7. **No WindowMode grid column**.
8. **Array return discipline** — avoid `return @($one)`; use `return , @($data)` for launch-args helper.
9. **Single-script GUI** — all manager logic stays in `cursor-profile-manager.ps1` (functions before `-FunctionsOnly` guard).

---

## 7. Pre-PR Checklist

- [ ] Layer boundaries respected (Manager GUI + tests + docs only; no Agent Story churn).
- [ ] Domain entities and mappings encapsulated — N/A (no EF); profile JSON field + helpers only.
- [ ] Schema migrations created — N/A; soft backfill in `Load-Profiles` instead.
- [ ] Authorization checks applied — N/A.
- [ ] i18n keys declared — N/A (en-us literals).
- [ ] Test cases cover all ACs (section 5).
- [ ] `Get-CursorWindowModeLaunchArgs` merged into all Start arg paths (AC3).
- [ ] No grid column for WindowMode (AC4).
- [ ] `# App-Version` and `$script:AppVersionId` bumped in sync (AC6).
- [ ] README + AGENTS.md launch contract + CHANGELOG Added entry (AC6).
- [ ] `.\run-tests.ps1` green (AC5).
- [ ] Soft profile reset not introduced.
- [ ] No PS 7-only syntax.

---

## 8. Open Questions

None blocking. Defaults if interview is skipped:

| Topic | Default decision |
|-------|------------------|
| Invalid `WindowMode` on load | Normalize in place to `default` (not only missing-property backfill) |
| Test file layout | New `tests/WindowMode.Tests.ps1` + Storage backfill test |
| Version bump | Patch `2.0.21` → `2.0.22` |
| Dialog height | Increase by one control row (~40 px); keep FixedDialog width 500 |
| Combo enabled state | Always enabled (unlike Proxy type, which depends on RunProxied checkbox) |

If reviewers prefer invalid values left as-is until helper read time only, Load-Profiles can backfill missing only — helpers still normalize for launch/UI (AC1 still satisfied via helpers). Prefer normalize-on-load for cleaner JSON after first open/save.
