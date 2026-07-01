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

$AppWindowTitle = 'Cursor Profile Manager'
$SingleInstanceMutexName = 'Local\CursorProfileManager_GUI_v1'

function Show-ExistingAppWindow {
    param([Parameter(Mandatory)][string]$WindowTitle)

    if (-not ('Win32AppFocus' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Win32AppFocus {
    public const int SW_RESTORE = 9;
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowTitle);
    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr processId);
    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint attachThread, uint attachToThread, bool attach);
    public static void ForceForegroundWindow(IntPtr hWnd) {
        if (hWnd == IntPtr.Zero) { return; }
        if (IsIconic(hWnd)) {
            ShowWindow(hWnd, SW_RESTORE);
        }
        IntPtr foreground = GetForegroundWindow();
        uint foregroundThread = GetWindowThreadProcessId(foreground, IntPtr.Zero);
        uint currentThread = GetCurrentThreadId();
        if (foregroundThread != 0 && foregroundThread != currentThread) {
            AttachThreadInput(currentThread, foregroundThread, true);
            BringWindowToTop(hWnd);
            SetForegroundWindow(hWnd);
            AttachThreadInput(currentThread, foregroundThread, false);
        }
        else {
            BringWindowToTop(hWnd);
            SetForegroundWindow(hWnd);
        }
    }
}
'@
    }

    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        $hwnd = [Win32AppFocus]::FindWindow($null, $WindowTitle)
        if ($hwnd -ne [IntPtr]::Zero) {
            [Win32AppFocus]::ForceForegroundWindow($hwnd)
            return $true
        }
        Start-Sleep -Milliseconds 100
    }
    return $false
}

function Initialize-SingleInstance {
    param([Parameter(Mandatory)][string]$MutexName)

    $createdNew = $false
    $mutex = New-Object System.Threading.Mutex($true, $MutexName, [ref]$createdNew)
    if ($createdNew) {
        $script:AppInstanceMutex = $mutex
        return
    }

    $mutex.Dispose()
    [void](Show-ExistingAppWindow -WindowTitle $AppWindowTitle)
    exit 0
}

[void](Initialize-SingleInstance -MutexName $SingleInstanceMutexName)

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

function Get-UserDataDirInstanceCounts {
    # Returns normalized user-data-dir path -> number of Cursor.exe processes using it.
    $counts = @{}
    $procs = Get-CimInstance Win32_Process -Filter "name='Cursor.exe'" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        $cmd = $p.CommandLine
        if ($cmd -and $cmd -match '--user-data-dir[= ]"?([^"]+?)"?(\s--|\s|$)') {
            $dir = $matches[1].TrimEnd('\', '/').ToLowerInvariant()
            if ($counts.ContainsKey($dir)) {
                $counts[$dir]++
            }
            else {
                $counts[$dir] = 1
            }
        }
    }
    return $counts
}

function Get-ProfileInstanceCount {
    param([string]$UserDataDir, [hashtable]$InstanceCounts)
    if (-not $UserDataDir) { return 0 }
    $norm = $UserDataDir.TrimEnd('\', '/').ToLowerInvariant()
    if ($InstanceCounts.ContainsKey($norm)) {
        return [int]$InstanceCounts[$norm]
    }
    return 0
}

function Show-ProfileNotification {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $script:NotifyIcon) { return }
    $script:NotifyIcon.ShowBalloonTip(4000, $Title, $Message, [System.Windows.Forms.ToolTipIcon]::Info)
}

