# Cursor Profile Manager — Agent Guide

Reference for AI agents working in this repository.

## Purpose

Windows GUI utility to manage and launch **multiple isolated Cursor IDE instances**. Each profile uses its own `--user-data-dir` (Cursor 3.9+) for separate login, extensions, settings, and AI chat history.

**Scope:** GUI only — no CLI launchers, no macOS/Linux scripts, no build step.

## File map

| File | Role |
|------|------|
| `cursor-profile-manager.ps1` | Main app — WinForms GUI; CRUD profiles; launch Cursor; process monitoring; `profiles.json` persistence. |
| `cursor-profile-manager.bat` | Double-click wrapper (hidden PowerShell). |
| `install-desktop-shortcut.ps1` | Desktop `.lnk` to the GUI. |
| `README.md` | User docs — keep in sync with behavior. |
| `CHANGELOG.md` | User-facing history of features added, changed, or removed. |
| `AGENTS.md` | This file — architecture, contracts, PowerShell conventions. |

## Runtime layout (outside repo)

| Path | Contents |
|------|----------|
| `%USERPROFILE%\.cursor-profiles\` | Profile data dirs + `profiles.json` |

Override with `CURSOR_PROFILES_DIR`. Override binary with `CURSOR_BIN`.

## Launch contract

On **Start**, the GUI must invoke:

```text
Cursor.exe --user-data-dir="<absolute-path>" --new-window [project-path]
```

Rules:

- **Absolute paths** for `--user-data-dir` on Windows.
- **No** `--max-memory`, `--reuse-window`, or Cursor `--profile` flag.
- Create profile directory if missing before launch.
- **Multiple instances** of the same profile are allowed — each Start adds another `--new-window`.
- When the profile is **already running** and has a default project folder, launch empty `--new-window` then `--add <project>` (same-folder reuse otherwise).
- Detect `Cursor.exe` at `%LOCALAPPDATA%\Programs\cursor\` and `Programs\Cursor\`, then `cursor` on PATH.

## App architecture (main script)

High-level flow in `cursor-profile-manager.ps1`:

```text
Initialize-SingleInstance (mutex)
  → Load profiles from profiles.json
  → Build WinForms main window + DataGridView
  → GridModel (in-memory state) ← Build-GridModel ← process scan
  → Update-ProfileGrid (diff model; sync view only on change)
  → WMI watchers + 2 s timer → Update-ProfileGrid
```

Key modules inside the script:

| Area | Functions | Notes |
|------|-----------|-------|
| Single instance | `Initialize-SingleInstance`, `Show-ExistingAppWindow` | Named mutex + Win32 foreground |
| Storage | `Load-Profiles`, `Save-Profiles`, `New-ProfileObject` | UTF-8 JSON |
| Process scan | `Get-UserDataDirInstanceCounts`, `Get-ProfileInstanceCount` | CIM `Win32_Process`; count `--type=renderer` per user-data-dir (one window each) |
| Launch | `Find-CursorExecutable`, `Start-CursorProfileInstance` | |
| Grid model | `Build-GridModel`, `Test-GridModelEqual`, `Update-ProfileGrid` | View separated from UI |
| Grid view sync | `Apply-GridModelToView`, `Sync-GridRowToView` | In-place cell updates |
| Notifications | *(removed)* | Was tray balloon on instance count change |
| Process events | `Start-CursorProcessWatchers`, `Request-DeferredGridRefresh` | WMI + debounce timer |

**Do not** call `$grid.Rows.Clear()` on periodic refresh — update the model, diff, then patch rows.

## When editing

1. Update `cursor-profile-manager.ps1` and `README.md` together.
2. Update this file if file roles, launch contract, or architecture change.
3. Do not re-add CLI/bash launchers unless explicitly requested.
4. Do not commit `profiles.json` or profile data from `~/.cursor-profiles/`.

## Documentation and changelog (required)

After **any** agent change that adds, updates, or removes a user-visible feature, behavior, or file role:

1. **Document the behavior** — update `README.md` (and this file if architecture or contracts changed). User docs must match what the app actually does.
2. **Append a changelog entry** — add a dated section to `CHANGELOG.md` under `[Unreleased]` or a new `## YYYY-MM-DD` heading.

Each changelog entry must list:

- **Added** — new features or capabilities
- **Changed** — behavior or UX changes to existing features
- **Removed** — deleted features or dropped behavior
- **Fixed** — bug fixes (optional section; use when relevant)

One entry per logical change (do not batch unrelated work). If a feature is removed, say so explicitly under **Removed** and update README in the same commit/session.

Example:

```markdown
## 2026-06-30

### Added
- Instances column: shows running window count per profile (0, 1, 2, …).

### Changed
- Status refresh uses WMI events + 2 s fallback poll (was 5 s full grid rebuild).

### Removed
- (none)
```

Do not skip the changelog for “small” GUI tweaks — if the user would notice, it gets an entry.

## Smoke test

1. Add a profile → `profiles.json` updated.
2. Start profile → new Cursor window with correct `--user-data-dir`.
3. Start same profile again → Instances column shows `2`; both windows share profile data.
4. Start a second profile on same project → both profiles independent.
5. Close one Cursor window → Instances decrements.
6. Launch manager twice → second launch focuses existing window (no duplicate manager).
7. Status / Instances update within ~2 s of process start or exit.

