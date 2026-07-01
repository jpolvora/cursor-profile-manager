# Cursor Profile Manager

A Windows GUI to run **multiple Cursor IDE instances** on the same codebase — each with its own user-data directory, login, extensions, settings, and AI chat history.

Tested with **Cursor 3.9+** (uses `--user-data-dir`; the legacy `--max-memory` flag was removed in current builds).

## Overview

Each profile gets its own folder under `%USERPROFILE%\.cursor-profiles\` (override with `CURSOR_PROFILES_DIR`). That lets several Cursor windows open the **same project** at once without sharing account, extensions, or chat history.

The Profile Manager itself is a **single-instance app**: only one manager window runs at a time. Launching it again (shortcut, `.bat`, or script) brings the existing window to the front.

## Benefits

- **Multiple Cursors on one codebase** — parallel work in separate windows
- **Separate accounts** — work vs. personal, or different clients (sign in once per profile)
- **Custom user-data dirs** — pick any folder per profile
- **Parallel AI assistance** — independent agent/chat context per instance
- **Multiple windows per profile** — start the same profile more than once when needed

## Quick start

```powershell
.\cursor-profile-manager.ps1
```

Or double-click `cursor-profile-manager.bat`.

**Desktop shortcut** (Cursor icon, no console window):

```powershell
.\install-desktop-shortcut.ps1
```

Re-run after moving this folder to repair the shortcut.

## Features

| Feature | Description |
|---------|-------------|
| **Profile CRUD** | Add profiles from the toolbar; edit and delete per row in the **Actions** column |
| **Actions column** | Per-row buttons: **Start ▶**, **Focus**, **Close**, **Folder**, **Edit**, **Del** (Start disabled when Cursor is not installed; Focus/Close when Instances = 0) |
| **Double-click row** | Same as **Start** in the Actions column |
| **Status column** | `● Running` / `○ Idle` from live `Cursor.exe` process inspection |
| **Instances column** | Count of running windows per profile (0, 1, 2, …) |
| **Grid columns** | Name, User Data Dir, Instances, Status, Notes, Actions (default project folder is edited in Add/Edit only) |
| **Live updates** | WMI process create/exit events + 2 s fallback poll; grid updates only when data changes |
| **Single instance** | Second launch activates the existing manager window |
| **Persistence** | Profiles saved to `profiles.json` in the profiles directory |
| **Theme** | Light, dark, or **System default** (follows Windows app theme); bottom-toolbar dropdown; saved in `settings.json` |
| **Check for updates** | Footer link (with current `v#.#.#` beside it) compares `App-Version` markers against GitHub `master` and overwrites the install folder in place (`.bat` and Desktop shortcuts keep working) |
| **Cursor dependency** | Footer shows Cursor IDE version and CLI status; **Install Cursor** dialog when missing; Add and row **Start** blocked until IDE is detected |
| **Safe delete** | Optional data-folder removal; blocked while any instance is running |

## Usage

