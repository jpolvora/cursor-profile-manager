# Changelog

All notable user-facing changes to Cursor Profile Manager.

Format: dated sections with **Added**, **Changed**, **Removed**, and **Fixed** (when applicable). Newest dates first.

## 2.0.10

### Added

- **Exit confirmation** — closing the manager while the Agent Story proxy is running shows a confirmation dialog before stopping the proxy and dashboard.
- **Minimize to tray** — optional toolbar setting hides the window in the notification area when minimized or closed; double-click the tray icon or choose **Show** to restore.
- **Start with Windows** — optional toolbar setting registers the manager in the current user's Windows startup programs (`HKCU\...\Run`).

### Changed

- Release marker bumped to **2.0.10** (`# App-Version` / `$script:AppVersionId`).

## 2.0.9

### Fixed

- **Agent Story live log display** — dashboard API reads no longer block behind proxy capture writes (separate SQLite read connection); streaming requests appear in the grid as soon as the first chunk arrives instead of only after the IDE closes; the grid keeps showing existing rows while refreshing instead of staying on the loading spinner during heavy traffic.
- **Start Profile launch error** — resolved a null reference error ("You cannot call a method on a null-valued expression") in `Get-ProfileInstanceCount` that occurred when registering running proxied profiles.
- **Diagnostics cleanup** — reverted temporary test hooks and startup/launch file logging intercepts.

## 2.0.8

### Fixed

- **Profile Start launch error** — fixed a crash when the in-memory profiles list was nested (e.g. `@(@($p1,$p2))`), which made **Start** pass multiple profiles into launch and fail with `Cannot bind argument to parameter 'Path' because it is an empty string` on an empty optional project folder. Profile lookups and grid iteration now flatten the list; empty/whitespace project paths are ignored safely; launch errors show a **Launch Error** dialog instead of an unhandled PowerShell exception.
- **Launch arguments** — `--user-data-dir` is quoted again (`--user-data-dir="<path>"`) so paths with spaces launch correctly.

## 2.0.7

### Fixed

- **Profile launch registration** — `--add` follow-up launches no longer overwrite the main-process PID in the context marker and Agent Story registry; pre-launch marker writes with a null PID were removed.
- **Stale PID registry** — re-registering a profile removes the previous main-process mapping so recycled Windows PIDs cannot point at the wrong profile.
- **Proxy settings safety** — `settings.json` is not rewritten when the file is not valid JSON (avoids destroying comment-heavy VS Code settings).
- **Agent Story grid** — scroll position resets when filters or search change.

### Changed

- Release marker bumped to **2.0.7** (`# App-Version` / `$script:AppVersionId`).

## 2.0.6

### Fixed

- **Profile grouping** — PowerShell port-map script used invalid syntax (`$out = @{} Get-NetTCPConnection`), so PID→profile resolution failed for almost all captures; profile context now always wins over bogus inferred paths (`workbench`, `p:`); Agent Story auto-loads profile markers on startup; running proxied profiles re-register when Agent Story starts.

### Changed

- Release marker bumped to **2.0.6** (`# App-Version` / `$script:AppVersionId`).

## 2.0.5

### Fixed

- **Profile grouping (Unassigned)** — marker files written by PowerShell had a UTF-8 BOM that broke JSON parsing; Agent Story now strips BOM, writes markers without BOM, falls back to profile name/user-data-dir when no project folder is set, caches client-port→PID lookups, and uses a single-session fallback when only one profile is registered.

### Changed

- Release marker bumped to **2.0.5** (`# App-Version` / `$script:AppVersionId`).

## 2.0.4

### Added

- **Profile context for Agent Story** — on Start, the manager writes `cursor-profile-manager.context.json` into the profile's user-data dir, sets `CURSOR_PROFILE_MANAGER_*` env vars, registers the main process with Agent Story (`POST /api/profile-sessions/register`), and the proxy resolves the client PID to that profile so captures use the configured **project path** instead of **Unassigned**.

### Changed

- Release marker bumped to **2.0.4** (`# App-Version` / `$script:AppVersionId`).

## 2.0.3

### Fixed

- **Proxied agent traffic** — proxied profile launches now also set `HTTP_PROXY` / `HTTPS_PROXY`, `NODE_TLS_REJECT_UNAUTHORIZED=0`, and the profile's `User/settings.json` `http.proxy` / `http.proxyStrictSSL` entries so Cursor's Node agent subprocesses (e.g. `agent.api5.cursor.sh`) route through Agent Story, not just Chromium telemetry.

