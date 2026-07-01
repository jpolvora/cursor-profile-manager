#Requires -Version 5.1
<#
.SYNOPSIS
    GUI manager for isolated Cursor IDE profiles (Cursor 3.x).

.DESCRIPTION
    Lets you add, edit, delete and start named Cursor profiles. Each profile
    runs as its own --user-data-dir, so it has its own login/account,
    extensions, workspace settings (theme, font, etc.) and AI chat history,
    fully isolated from other profiles. Multiple profiles can run at once.

.EXAMPLE
    .\cursor-profile-manager.ps1
#>
param()

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Build UI symbols via code points so the script stays ASCII-safe under Windows PowerShell 5.1.
$UiStatusRunning = "$([char]0x25CF) Running"
$UiStatusIdle = "$([char]0x25CB) Idle"
$UiStartLabel = "Start $([char]0x25B6)"

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

$ProfilesRoot = if ($env:CURSOR_PROFILES_DIR) { $env:CURSOR_PROFILES_DIR } else { Join-Path $env:USERPROFILE '.cursor-profiles' }
$ConfigPath = Join-Path $ProfilesRoot 'profiles.json'

function Ensure-ProfilesRoot {
    if (-not (Test-Path $ProfilesRoot)) {
        New-Item -ItemType Directory -Path $ProfilesRoot -Force | Out-Null
    }
}

function Load-Profiles {
    Ensure-ProfilesRoot
    if (-not (Test-Path $ConfigPath)) {
        return @()
    }
    try {
        $raw = Get-Content -Raw -Path $ConfigPath -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $data = $raw | ConvertFrom-Json
        if ($null -eq $data) { return @() }
        return @($data)
    }
    catch {
        Write-Warning "Failed to read profiles.json: $($_.Exception.Message)"
        return @()
    }
}

function Save-Profiles {
    param([Parameter(Mandatory)][array]$Profiles)
    Ensure-ProfilesRoot
    $Profiles | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigPath -Encoding UTF8
}

function New-ProfileObject {
    param(
        [string]$Name,
        [string]$UserDataDir,
        [string]$ProjectPath,
        [string]$Notes
    )
    [PSCustomObject]@{
        Id          = [guid]::NewGuid().ToString()
        Name        = $Name
        UserDataDir = $UserDataDir
        ProjectPath = $ProjectPath
        Notes       = $Notes
        CreatedAt   = (Get-Date).ToString('s')
    }
}

# ---------------------------------------------------------------------------
# Cursor process helpers
# ---------------------------------------------------------------------------

function Find-CursorExecutable {
    if ($env:CURSOR_BIN -and (Test-Path $env:CURSOR_BIN)) {
        return $env:CURSOR_BIN
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\cursor\Cursor.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Cursor\Cursor.exe')
    )

    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }

    $cmd = Get-Command cursor -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    return $null
}

function Get-RunningUserDataDirs {
    # Returns a set of user-data-dir paths currently running, normalized (lowercase, no trailing slash)
    $dirs = New-Object 'System.Collections.Generic.HashSet[string]'
    $procs = Get-CimInstance Win32_Process -Filter "name='Cursor.exe'" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        $cmd = $p.CommandLine
        if ($cmd -and $cmd -match '--user-data-dir[= ]"?([^"]+?)"?(\s--|\s*$)') {
            $dir = $matches[1].TrimEnd('\', '/')
            [void]$dirs.Add($dir.ToLowerInvariant())
        }
    }
    return $dirs
}

