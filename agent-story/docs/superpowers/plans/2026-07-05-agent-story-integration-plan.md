# Agent Story Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate the Agent Story MITM proxy and web dashboard into the Cursor Profile Manager (multi-cursor) application, enabling running specific profiles proxied and starting/stopping the proxy server dynamically from the GUI.

**Architecture:** Extend the PowerShell WinForms application to manage background node/npm processes representing the proxy and dashboard. Modify the profile model and editor dialog to store/toggle a `RunProxied` boolean, and automatically append Chromium command-line flags on launch when active.

**Tech Stack:** PowerShell 5.1, WinForms, Node.js, npm, Pester 3.x+

## Global Constraints
* Every script must start with `#Requires -Version 5.1`.
* App version `$script:AppVersionId` and `# App-Version:` in `cursor-profile-manager.ps1` must be bumped to `1.3.7`.
* Use dotted numeric segments (`1.3.7`).
* All background/UI callback updates from background threads must use `$form.BeginInvoke`.
* Always use `taskkill /F /T /PID` to terminate the Node/Vite process tree to avoid orphan ports.
* No PowerShell 7 specific operators (null-coalescing `??`, ternary `? :`, etc.).

---

### Task 1: Update Profile Model and storage tests

**Files:**
* Modify: `l:\source\multi-cursor\cursor-profile-manager.ps1:520-535`
* Modify: `l:\source\multi-cursor\tests\TestHelpers.ps1:22-31`
* Modify: `l:\source\multi-cursor\tests\GridModel.Tests.ps1:9-28`

**Interfaces:**
* Consumes: None (base storage helpers)
* Produces: `New-ProfileObject` with `RunProxied` support.

- [ ] **Step 1: Modify `New-ProfileObject` in `cursor-profile-manager.ps1`**
  Add `[bool]$RunProxied = $false` parameter and include it in the returned custom object.
  ```powershell
  function New-ProfileObject {
      param(
          [string]$Name,
          [string]$UserDataDir,
          [string]$ProjectPath,
          [string]$Notes,
          [bool]$RunProxied = $false
      )
      [PSCustomObject]@{
          Id          = [guid]::NewGuid().ToString()
          Name        = $Name
          UserDataDir = $UserDataDir
          ProjectPath = $ProjectPath
          Notes       = $Notes
          RunProxied  = $RunProxied
          CreatedAt   = (Get-Date).ToString('s')
      }
  }
  ```

- [ ] **Step 2: Modify `New-TestProfile` in `tests/TestHelpers.ps1`**
  ```powershell
  function New-TestProfile {
      param(
          [string]$Name = 'test-profile',
          [string]$UserDataDir = 'C:\Test\profile-a',
          [string]$ProjectPath = '',
          [string]$Notes = '',
          [bool]$RunProxied = $false
      )

      return New-ProfileObject -Name $Name -UserDataDir $UserDataDir -ProjectPath $ProjectPath -Notes $Notes -RunProxied $RunProxied
  }
  ```

