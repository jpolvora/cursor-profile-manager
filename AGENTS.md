# Cursor Profile Manager — Agent Guide

Reference for AI agents working in this repository.

## Purpose

Windows GUI utility to manage and launch **multiple isolated Cursor IDE instances**. Each profile uses its own `--user-data-dir` (Cursor 3.9+) for separate login, extensions, settings, and AI chat history.

**Scope:** GUI only — no CLI launchers, no macOS/Linux scripts, no build step.

## File map

| File | Role |
|------|------|
| `cursor-profile-manager.ps1` | Main app — WinForms GUI; CRUD profiles; launch Cursor; `profiles.json` persistence. |
| `cursor-profile-manager.bat` | Double-click wrapper (hidden PowerShell). |
| `install-desktop-shortcut.ps1` | Desktop `.lnk` to the GUI. |
| `README.md` | User docs — keep in sync with behavior. |

## Runtime layout (outside repo)

| Path | Contents |
|------|----------|
| `%USERPROFILE%\.cursor-profiles\` | Profile data dirs + `profiles.json` |

Override with `CURSOR_PROFILES_DIR`. Override binary with `CURSOR_BIN`.

## Launch contract

On start, the GUI must invoke:

```text
Cursor.exe --user-data-dir="<absolute-path>" --new-window [project-path]
```

Rules:

- **Absolute paths** for `--user-data-dir` on Windows.
- **No** `--max-memory`, `--reuse-window`, or Cursor `--profile` flag.
- Create profile directory if missing before launch.
- Detect `Cursor.exe` at `%LOCALAPPDATA%\Programs\cursor\` and `Programs\Cursor\`, then `cursor` on PATH.

## Conventions

- `#Requires -Version 5.1`, `$ErrorActionPreference = 'Stop'`.
- All GUI logic in `cursor-profile-manager.ps1` — WinForms only, no external deps.
- Keep changes minimal; no new dependencies, CI, or tests unless requested.
- Do not commit `profiles.json` or profile data from `~/.cursor-profiles/`.

## When editing

1. Update `cursor-profile-manager.ps1` and `README.md` together.
2. Update this file if file roles or launch contract change.
3. Do not re-add CLI/bash launchers unless explicitly requested.

## Smoke test

1. Add a profile → `profiles.json` updated.
2. Start profile → new Cursor window with correct `--user-data-dir`.
3. Start second profile on same project → both windows independent.
4. Status column shows Running/Idle correctly.