### Changed

- Release marker bumped to **2.0.3** (`# App-Version` / `$script:AppVersionId`).

## 2.0.2

### Added

- **Open dashboard** link on the toolbar — appears when the Agent Story UI is listening on port 5173; opens `http://localhost:5173/` in your default browser (`AGENT_STORY_UI_URL` overrides the URL).

### Fixed

- **Agent Story MITM proxy IPv4 bind** — the proxy now listens on `127.0.0.1:8080` instead of IPv6-only `[::1]:8080`, so Cursor instances launched with `--proxy-server=http://127.0.0.1:8080` can connect and capture traffic.

## 2.0.1

### Changed

- **Agent Story toolbar toggle** — the toolbar button detects running Agent Story via process handles **and** listening ports (8080, 3001, 5173), so it shows **Stop Agent Story** for orphaned or externally started instances and stops them on click. Status label updates every 2 s and on launch.

## 2.0.0

### Removed

- **Single-instance lock** — multiple Profile Manager windows may run at once; mutex, legacy title matching, and stale-instance recovery removed.

### Changed

- Release marker set to **2.0.0** (`# App-Version` / `$script:AppVersionId`).

## 2026-07-05 (9)

### Fixed

- **`B:/` drive not found on launch** — usually a Desktop shortcut or working directory still pointing at an old drive after the repo moved. The `.bat` launcher now `cd`s to its own folder first; startup validates install/profiles drives and shows a clear error; re-run `install-desktop-shortcut.ps1` to refresh the shortcut path and versioned name.

- Release marker bumped to **1.3.15** (`# App-Version` / `$script:AppVersionId`).

## 2026-07-05 (8)

### Fixed

- **Launch appears to do nothing** — single-instance focus now tries both the versioned title and the legacy `Cursor Profile Manager` title (pre-v1.3.12). If another copy holds the lock but no window is found, a warning dialog is shown instead of exiting silently.

- Release marker bumped to **1.3.14** (`# App-Version` / `$script:AppVersionId`).

## 2026-07-05 (7)

### Changed

- **Window title / version** — added `Get-AppVersionId`, `Get-AppVersionLabel`, `Get-AppDisplayName`, and `Get-AppWindowTitle` so the title bar and footer always derive from `$script:AppVersionId`; bump the version markers only, never a separate title string.

- Release marker bumped to **1.3.13** (`# App-Version` / `$script:AppVersionId`).

## 2026-07-05 (6)

### Changed

- Main window title now includes the release version (e.g. **Cursor Profile Manager v1.3.12**) so it is easy to tell apart from a Cursor IDE window editing this repo.

- Release marker bumped to **1.3.12** (`# App-Version` / `$script:AppVersionId`).

## 2026-07-05 (5)

### Fixed

- **Timer crash (`PipelineStoppedException`)** — refresh and debounce timer handlers now run inside a safe wrapper that catches pipeline-stop and other errors instead of crashing the GUI. Shutdown sets a flag so in-flight ticks skip grid/port updates. Port-listener parsing no longer reuses `$matches` (conflicts with the `-match` automatic `$Matches` variable).

- Release marker bumped to **1.3.11** (`# App-Version` / `$script:AppVersionId`).

## 2026-07-05 (4)

### Fixed

- **Silent startup failure** — if a prior instance crashed while holding the single-instance lock, a new launch now recovers instead of exiting with no window. Startup errors also show a message box (and the `.bat` wrapper reports failure).
- Release marker bumped to **1.3.10** (`# App-Version` / `$script:AppVersionId`).

## 2026-07-05 (3)

### Fixed

- **Start Agent Story** — pre-flight port checks, post-start health validation, and clearer error dialogs when ports are busy or processes exit early.
- **Agent Story cleanup** — stopping Agent Story now also releases listeners on ports 8080, 3001, and 5173 (clears orphaned Node/Vite processes from prior runs).
- **Health check** — service detection uses listening-process lookup instead of a loopback bind test (fixes false failures when the API binds on `0.0.0.0:3001`).
- **Proxied relaunch** — `--add` project-folder launches now include proxy flags when the profile is configured as proxied.
- **Agent Story server** — API and proxy start independently with explicit bind errors; port conflicts exit cleanly.

### Changed

- Agent Story UI is started via `node …/vite.js --port 5173 --strictPort` for reliable process tracking and a fixed dashboard port.
- Running status shows dashboard URL: `Running (localhost:5173)`; partial startup shows `Partial`.
- Release marker bumped to **1.3.9** (`# App-Version` / `$script:AppVersionId`).

