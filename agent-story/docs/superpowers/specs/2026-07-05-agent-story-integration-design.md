# Design Spec: Agent Story Integration

This document outlines the design and integration of the Agent Story MITM proxy and web dashboard with the Cursor Profile Manager (multi-cursor).

## 1. Overview
The goal of this integration is to allow developers to start and stop the Agent Story proxy server and UI dashboard directly from the Cursor Profile Manager GUI. Additionally, users can configure individual Cursor profiles to run "proxied," meaning they will route their AI agent traffic through the Agent Story proxy when launched.

## 2. Requirements & Behavior
1. **Background Processes**:
   * Server: Node.js MITM proxy started from `server/index.js`.
   * UI: React Vite development server started via `npm run dev` in `ui/`.
   * Stored as script-scoped variables: `$script:AgentStoryProxyProcess` and `$script:AgentStoryUiProcess`.
2. **Auto-Stop**:
   * If running, both processes (and all their child processes) must be terminated when the manager is closed.
   * Terminated using `taskkill /F /T /PID <pid>` to clean up child processes (e.g. Node/Vite processes spawned by `npm` or `cmd`).
3. **UI Integration**:
   * Add a `Proxy` checkbox status column to the DataGridView (read-only checkbox representation).
   * Update the Add/Edit Profile Dialog (`Show-ProfileDialog`) to display a checkbox: `Run proxied (Route traffic through Agent Story proxy)`.
   * Add a separator and `Start Agent Story` / `Stop Agent Story` button on the main toolbar, along with a running status indicator:
     * `○ Agent Story: Stopped` (muted text)
     * `● Agent Story: Running` (green text)
4. **Proxied Launch Flow**:
   * When launching a profile:
     * If `RunProxied` is checked on the profile:
       * If the proxy is running: Launch Cursor with `--proxy-server="http://127.0.0.1:8080"` and `--ignore-certificate-errors`.
       * If the proxy is NOT running: Prompt the user to start the proxy, launch unproxied, or cancel.
5. **Path Resolution**:
   * Resolve `agent-story\` relative to the manager install root (`$script:InstallRoot`), or honor `AGENT_STORY_DIR` when set.

## 3. Storage Changes
* The `profiles.json` schema will include `RunProxied` (boolean) on profile objects.

## 4. UI Elements Added
* **Grid**: `Proxy` column (index 4, after `Status`, before `Notes`).
* **Dialog**: Checkbox `chkProxy` at $y = 176$ in `Show-ProfileDialog`.
* **Toolbar**:
  * Separator panel `sepAgentStory` in `$script:ProfileFlow`.
  * Button `$btnAgentStory` in `$script:ProfileFlow`.
  * Label `$lblAgentStoryStatus` in `$script:ProfileFlow`.

## 5. Verification Plan
### Automated Tests
* Add tests in `tests/GridModel.Tests.ps1` to assert `RunProxied` is part of the grid model row comparison.
* Run `.\run-tests.ps1` to verify all tests pass.

### Manual Verification
* Start manager → Click "Add" → Check "Run proxied" → Save profile. Check that `Proxy` column shows the checked state.
* Click "Start Agent Story" → verify Node/npm processes launch and indicator changes to `● Agent Story: Running`.
* Start proxied profile → verify Cursor launches. Check that traffic is captured if interactive.
* Close manager → verify Node/Vite processes are terminated and ports are released.