- [ ] **Step 3: Run existing Pester tests to make sure they pass**
  Run command: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-tests.ps1` in `l:\source\multi-cursor`
  Expected: PASS

- [ ] **Step 4: Commit**
  ```bash
  git add cursor-profile-manager.ps1 tests/TestHelpers.ps1
  git commit -m "feat: add RunProxied parameter to ProfileObject"
  ```

---

### Task 2: Update Profile Dialog (Add/Edit)

**Files:**
* Modify: `l:\source\multi-cursor\cursor-profile-manager.ps1:1772-1970`
* Modify: `l:\source\multi-cursor\cursor-profile-manager.ps1:1560-1577`
* Modify: `l:\source\multi-cursor\cursor-profile-manager.ps1:2471-2485`

**Interfaces:**
* Consumes: `New-ProfileObject` with `RunProxied` support.
* Produces: Interactive "Run proxied" checkbox in `Show-ProfileDialog`, returning it in the dialog results.

- [ ] **Step 1: Increase Dialog height and add checkbox in `Show-ProfileDialog`**
  Change `$dlg.Size` height to `394` (from `360`).
  Add the CheckBox control `$chkProxy` at `$y = 176` and increment following `$y` values by `34` to push down the separator, hint label, and buttons.
  ```powershell
  # Inside Show-ProfileDialog:
  $dlg.Size = New-Object System.Drawing.Size(500, 394)
  
  # After Notes text box setup at line 1890:
  $y += 38
  
  # Run proxied checkbox
  $chkProxy = New-Object System.Windows.Forms.CheckBox
  $chkProxy.Text = 'Run proxied (Route traffic through Agent Story proxy)'
  $chkProxy.Location = New-Object System.Drawing.Point($fieldX, $y)
  $chkProxy.Size = New-Object System.Drawing.Size($fieldWidth, 24)
  $chkProxy.ForeColor = $script:UiTextPrimary
  if ($isEdit) { $chkProxy.Checked = [bool]$Existing.RunProxied }
  $dlg.Controls.Add($chkProxy)
  
  $y += 34  # instead of 42
  
  # Shift subsequent controls down accordingly
  ```
  Ensure it returns `RunProxied = $chkProxy.Checked` in the final custom object.

- [ ] **Step 2: Update `Edit-Profile` to set `RunProxied` on saving**
  Modify the property assignment:
  ```powershell
  $Profile.RunProxied = $result.RunProxied
  ```

- [ ] **Step 3: Update `btnAdd.Add_Click` at the bottom of the script**
  Modify `New-ProfileObject` call to pass `-RunProxied $result.RunProxied`.

- [ ] **Step 4: Commit**
  ```bash
  git add cursor-profile-manager.ps1
  git commit -m "feat: add RunProxied checkbox to Add/Edit Profile Dialog"
  ```

---

### Task 3: Update Grid Columns and Model

**Files:**
* Modify: `l:\source\multi-cursor\cursor-profile-manager.ps1:1976-1992`
* Modify: `l:\source\multi-cursor\cursor-profile-manager.ps1:2012-2023`
* Modify: `l:\source\multi-cursor\cursor-profile-manager.ps1:2042-2112`
* Modify: `l:\source\multi-cursor\cursor-profile-manager.ps1:2138-2139`
* Modify: `l:\source\multi-cursor\cursor-profile-manager.ps1:2406-2425`
* Modify: `l:\source\multi-cursor\tests\GridModel.Tests.ps1`

**Interfaces:**
* Consumes: `profiles.json` records with `RunProxied` attribute.
* Produces: A read-only checkbox column `Proxy` in the grid representing the state of `RunProxied`.

- [ ] **Step 1: Insert Proxy column in DataGridView setup**
  Add the checkbox column in the main window grid setup section:
  ```powershell
  [void]$grid.Columns.Add('Status', 'Status')
  
  $colProxy = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
  $colProxy.Name = 'Proxy'
  $colProxy.HeaderText = 'Proxy'
  $colProxy.Width = 45
  $colProxy.MinimumWidth = 45
  $colProxy.FillWeight = 40
  $colProxy.ReadOnly = $true
  $colProxy.DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleCenter
  [void]$grid.Columns.Add($colProxy)
  
  [void]$grid.Columns.Add('Notes', 'Notes')
  ```
  Set it as ReadOnly:
  ```powershell
  $grid.Columns['Proxy'].ReadOnly = $true
  ```

- [ ] **Step 2: Make empty cell generation dynamic**
  Modify line 2138 inside `Apply-GridModelToView`:
  ```powershell
  $emptyCells = @(1..$grid.Columns.Count | ForEach-Object { '' })
  ```

- [ ] **Step 3: Update `New-GridRowModel` and `Test-GridRowModelEqual`**
  ```powershell
  # In New-GridRowModel:
  RunProxied = [bool]$Profile.RunProxied
  
  # In Test-GridRowModelEqual:
  $A.RunProxied -eq $B.RunProxied
  ```

- [ ] **Step 4: Update `Sync-GridRowToView` to bind cell value**
  ```powershell
  if ($cells['Proxy'].Value -ne $ModelRow.RunProxied) {
      $cells['Proxy'].Value = $ModelRow.RunProxied
  }
  ```

- [ ] **Step 5: Write and run Pester tests in `tests/GridModel.Tests.ps1`**
  Add context tests for `RunProxied` to ensure it is correctly parsed by the grid row model and row equality check:
  ```powershell
  It 'includes RunProxied in row model' {
      $profile = New-TestProfile -Name 'proxied' -RunProxied $true
      $row = New-GridRowModel -Profile $profile -InstanceCount 0
      $row.RunProxied | Should Be $true
  }
  It 'detects RunProxied differences' {
      $profileA = New-TestProfile -Name 'same' -RunProxied $false
      $profileB = New-TestProfile -Name 'same' -RunProxied $true
      $rowA = New-GridRowModel -Profile $profileA -InstanceCount 0
      $rowB = New-GridRowModel -Profile $profileB -InstanceCount 0
      Test-GridRowModelEqual -A $rowA -B $rowB | Should Be $false
  }
  ```
  Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-tests.ps1`
  Expected: PASS