## 2026-07-05 (2)

### Fixed

- **Agent Story path** — `Find-AgentStoryRoot` now resolves `agent-story\` under the manager install folder instead of a sibling directory at the parent path (e.g. `L:\source\agent-story`).

### Changed

- Release marker bumped to **1.3.8** (`# App-Version` / `$script:AppVersionId`).

## 2026-07-05

### Added

- **Agent Story MITM Proxy Integration** — Start and stop the Agent Story proxy and Vite UI server directly from the manager toolbar.
- **Run Proxied profile option** — Added a `Proxy` checkbox column to the profiles grid and a `Run proxied` option to the Add/Edit Profile Dialog.
- **Auto-stop on close** — Background Node/Vite processes are automatically terminated on window close using process-tree termination (`taskkill`).
- **Prompt to start proxy** — Launching a proxied profile when the proxy is stopped prompts the user to start the proxy, launch unproxied, or abort.

### Changed

- Release marker bumped to **1.3.7** (`# App-Version` / `$script:AppVersionId`).

## 2026-07-02

### Added

- **README screenshots** — `screenshots/` folder with main window, Add Profile dialog, and Check for updates dialog.

## 2026-07-01 (4)

### Changed

- Release marker bumped to **1.3.6** (`# App-Version` / `$script:AppVersionId`).

## 2026-07-01 (3)

### Added

- **Unit tests** — Pester suite in `tests/` covering version compare/update status, profile/settings storage, grid model, UI theme helpers, Cursor command-line parsing, and update staging. Run with `.\run-tests.ps1` (requires Pester 3.x+).
- **`-FunctionsOnly` switch** — dot-sources the main script without launching the GUI (used by tests).

### Changed

- **Process parsing** — extracted `Get-NormalizedUserDataDirFromCommandLine` and `Get-UserDataDirInstanceCountsFromProcessRecords` for testable window counting.
- **Grid model functions** — moved above the GUI entry point so `-FunctionsOnly` loads all helpers.

### Fixed

- **`Load-Profiles`** — single-profile `profiles.json` files now return a one-element array (`return , @($data)`) instead of unwrapping to a scalar.

## 2026-07-01 (2)

### Fixed

- **Check for updates** — `Compare-AppVersionId` threw `Method invocation failed because [System.Int32] does not contain a method named 'ToArray'.` on every update check. Regular PowerShell arrays (`Object[]`) have no `.ToArray()` method; when a member call isn't found on the array, PowerShell dispatches it to each element instead, which is where the `System.Int32` in the error message came from. Removed the invalid `.ToArray()` call and return the version-number array with the unary comma operator (`, $numbers`) so a single-segment version isn't unwrapped to a scalar on return.

## 2026-07-01

### Fixed

- **C# interop** — changed `List<IntPtr>` to `IntPtr[]` in window focus helpers to fix binding errors on older PowerShell 5.1 environments.
- **Add/Edit dialog** — fixed an issue where validation would run after the dialog closed, causing data loss if the profile name was left empty.
- **Launch arguments** — updated the `--user-data-dir` argument to strictly use the format `--user-data-dir="<path>"` to prevent path parsing issues.
- **Storage** — wrapped profile and settings saves in `try/catch` blocks to prevent the app from crashing if the configuration files are locked or unwritable.

### Changed

- **Start** — moved from the toolbar to the first button in each row's **Actions** column (toolbar **Start** removed).

### Removed

- **Toolbar Start button** — launch a profile via **Start ▶** in the grid Actions column or double-click the row.

### Fixed

- **Toolbar separator** — removed the internal row divider that rendered as a broken dashed line between the profile and theme rows.

### Added

- **Cursor install check** — footer shows installed Cursor IDE version and CLI status; when missing, **Install Cursor** opens a setup dialog (download link, PATH CLI steps, **Check again**). Add requires Cursor IDE; row **Start** and Add disable when IDE is not found.

### Fixed

- **Toolbar Start button** — no longer renders as a large blue block (`Dock = Fill` removed; Start sits on the profile row with fixed size).
- **Actions column** — smaller buttons (8 pt font, narrower columns); selected-row highlight no longer floods action cells blue.

### Fixed

- **Startup crash** — manager failed to open after the Actions column was added because blank action column headers were rejected by PowerShell parameter validation.

### Added