function Test-ProfileRunning {
    param([string]$UserDataDir, [System.Collections.Generic.HashSet[string]]$RunningDirs)
    if (-not $UserDataDir) { return $false }
    $norm = $UserDataDir.TrimEnd('\', '/').ToLowerInvariant()
    return $RunningDirs.Contains($norm)
}

function Start-CursorProfileInstance {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Profile
    )

    $cursor = Find-CursorExecutable
    if (-not $cursor) {
        [System.Windows.Forms.MessageBox]::Show(
            "Cursor executable not found. Set the CURSOR_BIN environment variable or install Cursor.",
            'Cursor not found',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }

    if (-not (Test-Path $Profile.UserDataDir)) {
        New-Item -ItemType Directory -Path $Profile.UserDataDir -Force | Out-Null
    }

    $argList = @('--user-data-dir', $Profile.UserDataDir, '--new-window')

    if ($Profile.ProjectPath) {
        if (Test-Path $Profile.ProjectPath) {
            $argList += $Profile.ProjectPath
        }
        else {
            [System.Windows.Forms.MessageBox]::Show(
                "Project path not found, opening without a folder:`n$($Profile.ProjectPath)",
                'Warning',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    }

    Start-Process -FilePath $cursor -ArgumentList $argList
}

# ---------------------------------------------------------------------------
# Add / Edit dialog
# ---------------------------------------------------------------------------

function Show-ProfileDialog {
    param(
        [PSCustomObject]$Existing
    )

    $isEdit = $null -ne $Existing

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = if ($isEdit) { "Edit Profile" } else { "Add Profile" }
    $dlg.Size = New-Object System.Drawing.Size(480, 300)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false

    $y = 20
    $labelWidth = 110
    $fieldX = 140
    $fieldWidth = 300

    # Name
    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = 'Profile name:'
    $lblName.Location = New-Object System.Drawing.Point(20, $y)
    $lblName.Size = New-Object System.Drawing.Size($labelWidth, 20)
    $dlg.Controls.Add($lblName)

    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = New-Object System.Drawing.Point($fieldX, ($y - 3))
    $txtName.Size = New-Object System.Drawing.Size($fieldWidth, 20)
    if ($isEdit) { $txtName.Text = $Existing.Name }
    $dlg.Controls.Add($txtName)

    $y += 35

    # User data dir
    $lblDir = New-Object System.Windows.Forms.Label
    $lblDir.Text = 'User data dir:'
    $lblDir.Location = New-Object System.Drawing.Point(20, $y)
    $lblDir.Size = New-Object System.Drawing.Size($labelWidth, 20)
    $dlg.Controls.Add($lblDir)

    $txtDir = New-Object System.Windows.Forms.TextBox
    $txtDir.Location = New-Object System.Drawing.Point($fieldX, ($y - 3))
    $txtDir.Size = New-Object System.Drawing.Size(230, 20)
    if ($isEdit) { $txtDir.Text = $Existing.UserDataDir }
    $dlg.Controls.Add($txtDir)

    $btnBrowseDir = New-Object System.Windows.Forms.Button
    $btnBrowseDir.Text = '...'
    $btnBrowseDir.Location = New-Object System.Drawing.Point(380, ($y - 4))
    $btnBrowseDir.Size = New-Object System.Drawing.Size(60, 23)
    $btnBrowseDir.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = 'Select (or create) a user-data-dir folder for this profile'
        if ($txtDir.Text -and (Test-Path $txtDir.Text)) { $fbd.SelectedPath = $txtDir.Text }
        if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtDir.Text = $fbd.SelectedPath
        }
    })
    $dlg.Controls.Add($btnBrowseDir)

    $y += 35

    # Project path
    $lblProj = New-Object System.Windows.Forms.Label
    $lblProj.Text = 'Project folder:'
    $lblProj.Location = New-Object System.Drawing.Point(20, $y)
    $lblProj.Size = New-Object System.Drawing.Size($labelWidth, 20)
    $dlg.Controls.Add($lblProj)

    $txtProj = New-Object System.Windows.Forms.TextBox
    $txtProj.Location = New-Object System.Drawing.Point($fieldX, ($y - 3))
    $txtProj.Size = New-Object System.Drawing.Size(230, 20)
    if ($isEdit) { $txtProj.Text = $Existing.ProjectPath }
    $dlg.Controls.Add($txtProj)

    $btnBrowseProj = New-Object System.Windows.Forms.Button
    $btnBrowseProj.Text = '...'
    $btnBrowseProj.Location = New-Object System.Drawing.Point(380, ($y - 4))
    $btnBrowseProj.Size = New-Object System.Drawing.Size(60, 23)
    $btnBrowseProj.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = 'Select a project folder to open with this profile (optional)'
        if ($txtProj.Text -and (Test-Path $txtProj.Text)) { $fbd.SelectedPath = $txtProj.Text }
        if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtProj.Text = $fbd.SelectedPath
        }
    })
    $dlg.Controls.Add($btnBrowseProj)

    $y += 35

    # Notes
    $lblNotes = New-Object System.Windows.Forms.Label
    $lblNotes.Text = 'Notes:'
    $lblNotes.Location = New-Object System.Drawing.Point(20, $y)
    $lblNotes.Size = New-Object System.Drawing.Size($labelWidth, 20)
    $dlg.Controls.Add($lblNotes)

    $txtNotes = New-Object System.Windows.Forms.TextBox
    $txtNotes.Location = New-Object System.Drawing.Point($fieldX, ($y - 3))
    $txtNotes.Size = New-Object System.Drawing.Size($fieldWidth, 20)
    if ($isEdit) { $txtNotes.Text = $Existing.Notes }
    $dlg.Controls.Add($txtNotes)

    $y += 45

    $lblHint = New-Object System.Windows.Forms.Label
    $lblHint.Text = "Sign in to a different Cursor account the first time this`nprofile launches. Theme, fonts and extensions are saved`nper-profile automatically."
    $lblHint.Location = New-Object System.Drawing.Point(20, $y)
    $lblHint.Size = New-Object System.Drawing.Size(430, 50)
    $lblHint.ForeColor = [System.Drawing.Color]::DimGray
    $dlg.Controls.Add($lblHint)

    $y += 65

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = if ($isEdit) { 'Save' } else { 'Add' }
    $btnOk.Location = New-Object System.Drawing.Point(280, $y)
    $btnOk.Size = New-Object System.Drawing.Size(80, 28)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($btnOk)
    $dlg.AcceptButton = $btnOk

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Location = New-Object System.Drawing.Point(370, $y)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 28)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnCancel)
    $dlg.CancelButton = $btnCancel

    if (-not $isEdit) {
        $txtName.Add_TextChanged({
            if (-not $txtDir.Tag -or $txtDir.Tag -eq 'auto') {
                $safe = ($txtName.Text -replace '[\\/:*?"<>|]', '_').Trim()
                if ($safe) {
                    $txtDir.Text = Join-Path $ProfilesRoot $safe
                    $txtDir.Tag = 'auto'
                }
            }
        })
        $txtDir.Add_TextChanged({ if ($txtDir.Tag -ne 'auto') { $txtDir.Tag = 'manual' } })
    }

    $result = $dlg.ShowDialog()

    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($txtName.Text)) {
        [System.Windows.Forms.MessageBox]::Show('Profile name is required.', 'Validation', 'OK', 'Warning') | Out-Null
        return $null
    }

    $dir = $txtDir.Text
    if ([string]::IsNullOrWhiteSpace($dir)) {
        $safe = ($txtName.Text -replace '[\\/:*?"<>|]', '_').Trim()
        $dir = Join-Path $ProfilesRoot $safe
    }

    return [PSCustomObject]@{
        Name        = $txtName.Text.Trim()
        UserDataDir = $dir
        ProjectPath = $txtProj.Text.Trim()
        Notes       = $txtNotes.Text.Trim()
    }
}

