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
[void][System.Windows.Forms.Application]::EnableVisualStyles()
[void][System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

if (-not ('TextBoxCue' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class TextBoxCue {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, string lParam);

    public static void SetCue(IntPtr handle, string cue) {
        if (handle != IntPtr.Zero) {
            SendMessage(handle, 0x1501, IntPtr.Zero, cue);
        }
    }
}
'@
}

# Build UI symbols via code points so the script stays ASCII-safe under Windows PowerShell 5.1.
$UiStatusRunning = "$([char]0x25CF) Running"
$UiStatusIdle = "$([char]0x25CB) Idle"
$UiStartLabel = "Start $([char]0x25B6)"

# ---------------------------------------------------------------------------
# UI theme
# ---------------------------------------------------------------------------

$script:UiFont = New-Object System.Drawing.Font 'Segoe UI', 9
$script:UiFontSemibold = New-Object System.Drawing.Font 'Segoe UI', 9, ([System.Drawing.FontStyle]::Bold)
$script:UiThemePreference = 'default'
$script:UiEffectiveTheme = 'light'
$script:UiBackColor = [System.Drawing.Color]::White
$script:UiPanelColor = [System.Drawing.Color]::White
$script:UiBorderColor = [System.Drawing.Color]::FromArgb(220, 223, 228)
$script:UiTextMuted = [System.Drawing.Color]::FromArgb(96, 101, 108)
$script:UiTextPrimary = [System.Drawing.Color]::FromArgb(32, 33, 36)
$script:UiAccent = [System.Drawing.Color]::FromArgb(0, 102, 204)
$script:UiAccentHover = [System.Drawing.Color]::FromArgb(0, 90, 184)
$script:UiAccentText = [System.Drawing.Color]::White
$script:UiGridHeader = [System.Drawing.Color]::FromArgb(248, 249, 251)
$script:UiGridAltRow = [System.Drawing.Color]::FromArgb(250, 251, 253)
$script:UiSelectionBack = [System.Drawing.Color]::FromArgb(204, 229, 255)
$script:UiSelectionFore = [System.Drawing.Color]::FromArgb(32, 33, 36)
$script:UiRunningColor = [System.Drawing.Color]::FromArgb(16, 124, 65)
$script:UiIdleColor = [System.Drawing.Color]::FromArgb(120, 124, 130)
$script:UiInputBackColor = [System.Drawing.Color]::White
$script:UiInputForeColor = [System.Drawing.Color]::FromArgb(32, 33, 36)
$script:UiThemeComboSync = $false

function Get-UiThemePalettes {
    return @{
        light = @{
            BackColor      = [System.Drawing.Color]::FromArgb(245, 246, 248)
            PanelColor     = [System.Drawing.Color]::White
            BorderColor    = [System.Drawing.Color]::FromArgb(220, 223, 228)
            TextMuted      = [System.Drawing.Color]::FromArgb(96, 101, 108)
            TextPrimary    = [System.Drawing.Color]::FromArgb(32, 33, 36)
            Accent         = [System.Drawing.Color]::FromArgb(0, 102, 204)
            AccentHover    = [System.Drawing.Color]::FromArgb(0, 90, 184)
            AccentText     = [System.Drawing.Color]::White
            GridHeader     = [System.Drawing.Color]::FromArgb(248, 249, 251)
            GridAltRow     = [System.Drawing.Color]::FromArgb(250, 251, 253)
            SelectionBack  = [System.Drawing.Color]::FromArgb(204, 229, 255)
            SelectionFore  = [System.Drawing.Color]::FromArgb(32, 33, 36)
            RunningColor   = [System.Drawing.Color]::FromArgb(16, 124, 65)
            IdleColor      = [System.Drawing.Color]::FromArgb(120, 124, 130)
            InputBackColor = [System.Drawing.Color]::White
            InputForeColor = [System.Drawing.Color]::FromArgb(32, 33, 36)
        }
        dark = @{
            BackColor      = [System.Drawing.Color]::FromArgb(32, 33, 36)
            PanelColor     = [System.Drawing.Color]::FromArgb(45, 45, 48)
            BorderColor    = [System.Drawing.Color]::FromArgb(68, 71, 78)
            TextMuted      = [System.Drawing.Color]::FromArgb(154, 160, 166)
            TextPrimary    = [System.Drawing.Color]::FromArgb(232, 234, 237)
            Accent         = [System.Drawing.Color]::FromArgb(0, 120, 212)
            AccentHover    = [System.Drawing.Color]::FromArgb(0, 103, 181)
            AccentText     = [System.Drawing.Color]::White
            GridHeader     = [System.Drawing.Color]::FromArgb(50, 51, 55)
            GridAltRow     = [System.Drawing.Color]::FromArgb(40, 41, 45)
            SelectionBack  = [System.Drawing.Color]::FromArgb(0, 72, 128)
            SelectionFore  = [System.Drawing.Color]::White
            RunningColor   = [System.Drawing.Color]::FromArgb(76, 195, 113)
            IdleColor      = [System.Drawing.Color]::FromArgb(154, 160, 166)
            InputBackColor = [System.Drawing.Color]::FromArgb(55, 56, 60)
            InputForeColor = [System.Drawing.Color]::FromArgb(232, 234, 237)
        }
    }
}

function Test-WindowsAppsUseLightTheme {
    try {
        $value = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop
        return ($value.AppsUseLightTheme -ne 0)
    }
    catch {
        return $true
    }
}

function Get-EffectiveUiThemeName {
    param([string]$Preference = $script:UiThemePreference)

    switch ($Preference) {
        'light' { return 'light' }
        'dark' { return 'dark' }
        default {
            if (Test-WindowsAppsUseLightTheme) { return 'light' }
            return 'dark'
        }
    }
}

function Set-UiThemePalette {
    param([Parameter(Mandatory)][string]$ThemeName)

    $palettes = Get-UiThemePalettes
    if (-not $palettes.ContainsKey($ThemeName)) {
        $ThemeName = 'light'
    }
    $palette = $palettes[$ThemeName]

    $script:UiEffectiveTheme = $ThemeName
    $script:UiBackColor = $palette.BackColor
    $script:UiPanelColor = $palette.PanelColor
    $script:UiBorderColor = $palette.BorderColor
    $script:UiTextMuted = $palette.TextMuted
    $script:UiTextPrimary = $palette.TextPrimary
    $script:UiAccent = $palette.Accent
    $script:UiAccentHover = $palette.AccentHover
    $script:UiAccentText = $palette.AccentText
    $script:UiGridHeader = $palette.GridHeader
    $script:UiGridAltRow = $palette.GridAltRow
    $script:UiSelectionBack = $palette.SelectionBack
    $script:UiSelectionFore = $palette.SelectionFore
    $script:UiRunningColor = $palette.RunningColor
    $script:UiIdleColor = $palette.IdleColor
    $script:UiInputBackColor = $palette.InputBackColor
    $script:UiInputForeColor = $palette.InputForeColor
    $script:DefaultGridForeColor = $script:UiTextPrimary
    $script:RunningGridForeColor = $script:UiRunningColor
}

function Get-UiThemePreferenceIndex {
    param([string]$Preference)

    switch ($Preference) {
        'light' { return 1 }
        'dark' { return 2 }
        default { return 0 }
    }
}

function Get-UiThemePreferenceFromIndex {
    param([int]$Index)

    switch ($Index) {
        1 { return 'light' }
        2 { return 'dark' }
        default { return 'default' }
    }
}

function Set-FormIcon {
    param([System.Windows.Forms.Form]$TargetForm)

    $cursorPath = Find-CursorExecutable
    if ($cursorPath) {
        $TargetForm.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($cursorPath)
    }
}

function Set-ButtonFlatStyle {
    param(
        [System.Windows.Forms.Button]$Button,
        [switch]$Primary
    )

    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.Font = $script:UiFont
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.UseVisualStyleBackColor = $false

    if ($Primary) {
        $Button.BackColor = $script:UiAccent
        $Button.ForeColor = $script:UiAccentText
        $Button.FlatAppearance.BorderSize = 0
        $Button.Font = $script:UiFontSemibold
        $Button.Add_MouseEnter({ $this.BackColor = $script:UiAccentHover })
        $Button.Add_MouseLeave({ $this.BackColor = $script:UiAccent })
    }
    else {
        $Button.BackColor = $script:UiPanelColor
        $Button.ForeColor = $script:UiTextPrimary
        $Button.FlatAppearance.BorderColor = $script:UiBorderColor
        $Button.FlatAppearance.BorderSize = 1
        $Button.Add_MouseEnter({ $this.BackColor = $script:UiGridAltRow })
        $Button.Add_MouseLeave({ $this.BackColor = $script:UiPanelColor })
    }
}

function Update-ToolbarButtonTheme {
    param(
        [System.Windows.Forms.Button]$Button,
        [switch]$Primary
    )

    if ($Primary) {
        $Button.BackColor = $script:UiAccent
        $Button.ForeColor = $script:UiAccentText
        return
    }

    $Button.BackColor = $script:UiPanelColor
    $Button.ForeColor = $script:UiTextPrimary
    $Button.FlatAppearance.BorderColor = $script:UiBorderColor
}

function Apply-UiThemeToTextInputs {
    param([System.Windows.Forms.TextBox[]]$TextBoxes)

    foreach ($textBox in $TextBoxes) {
        $textBox.BackColor = $script:UiInputBackColor
        $textBox.ForeColor = $script:UiInputForeColor
    }
}

function Apply-DataGridTheme {
    param([System.Windows.Forms.DataGridView]$TargetGrid)

    $TargetGrid.BackgroundColor = $script:UiPanelColor
    $TargetGrid.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $TargetGrid.CellBorderStyle = [System.Windows.Forms.DataGridViewCellBorderStyle]::SingleHorizontal
    $TargetGrid.GridColor = $script:UiBorderColor
    $TargetGrid.EnableHeadersVisualStyles = $false
    $TargetGrid.ColumnHeadersBorderStyle = [System.Windows.Forms.DataGridViewHeaderBorderStyle]::None
    $TargetGrid.ColumnHeadersHeight = 32
    $TargetGrid.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::DisableResizing
    $TargetGrid.RowTemplate.Height = 30
    $TargetGrid.AlternatingRowsDefaultCellStyle.BackColor = $script:UiGridAltRow
    $TargetGrid.DefaultCellStyle.BackColor = $script:UiPanelColor
    $TargetGrid.DefaultCellStyle.ForeColor = $script:UiTextPrimary
    $TargetGrid.DefaultCellStyle.SelectionBackColor = $script:UiSelectionBack
    $TargetGrid.DefaultCellStyle.SelectionForeColor = $script:UiSelectionFore
    $TargetGrid.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(4, 0, 4, 0)
    $TargetGrid.ColumnHeadersDefaultCellStyle.BackColor = $script:UiGridHeader
    $TargetGrid.ColumnHeadersDefaultCellStyle.ForeColor = $script:UiTextPrimary
    $TargetGrid.ColumnHeadersDefaultCellStyle.Font = $script:UiFontSemibold
    $TargetGrid.ColumnHeadersDefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleLeft
    $TargetGrid.ColumnHeadersDefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(6, 0, 4, 0)
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

$ProfilesRoot = if ($env:CURSOR_PROFILES_DIR) { $env:CURSOR_PROFILES_DIR } else { Join-Path $env:USERPROFILE '.cursor-profiles' }
$ConfigPath = Join-Path $ProfilesRoot 'profiles.json'
$SettingsPath = Join-Path $ProfilesRoot 'settings.json'

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

function Load-AppSettings {
    Ensure-ProfilesRoot
    if (-not (Test-Path $SettingsPath)) {
        return
    }
    try {
        $raw = Get-Content -Raw -Path $SettingsPath -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return }
        $data = $raw | ConvertFrom-Json
        if ($null -eq $data) { return }
        $theme = [string]$data.Theme
        if ($theme -eq 'light' -or $theme -eq 'dark' -or $theme -eq 'default') {
            $script:UiThemePreference = $theme
        }
    }
    catch {
        Write-Warning "Failed to read settings.json: $($_.Exception.Message)"
    }
}

function Save-AppSettings {
    Ensure-ProfilesRoot
    $settings = [PSCustomObject]@{
        Theme = $script:UiThemePreference
    }
    $settings | ConvertTo-Json -Depth 3 | Set-Content -Path $SettingsPath -Encoding UTF8
}

function Sync-UiThemeComboSelection {
    if (-not $script:ThemeCombo) { return }

    $script:UiThemeComboSync = $true
    try {
        $script:ThemeCombo.SelectedIndex = Get-UiThemePreferenceIndex -Preference $script:UiThemePreference
    }
    finally {
        $script:UiThemeComboSync = $false
    }
}

function Update-ToolbarLayout {
    if (-not $toolbarPanel -or -not $btnStart) { return }

    $startX = $toolbarPanel.ClientSize.Width - $btnStart.Width - 12
    $btnStart.Location = New-Object System.Drawing.Point($startX, 10)

    if ($script:ThemeCombo) {
        $themeWidth = 118
        $themeLabelWidth = 42
        $gap = 8
        $script:ThemeCombo.Width = $themeWidth
        $script:ThemeCombo.Location = New-Object System.Drawing.Point(($startX - $gap - $themeWidth), 12)
        if ($script:ThemeLabel) {
            $script:ThemeLabel.Location = New-Object System.Drawing.Point(($startX - $gap - $themeWidth - $themeLabelWidth - 4), 16)
        }
    }
}

function Apply-UiThemeToMainWindow {
    if (-not $form) { return }

    $form.SuspendLayout()
    try {
        $form.BackColor = $script:UiBackColor

        $statusPanel.BackColor = $script:UiPanelColor
        $lblStatus.ForeColor = $script:UiTextMuted

        $toolbarPanel.BackColor = $script:UiPanelColor
        $toolbarSep.BackColor = $script:UiBorderColor

        $contentPanel.BackColor = $script:UiBackColor
        $lblGridHint.ForeColor = $script:UiTextMuted

        $gridHost.BackColor = $script:UiPanelColor
        Apply-DataGridTheme -TargetGrid $grid

        Update-ToolbarButtonTheme -Button $btnAdd
        Update-ToolbarButtonTheme -Button $btnEdit
        Update-ToolbarButtonTheme -Button $btnDelete
        Update-ToolbarButtonTheme -Button $btnRefresh
        Update-ToolbarButtonTheme -Button $btnStart -Primary

        if ($script:ThemeLabel) {
            $script:ThemeLabel.ForeColor = $script:UiTextMuted
            $script:ThemeLabel.BackColor = $script:UiPanelColor
        }
        if ($script:ThemeCombo) {
            $script:ThemeCombo.BackColor = $script:UiInputBackColor
            $script:ThemeCombo.ForeColor = $script:UiInputForeColor
        }

        Sync-UiThemeComboSelection
        Update-ToolbarLayout
    }
    finally {
        $form.ResumeLayout($true)
    }
}

function Set-UiThemePreference {
    param(
        [Parameter(Mandatory)][string]$Preference,
        [switch]$Persist
    )

    if ($Preference -ne 'light' -and $Preference -ne 'dark' -and $Preference -ne 'default') {
        $Preference = 'default'
    }

    $script:UiThemePreference = $Preference
    $effective = Get-EffectiveUiThemeName -Preference $Preference
    $themeChanged = $effective -ne $script:UiEffectiveTheme
    Set-UiThemePalette -ThemeName $effective

    if ($form) {
        Apply-UiThemeToMainWindow
        if ($themeChanged) {
            Update-ProfileGrid
        }
    }

    if ($Persist) {
        Save-AppSettings
    }
}

function Test-UiSystemThemeChanged {
    if ($script:UiThemePreference -ne 'default') {
        return $false
    }

    $effective = Get-EffectiveUiThemeName -Preference 'default'
    return $effective -ne $script:UiEffectiveTheme
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
    # Count Cursor windows per user-data-dir via --type=renderer processes. Electron keeps
    # one main process per profile; each additional window is a renderer child.
    $counts = @{}
    $procs = @(Get-CimInstance Win32_Process -Filter "name='Cursor.exe'" -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return $counts }

    $cursorPids = @{}
    foreach ($p in $procs) {
        $cursorPids[$p.ProcessId] = $true
    }

    $mainByDir = @{}
    foreach ($p in $procs) {
        $cmd = $p.CommandLine
        if (-not $cmd -or $cmd -notmatch '--user-data-dir[= ]"?([^"]+?)"?(\s--|\s|$)') { continue }
        if ($cmd -match '--type=') { continue }
        if ($cursorPids.ContainsKey($p.ParentProcessId)) { continue }

        $dir = $matches[1].TrimEnd('\', '/').ToLowerInvariant()
        $mainByDir[$dir] = $true
    }

    foreach ($p in $procs) {
        $cmd = $p.CommandLine
        if (-not $cmd -or $cmd -notmatch '--type=renderer') { continue }
        if ($cmd -notmatch '--user-data-dir[= ]"?([^"]+?)"?(\s--|\s|$)') { continue }

        $dir = $matches[1].TrimEnd('\', '/').ToLowerInvariant()
        if (-not $mainByDir.ContainsKey($dir)) { continue }

        if ($counts.ContainsKey($dir)) {
            $counts[$dir]++
        }
        else {
            $counts[$dir] = 1
        }
    }

    foreach ($dir in $mainByDir.Keys) {
        if (-not $counts.ContainsKey($dir)) {
            $counts[$dir] = 1
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

    $projectExists = $false
    if ($Profile.ProjectPath) {
        if (Test-Path $Profile.ProjectPath) {
            $projectExists = $true
        }
        else {
            [System.Windows.Forms.MessageBox]::Show(
                "Project path not found, opening without a folder:`n$($Profile.ProjectPath)",
                'Warning',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    }

    $instanceCounts = Get-UserDataDirInstanceCounts
    $runningCount = Get-ProfileInstanceCount -UserDataDir $Profile.UserDataDir -InstanceCounts $instanceCounts

    # Cursor/VS Code reuses the existing window when the same folder is already open,
    # even with --new-window. Open an empty window, then --add the project folder.
    if ($runningCount -gt 0 -and $projectExists) {
        Start-Process -FilePath $cursor -ArgumentList @('--user-data-dir', $Profile.UserDataDir, '--new-window')
        Start-Sleep -Milliseconds 800
        Start-Process -FilePath $cursor -ArgumentList @('--user-data-dir', $Profile.UserDataDir, '--add', $Profile.ProjectPath)
        return
    }

    $argList = @('--user-data-dir', $Profile.UserDataDir, '--new-window')
    if ($projectExists) {
        $argList += $Profile.ProjectPath
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
    $dlg.Size = New-Object System.Drawing.Size(500, 360)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.Font = $script:UiFont
    $dlg.BackColor = $script:UiBackColor
    [void](Set-FormIcon -TargetForm $dlg)

    $y = 20
    $labelWidth = 130
    $fieldX = 150
    $fieldWidth = 290
    $browseWidth = 72

    # Name
    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = 'Profile name:'
    $lblName.Location = New-Object System.Drawing.Point(20, ($y + 2))
    $lblName.Size = New-Object System.Drawing.Size($labelWidth, 20)
    $lblName.ForeColor = $script:UiTextPrimary
    $dlg.Controls.Add($lblName)

    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = New-Object System.Drawing.Point($fieldX, $y)
    $txtName.Size = New-Object System.Drawing.Size($fieldWidth, 23)
    if ($isEdit) { $txtName.Text = $Existing.Name }
    $dlg.Controls.Add($txtName)

    $y += 38

    # User data dir
    $lblDir = New-Object System.Windows.Forms.Label
    $lblDir.Text = 'User data dir:'
    $lblDir.Location = New-Object System.Drawing.Point(20, ($y + 2))
    $lblDir.Size = New-Object System.Drawing.Size($labelWidth, 20)
    $lblDir.ForeColor = $script:UiTextPrimary
    $dlg.Controls.Add($lblDir)

    $txtDir = New-Object System.Windows.Forms.TextBox
    $txtDir.Location = New-Object System.Drawing.Point($fieldX, $y)
    $txtDir.Size = New-Object System.Drawing.Size(($fieldWidth - $browseWidth - 8), 23)
    if ($isEdit) { $txtDir.Text = $Existing.UserDataDir }
    $dlg.Controls.Add($txtDir)

    $btnBrowseDir = New-Object System.Windows.Forms.Button
    $btnBrowseDir.Text = 'Browse'
    $btnBrowseDir.Location = New-Object System.Drawing.Point(($fieldX + $txtDir.Width + 8), ($y - 1))
    $btnBrowseDir.Size = New-Object System.Drawing.Size($browseWidth, 25)
    Set-ButtonFlatStyle -Button $btnBrowseDir
    $btnBrowseDir.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = 'Select (or create) a user-data-dir folder for this profile'
        if ($txtDir.Text -and (Test-Path $txtDir.Text)) { $fbd.SelectedPath = $txtDir.Text }
        if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtDir.Text = $fbd.SelectedPath
        }
    })
    $dlg.Controls.Add($btnBrowseDir)

    $y += 38

    # Project path
    $lblProj = New-Object System.Windows.Forms.Label
    $lblProj.Text = 'Project folder (optional):'
    $lblProj.Location = New-Object System.Drawing.Point(20, ($y + 2))
    $lblProj.Size = New-Object System.Drawing.Size($labelWidth, 20)
    $lblProj.ForeColor = $script:UiTextPrimary
    $dlg.Controls.Add($lblProj)

    $txtProj = New-Object System.Windows.Forms.TextBox
    $txtProj.Location = New-Object System.Drawing.Point($fieldX, $y)
    $txtProj.Size = New-Object System.Drawing.Size(($fieldWidth - $browseWidth - 8), 23)
    if ($isEdit) { $txtProj.Text = $Existing.ProjectPath }
    $dlg.Controls.Add($txtProj)

    $dlg.Add_Load({
        [TextBoxCue]::SetCue($txtProj.Handle, 'Leave empty to open with no folder on Start')
    })

    $btnBrowseProj = New-Object System.Windows.Forms.Button
    $btnBrowseProj.Text = 'Browse'
    $btnBrowseProj.Location = New-Object System.Drawing.Point(($fieldX + $txtProj.Width + 8), ($y - 1))
    $btnBrowseProj.Size = New-Object System.Drawing.Size($browseWidth, 25)
    Set-ButtonFlatStyle -Button $btnBrowseProj
    $btnBrowseProj.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = 'Select a project folder to open with this profile (optional)'
        if ($txtProj.Text -and (Test-Path $txtProj.Text)) { $fbd.SelectedPath = $txtProj.Text }
        if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtProj.Text = $fbd.SelectedPath
        }
    })
    $dlg.Controls.Add($btnBrowseProj)

    $y += 38

    # Notes
    $lblNotes = New-Object System.Windows.Forms.Label
    $lblNotes.Text = 'Notes:'
    $lblNotes.Location = New-Object System.Drawing.Point(20, ($y + 2))
    $lblNotes.Size = New-Object System.Drawing.Size($labelWidth, 20)
    $lblNotes.ForeColor = $script:UiTextPrimary
    $dlg.Controls.Add($lblNotes)

    $txtNotes = New-Object System.Windows.Forms.TextBox
    $txtNotes.Location = New-Object System.Drawing.Point($fieldX, $y)
    $txtNotes.Size = New-Object System.Drawing.Size($fieldWidth, 23)
    if ($isEdit) { $txtNotes.Text = $Existing.Notes }
    $dlg.Controls.Add($txtNotes)

    $y += 42

    $sepHint = New-Object System.Windows.Forms.Panel
    $sepHint.Location = New-Object System.Drawing.Point(20, $y)
    $sepHint.Size = New-Object System.Drawing.Size(440, 1)
    $sepHint.BackColor = $script:UiBorderColor
    $dlg.Controls.Add($sepHint)

    $y += 12

    $lblHint = New-Object System.Windows.Forms.Label
    $lblHint.Text = "Sign in to a different Cursor account the first time this profile launches.`nTheme, fonts, and extensions are saved per profile automatically."
    $lblHint.Location = New-Object System.Drawing.Point(20, $y)
    $lblHint.Size = New-Object System.Drawing.Size(440, 36)
    $lblHint.ForeColor = $script:UiTextMuted
    $dlg.Controls.Add($lblHint)

    $y += 48

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = if ($isEdit) { 'Save' } else { 'Add' }
    $btnOk.Location = New-Object System.Drawing.Point(298, $y)
    $btnOk.Size = New-Object System.Drawing.Size(82, 30)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    Set-ButtonFlatStyle -Button $btnOk -Primary
    $dlg.Controls.Add($btnOk)
    $dlg.AcceptButton = $btnOk

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Cancel'
    $btnCancel.Location = New-Object System.Drawing.Point(388, $y)
    $btnCancel.Size = New-Object System.Drawing.Size(82, 30)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    Set-ButtonFlatStyle -Button $btnCancel
    $dlg.Controls.Add($btnCancel)
    $dlg.CancelButton = $btnCancel

    Apply-UiThemeToTextInputs -TextBoxes @($txtName, $txtDir, $txtProj, $txtNotes)

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

    $result = $dlg.ShowDialog($form)

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

Ensure-ProfilesRoot
Load-AppSettings
Set-UiThemePalette -ThemeName (Get-EffectiveUiThemeName)

$script:Profiles = Load-Profiles

$form = New-Object System.Windows.Forms.Form
$form.Text = $AppWindowTitle
$form.Size = New-Object System.Drawing.Size(860, 520)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(720, 420)
$form.Font = $script:UiFont
$form.BackColor = $script:UiBackColor
[void](Set-FormIcon -TargetForm $form)

$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$statusPanel.Height = 30
$statusPanel.BackColor = $script:UiPanelColor
$statusPanel.Padding = New-Object System.Windows.Forms.Padding(14, 0, 14, 0)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Profiles dir: $ProfilesRoot"
$lblStatus.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblStatus.ForeColor = $script:UiTextMuted
$statusPanel.Controls.Add($lblStatus)

$toolbarPanel = New-Object System.Windows.Forms.Panel
$toolbarPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$toolbarPanel.Height = 52
$toolbarPanel.BackColor = $script:UiPanelColor
$toolbarPanel.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 10)

$toolbarSep = New-Object System.Windows.Forms.Panel
$toolbarSep.Dock = [System.Windows.Forms.DockStyle]::Bottom
$toolbarSep.Height = 1
$toolbarSep.BackColor = $script:UiBorderColor

$contentPanel = New-Object System.Windows.Forms.Panel
$contentPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$contentPanel.BackColor = $script:UiBackColor
$contentPanel.Padding = New-Object System.Windows.Forms.Padding(14, 14, 14, 8)

$lblGridHint = New-Object System.Windows.Forms.Label
$lblGridHint.Text = 'Double-click a row to start a new window for that profile.'
$lblGridHint.Dock = [System.Windows.Forms.DockStyle]::Bottom
$lblGridHint.Height = 22
$lblGridHint.ForeColor = $script:UiTextMuted
$lblGridHint.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

$gridHost = New-Object System.Windows.Forms.Panel
$gridHost.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridHost.BackColor = $script:UiPanelColor
$gridHost.Padding = New-Object System.Windows.Forms.Padding(1)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = [System.Windows.Forms.DockStyle]::Fill
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
Apply-DataGridTheme -TargetGrid $grid

$gridHost.Controls.Add($grid)
$contentPanel.Controls.Add($gridHost)
$contentPanel.Controls.Add($lblGridHint)
$form.Controls.Add($contentPanel)
$form.Controls.Add($toolbarSep)
$form.Controls.Add($toolbarPanel)
$form.Controls.Add($statusPanel)

$script:GridModel = $null
$script:DefaultGridForeColor = $script:UiTextPrimary
$script:RunningGridForeColor = $script:UiRunningColor

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
    $statusColor = if ($ModelRow.IsRunning) { $script:RunningGridForeColor } else { $script:UiIdleColor }
    if ($cells['Status'].Style.ForeColor -ne $statusColor) {
        $cells['Status'].Style.ForeColor = $statusColor
    }
    if ($cells['Instances'].Style.ForeColor -ne $foreColor) {
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

    Apply-GridModelToView -Model $newModel -PreviousModel $previousModel
    $script:GridModel = $newModel
}

function Request-DeferredGridRefresh {
    $script:ProcessEventDebounceTimer.Stop()
    $script:ProcessEventDebounceTimer.Start()
}

function Get-SelectedProfile {
    if ($grid.SelectedRows.Count -eq 0) { return $null }
    $id = $grid.SelectedRows[0].Tag
    return $script:Profiles | Where-Object { $_.Id -eq $id } | Select-Object -First 1
}

function Get-ProfileFromGridRow {
    param([Parameter(Mandatory)][int]$RowIndex)

    if ($RowIndex -lt 0 -or $RowIndex -ge $grid.Rows.Count) { return $null }
    $id = $grid.Rows[$RowIndex].Tag
    if (-not $id) { return $null }
    return $script:Profiles | Where-Object { $_.Id -eq $id } | Select-Object -First 1
}

function Start-ProfileFromGridRow {
    param([Parameter(Mandatory)][int]$RowIndex)

    $profile = Get-ProfileFromGridRow -RowIndex $RowIndex
    if (-not $profile) { return $false }
    Start-CursorProfileInstance -Profile $profile
    Request-DeferredGridRefresh
    return $true
}

$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text = 'Add'
$btnAdd.Size = New-Object System.Drawing.Size(88, 32)
$btnAdd.Location = New-Object System.Drawing.Point(12, 10)
Set-ButtonFlatStyle -Button $btnAdd
$toolbarPanel.Controls.Add($btnAdd)

$btnEdit = New-Object System.Windows.Forms.Button
$btnEdit.Text = 'Edit'
$btnEdit.Size = New-Object System.Drawing.Size(88, 32)
$btnEdit.Location = New-Object System.Drawing.Point(108, 10)
Set-ButtonFlatStyle -Button $btnEdit
$toolbarPanel.Controls.Add($btnEdit)

$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text = 'Delete'
$btnDelete.Size = New-Object System.Drawing.Size(88, 32)
$btnDelete.Location = New-Object System.Drawing.Point(204, 10)
Set-ButtonFlatStyle -Button $btnDelete
$toolbarPanel.Controls.Add($btnDelete)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Refresh'
$btnRefresh.Size = New-Object System.Drawing.Size(88, 32)
$btnRefresh.Location = New-Object System.Drawing.Point(300, 10)
Set-ButtonFlatStyle -Button $btnRefresh
$toolbarPanel.Controls.Add($btnRefresh)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = $UiStartLabel
$btnStart.Size = New-Object System.Drawing.Size(112, 32)
$btnStart.Anchor = 'Top, Right'
Set-ButtonFlatStyle -Button $btnStart -Primary
$toolbarPanel.Controls.Add($btnStart)

$script:ThemeLabel = New-Object System.Windows.Forms.Label
$script:ThemeLabel.Text = 'Theme:'
$script:ThemeLabel.AutoSize = $true
$script:ThemeLabel.Anchor = 'Top, Right'
$script:ThemeLabel.ForeColor = $script:UiTextMuted
$script:ThemeLabel.BackColor = $script:UiPanelColor
$toolbarPanel.Controls.Add($script:ThemeLabel)

$script:ThemeCombo = New-Object System.Windows.Forms.ComboBox
$script:ThemeCombo.DropDownStyle = 'DropDownList'
$script:ThemeCombo.Anchor = 'Top, Right'
$script:ThemeCombo.Size = New-Object System.Drawing.Size(118, 23)
[void]$script:ThemeCombo.Items.AddRange(@('System default', 'Light', 'Dark'))
$script:ThemeCombo.SelectedIndex = Get-UiThemePreferenceIndex -Preference $script:UiThemePreference
$script:ThemeCombo.BackColor = $script:UiInputBackColor
$script:ThemeCombo.ForeColor = $script:UiInputForeColor
$script:ThemeCombo.Add_SelectedIndexChanged({
    if ($script:UiThemeComboSync) { return }
    $preference = Get-UiThemePreferenceFromIndex -Index $script:ThemeCombo.SelectedIndex
    if ($preference -eq $script:UiThemePreference) { return }
    Set-UiThemePreference -Preference $preference -Persist
})
$toolbarPanel.Controls.Add($script:ThemeCombo)

$toolbarPanel.Add_Resize({ Update-ToolbarLayout })
Update-ToolbarLayout

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
        [void](Start-ProfileFromGridRow -RowIndex $e.RowIndex)
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
$refreshTimer.Add_Tick({
    if (Test-UiSystemThemeChanged) {
        Set-UiThemePreference -Preference $script:UiThemePreference
    }
    Update-ProfileGrid
})
$refreshTimer.Start()

Start-CursorProcessWatchers -OwnerForm $form -DebounceTimer $processEventDebounce

$form.Add_FormClosing({
    $refreshTimer.Stop()
    $processEventDebounce.Stop()
    Stop-CursorProcessWatchers
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