- [ ] **Step 6: Commit**
  ```bash
  git add cursor-profile-manager.ps1 tests/GridModel.Tests.ps1
  git commit -m "feat: add Proxy column to DataGridView and grid model"
  ```

---

### Task 4: Implement Proxy Process Management

**Files:**
* Modify: `l:\source\multi-cursor\cursor-profile-manager.ps1` (new functions and process state fields)
* Modify: `l:\source\multi-cursor\cursor-profile-manager.ps1:2533-2537` (FormClosing event)

**Interfaces:**
* Consumes: Node.js/npm configuration and installation directories.
* Produces: Process handles for starting and terminating the proxy and UI servers, auto-terminated on close.

- [ ] **Step 1: Initialize global script variables**
  Add script variables at the top section:
  ```powershell
  $script:AgentStoryProxyProcess = $null
  $script:AgentStoryUiProcess = $null
  ```

- [ ] **Step 2: Add functions `Find-AgentStoryRoot` and `Ensure-NodeDependencies`**
  Implement root lookup and dependency checking.
  ```powershell
  function Find-AgentStoryRoot {
      if ($env:AGENT_STORY_DIR -and (Test-Path $env:AGENT_STORY_DIR)) {
          return $env:AGENT_STORY_DIR
      }
      $parent = Split-Path $script:InstallRoot -Parent
      if ($parent) {
          $candidate = Join-Path $parent "agent-story"
          if (Test-Path $candidate) {
              return $candidate
          }
      }
      if (Test-Path "agent-story") {
          return (Resolve-Path "agent-story").Path
      }
      if (Test-Path "..\agent-story") {
          return (Resolve-Path "..\agent-story").Path
      }
      return $null
  }
  
  function Ensure-NodeDependencies {
      param(
          [Parameter(Mandatory)][string]$Dir,
          [Parameter(Mandatory)][string]$Name
      )
      $nodeModules = Join-Path $Dir "node_modules"
      if (Test-Path $nodeModules) {
          return $true
      }
      
      $confirm = [System.Windows.Forms.MessageBox]::Show(
          "Dependencies (node_modules) are missing for Agent Story $Name. Would you like to run 'npm install' now? This will open a terminal window.",
          "Missing Dependencies",
          [System.Windows.Forms.MessageBoxButtons]::YesNo,
          [System.Windows.Forms.MessageBoxIcon]::Question
      )
      if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
          return $false
      }
      
      try {
          $psi = New-Object System.Diagnostics.ProcessStartInfo
          $psi.FileName = "cmd.exe"
          $psi.Arguments = "/c echo Installing $Name dependencies... && npm install"
          $psi.WorkingDirectory = $Dir
          $psi.UseShellExecute = $true
          $p = [System.Diagnostics.Process]::Start($psi)
          $p.WaitForExit()
          if ($p.ExitCode -ne 0) {
              [System.Windows.Forms.MessageBox]::Show("npm install failed with exit code $($p.ExitCode).", "Install Failed", "OK", "Error") | Out-Null
              return $false
          }
          return $true
      }
      catch {
          [System.Windows.Forms.MessageBox]::Show("Failed to start npm install: $($_.Exception.Message)", "Error", "OK", "Error") | Out-Null
          return $false
      }
  }
  ```