1. Open the Profile Manager.
2. Add a profile (name auto-suggests a folder under `.cursor-profiles\`).
3. Optionally set a default project folder (leave blank to open with no folder on Start).
4. Click **Start ▶** in a row's Actions column (or double-click the row) — Cursor opens with `--user-data-dir` and `--new-window`.
5. Click **Start ▶** again on the same row to open another window for that profile.
6. Use other Actions: **Focus** / **Close** (when running), **Folder**, **Edit**, or **Del**.
7. On first launch, sign in with the account for that profile; settings and extensions persist there.

## Technical details

### How it works

```text
Cursor.exe --user-data-dir "<profile-dir>" --new-window [project-path]
```

Each profile keeps its own extensions, window layout, session history, and login.

This tool uses **separate `--user-data-dir` folders**, not Cursor 3.x's built-in `--profile` flag, so login and on-disk data stay fully isolated.

### Runtime detection

Running profiles are detected by parsing `Cursor.exe` command lines for `--user-data-dir`. The **Instances** count is the number of **`--type=renderer`** processes for that profile (one per window). Electron uses a single main process per profile; counting only that process always showed `1` while running. Helper processes (`gpu`, `utility`, etc.) are excluded.

When a profile is **already running** and has a default project folder, **Start** opens an empty `--new-window` and then `--add`s the folder. Cursor reuses the existing window if you pass the same folder in one launch, even with `--new-window`.

Status refresh uses:

1. **WMI** — `__InstanceCreationEvent` / `__InstanceDeletionEvent` on `Cursor.exe` (debounced ~500 ms)
2. **Fallback timer** — poll every 2 s if an event is missed

The UI grid is driven by an in-memory model; the grid is touched only when that model changes (no full redraw on idle polls).

### Environment variables

| Variable | Description |
|----------|-------------|
| `CURSOR_PROFILES_DIR` | Root for profile folders and `profiles.json` |
| `CURSOR_BIN` | Path to `Cursor.exe` (auto-detected if unset) |

Cursor IDE is auto-detected under `%LOCALAPPDATA%\Programs\cursor\` (or `Cursor\`), then `cursor` on PATH. The footer shows the detected version; the **cursor** CLI is checked on PATH or beside the IDE install. Use **Install Cursor** in the footer if neither is found.

### `profiles.json`

Stored at `<CURSOR_PROFILES_DIR>\profiles.json`:

```json
[
  {
    "Id": "f3b1...-guid",
    "Name": "Work",
    "UserDataDir": "C:\\Users\\you\\.cursor-profiles\\Work",
    "ProjectPath": "L:\\source\\work-app",
    "Notes": "Client account",
    "CreatedAt": "2026-06-30T12:00:00"
  }
]
```

Editable by hand; safe to back up or sync across machines. Read/write uses **UTF-8**.

### `settings.json`

Stored at `<CURSOR_PROFILES_DIR>\settings.json` (manager UI preferences, separate from Cursor profile data):

```json
{
  "Theme": "default"
}
```

| `Theme` value | Behavior |
|---------------|----------|
| `default` | Match Windows **Settings → Personalization → Colors → Choose your mode** (app theme via `AppsUseLightTheme` registry key); updates while the manager is open |
| `light` | Always use the light palette |
| `dark` | Always use the dark palette |

Use the **Theme** dropdown in the toolbar to change this; the choice is saved automatically.

### Updates

Click **Check for updates** in the footer status bar. The manager reads the `# App-Version` marker from your local `cursor-profile-manager.ps1` and from GitHub `master`, then:

| Situation | Result |
|-----------|--------|
| Missing version marker (local or GitHub) | Treated as outdated — update offered |
| GitHub version **greater** than local | Update offered |
| Same version | “No updates”; optional **force reinstall** with confirmation |
| Local version **greater** than GitHub | “No updates”; optional **force reinstall** with confirmation |

On apply, it downloads `cursor-profile-manager.ps1`, `cursor-profile-manager.bat`, and `install-desktop-shortcut.ps1`, replaces them in the folder you launched from, then restarts. Existing `.bat` launchers and Desktop shortcuts keep working.

Current release marker in the main script: `# App-Version: 1.3.5` / `$script:AppVersionId` (also shown in the footer as `v1.3.5`).

## Unit tests

Requires [Pester](https://pester.dev/) 3.x or later (often preinstalled on Windows). From the repo root:

```powershell
.\run-tests.ps1
```

Tests use a temporary profiles directory — your real `~/.cursor-profiles` data is not touched.

### Manual launch (without the GUI)

```powershell
& "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe" `
  --user-data-dir "$env:USERPROFILE\.cursor-profiles\agent-1" `
  --new-window L:\source\my-project
```

## Project files

| File | Purpose |
|------|---------|
| `cursor-profile-manager.ps1` | Main WinForms GUI |
| `cursor-profile-manager.bat` | Hidden PowerShell launcher |
| `install-desktop-shortcut.ps1` | Creates/repairs a Desktop shortcut |
| `run-tests.ps1` | Pester unit test runner |
| `tests/` | Unit tests for core helpers and logic |
| `CHANGELOG.md` | User-facing change history |
| `AGENTS.md` | Guide for AI agents and PowerShell conventions in this repo |

## Notes

- **Windows only** — WinForms GUI; requires **Windows PowerShell 5.1+** (built into Windows).
- Each running profile is a separate Electron process (~500 MB+ RAM).
- Extensions are duplicated per profile on disk.
- Terminal `cursor` always uses the default profile — use this manager for extra instances.

## License

MIT