---

## PowerShell programming recommendations

Conventions used in this repo. Follow them for new code and refactors.

### Version and baseline

- Start every script with `#Requires -Version 5.1`.
- Set `$ErrorActionPreference = 'Stop'` at the top (after `param()`).
- Target **Windows PowerShell 5.1** (desktop `powershell.exe`), not PowerShell 7-only features (`??`, ternary, `-AsHashtable`, etc.) unless the project scope changes.

### Encoding and string literals

- **Save `.ps1` files as ASCII or UTF-8 with BOM.** Windows PowerShell 5.1 reads UTF-8 **without BOM** as the system ANSI code page → mojibake (`â—`, `â¶`).
- Prefer **ASCII-only source** for UI strings that need symbols; build Unicode at runtime:

```powershell
$UiStatusRunning = "$([char]0x25CF) Running"   # ● Running
$UiStartLabel = "Start $([char]0x25B6)"        # Start ▶
```

- JSON persistence: always pair `Get-Content -Encoding UTF8` with `Set-Content -Encoding UTF8` (PS 5.1 UTF8 = BOM, which is fine).

### Functions and structure

- Use **`Verb-Noun` names** approved by `Get-Verb` (`Build-GridModel`, not `Create-GridModel` unless `New-` for object construction).
- Keep **all GUI logic in one script** — no modules or external dependencies.
- Group related functions with `# ---` section headers.
- Prefer **small, named functions** over long event-handler blocks.
- Use `[Parameter(Mandatory)]` on required params; type-hint when it clarifies intent (`[hashtable]`, `[PSCustomObject]`).

### State

- App-wide mutable state: **`$script:VariableName`** (profiles list, grid model, mutex, timers).
- Avoid `$global:` unless truly necessary.
- Separate **data model from view** (`$script:GridModel` vs `DataGridView` rows) and sync only on diff.

### WinForms UI

- Load assemblies once: `System.Windows.Forms`, `System.Drawing`.
- Enable **`DoubleBuffered`** on `DataGridView` via reflection (non-public property).
- Wrap bulk UI changes in **`SuspendLayout()` / `ResumeLayout($true)`**.
- Update cells **in place**; compare values before assigning to reduce flicker.
- Wire **`FormClosing`** (and `try/finally` after `ShowDialog`) to stop timers, dispose WMI watchers, release mutex, hide tray icon.
- WMI / background callbacks that touch UI must **`$form.BeginInvoke([Action]{ ... })`** — never update controls from the WMI thread.

### Native interop

- Use **`Add-Type`** with a here-string for small Win32 needs (foreground window, mutex is managed).
- Guard `Add-Type` with `if (-not ('TypeName' -as [type]))` so re-dot-sourcing does not fail.
- Prefer **`Local\` mutex names** for per-user single-instance (`Local\CursorProfileManager_GUI_v1`).

### Process and WMI

- Query processes with **`Get-CimInstance Win32_Process`** (not deprecated WMI cmdlets).
- Parse `--user-data-dir` from `CommandLine` with a tested regex; normalize paths (trim trailing `\`, lowercase for comparison).
- **Count windows** per dir: `--type=renderer` processes whose user-data-dir matches an active main process for that dir; if main exists but no renderer yet (startup), count as 1.
- WMI event watchers: subscribe with **`.add_EventArrived($handler)`** on the UI thread — **not** `Register-ObjectEvent` (separate runspace; breaks `$form` access).
- Debounce rapid process events with a **one-shot `Timer`** (~500 ms) before rescanning.

### Error handling

- `$ErrorActionPreference = 'Stop'` for the script; use **`try/catch`** around user-data operations that can fail (delete folder, read corrupt JSON).
- On recoverable read errors (bad JSON), **`Write-Warning`** and return empty collection — do not crash the GUI.
- **`MessageBox`** for user-facing errors; avoid throwing from button click handlers unless intentional.

### Performance

- **Early return** when `$script:GridModel` equals newly built model — skip grid paint on idle polls.
- Do not poll faster than needed; 2 s fallback + WMI is enough for status.
- Avoid **`Start-Sleep` in the UI thread** except short debounce / single-instance window lookup retries.

### What to avoid

| Avoid | Use instead |
|-------|-------------|
| `$grid.Rows.Clear()` on timer tick | Model diff + in-place sync |
| Unicode literals in PS 5.1 scripts without BOM | `[char]0x....` or UTF-8 BOM |
| `Register-ObjectEvent` for WinForms + WMI | `.add_EventArrived` + `BeginInvoke` |
| New NuGet modules / PS galleries | WinForms + built-in CIM only |
| PS 7-only syntax | PS 5.1-compatible constructs |
| Committing user `profiles.json` | Document path only |

### Adding a feature (checklist)

1. Does it change launch args or `profiles.json` shape? → Update launch contract + README.
2. Does it affect running detection? → Update `Get-UserDataDirInstanceCounts` / grid model fields.
3. Does it need periodic UI refresh? → Extend `Build-GridModel` + `Test-GridModelEqual`; do not bypass the model.
4. New user-visible strings with symbols? → `[char]` code points or ASCII labels.
5. **Add a `CHANGELOG.md` entry** (Added / Changed / Removed / Fixed).
6. Run smoke test (see above).