- [ ] **Step 3: Add functions `Start-AgentStoryProxy`, `Stop-AgentStory`, and `Update-AgentStoryUiState`**
  ```powershell
  function Start-AgentStoryProxy {
      $root = Find-AgentStoryRoot
      if (-not $root) {
          [System.Windows.Forms.MessageBox]::Show(
              "Agent Story directory not found. Please set AGENT_STORY_DIR env variable or place the 'agent-story' folder in the same parent directory as this manager.",
              "Agent Story Not Found",
              "OK",
              "Error"
          ) | Out-Null
          return $false
      }
      
      $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
      $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
      if (-not $nodeCmd -or -not $npmCmd) {
          [System.Windows.Forms.MessageBox]::Show(
              "Node.js and npm are required to run Agent Story. Please install them and make sure they are on your PATH.",
              "Node.js/npm Missing",
              "OK",
              "Error"
          ) | Out-Null
          return $false
      }
      
      $serverDir = Join-Path $root "server"
      $uiDir = Join-Path $root "ui"
      
      if (-not (Ensure-NodeDependencies -Dir $serverDir -Name "Server")) { return $false }
      if (-not (Ensure-NodeDependencies -Dir $uiDir -Name "UI")) { return $false }
      
      try {
          $serverPsi = New-Object System.Diagnostics.ProcessStartInfo
          $serverPsi.FileName = "node"
          $serverPsi.Arguments = "index.js"
          $serverPsi.WorkingDirectory = $serverDir
          $serverPsi.CreateNoWindow = $true
          $serverPsi.UseShellExecute = $false
          $script:AgentStoryProxyProcess = [System.Diagnostics.Process]::Start($serverPsi)
      }
      catch {
          [System.Windows.Forms.MessageBox]::Show("Failed to start Agent Story proxy server: $($_.Exception.Message)", "Error", "OK", "Error") | Out-Null
          return $false
      }
      
      try {
          $uiPsi = New-Object System.Diagnostics.ProcessStartInfo
          $uiPsi.FileName = "cmd.exe"
          $uiPsi.Arguments = "/c npm run dev"
          $uiPsi.WorkingDirectory = $uiDir
          $uiPsi.CreateNoWindow = $true
          $uiPsi.UseShellExecute = $false
          $script:AgentStoryUiProcess = [System.Diagnostics.Process]::Start($uiPsi)
      }
      catch {
          Stop-AgentStory
          [System.Windows.Forms.MessageBox]::Show("Failed to start Agent Story UI server: $($_.Exception.Message)", "Error", "OK", "Error") | Out-Null
          return $false
      }
      
      Update-AgentStoryUiState
      return $true
  }
  
  function Stop-AgentStory {
      if ($script:AgentStoryProxyProcess) {
          try {
              if (-not $script:AgentStoryProxyProcess.HasExited) {
                  Start-Process -FilePath "taskkill.exe" -ArgumentList @("/F", "/T", "/PID", [string]$script:AgentStoryProxyProcess.Id) -WindowStyle Hidden -CreateNoWindow -Wait
              }
          } catch {}
          $script:AgentStoryProxyProcess = $null
      }
      if ($script:AgentStoryUiProcess) {
          try {
              if (-not $script:AgentStoryUiProcess.HasExited) {
                  Start-Process -FilePath "taskkill.exe" -ArgumentList @("/F", "/T", "/PID", [string]$script:AgentStoryUiProcess.Id) -WindowStyle Hidden -CreateNoWindow -Wait
              }
          } catch {}
          $script:AgentStoryUiProcess = $null
      }
      Update-AgentStoryUiState
  }
  
  function Update-AgentStoryUiState {
      if (-not $script:btnAgentStory -or -not $script:lblAgentStoryStatus) { return }
      
      $proxyRunning = $false
      if ($script:AgentStoryProxyProcess) {
          try {
              if (-not $script:AgentStoryProxyProcess.HasExited) {
                  $proxyRunning = $true
              }
          } catch {}
      }
      
      if ($proxyRunning) {
          $script:btnAgentStory.Text = "Stop Agent Story"
          $script:lblAgentStoryStatus.Text = "$([char]0x25CF) Agent Story: Running"
          $script:lblAgentStoryStatus.ForeColor = $script:UiRunningColor
      } else {
          $script:btnAgentStory.Text = "Start Agent Story"
          $script:lblAgentStoryStatus.Text = "$([char]0x25CB) Agent Story: Stopped"
          $script:lblAgentStoryStatus.ForeColor = $script:UiTextMuted
      }
  }
  ```

