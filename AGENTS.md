# Cursor Profile Manager — Agent Guide

Reference for AI agents working in this repository.

## Purpose

Windows GUI utility to manage and launch **multiple isolated Cursor IDE instances**. Each profile uses its own `--user-data-dir` (Cursor 3.9+) for separate login, extensions, settings, and AI chat history.

**Scope:** GUI only — no CLI launchers, no macOS/Linux scripts, no build step.

## Learnings (read before implementing)

Hard-won failures from past sessions. **Read this section before writing or changing code** so the same mistakes are not repeated.

### PowerShell 5.1 types and parameters

| Mistake | Symptom | Do instead |
|---------|---------|------------|
| `New-Object 'System.Collections.Generic.List[uint]'` or passing `List[uint]` to `Add-Type` | `Cannot find type [System.Collections.Generic.List[uint]]` at runtime (e.g. on **Focus**) | Pass **`[int[]]`** to C# interop; cast to `uint` inside the C# method |
| `[Parameter(Mandatory)][string]$HeaderText` with `-HeaderText ''` | App **fails to start** — `Cannot bind argument to parameter 'HeaderText' because it is an empty string` | Use `[AllowEmptyString()][string]$HeaderText = ''` when empty is valid |
| `foreach ($pid in $pids)` | Subtle bugs — `$pid` shadows the automatic **`$PID`** variable | Use `$procId` or another name |
| Generic `List[IntPtr]` in PS 5.1 helpers | May fail depending on environment | Prefer plain **`@()`** arrays and `[int[]]` casts |
| `$arr.ToArray()` on a plain `@()`-built array | `Method invocation failed because [System.Int32] does not contain a method named 'ToArray'` — PowerShell has no `.ToArray()` on `Object[]`; it silently dispatches unresolved member calls to each **element** instead, so the error names the element type, not the array | Regular PS arrays are already arrays — drop `.ToArray()`; use `, $arr` (unary comma) on `return` to stop a single-element array being unwrapped to a scalar |
| `return @($singleItem)` from a function | Callers see a **scalar**, not a one-element array — `.Count` is wrong in tests and callers | Use `return , @($data)` so PowerShell does not unwrap a single-element array on output |

### WinForms layout

| Mistake | Symptom | Do instead |
|---------|---------|------------|
| Manual `Location` / `Update-ToolbarLayout` for many toolbar buttons | Misaligned rows, clipped controls (Start as a thin blue strip) | **`TableLayoutPanel`** + **`FlowLayoutPanel`** with dock/fill; fixed **`Absolute`** column widths for button groups |
| `TableLayoutPanel` column `AutoSize` for a panel of action buttons | Column collapses to ~0 width; buttons clip | Give the actions column a **fixed pixel width** (e.g. 116–310 px for the group) |
| **`Dock = Fill` on toolbar Start (or any accent button) in a table cell** | Button paints as a large blue block over the launch row | **Never** dock-fill primary buttons; use fixed **Size**, **Anchor Right**, in a small host panel |
| `ActionsHost` + manual `Resize` to right-align a `FlowLayoutPanel` | Fragile; easy to get wrong | **`FlowDirection = RightToLeft`** in a fixed-width cell, or dock fill in a sized column |
| `ReadOnly = $true` on the whole `DataGridView` | **Button columns do not click** | Leave the grid editable; set **`ReadOnly = $true`** only on text columns |

### WinForms grid action columns

- Add button columns via **`DataGridViewButtonColumn`** with **`UseColumnTextForButtonValue = $true`**.
- Handle clicks with **`CellContentClick`**, not `CellClick`.
- Skip double-click Start when the click is on a button column (`DataGridViewButtonColumn`).
- For running-only actions (Focus, Close): set **`$cell.ReadOnly = -not $IsRunning`** and muted **`ForeColor`** in `Sync-GridRowToView`.
- Set action cells **`SelectionBackColor`** / **`BackColor`** to the row surface color so selected rows do not paint action buttons solid blue.
- When adding columns, update **`Rows.Add`** arity (text columns + action columns) and keep **`$script:GridActionColumnCount`** in sync if used.

### Win32 interop

- Load **`Initialize-Win32AppFocus`** at **normal startup** — Focus/foreground Win32 APIs are used to focus profile instances.
- Extend the existing guarded `Add-Type` block; do not duplicate Win32 types.

