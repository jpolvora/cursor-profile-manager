# Changelog

All notable user-facing changes to Cursor Profile Manager.

Format: dated sections with **Added**, **Changed**, **Removed**, and **Fixed** (when applicable). Newest dates first.

## 2026-07-01

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