function Start-CursorProcessWatchers {
    param(
        [System.Windows.Forms.Form]$OwnerForm,
        [System.Windows.Forms.Timer]$DebounceTimer
    )

    $handler = [System.Management.EventArrivedEventHandler]{
        param($sender, $e)
        if ($OwnerForm.IsDisposed) { return }
        if ($OwnerForm.InvokeRequired) {
            [void]$OwnerForm.BeginInvoke([Action]{
                $DebounceTimer.Stop()
                $DebounceTimer.Start()
            })
        }
        else {
            $DebounceTimer.Stop()
            $DebounceTimer.Start()
        }
    }

    $queries = @(
        "SELECT * FROM __InstanceCreationEvent WITHIN 1 WHERE TargetInstance ISA 'Win32_Process' AND TargetInstance.Name='Cursor.exe'",
        "SELECT * FROM __InstanceDeletionEvent WITHIN 1 WHERE TargetInstance ISA 'Win32_Process' AND TargetInstance.Name='Cursor.exe'"
    )

    $script:ProcessEventWatchers = @()
    foreach ($queryText in $queries) {
        $watcher = New-Object System.Management.ManagementEventWatcher
        $watcher.Query = New-Object System.Management.WqlEventQuery($queryText)
        $watcher.add_EventArrived($handler)
        $watcher.Start()
        $script:ProcessEventWatchers += $watcher
    }
}

function Stop-CursorProcessWatchers {
    if ($script:ProcessEventWatchers) {
        foreach ($watcher in $script:ProcessEventWatchers) {
            try {
                $watcher.Stop()
                $watcher.Dispose()
            }
            catch { }
        }
        $script:ProcessEventWatchers = $null
    }
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
$form.Text = $AppWindowTitle
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
[void]$grid.Columns.Add('Instances', 'Instances')
[void]$grid.Columns.Add('Name', 'Name')
[void]$grid.Columns.Add('UserDataDir', 'User data dir')
[void]$grid.Columns.Add('ProjectPath', 'Project')
[void]$grid.Columns.Add('Notes', 'Notes')
$grid.Columns['Status'].FillWeight = 60
$grid.Columns['Instances'].FillWeight = 50
$grid.Columns['Instances'].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleCenter
$grid.Columns['Name'].FillWeight = 100
$grid.Columns['UserDataDir'].FillWeight = 200
$grid.Columns['ProjectPath'].FillWeight = 160
$grid.Columns['Notes'].FillWeight = 130

# Reduce paint flicker during frequent status updates.
$grid.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance, NonPublic').SetValue($grid, $true, $null)

$form.Controls.Add($grid)

$script:GridModel = $null
$script:DefaultGridForeColor = $grid.DefaultCellStyle.ForeColor
$script:RunningGridForeColor = [System.Drawing.Color]::SeaGreen

function New-GridRowModel {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Profile,
        [Parameter(Mandatory)][int]$InstanceCount
    )

    $isRunning = $InstanceCount -gt 0
    return [PSCustomObject]@{
        Id          = $Profile.Id
        Status      = if ($isRunning) { $UiStatusRunning } else { $UiStatusIdle }
        Instances   = $InstanceCount
        Name        = $Profile.Name
        UserDataDir = $Profile.UserDataDir
        ProjectPath = $Profile.ProjectPath
        Notes       = $Profile.Notes
        IsRunning   = $isRunning
    }
}

function Build-GridModel {
    $instanceCounts = Get-UserDataDirInstanceCounts
    $order = New-Object 'System.Collections.Generic.List[string]'
    $rowsById = @{}

    foreach ($p in $script:Profiles) {
        $instanceCount = Get-ProfileInstanceCount -UserDataDir $p.UserDataDir -InstanceCounts $instanceCounts
        $row = New-GridRowModel -Profile $p -InstanceCount $instanceCount
        $order.Add($p.Id)
        $rowsById[$p.Id] = $row
    }

    return [PSCustomObject]@{
        Order    = $order
        RowsById = $rowsById
    }
}

function Test-GridRowModelEqual {
    param(
        [PSCustomObject]$A,
        [PSCustomObject]$B
    )

    return $A.Status -eq $B.Status -and
        $A.Instances -eq $B.Instances -and
        $A.Name -eq $B.Name -and
        $A.UserDataDir -eq $B.UserDataDir -and
        $A.ProjectPath -eq $B.ProjectPath -and
        $A.Notes -eq $B.Notes
}

function Test-GridModelEqual {
    param(
        [PSCustomObject]$A,
        [PSCustomObject]$B
    )

    if ($A.Order.Count -ne $B.Order.Count) { return $false }
    for ($i = 0; $i -lt $A.Order.Count; $i++) {
        $id = $A.Order[$i]
        if ($B.Order[$i] -ne $id) { return $false }
        if (-not (Test-GridRowModelEqual -A $A.RowsById[$id] -B $B.RowsById[$id])) {
            return $false
        }
    }
    return $true
}