### Verification

- After GUI or startup-path changes, **run `cursor-profile-manager.ps1`** (or parse + launch smoke) — layout bugs often do not show up in static review alone.
- After logic changes, **run `.\run-tests.ps1`** — Pester covers version compare, storage, grid model, theme, process parsing, and update helpers.
- With `$ErrorActionPreference = 'Stop'`, a single parameter-binding error **exits before `ShowDialog`** — user sees “app not starting”.

When a new bug is fixed, **append a row or bullet here** (and add a **Fixed** changelog entry) so the next agent inherits it.

## File map

| File | Role |
|------|------|
| `cursor-profile-manager.ps1` | Main app — WinForms GUI; CRUD profiles; launch Cursor; process monitoring; `profiles.json` persistence. Accepts `-FunctionsOnly` to load functions without starting the GUI (used by unit tests). |
| `cursor-profile-manager.bat` | Double-click wrapper (hidden PowerShell). |
| `install-desktop-shortcut.ps1` | Desktop `.lnk` to the GUI. |
| `run-tests.ps1` | Runs the Pester unit test suite in `tests/`. |
| `tests/` | Pester tests for version compare, storage, grid model, theme, process parsing, and update helpers. |
| `README.md` | User docs — keep in sync with behavior. |
| `CHANGELOG.md` | User-facing history of features added, changed, or removed. |
| `AGENTS.md` | This file — architecture, contracts, PowerShell conventions. |
| `agent-story/` | Embedded Node/React proxy and visualization dashboard codebase. |

## Runtime layout (outside repo)

| Path | Contents |
|------|----------|
| `%USERPROFILE%\.cursor-profiles\` | Profile data dirs + `profiles.json` + `settings.json` + `launch.log` |

Override with `CURSOR_PROFILES_DIR`. Override binary with `CURSOR_BIN`.

## App version ID

The main script carries a release marker used by **Check for updates**, the **window title**, and the footer version label:

```powershell
# App-Version: 2.0.7
$script:AppVersionId = '2.0.7'
$script:AppDisplayName = 'Cursor Profile Manager'
```

**Do not hardcode the window title or footer `v#.#.#` text.** Derive them via helpers (defined near the top of `cursor-profile-manager.ps1`):

| Helper | Returns | Used for |
|--------|---------|----------|
| `Get-AppVersionId` | `$script:AppVersionId` | update check, tests |
| `Get-AppDisplayName` | `$script:AppDisplayName` | title base name |
| `Get-AppVersionLabel` | `v2.0.7` (or `''` when unset) | footer link prefix |
| `Get-AppWindowTitle` | `Cursor Profile Manager v2.0.7` | `$form.Text`, error dialogs |

Rules:

- Keep **both** the `# App-Version:` comment and `$script:AppVersionId` in sync in `cursor-profile-manager.ps1`.
- When bumping the version, update **only** those two markers — the window title and footer label update automatically through the helpers.
- Use `Get-AppWindowTitle` (not a literal string) anywhere the manager window title is needed.
- Use dotted numeric segments (`major.minor.patch`, e.g. `1.2.0`). The updater compares segment by segment as integers.
- **Increment the version** after every improvement session or commit that changes shipped behavior or scripts, so GitHub `master` and local installs can detect newer releases.
- Update check treats a missing marker (local or remote) as **outdated**. When both markers exist, apply an update only if GitHub’s version is **greater**; equal or older GitHub versions can still be **force reinstalled** with confirmation.

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
- **RunProxied profiles:** **ProxyType** `default` (MITM + dashboard, port 8080) or `alternative` (pass-through discovery log, port 8081). Default type appends `--proxy-server`, `--proxy-bypass-list`, and `--ignore-certificate-errors`; sets `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` / `GLOBAL_AGENT_*` / `NODE_TLS_REJECT_UNAUTHORIZED=0`; syncs `http.proxy` in settings and `argv.json`. Alternative type uses localhost-only bypass (Git/npm/MCP traffic is logged as CONNECT), writes NDJSON to `agent-story/server/pass-through-proxy.log`, and runs `npm run analyze-pass-through-log` for host discovery vs default MITM list. User must **fully quit** Cursor before relaunching proxied profiles.
- **Profile context (all launches):** write `<user-data-dir>\cursor-profile-manager.context.json`, set `CURSOR_PROFILE_MANAGER_*` env vars on spawn, register main PID with Agent Story (`POST /api/profile-sessions/register`). The proxy maps client TCP connections → Cursor PID → user-data-dir → project path for capture grouping.