# ---------------------------------------------------------------------------
# Main window
# ---------------------------------------------------------------------------

$script:Profiles = Load-Profiles

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Cursor Profile Manager'
$form.Size = New-Object System.Drawing.Size(820, 480)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(700, 380)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(12, 12)
$grid.Size = New-Object System.Drawing.Size(796, 370)
$grid.Anchor = 'Top, Bottom, Left, Right'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.ReadOnly = $true
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.RowHeadersVisible = $false

[void]$grid.Columns.Add('Status', 'Status')
[void]$grid.Columns.Add('Name', 'Name')
[void]$grid.Columns.Add('UserDataDir', 'User data dir')
[void]$grid.Columns.Add('ProjectPath', 'Project')
[void]$grid.Columns.Add('Notes', 'Notes')
$grid.Columns['Status'].FillWeight = 60
$grid.Columns['Name'].FillWeight = 110
$grid.Columns['UserDataDir'].FillWeight = 220
$grid.Columns['ProjectPath'].FillWeight = 180
$grid.Columns['Notes'].FillWeight = 140

$form.Controls.Add($grid)

function Refresh-Grid {
    $grid.Rows.Clear()
    $running = Get-RunningUserDataDirs
    foreach ($p in $script:Profiles) {
        $isRunning = Test-ProfileRunning -UserDataDir $p.UserDataDir -RunningDirs $running
        $statusText = if ($isRunning) { $UiStatusRunning } else { $UiStatusIdle }
        $rowIdx = $grid.Rows.Add($statusText, $p.Name, $p.UserDataDir, $p.ProjectPath, $p.Notes)
        $grid.Rows[$rowIdx].Tag = $p.Id
        if ($isRunning) {
            $grid.Rows[$rowIdx].Cells['Status'].Style.ForeColor = [System.Drawing.Color]::SeaGreen
        }
    }
}

function Get-SelectedProfile {
    if ($grid.SelectedRows.Count -eq 0) { return $null }
    $id = $grid.SelectedRows[0].Tag
    return $script:Profiles | Where-Object { $_.Id -eq $id } | Select-Object -First 1
}

$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text = 'Add'
$btnAdd.Location = New-Object System.Drawing.Point(12, 394)
$btnAdd.Size = New-Object System.Drawing.Size(90, 32)
$btnAdd.Anchor = 'Bottom, Left'
$form.Controls.Add($btnAdd)

$btnEdit = New-Object System.Windows.Forms.Button
$btnEdit.Text = 'Edit'
$btnEdit.Location = New-Object System.Drawing.Point(110, 394)
$btnEdit.Size = New-Object System.Drawing.Size(90, 32)
$btnEdit.Anchor = 'Bottom, Left'
$form.Controls.Add($btnEdit)