function Notify-InstanceCountChange {
    param(
        [string]$ProfileName,
        [int]$PreviousCount,
        [int]$CurrentCount
    )

    if ($CurrentCount -eq 0) {
        Show-ProfileNotification -Title 'Profile stopped' -Message "$ProfileName is now idle."
        return
    }

    if ($PreviousCount -eq 0) {
        $suffix = if ($CurrentCount -eq 1) { '' } else { 's' }
        Show-ProfileNotification -Title 'Profile started' -Message "$ProfileName is running ($CurrentCount instance$suffix)."
        return
    }

    if ($CurrentCount -gt $PreviousCount) {
        Show-ProfileNotification -Title 'Instance started' -Message "$ProfileName now has $CurrentCount running instances."
        return
    }

    $suffix = if ($CurrentCount -eq 1) { '' } else { 's' }
    Show-ProfileNotification -Title 'Instance closed' -Message "$ProfileName has $CurrentCount running instance$suffix."
}

function Invoke-GridModelNotifications {
    param(
        [Parameter(Mandatory)][PSCustomObject]$PreviousModel,
        [Parameter(Mandatory)][PSCustomObject]$NewModel
    )

    foreach ($id in $NewModel.Order) {
        $previousCount = 0
        if ($PreviousModel.RowsById.ContainsKey($id)) {
            $previousCount = [int]$PreviousModel.RowsById[$id].Instances
        }
        $currentCount = [int]$NewModel.RowsById[$id].Instances
        if ($previousCount -ne $currentCount) {
            Notify-InstanceCountChange -ProfileName $NewModel.RowsById[$id].Name -PreviousCount $previousCount -CurrentCount $currentCount
        }
    }
}

function Sync-GridRowToView {
    param(
        [System.Windows.Forms.DataGridViewRow]$Row,
        [PSCustomObject]$ModelRow
    )

    $foreColor = if ($ModelRow.IsRunning) { $script:RunningGridForeColor } else { $script:DefaultGridForeColor }
    $cells = $Row.Cells

    if ([string]$cells['Status'].Value -ne $ModelRow.Status) {
        $cells['Status'].Value = $ModelRow.Status
    }
    if ([string]$cells['Instances'].Value -ne [string]$ModelRow.Instances) {
        $cells['Instances'].Value = [string]$ModelRow.Instances
    }
    if ([string]$cells['Name'].Value -ne $ModelRow.Name) {
        $cells['Name'].Value = $ModelRow.Name
    }
    if ([string]$cells['UserDataDir'].Value -ne $ModelRow.UserDataDir) {
        $cells['UserDataDir'].Value = $ModelRow.UserDataDir
    }
    if ([string]$cells['ProjectPath'].Value -ne $ModelRow.ProjectPath) {
        $cells['ProjectPath'].Value = $ModelRow.ProjectPath
    }
    if ([string]$cells['Notes'].Value -ne $ModelRow.Notes) {
        $cells['Notes'].Value = $ModelRow.Notes
    }
    if ($cells['Status'].Style.ForeColor -ne $foreColor) {
        $cells['Status'].Style.ForeColor = $foreColor
        $cells['Instances'].Style.ForeColor = $foreColor
    }
}

function Apply-GridModelToView {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Model,
        [PSCustomObject]$PreviousModel
    )

    $existingRows = @{}
    foreach ($row in $grid.Rows) {
        if ($null -ne $row.Tag) {
            $existingRows[$row.Tag] = $row
        }
    }

    $grid.SuspendLayout()
    try {
        foreach ($id in $Model.Order) {
            $modelRow = $Model.RowsById[$id]
            $previousRow = if ($PreviousModel) { $PreviousModel.RowsById[$id] } else { $null }

            if ($existingRows.ContainsKey($id)) {
                $row = $existingRows[$id]
                [void]$existingRows.Remove($id)
            }
            else {
                $rowIdx = $grid.Rows.Add('', '', '', '', '', '')
                $row = $grid.Rows[$rowIdx]
                $row.Tag = $id
            }

            if (-not $previousRow -or -not (Test-GridRowModelEqual -A $previousRow -B $modelRow)) {
                Sync-GridRowToView -Row $row -ModelRow $modelRow
            }
        }

        foreach ($staleId in @($existingRows.Keys)) {
            $grid.Rows.Remove($existingRows[$staleId])
        }
    }
    finally {
        $grid.ResumeLayout($true)
    }
}