## App architecture (main script)

High-level flow in `cursor-profile-manager.ps1`:

```text
Load profiles from profiles.json
  → Build WinForms main window + DataGridView
  → GridModel (in-memory state) ← Build-GridModel ← process scan
  → Update-ProfileGrid (diff model; sync view only on change)
  → WMI watchers + 2 s timer → Update-ProfileGrid
```

Key modules inside the script:

| Area | Functions | Notes |
|------|-----------|-------|
| Storage | `Load-Profiles`, `Save-Profiles`, `New-ProfileObject`, `Load-AppSettings`, `Save-AppSettings`, app options (`Get-AppLaunchArguments`, `Set-AppAutoStartEnabled`, tray helpers) | UTF-8 JSON; `settings.json` stores theme, minimize-to-tray, and auto-start preferences |
| UI theme | `Get-UiThemePalettes`, `Test-WindowsAppsUseLightTheme`, `Set-UiThemePalette`, `Set-UiThemePreference`, `Apply-UiThemeToMainWindow` | Light/dark palettes; `default` follows Windows `AppsUseLightTheme` |
| In-app update | `Invoke-CheckForAppUpdate`, `Get-AppVersionIdFromScriptContent`, `Compare-AppVersionId`, `Start-DeferredAppUpdate` | Raw GitHub `master` files; version compare via `# App-Version` / `$script:AppVersionId`; deferred copy after exit |
| Process scan | `Get-NormalizedUserDataDirFromCommandLine`, `Get-UserDataDirInstanceCountsFromProcessRecords`, `Get-UserDataDirInstanceCounts`, `Get-ProfileInstanceCount` | CIM `Win32_Process`; count `--type=renderer` per user-data-dir (one window each); parsing helpers are unit-tested with mock process records |
| Launch | `Find-CursorExecutable`, `Find-CursorCliExecutable`, `Get-CursorInstallInfo`, `Test-CursorInstallReady`, `Show-CursorInstallDialog`, `Start-CursorProfileInstance`, `Write-ProfileLaunchLogEntry`, `Get-LastProfileLaunchLogError`, `Show-ProfileLaunchFailure`, `Get-CursorProxyUrl`, `Get-CursorProxyLaunchArgs`, `Get-CursorProxyEnvironmentVariables`, `Update-CursorProfileProxySettings`, `Write-CursorProfileContextMarker`, `Register-CursorProfileWithAgentStory`, `Start-CursorProfileProcess`, `Invoke-ProcessWithEnvironment` | Proxied launches set Chromium flags + Node proxy env + profile `http.proxy`; all launches write profile context marker and register PID with Agent Story; append diagnostics to `launch.log` |
| Focus | `Get-CursorProfileWindowHandles`, `Invoke-FocusCursorProfile` | EnumWindows by profile PIDs; cycles when multiple windows |
| Close | `Invoke-CloseAllCursorProfileInstances` | WM_CLOSE on profile windows, then force-stop remaining PIDs |
| Grid actions | `Add-GridActionColumns`, `Invoke-GridProfileAction`, `Sync-GridActionInstallState`, `Edit-Profile`, `Remove-Profile` | Per-row buttons: Start, Focus, Close, Folder, Edit, Del |
| Grid model | `Build-GridModel`, `Test-GridModelEqual`, `Update-ProfileGrid` | View separated from UI |
| Grid view sync | `Apply-GridModelToView`, `Sync-GridRowToView` | In-place cell updates |
| Notifications | *(removed)* | Was tray balloon on instance count change |
| Process events | `Start-CursorProcessWatchers`, `Request-DeferredGridRefresh` | WMI + debounce timer |
| Agent Story | `Find-AgentStoryRoot`, `Get-AgentStoryDatabasePaths`, `Remove-AgentStoryDatabaseFiles`, `Invoke-AgentStoryDatabaseClean`, `Test-TcpPortInUse`, `Get-AgentStoryBlockedPorts`, `Test-AgentStoryProcessAlive`, `Test-AgentStoryServicePortListening`, `Resolve-AgentStoryRunState`, `Test-AgentStoryAnyRunning`, `Test-AgentStoryProxyRunning`, `Start-AgentStoryProxy`, `Stop-AgentStory`, `Open-AgentStoryDashboard`, `Update-AgentStoryUiState` | Manages backend proxy and React dashboard daemon processes, checks port bindings, cleans the SQLite database, and updates toolbar UI state |