- [ ] **Step 4: Bind process termination to FormClosing event**
  Add the termination call in `FormClosing`:
  ```powershell
  $form.Add_FormClosing({
      $refreshTimer.Stop()
      $processEventDebounce.Stop()
      Stop-CursorProcessWatchers
      Stop-AgentStory
  })
  ```

- [ ] **Step 5: Run tests**
  Expected: PASS

- [ ] **Step 6: Commit**
  ```bash
  git add cursor-profile-manager.ps1
  git commit -m "feat: implement background process management for Agent Story"
  ```

---

### Task 5: Add Agent Story Control to GUI Toolbar

**Files:**
* Modify: `l:\source\multi-cursor\cursor-profile-manager.ps1:2441-2444` (Main form controls setup)
* Modify: `l:\source\multi-cursor\cursor-profile-manager.ps1:661-665` (Apply-ToolbarTheme)
* Modify: `l:\source\multi-cursor\cursor-profile-manager.ps1:2521-2528` (refreshTimer event)

**Interfaces:**
* Consumes: `Start-AgentStoryProxy` and `Stop-AgentStory` functions.
* Produces: Dynamic interactive button and status text inside the main toolbar `$script:ProfileFlow`.

- [ ] **Step 1: Instantiate controls and add to `$script:ProfileFlow`**
  ```powershell
  # Add after btnRefresh creation:
  $script:sepAgentStory = New-ToolbarFlowSeparator
  $script:btnAgentStory = New-ToolbarButton -Text 'Start Agent Story' -Width 132
  $script:lblAgentStoryStatus = New-Object System.Windows.Forms.Label
  $script:lblAgentStoryStatus.Text = "$([char]0x25CB) Agent Story: Stopped"
  $script:lblAgentStoryStatus.ForeColor = $script:UiTextMuted
  $script:lblAgentStoryStatus.BackColor = $script:UiPanelColor
  $script:lblAgentStoryStatus.AutoSize = $true
  $script:lblAgentStoryStatus.Margin = New-Object System.Windows.Forms.Padding 0, 6, 8, 0
  $script:lblAgentStoryStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
  
  $script:ProfileFlow.Controls.AddRange(@($btnAdd, $btnRefresh, $script:sepAgentStory, $script:btnAgentStory, $script:lblAgentStoryStatus))
  ```

- [ ] **Step 2: Bind theme styles in `Apply-ToolbarTheme`**
  ```powershell
  if ($script:btnAgentStory) {
      Update-ToolbarButtonTheme -Button $script:btnAgentStory
  }
  if ($script:lblAgentStoryStatus) {
      $script:lblAgentStoryStatus.ForeColor = if ($script:AgentStoryProxyProcess -and -not $script:AgentStoryProxyProcess.HasExited) { $script:UiRunningColor } else { $script:UiTextMuted }
      $script:lblAgentStoryStatus.BackColor = $script:UiPanelColor
  }
  if ($script:sepAgentStory) {
      $script:sepAgentStory.BackColor = $script:UiBorderColor
  }
  ```

