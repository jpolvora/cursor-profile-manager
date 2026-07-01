# Changelog

All notable user-facing changes to Cursor Profile Manager.

Format: dated sections with **Added**, **Changed**, **Removed**, and **Fixed** (when applicable). Newest dates first.

## 2026-06-30

### Added

- **Instances column** — shows how many Cursor windows are running per profile (0, 1, 2, …).
- **Multiple windows per profile** — Start / double-click always opens another `--new-window` for the same profile.
- **Tray notifications** — balloon tips when instances start, stop, or the count changes.
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