**Do not** call `$grid.Rows.Clear()` on periodic refresh — update the model, diff, then patch rows.

## When editing

0. **Read [Learnings (read before implementing)](#learnings-read-before-implementing)** and [Before implementing](#before-implementing) before writing code.
1. Update `cursor-profile-manager.ps1` and `README.md` together.
2. Update this file if file roles, launch contract, or architecture change.
3. **Bump the app version** in `cursor-profile-manager.ps1` (see [App version ID](#app-version-id)) on every improvement session or commit that changes shipped scripts.
4. Do not re-add CLI/bash launchers unless explicitly requested.
5. Do not commit `profiles.json` or profile data from `~/.cursor-profiles/`.
6. **Add or update unit tests** — see [Unit tests (required)](#unit-tests-required).

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

## Unit tests (required)

The repo uses **Pester 3.x+** (Windows PowerShell 5.1). Run the full suite with:

```powershell
.\run-tests.ps1
```

### Layout

| Path | Role |
|------|------|
| `run-tests.ps1` | Test runner; restores `CURSOR_PROFILES_DIR` after the run |
| `tests/Bootstrap.ps1` | Dot-sources `cursor-profile-manager.ps1 -FunctionsOnly` into each test file’s scope |
| `tests/TestHelpers.ps1` | Shared helpers (`New-TestProfile`, temp profiles dir reset) |
| `tests/*.Tests.ps1` | Describe/It blocks grouped by area (version, storage, grid, theme, process parsing, update) |

Tests use a temp `CURSOR_PROFILES_DIR` — never the user’s real `~/.cursor-profiles`.

### Rules for agents

1. **Every new feature or behavior change** — add tests for the new/changed logic, or extend an existing `*.Tests.ps1` file.
2. **When existing behavior changes** — update affected tests so they match the new contract; do not leave failing tests.
3. **Do not delete tests** unless the code under test was removed (dead code). Prefer updating assertions over removal.
4. **Prefer pure helpers** — extract testable logic (e.g. `Get-NormalizedUserDataDirFromCommandLine`, `Get-UserDataDirInstanceCountsFromProcessRecords`) instead of mocking CIM or WinForms when practical.
5. **Run `.\run-tests.ps1`** before claiming work complete (in addition to the GUI smoke test when UI changed).
6. Keep `-FunctionsOnly` working — all functions must be defined **before** the `if ($FunctionsOnly) { return }` guard at the bottom of the main script.

## Smoke test

1. Add a profile → `profiles.json` updated.
2. Start profile → new Cursor window with correct `--user-data-dir`.
3. Start same profile again → Instances column shows `2`; both windows share profile data.
4. Start a second profile on same project → both profiles independent.
5. Close one Cursor window → Instances decrements.
6. Launch manager twice → two independent manager windows open.
7. Status / Instances update within ~2 s of process start or exit.

---

## Before implementing

Before writing or changing code, **think through the plan** against this repo’s constraints — do not start coding until compatibility is clear.

1. **Identify the PowerShell baseline** — scripts currently require **Windows PowerShell 5.1** (`#Requires -Version 5.1`; desktop `powershell.exe`). Every planned cmdlet, operator, type, and API must work on that baseline.
2. **Check planned code for version-specific features** — common PS 7-only traps: null-coalescing (`??`), ternary (`? :`), `-AsHashtable`, `ForEach-Object -Parallel`, `ConvertFrom-Json -AsHashtable`, pipeline chain operators (`&&`, `||`), and changed default behavior in built-in cmdlets. WinForms and CIM usage here must also remain valid on 5.1.
3. **If 5.1 is not enough** — do not silently use newer syntax. Instead:
   - State **why** the feature needs a higher version.
   - Propose a **minimal** `#Requires` bump (e.g. `7.4`) and whether the project should target `pwsh` instead of `powershell.exe`.
   - List user impact (install step, `.bat` wrapper change, README note) and get explicit approval before raising requirements.
4. **Prefer 5.1-compatible alternatives** when they are equally clear — e.g. `if ($x) { $x } else { $y }` instead of `??`, explicit hashtables instead of `-AsHashtable`.

Default: stay on **5.1** unless the user approves a documented minimum-version upgrade.

## PowerShell programming recommendations

Conventions used in this repo. Follow them for new code and refactors.

### Version and baseline

- Start every script with `#Requires -Version 5.1`.
- Set `$ErrorActionPreference = 'Stop'` at the top (after `param()`).
- Target **Windows PowerShell 5.1** (desktop `powershell.exe`), not PowerShell 7-only features (`??`, ternary, `-AsHashtable`, etc.) unless the project scope changes (see [Before implementing](#before-implementing)).

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

- App-wide mutable state: **`$script:VariableName`** (profiles list, grid model, timers).
- Avoid `$global:` unless truly necessary.
- Separate **data model from view** (`$script:GridModel` vs `DataGridView` rows) and sync only on diff.

### WinForms UI

- Load assemblies once: `System.Windows.Forms`, `System.Drawing`; then call `Application.EnableVisualStyles()` and `SetCompatibleTextRenderingDefault($false)` before creating any controls.
- Enable **`DoubleBuffered`** on `DataGridView` via reflection (non-public property).
- Wrap bulk UI changes in **`SuspendLayout()` / `ResumeLayout($true)`**.
- Update cells **in place**; compare values before assigning to reduce flicker.
- Wire **`FormClosing`** (and cleanup after `ShowDialog`) to stop timers and dispose WMI watchers.
- WMI / background callbacks that touch UI must **`$form.BeginInvoke([Action]{ ... })`** — never update controls from the WMI thread.

### Native interop

- Use **`Add-Type`** with a here-string for small Win32 needs (foreground window, WM_CLOSE).
- Guard `Add-Type` with `if (-not ('TypeName' -as [type]))` so re-dot-sourcing does not fail.

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
- Avoid **`Start-Sleep` in the UI thread** except short debounce delays.

### What to avoid (pitfalls) - Lesson Learned (learnings)

| Avoid | Use instead |
|-------|-------------|
| `$grid.Rows.Clear()` on timer tick | Model diff + in-place sync |
| Unicode literals in PS 5.1 scripts without BOM | `[char]0x....` or UTF-8 BOM |
| `Register-ObjectEvent` for WinForms + WMI | `.add_EventArrived` + `BeginInvoke` |
| New NuGet modules / PS galleries | WinForms + built-in CIM only |
| PS 7-only syntax | PS 5.1-compatible constructs |
| `List[uint]` / mandatory `[string]` params passed `''` | `[int[]]` interop; `[AllowEmptyString()]` on optional empty headers |
| `.ToArray()` on a plain PS array | Drop it — `Object[]` has no `.ToArray()`; use `, $arr` on `return` instead |
| `return @($oneItem)` from a function | Use `return , @($data)` so callers always get an array |
| `$grid.ReadOnly = $true` with button columns | Text columns `ReadOnly`; use `CellContentClick` for buttons |
| Toolbar buttons positioned by hand | `TableLayoutPanel` / `FlowLayoutPanel`; fixed-width action columns |
| **`Dock = Fill` on a primary `Button` inside `TableLayoutPanel`** | Huge blue rectangle; hint row swallowed | Fixed **width + anchor right** in a host panel (see **Start** on profile row) |
| Committing user `profiles.json` | Document path only |

### Adding a feature (checklist)

1. Does it change launch args or `profiles.json` shape? → Update launch contract + README.
2. Does it affect running detection? → Update `Get-UserDataDirInstanceCounts` / grid model fields.
3. Does it need periodic UI refresh? → Extend `Build-GridModel` + `Test-GridModelEqual`; do not bypass the model.
4. New user-visible strings with symbols? → `[char]` code points or ASCII labels.
5. **Add a `CHANGELOG.md` entry** (Added / Changed / Removed / Fixed).
6. **Bump `$script:AppVersionId` and `# App-Version:`** in `cursor-profile-manager.ps1` when shipped script behavior changes. Do **not** edit the window title separately — use `Get-AppWindowTitle`.
7. **Add or update unit tests** in `tests/` and run `.\run-tests.ps1`.
8. Run smoke test (see above).