- [ ] **Step 3: Bind button Click event**
  Add after Refresh Click handler setup:
  ```powershell
  $script:btnAgentStory.Add_Click({
      $proxyRunning = $false
      if ($script:AgentStoryProxyProcess) {
          try {
              if (-not $script:AgentStoryProxyProcess.HasExited) {
                  $proxyRunning = $true
              }
          } catch {}
      }
      
      if ($proxyRunning) {
          Stop-AgentStory
      } else {
          [void](Start-AgentStoryProxy)
      }
  })
  ```

- [ ] **Step 4: Update refresh timer Tick event to keep status indicator updated**
  ```powershell
  $refreshTimer.Add_Tick({
      if (Test-UiSystemThemeChanged) {
          Set-UiThemePreference -Preference $script:UiThemePreference
      }
      Update-ProfileGrid
      Update-AgentStoryUiState
  })
  ```

- [ ] **Step 5: Run tests**
  Expected: PASS

- [ ] **Step 6: Commit**
  ```bash
  git add cursor-profile-manager.ps1
  git commit -m "feat: add Agent Story start/stop button and status indicator to toolbar"
  ```

---

### Task 6: Integrate Proxied Launching inside Cursor Launcher

**Files:**
* Modify: `l:\source\multi-cursor\cursor-profile-manager.ps1:1718-1766`

**Interfaces:**
* Consumes: `Profile.RunProxied` configuration and proxy running status.
* Produces: Launches Cursor instances with MITM proxy CLI arguments when proxied mode is enabled and active.

- [ ] **Step 1: Modify `Start-CursorProfileInstance`**
  Extract extra args building:
  ```powershell
  $extraArgs = @()
  if ($Profile.RunProxied) {
      $proxyRunning = $false
      if ($script:AgentStoryProxyProcess) {
          try {
              if (-not $script:AgentStoryProxyProcess.HasExited) {
                  $proxyRunning = $true
              }
          } catch {}
      }
      
      if (-not $proxyRunning) {
          $startProxy = [System.Windows.Forms.MessageBox]::Show(
              "This profile is configured to run proxied, but the Agent Story proxy is not running.`n`nWould you like to start the Agent Story proxy now?",
              "Agent Story Proxy Not Running",
              [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
              [System.Windows.Forms.MessageBoxIcon]::Question
          )
          
          if ($startProxy -eq [System.Windows.Forms.DialogResult]::Yes) {
              $started = Start-AgentStoryProxy
              if ($started) {
                  $proxyRunning = $true
              } else {
                  return
              }
          }
          elseif ($startProxy -eq [System.Windows.Forms.DialogResult]::No) {
              $proxyRunning = $false
          }
          else {
              return
          }
      }
      
      if ($proxyRunning) {
          $extraArgs += '--proxy-server=http://127.0.0.1:8080'
          $extraArgs += '--ignore-certificate-errors'
      }
  }
  ```
  Append `$extraArgs` to `$argList` inside both starting branches:
  ```powershell
  # Reuse branch:
  if ($runningCount -gt 0 -and $projectExists) {
      Start-Process -FilePath $cursor -ArgumentList (@("--user-data-dir=$($Profile.UserDataDir)", '--new-window') + $extraArgs)
      Start-Sleep -Milliseconds 800
      Start-Process -FilePath $cursor -ArgumentList @("--user-data-dir=$($Profile.UserDataDir)", '--add', $Profile.ProjectPath)
      return
  }
  
  # Standard launch branch:
  $argList = @("--user-data-dir=$($Profile.UserDataDir)", '--new-window') + $extraArgs
  if ($projectExists) {
      $argList += $Profile.ProjectPath
  }
  Start-Process -FilePath $cursor -ArgumentList $argList
  ```

- [ ] **Step 2: Bump app version in comments and code**
  Bump `# App-Version: 1.3.7` and `$script:AppVersionId = '1.3.7'` in `cursor-profile-manager.ps1`.

- [ ] **Step 3: Run Pester tests**
  Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-tests.ps1`
  Expected: PASS

- [ ] **Step 4: Commit**
  ```bash
  git add cursor-profile-manager.ps1
  git commit -m "feat: append MITM proxy arguments on launch if profile is proxied"
  ```