function Update-ProfileGrid {
    $newModel = Build-GridModel
    $previousModel = $script:GridModel

    if ($previousModel -and (Test-GridModelEqual -A $previousModel -B $newModel)) {
        return
    }

    if ($previousModel) {
        Invoke-GridModelNotifications -PreviousModel $previousModel -NewModel $newModel
    }

    Apply-GridModelToView -Model $newModel -PreviousModel $previousModel
    $script:GridModel = $newModel
}

function Request-DeferredGridRefresh {
    Update-ProfileGrid
    $script:ProcessEventDebounceTimer.Stop()
    $script:ProcessEventDebounceTimer.Start()
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
        Update-ProfileGrid
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
        Update-ProfileGrid
    }
})

$btnDelete.Add_Click({
    $selected = Get-SelectedProfile
    if (-not $selected) {
        [System.Windows.Forms.MessageBox]::Show('Select a profile to delete.', 'No selection', 'OK', 'Information') | Out-Null
        return
    }

    $instanceCounts = Get-UserDataDirInstanceCounts
    $instanceCount = Get-ProfileInstanceCount -UserDataDir $selected.UserDataDir -InstanceCounts $instanceCounts
    if ($instanceCount -gt 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Close all running Cursor windows for '$($selected.Name)' ($instanceCount instance$(if ($instanceCount -ne 1) { 's' })) before deleting it.",
            'Profile is running',
            'OK',
            'Warning') | Out-Null
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
    Update-ProfileGrid
})

$btnStart.Add_Click({
    $selected = Get-SelectedProfile
    if (-not $selected) {
        [System.Windows.Forms.MessageBox]::Show('Select a profile to start.', 'No selection', 'OK', 'Information') | Out-Null
        return
    }
    Start-CursorProfileInstance -Profile $selected
    Request-DeferredGridRefresh
})

$btnRefresh.Add_Click({ Update-ProfileGrid })

$grid.Add_CellDoubleClick({
    param($s, $e)
    if ($e.RowIndex -ge 0) {
        $selected = Get-SelectedProfile
        if ($selected) {
            Start-CursorProfileInstance -Profile $selected
            Request-DeferredGridRefresh
        }
    }
})

$processEventDebounce = New-Object System.Windows.Forms.Timer
$processEventDebounce.Interval = 500
$script:ProcessEventDebounceTimer = $processEventDebounce
$processEventDebounce.Add_Tick({
    $processEventDebounce.Stop()
    Update-ProfileGrid
})

$refreshTimer = New-Object System.Windows.Forms.Timer
$refreshTimer.Interval = 2000
$refreshTimer.Add_Tick({ Update-ProfileGrid })
$refreshTimer.Start()

$script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
$cursorIconPath = Find-CursorExecutable
if ($cursorIconPath) {
    $script:NotifyIcon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($cursorIconPath)
}
else {
    $script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Application
}
$script:NotifyIcon.Visible = $true

Start-CursorProcessWatchers -OwnerForm $form -DebounceTimer $processEventDebounce

$form.Add_FormClosing({
    $refreshTimer.Stop()
    $processEventDebounce.Stop()
    Stop-CursorProcessWatchers
    if ($script:NotifyIcon) {
        $script:NotifyIcon.Visible = $false
        $script:NotifyIcon.Dispose()
        $script:NotifyIcon = $null
    }
})

Update-ProfileGrid

try {
    [void]$form.ShowDialog()
}
finally {
    if ($script:AppInstanceMutex) {
        try { $script:AppInstanceMutex.ReleaseMutex() } catch { }
        $script:AppInstanceMutex.Dispose()
        $script:AppInstanceMutex = $null
    }
}