- **Actions column** — per-row grid buttons (Focus, Close, Folder, Edit, Delete) replace toolbar actions for individual profiles; Focus/Close are enabled only when Instances > 0.
- **Focus** — brings an existing Cursor window for a profile to the foreground; cycles when multiple windows are open (grid Actions button).
- **Close all** — closes every Cursor window for a profile with confirmation; force-terminates remaining processes after graceful close (grid Actions button).
- **Check for updates** — footer link compares `App-Version` markers against GitHub `master`, downloads newer scripts, overwrites the launch folder in place, then restarts (shortcuts unchanged).
- **Folder button** — opens a profile's user-data-dir in File Explorer (grid Actions button).
- **GUI themes** — light and dark palettes plus **System default** (follows Windows app light/dark via `AppsUseLightTheme`); toolbar **Theme** dropdown; preference saved to `settings.json`.

### Changed

- **AGENTS.md** — added **Learnings (read before implementing)** section so agents review past PS 5.1 / WinForms pitfalls before coding.
- **Toolbar** — profile row keeps Add and Refresh only; launch row keeps Theme and Start.
- **Toolbar layout** — docked two-row toolbar with section label, grouped profile actions, separator, contextual hints, and Start on the launch row.

### Removed

- **Toolbar profile actions** — Edit, Delete, Folder, Focus, and Close all removed from the toolbar (use per-row Actions column instead).

### Fixed

- **Focus on Windows PowerShell 5.1** — no longer throws when resolving `List[uint]` during window lookup (uses `int[]` interop instead).

### Changed

- **Footer version label** — current app version shown beside **Check for updates** (e.g. `v1.2.9`).
- **Check for updates** — uses `# App-Version` / `$script:AppVersionId` (missing marker = outdated; update when GitHub is greater; force reinstall with confirmation when not newer).
- **Grid columns** — order is now Name, User Data Dir, Instances, Status, Notes; Project column removed from the grid (still editable in Add/Edit).

### Removed

- **Tray notifications** — balloon tips on instance start/stop/count change (removed with the buggy notification loop).

### Changed

- **GUI refresh** — Segoe UI theme, docked layout, styled grid and toolbar, accent **Start** button, Cursor icon, and polished Add/Edit dialog.
- **Add/Edit profile dialog** — project folder field shows optional label and placeholder hint when empty.
- **Grid double-click** — starts the double-clicked profile row (uses row index, not prior selection).

### Fixed

- **WinForms visual styles** — enable OS-native control rendering on startup (avoids flat 90s fallback).
- **Multiple windows per profile** — when a profile already has a window open, Start opens a new window instead of focusing the existing one; repeat launches with a default project use `--new-window` then `--add` (Cursor reuses the window if the same folder is passed in one command).
- **Instances count** — counts `--type=renderer` windows per profile (was capped at 1 because only the main Electron process was counted).
- **Instances count (subprocess noise)** — no longer counts gpu/utility helpers from the earlier over-counting fix.
- **Refresh after Start** — deferred refresh only resets the debounce timer instead of forcing an immediate rescan during the process spawn burst.

## 2026-06-30

### Added

- **Instances column** — shows how many Cursor windows are running per profile (0, 1, 2, …).
- **Multiple windows per profile** — Start / double-click always opens another `--new-window` for the same profile.
- **Tray notifications** — balloon tips when instances start, stop, or the count changes. *(Removed 2026-07-01.)*
- **Single-instance manager** — only one Profile Manager window; a second launch brings the existing window to the front.
- **In-memory grid model** — status data is kept separate from the DataGridView; the UI updates only when the model changes.
- **`CHANGELOG.md`** — user-facing change history (this file).
- **`AGENTS.md`** — agent guide with architecture notes and PowerShell conventions.

### Changed

- **Status refresh** — WMI process create/exit events (debounced ~500 ms) plus 2 s fallback poll (was 5 s full grid rebuild).
- **Grid updates** — in-place cell updates with double-buffering; no full grid clear on refresh (reduces flicker).
- **Delete guard** — blocks profile delete while any instance is running; message includes instance count.
- **`profiles.json` I/O** — reads with explicit UTF-8 encoding.
- **UI symbols** — status/start icons built via `[char]` code points (fixes mojibake on Windows PowerShell 5.1).
- **README** — expanded features, runtime detection, and project file list.

### Removed

- Cross-platform CLI launchers (batch/shell/PowerShell scripts for Cursor profiles outside the GUI scope).

### Fixed

- **Encoding** — Status column, Start button, and profile text no longer show garbled characters (`â—`, `â¶`, etc.) on Windows PowerShell 5.1.