$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text = 'Delete'
$btnDelete.Location = New-Object System.Drawing.Point(208, 394)
$btnDelete.Size = New-Object System.Drawing.Size(90, 32)
$btnDelete.Anchor = 'Bottom, Left'
$form.Controls.Add($btnDelete)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Refresh'
$btnRefresh.Location = New-Object System.Drawing.Point(306, 394)
$btnRefresh.Size = New-Object System.Drawing.Size(90, 32)
$btnRefresh.Anchor = 'Bottom, Left'
$form.Controls.Add($btnRefresh)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = $UiStartLabel
$btnStart.Location = New-Object System.Drawing.Point(698, 394)
$btnStart.Size = New-Object System.Drawing.Size(110, 32)
$btnStart.Anchor = 'Bottom, Right'
$btnStart.Font = New-Object System.Drawing.Font($btnStart.Font, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnStart)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Profiles dir: $ProfilesRoot"
$lblStatus.Location = New-Object System.Drawing.Point(12, 432)
$lblStatus.Size = New-Object System.Drawing.Size(700, 20)
$lblStatus.Anchor = 'Bottom, Left'
$lblStatus.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblStatus)

$btnAdd.Add_Click({
    $result = Show-ProfileDialog -Existing $null
    if ($result) {
        if ($script:Profiles | Where-Object { $_.Name -eq $result.Name }) {
            [System.Windows.Forms.MessageBox]::Show("A profile named '$($result.Name)' already exists.", 'Duplicate name', 'OK', 'Warning') | Out-Null
            return
        }
        $newProfile = New-ProfileObject -Name $result.Name -UserDataDir $result.UserDataDir -ProjectPath $result.ProjectPath -Notes $result.Notes
        $script:Profiles = @($script:Profiles) + $newProfile
        Save-Profiles -Profiles $script:Profiles
        Refresh-Grid
    }
})

$btnEdit.Add_Click({
    $selected = Get-SelectedProfile
    if (-not $selected) {
        [System.Windows.Forms.MessageBox]::Show('Select a profile to edit.', 'No selection', 'OK', 'Information') | Out-Null
        return
    }
    $result = Show-ProfileDialog -Existing $selected
    if ($result) {
        $selected.Name = $result.Name
        $selected.UserDataDir = $result.UserDataDir
        $selected.ProjectPath = $result.ProjectPath
        $selected.Notes = $result.Notes
        Save-Profiles -Profiles $script:Profiles
        Refresh-Grid
    }
})

$btnDelete.Add_Click({
    $selected = Get-SelectedProfile
    if (-not $selected) {
        [System.Windows.Forms.MessageBox]::Show('Select a profile to delete.', 'No selection', 'OK', 'Information') | Out-Null
        return
    }

    $running = Get-RunningUserDataDirs
    if (Test-ProfileRunning -UserDataDir $selected.UserDataDir -RunningDirs $running) {
        [System.Windows.Forms.MessageBox]::Show("Close the running Cursor window for '$($selected.Name)' before deleting it.", 'Profile is running', 'OK', 'Warning') | Out-Null
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Delete profile '$($selected.Name)'?",
        'Confirm delete',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $deleteFolder = [System.Windows.Forms.MessageBox]::Show(
        "Also delete the profile's data folder?`n$($selected.UserDataDir)`n`nThis permanently removes its login, extensions and settings.",
        'Delete data folder',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)

    if ($deleteFolder -eq [System.Windows.Forms.DialogResult]::Yes -and (Test-Path $selected.UserDataDir)) {
        try {
            Remove-Item -Path $selected.UserDataDir -Recurse -Force
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Failed to delete folder: $($_.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null
        }
    }

    $script:Profiles = @($script:Profiles | Where-Object { $_.Id -ne $selected.Id })
    Save-Profiles -Profiles $script:Profiles
    Refresh-Grid
})

$btnStart.Add_Click({
    $selected = Get-SelectedProfile
    if (-not $selected) {
        [System.Windows.Forms.MessageBox]::Show('Select a profile to start.', 'No selection', 'OK', 'Information') | Out-Null
        return
    }
    Start-CursorProfileInstance -Profile $selected
    Start-Sleep -Milliseconds 800
    Refresh-Grid
})

$btnRefresh.Add_Click({ Refresh-Grid })

$grid.Add_CellDoubleClick({
    param($s, $e)
    if ($e.RowIndex -ge 0) {
        $selected = Get-SelectedProfile
        if ($selected) {
            Start-CursorProfileInstance -Profile $selected
            Start-Sleep -Milliseconds 800
            Refresh-Grid
        }
    }
})

$refreshTimer = New-Object System.Windows.Forms.Timer
$refreshTimer.Interval = 5000
$refreshTimer.Add_Tick({ Refresh-Grid })
$refreshTimer.Start()
$form.Add_FormClosing({ $refreshTimer.Stop() })

Refresh-Grid

[void]$form.ShowDialog()
