# Cursor Profile Manager

A Windows GUI to run **multiple Cursor IDE instances** on the same codebase — each with its own user-data directory, login, extensions, settings, and AI chat history.

Tested with **Cursor 3.9+** (uses `--user-data-dir`; the legacy `--max-memory` flag was removed in current builds).

## Overview

Each profile gets its own folder under `%USERPROFILE%\.cursor-profiles\` (override with `CURSOR_PROFILES_DIR`). That lets several Cursor windows open the **same project** at once without sharing account, extensions, or chat history.

## Benefits

- **Multiple Cursors on one codebase** — parallel work in separate windows
- **Separate accounts** — work vs. personal, or different clients (sign in once per profile)
- **Custom user-data dirs** — pick any folder per profile
- **Parallel AI assistance** — independent agent/chat context per instance

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

- **Add / Edit / Delete** profiles (name, user-data-dir, default project folder, notes)
- **Start ▶** (or double-click a row) opens that profile in a new Cursor window
- **Live status** — `● Running` / `○ Idle`, refreshed every 5s from `Cursor.exe` command lines
- Profiles saved to `profiles.json` in the profiles directory
- Delete optionally removes the profile's data folder (with confirmation); blocked while running

## Usage

1. Open the Profile Manager.
2. Add a profile (name auto-suggests a folder under `.cursor-profiles\`).
3. Optionally set a default project folder.
4. Click **Start ▶** — Cursor opens with `--user-data-dir` and `--new-window`.
5. On first launch, sign in with the account for that profile; settings and extensions persist there.

## Technical details

### How it works

```text
Cursor.exe --user-data-dir "<profile-dir>" --new-window [project-path]
```

Each profile keeps its own extensions, window layout, session history, and login.

This tool uses **separate `--user-data-dir` folders**, not Cursor 3.x's built-in `--profile` flag, so login and on-disk data stay fully isolated.

### Environment variables

| Variable | Description |
|----------|-------------|
| `CURSOR_PROFILES_DIR` | Root for profile folders and `profiles.json` |
| `CURSOR_BIN` | Path to `Cursor.exe` (auto-detected if unset) |

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

Editable by hand; safe to back up or sync across machines.

### Manual launch (without the GUI)

```powershell
& "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe" `
  --user-data-dir "$env:USERPROFILE\.cursor-profiles\agent-1" `
  --new-window L:\source\my-project
```

## Notes

- **Windows only** — WinForms GUI; requires PowerShell 5.1+.
- Each running profile is a separate Electron process (~500MB+ RAM).
- Extensions are duplicated per profile on disk.
- Terminal `cursor` always uses the default profile — use this manager for extra instances.

## License

MIT
