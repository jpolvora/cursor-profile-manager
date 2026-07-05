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
param(
    [switch]$FunctionsOnly,
    [switch]$StartMinimized
)

$ErrorActionPreference = 'Stop'

# App-Version: 2.0.10
$script:AppVersionId = '2.0.10'
$script:AppDisplayName = 'Cursor Profile Manager'
$script:CursorDownloadUrl = 'https://cursor.com/download'
$script:GridActionColumnCount = 6
$script:AgentStoryProxyProcess = $null
$script:AgentStoryUiProcess = $null
$script:btnAgentStory = $null
$script:lblAgentStoryStatus = $null
$script:lnkAgentStoryOpen = $null
$script:sepAgentStory = $null
$script:AgentStoryUiUrl = 'http://localhost:5173/'
$script:AgentStoryProxyUrl = 'http://127.0.0.1:8080'
$script:ProfileContextMarkerFile = 'cursor-profile-manager.context.json'
$script:UiShuttingDown = $false
$script:InstallRoot = $PSScriptRoot
$script:UpdateRepoId = 'jpolvora/cursor-profile-manager'
$script:UpdateBranch = 'master'
$script:UpdateManagedFiles = @(
    'cursor-profile-manager.ps1',
    'cursor-profile-manager.bat',
    'install-desktop-shortcut.ps1'
)

function Get-AppDisplayName {
    return $script:AppDisplayName
}

function Get-AppVersionId {
    return $script:AppVersionId
}

function Get-AppVersionLabel {
    param([string]$VersionId)

    if (-not $PSBoundParameters.ContainsKey('VersionId')) {
        $VersionId = Get-AppVersionId
    }
    if ([string]::IsNullOrWhiteSpace($VersionId)) {
        return ''
    }
    return "v$VersionId"
}

function Get-AppWindowTitle {
    param([string]$VersionId)

    if (-not $PSBoundParameters.ContainsKey('VersionId')) {
        $VersionId = Get-AppVersionId
    }
    $label = Get-AppVersionLabel -VersionId $VersionId
    if ([string]::IsNullOrWhiteSpace($label)) {
        return Get-AppDisplayName
    }
    return "$(Get-AppDisplayName) $label"
}

function Initialize-Win32AppFocus {
    if ('Win32AppFocus' -as [type]) { return }

    Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class Win32AppFocus {
    public const int SW_RESTORE = 9;
    public const uint WM_CLOSE = 0x0010;
    private const uint GW_OWNER = 4;
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
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
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint attachThread, uint attachToThread, bool attach);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    public static void CloseWindow(IntPtr hWnd) {
        if (hWnd != IntPtr.Zero) {
            PostMessage(hWnd, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
        }
    }
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
    public static IntPtr[] GetVisibleTopLevelWindowsForProcesses(int[] processIds) {
        var pidSet = new HashSet<uint>();
        if (processIds != null) {
            foreach (int id in processIds) {
                pidSet.Add((uint)id);
            }
        }
        var handles = new List<IntPtr>();
        EnumWindows((hWnd, lParam) => {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (!pidSet.Contains(pid)) { return true; }
            if (!IsWindowVisible(hWnd)) { return true; }
            if (GetWindow(hWnd, GW_OWNER) != IntPtr.Zero) { return true; }
            handles.Add(hWnd);
            return true;
        }, IntPtr.Zero);
        return handles.ToArray();
    }
}
'@
}

function Test-DriveRootAccessible {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $true
    }
    if ($Path -match '^([A-Za-z]:)[\\/]?') {
        return Test-Path -LiteralPath ($Matches[1] + '\')
    }
    return $true
}

function Assert-LaunchPathsReady {
    if (-not (Test-DriveRootAccessible -Path $script:InstallRoot)) {
        throw @"
Install folder drive is not available:
$($script:InstallRoot)

If you moved the repo or removed a drive, launch from cursor-profile-manager.bat in the current folder or run install-desktop-shortcut.ps1 to recreate your Desktop shortcut.
"@
    }

    if (-not (Test-DriveRootAccessible -Path $ProfilesRoot)) {
        throw @"
Profiles folder drive is not available:
$ProfilesRoot

Check CURSOR_PROFILES_DIR or reconnect the drive, then try again.
"@
    }
}
Initialize-Win32AppFocus

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
$UiGridStartLabel = "Start $([char]0x25B6)"

# ---------------------------------------------------------------------------
# UI theme
# ---------------------------------------------------------------------------

$script:UiFont = New-Object System.Drawing.Font 'Segoe UI', 9
$script:UiFontSemibold = New-Object System.Drawing.Font 'Segoe UI', 9, ([System.Drawing.FontStyle]::Bold)
$script:UiGridActionFont = New-Object System.Drawing.Font 'Segoe UI', 8
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
$script:MinimizeToTray = $false
$script:AutoStartWithWindows = $false
$script:AppOptionsCheckSync = $false
$script:TrayNotifyIcon = $null
$script:TrayMinimizeSync = $false
$script:UiExitConfirmed = $false
$script:ChkMinimizeToTray = $null
$script:ChkAutoStartWithWindows = $null

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
            WarningColor   = [System.Drawing.Color]::FromArgb(180, 95, 6)
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
            WarningColor   = [System.Drawing.Color]::FromArgb(255, 183, 77)
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
    $script:UiWarningColor = $palette.WarningColor
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
    $TargetGrid.RowTemplate.Height = 28
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

function New-GridActionButtonColumn {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()]
        [string]$HeaderText = '',
        [Parameter(Mandatory)][string]$ButtonText,
        [int]$Width = 52
    )

    $col = New-Object System.Windows.Forms.DataGridViewButtonColumn
    $col.Name = $Name
    $col.HeaderText = $HeaderText
    $col.Text = $ButtonText
    $col.UseColumnTextForButtonValue = $true
    $col.Width = $Width
    $col.MinimumWidth = $Width
    $col.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::None
    $col.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $col.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
    $col.DefaultCellStyle.Font = $script:UiGridActionFont
    $col.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding 1, 0, 1, 0
    $col.DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleCenter
    return $col
}

function Apply-GridActionColumnTheme {
    param([System.Windows.Forms.DataGridView]$TargetGrid)

    foreach ($actionName in @('ActStart', 'ActFocus', 'ActClose', 'ActFolder', 'ActEdit', 'ActDelete')) {
        if (-not $TargetGrid.Columns.Contains($actionName)) { continue }
        $col = $TargetGrid.Columns[$actionName]
        $col.DefaultCellStyle.BackColor = $script:UiPanelColor
        $col.DefaultCellStyle.ForeColor = $script:UiTextPrimary
        $col.DefaultCellStyle.SelectionBackColor = $script:UiPanelColor
        $col.DefaultCellStyle.SelectionForeColor = $script:UiTextPrimary
        $col.DefaultCellStyle.Font = $script:UiGridActionFont
    }
}

function Add-GridActionColumns {
    param([System.Windows.Forms.DataGridView]$TargetGrid)

    [void]$TargetGrid.Columns.Add((New-GridActionButtonColumn -Name 'ActStart' -HeaderText 'Actions' -ButtonText $UiGridStartLabel -Width 52))
    [void]$TargetGrid.Columns.Add((New-GridActionButtonColumn -Name 'ActFocus' -HeaderText '' -ButtonText 'Focus' -Width 46))
    [void]$TargetGrid.Columns.Add((New-GridActionButtonColumn -Name 'ActClose' -HeaderText '' -ButtonText 'Close' -Width 46))
    [void]$TargetGrid.Columns.Add((New-GridActionButtonColumn -Name 'ActFolder' -HeaderText '' -ButtonText 'Folder' -Width 48))
    [void]$TargetGrid.Columns.Add((New-GridActionButtonColumn -Name 'ActEdit' -HeaderText '' -ButtonText 'Edit' -Width 40))
    [void]$TargetGrid.Columns.Add((New-GridActionButtonColumn -Name 'ActDelete' -HeaderText '' -ButtonText 'Del' -Width 40))
    Apply-GridActionColumnTheme -TargetGrid $TargetGrid
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

function Test-IsProfileObject {
    param($Value)

    return ($null -ne $Value) -and ($null -ne $Value.PSObject.Properties['Id'])
}

function Normalize-ProfilesList {
    param([array]$Profiles)

    if ($null -eq $Profiles) {
        return @()
    }

    $flat = @()
    foreach ($entry in @($Profiles)) {
        if (Test-IsProfileObject $entry) {
            $flat += $entry
            continue
        }
        if ($null -eq $entry) { continue }
        foreach ($inner in @($entry)) {
            if (Test-IsProfileObject $inner) {
                $flat += $inner
            }
        }
    }
    return $flat
}

function Get-ProfilesList {
    return (Normalize-ProfilesList -Profiles $script:Profiles)
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
        
        $profilesList = @()
        foreach ($p in @($data)) {
            if ($null -eq $p.psobject.Properties['RunProxied']) {
                $p | Add-Member -MemberType NoteProperty -Name 'RunProxied' -Value $false -Force
            }
            $profilesList += $p
        }
        return , (Normalize-ProfilesList -Profiles $profilesList)
    }
    catch {
        Write-Warning "Failed to read profiles.json: $($_.Exception.Message)"
        return @()
    }
}

function Save-Profiles {
    param([Parameter(Mandatory)][array]$Profiles)
    Ensure-ProfilesRoot
    try {
        $Profiles | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigPath -Encoding UTF8
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to save profiles to profiles.json.`n`n$($_.Exception.Message)",
            'Save Error',
            'OK',
            'Error') | Out-Null
    }
}

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
        if ($null -ne $data.PSObject.Properties['MinimizeToTray']) {
            $script:MinimizeToTray = [bool]$data.MinimizeToTray
        }
        if ($null -ne $data.PSObject.Properties['AutoStartWithWindows']) {
            $script:AutoStartWithWindows = [bool]$data.AutoStartWithWindows
        }
    }
    catch {
        Write-Warning "Failed to read settings.json: $($_.Exception.Message)"
    }

    Sync-AppAutoStartRegistration
}

function Save-AppSettings {
    Ensure-ProfilesRoot
    $settings = [PSCustomObject]@{
        Theme                 = $script:UiThemePreference
        MinimizeToTray        = [bool]$script:MinimizeToTray
        AutoStartWithWindows  = [bool]$script:AutoStartWithWindows
    }
    try {
        $settings | ConvertTo-Json -Depth 3 | Set-Content -Path $SettingsPath -Encoding UTF8
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to save settings.json.`n`n$($_.Exception.Message)",
            'Save Error',
            'OK',
            'Error') | Out-Null
    }
}

function Get-AppAutoStartRegistryPath {
    return 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
}

function Get-AppAutoStartValueName {
    return 'CursorProfileManager'
}

function Get-AppLaunchArguments {
    param([switch]$ForAutoStart)

    $scriptPath = Join-Path $script:InstallRoot 'cursor-profile-manager.ps1'
    $parts = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-File', "`"$scriptPath`""
    )
    if ($ForAutoStart -and $script:MinimizeToTray) {
        $parts += '-StartMinimized'
    }
    return ($parts -join ' ')
}

function Test-AppAutoStartEnabled {
    $regPath = Get-AppAutoStartRegistryPath
    $valueName = Get-AppAutoStartValueName
    try {
        $current = Get-ItemProperty -Path $regPath -Name $valueName -ErrorAction Stop
        return ($null -ne $current.$valueName)
    }
    catch {
        return $false
    }
}

function Sync-AppAutoStartRegistration {
    $shouldRun = [bool]$script:AutoStartWithWindows
    $isRegistered = Test-AppAutoStartEnabled
    if ($shouldRun -eq $isRegistered) {
        if ($shouldRun) {
            Set-AppAutoStartEnabled -Enabled $true
        }
        return
    }
    Set-AppAutoStartEnabled -Enabled $shouldRun
}

function Set-AppAutoStartEnabled {
    param([bool]$Enabled)

    $regPath = Get-AppAutoStartRegistryPath
    $valueName = Get-AppAutoStartValueName
    if ($Enabled) {
        $target = (Get-Command powershell.exe).Source
        $arguments = Get-AppLaunchArguments -ForAutoStart
        Set-ItemProperty -Path $regPath -Name $valueName -Value "`"$target`" $arguments"
    }
    else {
        Remove-ItemProperty -Path $regPath -Name $valueName -ErrorAction SilentlyContinue
    }
}

function Test-AppExitConfirmationRequired {
    return (Test-AgentStoryProxyRunning)
}

function Confirm-AppExitIfNeeded {
    if (-not (Test-AppExitConfirmationRequired)) {
        return $true
    }

    $result = [System.Windows.Forms.MessageBox]::Show(
        "The Agent Story proxy is running.`n`nExit anyway? Closing the manager stops the proxy and dashboard.",
        (Get-AppDisplayName),
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Hide-MainWindowToTray {
    if (-not $form) { return }

    Initialize-AppTrayIcon
    $script:TrayMinimizeSync = $true
    try {
        $form.Hide()
        $form.ShowInTaskbar = $false
        if ($script:TrayNotifyIcon) {
            $script:TrayNotifyIcon.Visible = $true
            $script:TrayNotifyIcon.ShowBalloonTip(
                3000,
                (Get-AppDisplayName),
                'Running in the notification area.',
                [System.Windows.Forms.ToolTipIcon]::Info
            ) | Out-Null
        }
    }
    finally {
        $script:TrayMinimizeSync = $false
    }
}

function Show-MainWindowFromTray {
    if (-not $form) { return }

    $form.ShowInTaskbar = $true
    $form.Show()
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $form.Activate()
    if ($script:TrayNotifyIcon) {
        $script:TrayNotifyIcon.Visible = $false
    }
}

function Initialize-AppTrayIcon {
    if ($script:TrayNotifyIcon) { return }

    $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $cursorPath = Find-CursorExecutable
    if ($cursorPath) {
        $notifyIcon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($cursorPath)
    }
    elseif ($form -and $form.Icon) {
        $notifyIcon.Icon = $form.Icon
    }
    $notifyIcon.Text = Get-AppWindowTitle
    $notifyIcon.Visible = $false

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $showItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $showItem.Text = 'Show'
    $showItem.Add_Click({ Show-MainWindowFromTray })
    $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $exitItem.Text = 'Exit'
    $exitItem.Add_Click({
        if (-not (Confirm-AppExitIfNeeded)) { return }
        $script:UiExitConfirmed = $true
        if ($form) { $form.Close() }
    })
    [void]$menu.Items.Add($showItem)
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$menu.Items.Add($exitItem)
    $notifyIcon.ContextMenuStrip = $menu
    $notifyIcon.Add_DoubleClick({ Show-MainWindowFromTray })

    $script:TrayNotifyIcon = $notifyIcon
}

function Sync-AppOptionsCheckboxes {
    if (-not $script:ChkMinimizeToTray -and -not $script:ChkAutoStartWithWindows) { return }

    $script:AppOptionsCheckSync = $true
    try {
        if ($script:ChkMinimizeToTray) {
            $script:ChkMinimizeToTray.Checked = [bool]$script:MinimizeToTray
        }
        if ($script:ChkAutoStartWithWindows) {
            $script:ChkAutoStartWithWindows.Checked = [bool]$script:AutoStartWithWindows
        }
    }
    finally {
        $script:AppOptionsCheckSync = $false
    }
}

function Set-AppMinimizeToTrayPreference {
    param(
        [bool]$Enabled,
        [switch]$Persist
    )

    $script:MinimizeToTray = $Enabled
    Sync-AppOptionsCheckboxes

    if ($script:AutoStartWithWindows) {
        Set-AppAutoStartEnabled -Enabled $true
    }

    if ($Persist) {
        Save-AppSettings
    }
}

function Set-AppAutoStartPreference {
    param(
        [bool]$Enabled,
        [switch]$Persist
    )

    $script:AutoStartWithWindows = $Enabled
    Set-AppAutoStartEnabled -Enabled $Enabled
    Sync-AppOptionsCheckboxes

    if ($Persist) {
        Save-AppSettings
    }
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

function New-ToolbarButton {
    param(
        [Parameter(Mandatory)][string]$Text,
        [switch]$Primary,
        [int]$Width = 0
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $buttonWidth = if ($Width -gt 0) { $Width } elseif ($Primary) { 108 } else { 82 }
    $btn.Size = New-Object System.Drawing.Size($buttonWidth, 30)
    $btn.Margin = New-Object System.Windows.Forms.Padding 0, 0, 8, 0
    $btn.AutoSize = $false
    if ($Primary) {
        Set-ButtonFlatStyle -Button $btn -Primary
    }
    else {
        Set-ButtonFlatStyle -Button $btn
    }
    return $btn
}

function New-ToolbarFlowSeparator {
    $sep = New-Object System.Windows.Forms.Panel
    $sep.Width = 1
    $sep.Height = 22
    $sep.Margin = New-Object System.Windows.Forms.Padding 6, 4, 14, 4
    $sep.BackColor = $script:UiBorderColor
    return $sep
}

function New-ToolbarSectionLabel {
    param([Parameter(Mandatory)][string]$Text)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $false
    $label.Width = 58
    $label.Height = 30
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $label.ForeColor = $script:UiTextMuted
    $label.BackColor = $script:UiPanelColor
    $label.Font = $script:UiFont
    $label.Margin = New-Object System.Windows.Forms.Padding 0, 0, 4, 0
    return $label
}

function Apply-ToolbarTheme {
    if (-not $toolbarPanel) { return }

    $toolbarPanel.BackColor = $script:UiPanelColor
    if ($script:ToolbarTable) {
        $script:ToolbarTable.BackColor = $script:UiPanelColor
    }
    if ($script:LblProfilesSection) {
        $script:LblProfilesSection.ForeColor = $script:UiTextMuted
        $script:LblProfilesSection.BackColor = $script:UiPanelColor
    }
    if ($script:LblLaunchHint) {
        $script:LblLaunchHint.ForeColor = $script:UiTextMuted
        $script:LblLaunchHint.BackColor = $script:UiPanelColor
    }
    if ($script:ProfileFlow) {
        $script:ProfileFlow.BackColor = $script:UiPanelColor
    }
    if ($script:ThemeFlow) {
        $script:ThemeFlow.BackColor = $script:UiPanelColor
    }
    if ($script:LaunchTable) {
        $script:LaunchTable.BackColor = $script:UiPanelColor
    }
    if ($script:ProfileTable) {
        $script:ProfileTable.BackColor = $script:UiPanelColor
    }

    if ($btnAdd) {
        Update-ToolbarButtonTheme -Button $btnAdd
        Update-ToolbarButtonTheme -Button $btnRefresh
    }

    if ($script:btnAgentStory) {
        Update-ToolbarButtonTheme -Button $script:btnAgentStory
    }
    if ($script:lblAgentStoryStatus) {
        $script:lblAgentStoryStatus.BackColor = $script:UiPanelColor
    }
    if ($script:lnkAgentStoryOpen) {
        $script:lnkAgentStoryOpen.BackColor = $script:UiPanelColor
        $script:lnkAgentStoryOpen.LinkColor = $script:UiAccent
        $script:lnkAgentStoryOpen.ActiveLinkColor = $script:UiAccentHover
        $script:lnkAgentStoryOpen.VisitedLinkColor = $script:UiAccent
        Set-AgentStoryOpenLinkDisplay
    }
    if ($script:sepAgentStory) {
        $script:sepAgentStory.BackColor = $script:UiBorderColor
    }

    if ($script:ThemeLabel) {
        $script:ThemeLabel.ForeColor = $script:UiTextMuted
        $script:ThemeLabel.BackColor = $script:UiPanelColor
    }
    if ($script:ThemeCombo) {
        $script:ThemeCombo.BackColor = $script:UiInputBackColor
        $script:ThemeCombo.ForeColor = $script:UiInputForeColor
    }
    if ($script:ChkMinimizeToTray) {
        $script:ChkMinimizeToTray.ForeColor = $script:UiTextPrimary
        $script:ChkMinimizeToTray.BackColor = $script:UiPanelColor
    }
    if ($script:ChkAutoStartWithWindows) {
        $script:ChkAutoStartWithWindows.ForeColor = $script:UiTextPrimary
        $script:ChkAutoStartWithWindows.BackColor = $script:UiPanelColor
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

        $gridHost.BackColor = $script:UiPanelColor
        Apply-DataGridTheme -TargetGrid $grid
        Apply-GridActionColumnTheme -TargetGrid $grid

        Apply-ToolbarTheme

        if ($script:CheckUpdateLink) {
            $script:CheckUpdateLink.ForeColor = $script:UiTextMuted
            $script:CheckUpdateLink.LinkColor = $script:UiAccent
            $script:CheckUpdateLink.ActiveLinkColor = $script:UiAccentHover
            $script:CheckUpdateLink.VisitedLinkColor = $script:UiAccent
            $script:CheckUpdateLink.BackColor = $script:UiPanelColor
            Set-CheckUpdateLinkDisplay
        }

        if ($script:CursorInstallLink) {
            $script:CursorInstallLink.BackColor = $script:UiPanelColor
            $script:CursorInstallLink.ActiveLinkColor = $script:UiAccentHover
            $script:CursorInstallLink.VisitedLinkColor = $script:UiAccent
            Set-CursorInstallLinkDisplay
        }

        Sync-UiThemeComboSelection
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
# In-app update (GitHub)
# ---------------------------------------------------------------------------

function Get-AppVersionIdFromScriptContent {
    param([string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) { return $null }
    if ($Content -match '(?m)^\s*#\s*App-Version:\s*(\S+)') {
        return $Matches[1].Trim()
    }
    if ($Content -match '\$script:AppVersionId\s*=\s*''([^'']+)''') {
        return $Matches[1].Trim()
    }
    return $null
}

function ConvertTo-AppVersionNumbers {
    param([string]$VersionId)

    if ([string]::IsNullOrWhiteSpace($VersionId)) { return $null }
    $parts = $VersionId.Trim().Split('.')
    $numbers = @()
    foreach ($part in $parts) {
        $segment = $part.Trim()
        if ($segment -notmatch '^\d+$') {
            return $null
        }
        $numbers += [int]$segment
    }
    if ($numbers.Count -eq 0) { return $null }
    return , $numbers
}

function Compare-AppVersionId {
    param(
        [string]$Left,
        [string]$Right
    )

    $leftNumbers = ConvertTo-AppVersionNumbers -VersionId $Left
    $rightNumbers = ConvertTo-AppVersionNumbers -VersionId $Right
    if ($null -eq $leftNumbers -or $null -eq $rightNumbers) {
        return $null
    }

    $maxLength = [Math]::Max($leftNumbers.Length, $rightNumbers.Length)
    for ($i = 0; $i -lt $maxLength; $i++) {
        $leftValue = if ($i -lt $leftNumbers.Length) { $leftNumbers[$i] } else { 0 }
        $rightValue = if ($i -lt $rightNumbers.Length) { $rightNumbers[$i] } else { 0 }
        if ($leftValue -lt $rightValue) { return -1 }
        if ($leftValue -gt $rightValue) { return 1 }
    }
    return 0
}

function Get-AppVersionUpdateStatus {
    param(
        [string]$LocalVersion,
        [string]$RemoteVersion
    )

    $localMissing = [string]::IsNullOrWhiteSpace($LocalVersion)
    $remoteMissing = [string]::IsNullOrWhiteSpace($RemoteVersion)
    $localDisplay = if ($localMissing) { '(none)' } else { $LocalVersion }
    $remoteDisplay = if ($remoteMissing) { '(none)' } else { $RemoteVersion }

    if ($localMissing -or $remoteMissing) {
        $reason = if ($localMissing -and $remoteMissing) {
            'No App-Version marker was found locally or on GitHub. The install is treated as outdated.'
        }
        elseif ($localMissing) {
            'No App-Version marker was found in your local copy. The install is treated as outdated.'
        }
        else {
            'No App-Version marker was found on GitHub. The install is treated as outdated.'
        }
        return [PSCustomObject]@{
            NeedsUpdate    = $true
            CanForceUpdate = $false
            LocalVersion   = $localDisplay
            RemoteVersion  = $remoteDisplay
            Reason         = $reason
        }
    }

    $comparison = Compare-AppVersionId -Left $LocalVersion -Right $RemoteVersion
    if ($null -eq $comparison) {
        return [PSCustomObject]@{
            NeedsUpdate    = $true
            CanForceUpdate = $false
            LocalVersion   = $localDisplay
            RemoteVersion  = $remoteDisplay
            Reason         = 'Version markers exist but could not be compared. The install is treated as outdated.'
        }
    }

    if ($comparison -lt 0) {
        return [PSCustomObject]@{
            NeedsUpdate    = $true
            CanForceUpdate = $false
            LocalVersion   = $localDisplay
            RemoteVersion  = $remoteDisplay
            Reason         = "A newer release is available ($RemoteVersion > $LocalVersion)."
        }
    }

    if ($comparison -eq 0) {
        return [PSCustomObject]@{
            NeedsUpdate    = $false
            CanForceUpdate = $true
            LocalVersion   = $localDisplay
            RemoteVersion  = $remoteDisplay
            Reason         = "You already have version $LocalVersion."
        }
    }

    return [PSCustomObject]@{
        NeedsUpdate    = $false
        CanForceUpdate = $true
        LocalVersion   = $localDisplay
        RemoteVersion  = $remoteDisplay
        Reason         = "Your local copy ($LocalVersion) is newer than GitHub ($RemoteVersion)."
    }
}

function Get-RemoteUpdateRawUrl {
    param([Parameter(Mandatory)][string]$FileName)

    return "https://raw.githubusercontent.com/$($script:UpdateRepoId)/$($script:UpdateBranch)/$FileName"
}

function Get-RemoteUpdateFileContent {
    param([Parameter(Mandatory)][string]$FileName)

    $url = Get-RemoteUpdateRawUrl -FileName $FileName
    $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'CursorProfileManager-Update')
        return $wc.DownloadString($url)
    }
    finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
    }
}

function Set-CheckUpdateLinkDisplay {
    if (-not $script:CheckUpdateLink) { return }

    $versionText = "$(Get-AppVersionLabel)  "
    $linkText = 'Check for updates'
    $script:CheckUpdateLink.Text = $versionText + $linkText
    $script:CheckUpdateLink.Links.Clear()
    [void]$script:CheckUpdateLink.Links.Add($versionText.Length, $linkText.Length)
}

function Get-RemoteManagedUpdateFiles {
    param([string]$MainScriptContent)

    $remoteFiles = @{}
    foreach ($fileName in $script:UpdateManagedFiles) {
        if ($fileName -eq 'cursor-profile-manager.ps1' -and -not [string]::IsNullOrWhiteSpace($MainScriptContent)) {
            $remoteFiles[$fileName] = $MainScriptContent
            continue
        }
        $remoteFiles[$fileName] = Get-RemoteUpdateFileContent -FileName $fileName
    }
    return $remoteFiles
}

function Save-UpdateStagingFiles {
    param(
        [Parameter(Mandatory)][hashtable]$FilesByName,
        [Parameter(Mandatory)][string]$StagingDir
    )

    if (Test-Path $StagingDir) {
        Remove-Item -Path $StagingDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null

    foreach ($name in $FilesByName.Keys) {
        $dest = Join-Path $StagingDir $name
        $content = [string]$FilesByName[$name]
        if ($name -like '*.bat') {
            [System.IO.File]::WriteAllText($dest, $content, [System.Text.Encoding]::ASCII)
        }
        else {
            $utf8Bom = New-Object System.Text.UTF8Encoding $true
            [System.IO.File]::WriteAllText($dest, $content, $utf8Bom)
        }
    }
}

function Start-DeferredAppUpdate {
    param([Parameter(Mandatory)][string]$StagingDir)

    $updaterPath = Join-Path $script:InstallRoot 'apply-profile-manager-update.ps1'
    $updaterContent = @'
#Requires -Version 5.1
param(
    [Parameter(Mandatory)][int]$ParentPid,
    [Parameter(Mandatory)][string]$StagingDir,
    [Parameter(Mandatory)][string]$InstallDir
)
$ErrorActionPreference = 'Stop'
$files = @(
    'cursor-profile-manager.ps1',
    'cursor-profile-manager.bat',
    'install-desktop-shortcut.ps1'
)
while (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) {
    Start-Sleep -Milliseconds 200
}
foreach ($name in $files) {
    $src = Join-Path $StagingDir $name
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination (Join-Path $InstallDir $name) -Force
    }
}
Remove-Item -Path $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
$selfPath = $MyInvocation.MyCommand.Path
Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
    '-File', (Join-Path $InstallDir 'cursor-profile-manager.ps1')
)
Start-Sleep -Milliseconds 500
Remove-Item -Path $selfPath -Force -ErrorAction SilentlyContinue
'@

    $utf8Bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($updaterPath, $updaterContent, $utf8Bom)

    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', $updaterPath,
        '-ParentPid', ([string]$PID),
        '-StagingDir', $StagingDir,
        '-InstallDir', $script:InstallRoot
    )

    $form.Close()
}

function Confirm-AppUpdateApply {
    param(
        [Parameter(Mandatory)][PSCustomObject]$UpdateStatus
    )

    $message = @(
        $UpdateStatus.Reason
        ''
        "Local version:  $($UpdateStatus.LocalVersion)"
        "GitHub version: $($UpdateStatus.RemoteVersion)"
        ''
        'Apply update now? The manager will close and restart. Desktop shortcuts and the .bat launcher keep working because files are overwritten in place.'
    ) -join [Environment]::NewLine

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        $message,
        'Apply update',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    return ($confirm -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Invoke-CheckForAppUpdate {
    if ([string]::IsNullOrWhiteSpace($script:InstallRoot) -or -not (Test-Path $script:InstallRoot)) {
        throw 'Could not determine the install folder for this copy of the Profile Manager.'
    }

    $stagingDir = Join-Path $script:InstallRoot '.update-staging'
    $remoteMainScript = Get-RemoteUpdateFileContent -FileName 'cursor-profile-manager.ps1'
    $remoteVersion = Get-AppVersionIdFromScriptContent -Content $remoteMainScript
    $localVersion = $script:AppVersionId
    $updateStatus = Get-AppVersionUpdateStatus -LocalVersion $localVersion -RemoteVersion $remoteVersion

    if (-not $updateStatus.NeedsUpdate) {
        $force = [System.Windows.Forms.MessageBox]::Show(
            @(
                $updateStatus.Reason
                ''
                "Local version:  $($updateStatus.LocalVersion)"
                "GitHub version: $($updateStatus.RemoteVersion)"
                ''
                'Force reinstall from GitHub anyway? This overwrites your local copy even though GitHub is not newer.'
            ) -join [Environment]::NewLine,
            'No updates',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($force -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }
    }
    elseif (-not (Confirm-AppUpdateApply -UpdateStatus $updateStatus)) {
        return
    }

    $remoteFiles = Get-RemoteManagedUpdateFiles -MainScriptContent $remoteMainScript
    Save-UpdateStagingFiles -FilesByName $remoteFiles -StagingDir $stagingDir
    Start-DeferredAppUpdate -StagingDir $stagingDir
}

# ---------------------------------------------------------------------------
# Agent Story integration helpers
# ---------------------------------------------------------------------------

function Find-AgentStoryRoot {
    if ($env:AGENT_STORY_DIR -and (Test-Path $env:AGENT_STORY_DIR)) {
        return (Resolve-Path $env:AGENT_STORY_DIR).Path
    }
    if ([string]::IsNullOrWhiteSpace($script:InstallRoot)) {
        return $null
    }
    $embedded = Join-Path $script:InstallRoot 'agent-story'
    if (Test-Path $embedded) {
        return (Resolve-Path $embedded).Path
    }
    return $null
}

function Test-TcpPortInUse {
    param(
        [Parameter(Mandatory)][int]$Port
    )

    foreach ($address in @([System.Net.IPAddress]::Loopback, [System.Net.IPAddress]::IPv6Loopback)) {
        $listener = $null
        try {
            $listener = New-Object System.Net.Sockets.TcpListener($address, $Port)
            $listener.Start()
        }
        catch {
            return $true
        }
        finally {
            if ($listener) {
                try { $listener.Stop() } catch { }
            }
        }
    }

    return $false
}

function Get-AgentStoryBlockedPorts {
    $blocked = @()
    foreach ($port in @(8080, 3001, 5173)) {
        if (Test-TcpPortInUse -Port $port) {
            $blocked += $port
        }
    }
    return , $blocked
}

function Test-AgentStoryProcessAlive {
    param(
        [System.Diagnostics.Process]$Process
    )

    if (-not $Process) { return $false }
    try {
        return -not $Process.HasExited
    }
    catch {
        return $false
    }
}

function Test-AgentStoryServicePortListening {
    param(
        [Parameter(Mandatory)][int]$Port
    )

    return ((Get-ListenerProcessIdsForPort -Port $Port).Count -gt 0)
}

function Resolve-AgentStoryRunState {
    param(
        [bool]$ProxyProcessAlive = (Test-AgentStoryProcessAlive -Process $script:AgentStoryProxyProcess),
        [bool]$UiProcessAlive = (Test-AgentStoryProcessAlive -Process $script:AgentStoryUiProcess),
        [bool]$ProxyPort8080 = (Test-AgentStoryServicePortListening -Port 8080),
        [bool]$ApiPort3001 = (Test-AgentStoryServicePortListening -Port 3001),
        [bool]$UiPort5173 = (Test-AgentStoryServicePortListening -Port 5173)
    )

    $proxyUp = $ProxyProcessAlive -or ($ProxyPort8080 -and $ApiPort3001)
    $uiUp = $UiProcessAlive -or $UiPort5173
    $anyPort = $ProxyPort8080 -or $ApiPort3001 -or $UiPort5173

    if ($proxyUp -and $uiUp) {
        return 'Running'
    }
    if ($ProxyProcessAlive -or $UiProcessAlive -or $anyPort) {
        return 'Partial'
    }
    return 'Stopped'
}

function Test-AgentStoryAnyRunning {
    return (Resolve-AgentStoryRunState) -ne 'Stopped'
}

function Test-AgentStoryProxyRunning {
    if (Test-AgentStoryServicePortListening -Port 8080) {
        return $true
    }
    if (Test-AgentStoryProcessAlive -Process $script:AgentStoryProxyProcess) {
        return (Test-AgentStoryServicePortListening -Port 8080)
    }
    return $false
}

function Get-CursorProxyUrl {
    if ($env:AGENT_STORY_PROXY_URL -and -not [string]::IsNullOrWhiteSpace($env:AGENT_STORY_PROXY_URL)) {
        return $env:AGENT_STORY_PROXY_URL.Trim()
    }
    return $script:AgentStoryProxyUrl
}

function Get-CursorProxyLaunchArgs {
    param(
        [bool]$UseProxy
    )

    if (-not $UseProxy) {
        return @()
    }
    $proxyUrl = Get-CursorProxyUrl
    return @(
        "--proxy-server=$proxyUrl",
        '--ignore-certificate-errors'
    )
}

function Get-CursorProxyEnvironmentVariables {
    param(
        [bool]$UseProxy
    )

    if (-not $UseProxy) {
        return @{}
    }

    $proxyUrl = Get-CursorProxyUrl
    return @{
        HTTP_PROXY                   = $proxyUrl
        HTTPS_PROXY                  = $proxyUrl
        NO_PROXY                     = 'localhost,127.0.0.1'
        NODE_TLS_REJECT_UNAUTHORIZED = '0'
    }
}

function Get-CursorProfileContextMarkerPath {
    param(
        [Parameter(Mandatory)][string]$UserDataDir
    )

    return Join-Path $UserDataDir $script:ProfileContextMarkerFile
}

function Write-CursorProfileContextMarker {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Profile,
        [int]$MainProcessId = 0
    )

    if (-not (Test-Path $Profile.UserDataDir)) {
        New-Item -ItemType Directory -Path $Profile.UserDataDir -Force | Out-Null
    }

    $marker = @{
        profileId     = $Profile.Id
        profileName   = $Profile.Name
        userDataDir   = $Profile.UserDataDir
        projectPath   = if ($Profile.ProjectPath) { $Profile.ProjectPath } else { $null }
        mainProcessId = if ($MainProcessId -gt 0) { $MainProcessId } else { $null }
        registeredAt  = (Get-Date).ToString('o')
        managerVersion = Get-AppVersionId
    }

    $markerPath = Get-CursorProfileContextMarkerPath -UserDataDir $Profile.UserDataDir
    $json = $marker | ConvertTo-Json -Depth 4
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($markerPath, $json, $utf8NoBom)
}

function Get-CursorProfileIdentityEnvironmentVariables {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Profile
    )

    $projectPath = if ($Profile.ProjectPath) { $Profile.ProjectPath } else { '' }
    return @{
        CURSOR_PROFILE_MANAGER_ID              = $Profile.Id
        CURSOR_PROFILE_MANAGER_NAME            = $Profile.Name
        CURSOR_PROFILE_MANAGER_USER_DATA_DIR   = $Profile.UserDataDir
        CURSOR_PROFILE_MANAGER_PROJECT_PATH    = $projectPath
    }
}

function Register-CursorProfileWithAgentStory {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Profile,
        [int]$MainProcessId = 0
    )

    if (-not (Test-AgentStoryServicePortListening -Port 3001)) {
        return
    }

    $body = @{
        profileId       = $Profile.Id
        profileName     = $Profile.Name
        userDataDir     = $Profile.UserDataDir
        projectPath     = if ($Profile.ProjectPath) { $Profile.ProjectPath } else { $null }
        mainProcessId   = if ($MainProcessId -gt 0) { $MainProcessId } else { $null }
    } | ConvertTo-Json -Depth 4

    try {
        Invoke-RestMethod -Uri 'http://127.0.0.1:3001/api/profile-sessions/register' `
            -Method Post -Body $body -ContentType 'application/json; charset=utf-8' -TimeoutSec 3 | Out-Null
    }
    catch {
        Write-Warning "Agent Story profile registration failed: $($_.Exception.Message)"
    }
}

function Merge-Hashtables {
    param(
        [hashtable[]]$Tables
    )

    $merged = @{}
    foreach ($table in $Tables) {
        if ($null -eq $table) { continue }
        foreach ($key in $table.Keys) {
            $merged[$key] = $table[$key]
        }
    }
    return $merged
}

function Start-CursorProfileProcess {
    param(
        [Parameter(Mandatory)][string]$ExecutablePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [hashtable]$Environment = @{},
        [Parameter(Mandatory)][PSCustomObject]$Profile,
        [bool]$RegisterProfile = $true
    )

    $proc = Invoke-ProcessWithEnvironment -FilePath $ExecutablePath -ArgumentList $ArgumentList -Environment $Environment -PassThru
    if ($RegisterProfile -and $proc -and -not $proc.HasExited) {
        Write-CursorProfileContextMarker -Profile $Profile -MainProcessId $proc.Id
        Register-CursorProfileWithAgentStory -Profile $Profile -MainProcessId $proc.Id
    }
    return $proc
}

function Get-CursorProfileUserSettingsPath {
    param(
        [Parameter(Mandatory)][string]$UserDataDir
    )

    return Join-Path (Join-Path $UserDataDir 'User') 'settings.json'
}

function Read-JsonObjectHashtableFromFile {
    param(
        [string]$Path
    )

    if (-not $Path -or -not (Test-Path $Path)) {
        return @{}
    }

    try {
        $raw = Get-Content -Raw -Path $Path -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return @{}
        }

        $obj = $raw | ConvertFrom-Json
        if ($null -eq $obj) {
            return @{}
        }

        $hash = @{}
        foreach ($prop in $obj.PSObject.Properties) {
            $hash[$prop.Name] = $prop.Value
        }
        return $hash
    }
    catch {
        Write-Warning "Failed to read JSON settings from $Path : $($_.Exception.Message)"
        return @{}
    }
}

function Write-JsonObjectHashtableToFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Data
    )

    $json = $Data | ConvertTo-Json -Depth 20
    Set-Content -Path $Path -Value $json -Encoding UTF8
}

function Update-CursorProfileProxySettings {
    param(
        [Parameter(Mandatory)][string]$UserDataDir,
        [bool]$EnableProxy
    )

    $userDir = Join-Path $UserDataDir 'User'
    if (-not (Test-Path $userDir)) {
        New-Item -ItemType Directory -Path $userDir -Force | Out-Null
    }

    $settingsPath = Get-CursorProfileUserSettingsPath -UserDataDir $UserDataDir

    if (-not (Test-Path $settingsPath)) {
        if (-not $EnableProxy) {
            return
        }

        Write-JsonObjectHashtableToFile -Path $settingsPath -Data @{
            'http.proxy'           = Get-CursorProxyUrl
            'http.proxyStrictSSL'  = $false
        }
        return
    }

    try {
        $raw = Get-Content -Raw -Path $settingsPath -Encoding UTF8 -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $null = $raw | ConvertFrom-Json -ErrorAction Stop
        }
    }
    catch {
        Write-Warning "Skipping proxy settings update for $settingsPath : settings.json is not valid JSON ($($_.Exception.Message))"
        return
    }

    $settings = Read-JsonObjectHashtableFromFile -Path $settingsPath

    if ($EnableProxy) {
        $settings['http.proxy'] = Get-CursorProxyUrl
        $settings['http.proxyStrictSSL'] = $false
    }
    else {
        if ($settings.ContainsKey('http.proxy')) {
            $settings.Remove('http.proxy')
        }
        if ($settings.ContainsKey('http.proxyStrictSSL')) {
            $settings.Remove('http.proxyStrictSSL')
        }
    }

    Write-JsonObjectHashtableToFile -Path $settingsPath -Data $settings
}

function Invoke-ProcessWithEnvironment {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [hashtable]$Environment = @{},
        [switch]$PassThru
    )

    if ($Environment.Count -eq 0) {
        if ($PassThru) {
            return Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru
        }
        Start-Process -FilePath $FilePath -ArgumentList $ArgumentList
        return
    }

    $backup = @{}
    try {
        foreach ($key in $Environment.Keys) {
            $backup[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
            [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], 'Process')
        }
        if ($PassThru) {
            return Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru
        }
        Start-Process -FilePath $FilePath -ArgumentList $ArgumentList
    }
    finally {
        foreach ($key in $backup.Keys) {
            if ([string]::IsNullOrEmpty($backup[$key])) {
                [Environment]::SetEnvironmentVariable($key, $null, 'Process')
            }
            else {
                [Environment]::SetEnvironmentVariable($key, $backup[$key], 'Process')
            }
        }
    }
}

function Get-NpmExecutablePath {
    $npmCmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($npmCmd) {
        return $npmCmd.Source
    }

    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if ($npmCmd) {
        return $npmCmd.Source
    }

    return $null
}

function Show-AgentStoryStartFailure {
    param(
        [Parameter(Mandatory)][string]$Message
    )

    if ($script:btnAgentStory) {
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            'Agent Story Start Failed',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    else {
        Write-Warning $Message
    }
}

function Wait-AgentStoryProcessesHealthy {
    param(
        [int]$TimeoutMs = 15000
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        $proxyAlive = Test-AgentStoryProcessAlive -Process $script:AgentStoryProxyProcess
        $uiAlive = Test-AgentStoryProcessAlive -Process $script:AgentStoryUiProcess
        $proxyPort = Test-AgentStoryServicePortListening -Port 8080
        $apiPort = Test-AgentStoryServicePortListening -Port 3001
        $uiPort = Test-AgentStoryServicePortListening -Port 5173

        if ($proxyAlive -and $uiAlive -and $proxyPort -and $apiPort -and $uiPort) {
            return $true
        }

        if (-not $proxyAlive -or -not $uiAlive) {
            return $false
        }

        Start-Sleep -Milliseconds 250
    }

    return $false
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

function Register-RunningProxiedProfilesWithAgentStory {
    if (-not (Test-AgentStoryServicePortListening -Port 3001)) {
        return
    }

    $instanceCounts = Get-UserDataDirInstanceCounts
    foreach ($profile in Get-ProfilesList) {
        if (-not $profile.RunProxied) { continue }

        $instanceCount = Get-ProfileInstanceCount -UserDataDir $profile.UserDataDir -InstanceCounts $instanceCounts
        if ($instanceCount -le 0) { continue }

        $mainPid = 0
        $procs = @(Get-CimInstance Win32_Process -Filter "name='Cursor.exe'" -ErrorAction SilentlyContinue)
        foreach ($proc in $procs) {
            $dir = Get-NormalizedUserDataDirFromCommandLine -CommandLine $proc.CommandLine
            if ($dir -ne $profile.UserDataDir.TrimEnd('\', '/').ToLowerInvariant()) { continue }
            if ($proc.CommandLine -match '--type=') { continue }
            $mainPid = [int]$proc.ProcessId
            break
        }

        Write-CursorProfileContextMarker -Profile $profile -MainProcessId $mainPid
        Register-CursorProfileWithAgentStory -Profile $profile -MainProcessId $mainPid
    }
}

function Start-AgentStoryProxy {
    $runState = Resolve-AgentStoryRunState
    if ($runState -eq 'Running') {
        Update-AgentStoryUiState
        return $true
    }
    if ($runState -eq 'Partial') {
        Stop-AgentStory
        Start-Sleep -Milliseconds 500
    }

    foreach ($port in @(8080, 3001, 5173)) {
        Stop-ListenerProcessesForPort -Port $port
    }
    Start-Sleep -Milliseconds 300

    $root = Find-AgentStoryRoot
    if (-not $root) {
        Show-AgentStoryStartFailure -Message "Agent Story directory not found. Expected agent-story\ under the manager install folder, or set AGENT_STORY_DIR to override."
        return $false
    }

    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    $npmPath = Get-NpmExecutablePath
    if (-not $nodeCmd -or -not $npmPath) {
        Show-AgentStoryStartFailure -Message "Node.js and npm are required to run Agent Story. Please install them and make sure they are on your PATH."
        return $false
    }

    $blockedPorts = Get-AgentStoryBlockedPorts
    if ($blockedPorts.Count -gt 0) {
        $portList = ($blockedPorts -join ', ')
        Show-AgentStoryStartFailure -Message "Agent Story ports are already in use: $portList.`n`nStop any running Agent Story instance, close orphaned Node/Vite processes, or click Stop Agent Story if the manager still shows it as running."
        return $false
    }

    $serverDir = Join-Path $root 'server'
    $uiDir = Join-Path $root 'ui'

    if (-not (Ensure-NodeDependencies -Dir $serverDir -Name 'Server')) { return $false }
    if (-not (Ensure-NodeDependencies -Dir $uiDir -Name 'UI')) { return $false }

    try {
        $serverPsi = New-Object System.Diagnostics.ProcessStartInfo
        $serverPsi.FileName = $nodeCmd.Source
        $serverPsi.Arguments = 'index.js'
        $serverPsi.WorkingDirectory = $serverDir
        $serverPsi.CreateNoWindow = $true
        $serverPsi.UseShellExecute = $false
        $script:AgentStoryProxyProcess = [System.Diagnostics.Process]::Start($serverPsi)
    }
    catch {
        Show-AgentStoryStartFailure -Message "Failed to start Agent Story proxy server: $($_.Exception.Message)"
        return $false
    }

    try {
        $viteScript = Join-Path $uiDir 'node_modules\vite\bin\vite.js'
        if (-not (Test-Path $viteScript)) {
            Stop-AgentStory
            Show-AgentStoryStartFailure -Message "Agent Story UI is missing Vite. Run npm install in agent-story\ui and try again."
            return $false
        }

        $uiPsi = New-Object System.Diagnostics.ProcessStartInfo
        $uiPsi.FileName = $nodeCmd.Source
        $uiPsi.Arguments = "`"$viteScript`" --port 5173 --strictPort"
        $uiPsi.WorkingDirectory = $uiDir
        $uiPsi.CreateNoWindow = $true
        $uiPsi.UseShellExecute = $false
        $script:AgentStoryUiProcess = [System.Diagnostics.Process]::Start($uiPsi)
    }
    catch {
        Stop-AgentStory
        Show-AgentStoryStartFailure -Message "Failed to start Agent Story UI server: $($_.Exception.Message)"
        return $false
    }

    if (-not (Wait-AgentStoryProcessesHealthy)) {
        Stop-AgentStory
        Show-AgentStoryStartFailure -Message "Agent Story started but exited or failed to bind ports 8080, 3001, and 5173.`n`nCheck for port conflicts or run server/ui manually from agent-story\ to see errors."
        return $false
    }

    Register-RunningProxiedProfilesWithAgentStory

    Update-AgentStoryUiState
    return $true
}

function Get-ListenerProcessIdsForPort {
    param(
        [Parameter(Mandatory)][int]$Port
    )

    $pids = @()
    $seen = @{}
    try {
        $listeningLines = @(netstat -ano | Select-String -Pattern ":$Port\s+.*LISTENING")
        foreach ($line in $listeningLines) {
            if ($line -match '\s+(\d+)\s*$') {
                $procId = [int]$Matches[1]
                if (-not $seen.ContainsKey($procId)) {
                    $seen[$procId] = $true
                    $pids += $procId
                }
            }
        }
    }
    catch { }

    return , $pids
}

function Stop-ListenerProcessesForPort {
    param(
        [Parameter(Mandatory)][int]$Port
    )

    foreach ($procId in (Get-ListenerProcessIdsForPort -Port $Port)) {
        try {
            & taskkill.exe /F /T /PID $procId | Out-Null
        }
        catch { }
    }
}

function Stop-AgentStory {
    if ($script:AgentStoryProxyProcess) {
        try {
            if (-not $script:AgentStoryProxyProcess.HasExited) {
                & taskkill.exe /F /T /PID $script:AgentStoryProxyProcess.Id | Out-Null
            }
        } catch {}
        $script:AgentStoryProxyProcess = $null
    }
    if ($script:AgentStoryUiProcess) {
        try {
            if (-not $script:AgentStoryUiProcess.HasExited) {
                & taskkill.exe /F /T /PID $script:AgentStoryUiProcess.Id | Out-Null
            }
        } catch {}
        $script:AgentStoryUiProcess = $null
    }

    foreach ($port in @(8080, 3001, 5173)) {
        Stop-ListenerProcessesForPort -Port $port
    }

    Update-AgentStoryUiState
}

function Get-AgentStoryUiUrl {
    if ($env:AGENT_STORY_UI_URL -and -not [string]::IsNullOrWhiteSpace($env:AGENT_STORY_UI_URL)) {
        return $env:AGENT_STORY_UI_URL.Trim()
    }
    return $script:AgentStoryUiUrl
}

function Test-AgentStoryUiAvailable {
    return (Test-AgentStoryServicePortListening -Port 5173)
}

function Open-AgentStoryDashboard {
    if (-not (Test-AgentStoryUiAvailable)) {
        [System.Windows.Forms.MessageBox]::Show(
            'Agent Story dashboard is not running. Start Agent Story from the toolbar first.',
            'Agent Story',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return $false
    }

    try {
        Start-Process -FilePath (Get-AgentStoryUiUrl)
        return $true
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not open Agent Story dashboard:`n$($_.Exception.Message)",
            'Agent Story',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return $false
    }
}

function Set-AgentStoryOpenLinkDisplay {
    if (-not $script:lnkAgentStoryOpen) { return }

    $uiAvailable = Test-AgentStoryUiAvailable
    $url = Get-AgentStoryUiUrl
    $script:lnkAgentStoryOpen.Text = "Open dashboard"
    $script:lnkAgentStoryOpen.Visible = $uiAvailable
    $script:lnkAgentStoryOpen.Enabled = $uiAvailable
    if ($uiAvailable) {
        $script:lnkAgentStoryOpen.LinkColor = $script:UiAccent
    }
    else {
        $script:lnkAgentStoryOpen.LinkColor = $script:UiTextMuted
    }
}

function Update-AgentStoryUiState {
    if ($script:UiShuttingDown) { return }
    if (-not $script:btnAgentStory -or -not $script:lblAgentStoryStatus) { return }
    if ($form -and $form.IsDisposed) { return }

    $runState = Resolve-AgentStoryRunState

    switch ($runState) {
        'Running' {
            $script:btnAgentStory.Text = 'Stop Agent Story'
            $script:lblAgentStoryStatus.Text = "$([char]0x25CF) Agent Story: Running"
            $script:lblAgentStoryStatus.ForeColor = $script:UiRunningColor
        }
        'Partial' {
            $script:btnAgentStory.Text = 'Stop Agent Story'
            $script:lblAgentStoryStatus.Text = "$([char]0x25CF) Agent Story: Partial"
            $script:lblAgentStoryStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 120, 0)
        }
        default {
            if ($script:AgentStoryProxyProcess -or $script:AgentStoryUiProcess) {
                $script:AgentStoryProxyProcess = $null
                $script:AgentStoryUiProcess = $null
            }
            $script:btnAgentStory.Text = 'Start Agent Story'
            $script:lblAgentStoryStatus.Text = "$([char]0x25CB) Agent Story: Stopped"
            $script:lblAgentStoryStatus.ForeColor = $script:UiTextMuted
        }
    }

    Set-AgentStoryOpenLinkDisplay
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

function Find-CursorCliExecutable {
    $cmd = Get-Command cursor -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    $idePath = Find-CursorExecutable
    if ($idePath -and $idePath -match '(?i)Cursor\.exe$') {
        $bundledCli = Join-Path (Split-Path -Parent $idePath) 'resources\app\bin\cursor.cmd'
        if (Test-Path -LiteralPath $bundledCli) { return $bundledCli }
    }

    return $null
}

function Get-CursorVersionFromExecutable {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    try {
        $vi = (Get-Item -LiteralPath $Path).VersionInfo
        $ver = [string]$vi.FileVersion
        if ([string]::IsNullOrWhiteSpace($ver)) {
            $ver = [string]$vi.ProductVersion
        }
        if ($ver -match '^([\d.]+)') {
            return $matches[1]
        }
        if (-not [string]::IsNullOrWhiteSpace($ver)) {
            return ($ver -split '\s+')[0]
        }
    }
    catch {
    }

    return $null
}

function Get-CursorInstallInfo {
    param([switch]$ForceRefresh)

    if (-not $ForceRefresh -and $script:CursorInstallInfo) {
        return $script:CursorInstallInfo
    }

    $idePath = Find-CursorExecutable
    $cliPath = Find-CursorCliExecutable
    $ideVersion = $null
    $cliVersion = $null

    if ($idePath -and $idePath -match '(?i)Cursor\.exe$') {
        $ideVersion = Get-CursorVersionFromExecutable -Path $idePath
    }
    elseif ($idePath) {
        $ideVersion = Get-CursorVersionFromExecutable -Path $idePath
    }

    if ($cliPath) {
        if ($ideVersion) {
            $cliVersion = $ideVersion
        }
        else {
            $cliVersion = Get-CursorVersionFromExecutable -Path $cliPath
        }
    }

    $isInstalled = -not [string]::IsNullOrWhiteSpace($idePath)
    $info = [PSCustomObject]@{
        IsInstalled = $isInstalled
        IdePath     = $idePath
        IdeVersion  = $ideVersion
        CliPath     = $cliPath
        CliVersion  = $cliVersion
        HasCli      = -not [string]::IsNullOrWhiteSpace($cliPath)
    }

    $script:CursorInstallInfo = $info
    return $info
}

function Update-CursorInstallUi {
    if ($script:CursorInstallLink) {
        Set-CursorInstallLinkDisplay
    }
    if ($btnAdd) {
        $btnAdd.Enabled = (Get-CursorInstallInfo).IsInstalled
    }
    Sync-GridActionInstallState
}

function Set-CursorInstallLinkDisplay {
    if (-not $script:CursorInstallLink) { return }

    $info = Get-CursorInstallInfo
    $script:CursorInstallLink.Links.Clear()

    if ($info.IsInstalled) {
        $versionText = if ($info.IdeVersion) { $info.IdeVersion } else { 'installed' }
        if ($info.HasCli) {
            $script:CursorInstallLink.Text = "Cursor $versionText | CLI"
            $script:CursorInstallLink.LinkArea = New-Object System.Windows.Forms.LinkArea(0, 0)
            $script:CursorInstallLink.LinkColor = $script:UiTextMuted
            $script:CursorInstallLink.ForeColor = $script:UiTextMuted
            return
        }

        $prefix = "Cursor $versionText | "
        $linkText = 'CLI missing'
        $script:CursorInstallLink.Text = $prefix + $linkText
        $script:CursorInstallLink.ForeColor = $script:UiWarningColor
        $script:CursorInstallLink.LinkColor = $script:UiAccent
        [void]$script:CursorInstallLink.Links.Add($prefix.Length, $linkText.Length)
        return
    }

    $prefix = 'Cursor not found - '
    $linkText = 'Install Cursor'
    $script:CursorInstallLink.Text = $prefix + $linkText
    $script:CursorInstallLink.ForeColor = $script:UiWarningColor
    $script:CursorInstallLink.LinkColor = $script:UiAccent
    [void]$script:CursorInstallLink.Links.Add($prefix.Length, $linkText.Length)
}

function Show-CursorInstallDialog {
    $info = Get-CursorInstallInfo -ForceRefresh

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Install Cursor'
    $dlg.Size = New-Object System.Drawing.Size(520, 360)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.Font = $script:UiFont
    $dlg.BackColor = $script:UiBackColor
    [void](Set-FormIcon -TargetForm $dlg)

    $lblIntro = New-Object System.Windows.Forms.Label
    $lblIntro.Location = New-Object System.Drawing.Point(20, 20)
    $lblIntro.Size = New-Object System.Drawing.Size(470, 48)
    $lblIntro.ForeColor = $script:UiTextPrimary
    $lblIntro.Text = 'Cursor IDE is required to add, edit, and start profiles. The cursor CLI is recommended for terminal and automation workflows.'
    $dlg.Controls.Add($lblIntro)

    $statusLines = @()
    if ($info.IdePath) {
        $ideVer = if ($info.IdeVersion) { " ($($info.IdeVersion))" } else { '' }
        $statusLines += "IDE: $($info.IdePath)$ideVer"
    }
    else {
        $statusLines += 'IDE: not found'
    }
    if ($info.CliPath) {
        $cliVer = if ($info.CliVersion) { " ($($info.CliVersion))" } else { '' }
        $statusLines += "CLI: $($info.CliPath)$cliVer"
    }
    else {
        $statusLines += 'CLI: not found on PATH (install from Cursor after IDE setup)'
    }

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Location = New-Object System.Drawing.Point(20, 78)
    $lblStatus.Size = New-Object System.Drawing.Size(470, 72)
    $lblStatus.ForeColor = $script:UiTextMuted
    $lblStatus.Text = ($statusLines -join [Environment]::NewLine)
    $dlg.Controls.Add($lblStatus)

    $lblSteps = New-Object System.Windows.Forms.Label
    $lblSteps.Location = New-Object System.Drawing.Point(20, 158)
    $lblSteps.Size = New-Object System.Drawing.Size(470, 88)
    $lblSteps.ForeColor = $script:UiTextPrimary
    $lblSteps.Text = @(
        '1. Download and install Cursor IDE.'
        '2. Open Cursor, press Ctrl+Shift+P, run "Shell Command: Install ''cursor'' command in PATH".'
        '3. Click Check again below, or set CURSOR_BIN to your Cursor.exe path.'
    ) -join [Environment]::NewLine
    $dlg.Controls.Add($lblSteps)

    $btnDownload = New-Object System.Windows.Forms.Button
    $btnDownload.Text = 'Open download page'
    $btnDownload.Location = New-Object System.Drawing.Point(20, 262)
    $btnDownload.Size = New-Object System.Drawing.Size(150, 28)
    $btnDownload.Add_Click({
        try {
            Start-Process $script:CursorDownloadUrl
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not open browser:`n$($_.Exception.Message)",
                'Error',
                'OK',
                'Error') | Out-Null
        }
    })
    $dlg.Controls.Add($btnDownload)

    $btnRecheck = New-Object System.Windows.Forms.Button
    $btnRecheck.Text = 'Check again'
    $btnRecheck.Location = New-Object System.Drawing.Point(180, 262)
    $btnRecheck.Size = New-Object System.Drawing.Size(100, 28)
    $btnRecheck.Add_Click({
        $refreshed = Get-CursorInstallInfo -ForceRefresh
        Update-CursorInstallUi

        $ideVer = if ($refreshed.IdeVersion) { " ($($refreshed.IdeVersion))" } else { '' }
        $cliVer = if ($refreshed.CliVersion) { " ($($refreshed.CliVersion))" } else { '' }
        $newStatus = @()
        if ($refreshed.IdePath) {
            $newStatus += "IDE: $($refreshed.IdePath)$ideVer"
        }
        else {
            $newStatus += 'IDE: not found'
        }
        if ($refreshed.CliPath) {
            $newStatus += "CLI: $($refreshed.CliPath)$cliVer"
        }
        else {
            $newStatus += 'CLI: not found on PATH (install from Cursor after IDE setup)'
        }
        $lblStatus.Text = ($newStatus -join [Environment]::NewLine)

        if ($refreshed.IsInstalled) {
            [System.Windows.Forms.MessageBox]::Show(
                'Cursor IDE is installed. You can add, edit, and start profiles now.',
                'Cursor ready',
                'OK',
                'Information') | Out-Null
            $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dlg.Close()
        }
    })
    $dlg.Controls.Add($btnRecheck)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Location = New-Object System.Drawing.Point(410, 262)
    $btnClose.Size = New-Object System.Drawing.Size(80, 28)
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnClose)
    $dlg.CancelButton = $btnClose

    if ($form) {
        [void]$dlg.ShowDialog($form)
    }
    else {
        [void]$dlg.ShowDialog()
    }
    $dlg.Dispose()
}

function Test-CursorInstallReady {
    $info = Get-CursorInstallInfo
    if ($info.IsInstalled) { return $true }

    Show-CursorInstallDialog
    $info = Get-CursorInstallInfo -ForceRefresh
    Update-CursorInstallUi
    return $info.IsInstalled
}

function Get-NormalizedUserDataDirFromCommandLine {
    param([string]$CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    if ($CommandLine -notmatch '--user-data-dir[= ]"?([^"]+?)"?(\s--|\s|$)') { return $null }
    return $matches[1].TrimEnd('\', '/').ToLowerInvariant()
}

function Get-UserDataDirInstanceCountsFromProcessRecords {
    param([array]$ProcessRecords)

    # Count Cursor windows per user-data-dir via --type=renderer processes. Electron keeps
    # one main process per profile; each additional window is a renderer child.
    $counts = @{}
    if ($null -eq $ProcessRecords -or $ProcessRecords.Count -eq 0) { return $counts }

    $cursorPids = @{}
    foreach ($p in $ProcessRecords) {
        $cursorPids[$p.ProcessId] = $true
    }

    $mainByDir = @{}
    foreach ($p in $ProcessRecords) {
        $cmd = $p.CommandLine
        $dir = Get-NormalizedUserDataDirFromCommandLine -CommandLine $cmd
        if (-not $dir) { continue }
        if ($cmd -match '--type=') { continue }
        if ($cursorPids.ContainsKey($p.ParentProcessId)) { continue }
        $mainByDir[$dir] = $true
    }

    foreach ($p in $ProcessRecords) {
        $cmd = $p.CommandLine
        if (-not $cmd -or $cmd -notmatch '--type=renderer') { continue }
        $dir = Get-NormalizedUserDataDirFromCommandLine -CommandLine $cmd
        if (-not $dir -or -not $mainByDir.ContainsKey($dir)) { continue }

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

function Get-UserDataDirInstanceCounts {
    $procs = @(Get-CimInstance Win32_Process -Filter "name='Cursor.exe'" -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return @{} }

    $records = foreach ($p in $procs) {
        [PSCustomObject]@{
            ProcessId       = [int]$p.ProcessId
            ParentProcessId = [int]$p.ParentProcessId
            CommandLine     = [string]$p.CommandLine
        }
    }
    return Get-UserDataDirInstanceCountsFromProcessRecords -ProcessRecords $records
}

function Get-ProfileInstanceCount {
    param(
        [string]$UserDataDir,
        [hashtable]$InstanceCounts = $null
    )
    if (-not $UserDataDir) { return 0 }
    if ($null -eq $InstanceCounts) {
        $InstanceCounts = Get-UserDataDirInstanceCounts
    }
    $norm = $UserDataDir.TrimEnd('\', '/').ToLowerInvariant()
    if ($InstanceCounts.ContainsKey($norm)) {
        return [int]$InstanceCounts[$norm]
    }
    return 0
}

function Get-CursorProcessIdsForUserDataDir {
    param([Parameter(Mandatory)][string]$UserDataDir)

    $norm = $UserDataDir.TrimEnd('\', '/').ToLowerInvariant()
    $pids = @()
    $procs = @(Get-CimInstance Win32_Process -Filter "name='Cursor.exe'" -ErrorAction SilentlyContinue)

    foreach ($p in $procs) {
        $dir = Get-NormalizedUserDataDirFromCommandLine -CommandLine $p.CommandLine
        if ($dir -ne $norm) { continue }
        $pids += [int]$p.ProcessId
    }

    return $pids
}

function Get-CursorProfileWindowHandles {
    param([Parameter(Mandatory)][string]$UserDataDir)

    Initialize-Win32AppFocus

    $pids = @(Get-CursorProcessIdsForUserDataDir -UserDataDir $UserDataDir)
    if ($pids.Count -eq 0) { return @() }

    $handles = [Win32AppFocus]::GetVisibleTopLevelWindowsForProcesses([int[]]$pids)
    if ($handles.Count -gt 0) {
        return @($handles | Sort-Object { $_.ToInt64() })
    }

    $fallback = @()
    foreach ($procId in $pids) {
        try {
            $proc = Get-Process -Id $procId -ErrorAction Stop
            if ($proc.MainWindowHandle -ne [IntPtr]::Zero) {
                $fallback += $proc.MainWindowHandle
            }
        }
        catch {
        }
    }

    return @($fallback | Sort-Object { $_.ToInt64() })
}

$script:FocusCycleByDir = @{}

function Invoke-FocusCursorProfile {
    param([Parameter(Mandatory)][PSCustomObject]$Profile)

    $instanceCounts = Get-UserDataDirInstanceCounts
    $runningCount = Get-ProfileInstanceCount -UserDataDir $Profile.UserDataDir -InstanceCounts $instanceCounts
    if ($runningCount -le 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No running Cursor windows were found for '$($Profile.Name)'.",
            'Profile not running',
            'OK',
            'Information') | Out-Null
        return $false
    }

    $handles = @(Get-CursorProfileWindowHandles -UserDataDir $Profile.UserDataDir)
    if ($handles.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Cursor is running for '$($Profile.Name)', but no window could be brought to the front.",
            'Window not found',
            'OK',
            'Warning') | Out-Null
        return $false
    }

    $norm = $Profile.UserDataDir.TrimEnd('\', '/').ToLowerInvariant()
    $index = 0
    if ($handles.Count -gt 1) {
        if ($script:FocusCycleByDir.ContainsKey($norm)) {
            $index = ($script:FocusCycleByDir[$norm] + 1) % $handles.Count
        }
        $script:FocusCycleByDir[$norm] = $index
    }

    [Win32AppFocus]::ForceForegroundWindow($handles[$index])
    return $true
}

function Invoke-CloseAllCursorProfileInstances {
    param([Parameter(Mandatory)][PSCustomObject]$Profile)

    $instanceCounts = Get-UserDataDirInstanceCounts
    $runningCount = Get-ProfileInstanceCount -UserDataDir $Profile.UserDataDir -InstanceCounts $instanceCounts
    if ($runningCount -le 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No running Cursor windows were found for '$($Profile.Name)'.",
            'Profile not running',
            'OK',
            'Information') | Out-Null
        return $false
    }

    $instanceLabel = if ($runningCount -eq 1) { '1 window' } else { "$runningCount windows" }
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Close all Cursor windows for '$($Profile.Name)' ($instanceLabel)?`n`nUnsaved work in those windows may be lost.",
        'Close all',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }

    Initialize-Win32AppFocus

    $handles = @(Get-CursorProfileWindowHandles -UserDataDir $Profile.UserDataDir)
    foreach ($hwnd in $handles) {
        [Win32AppFocus]::CloseWindow($hwnd)
    }

    $deadline = [datetime]::UtcNow.AddSeconds(5)
    while ([datetime]::UtcNow -lt $deadline) {
        $remaining = @(Get-CursorProcessIdsForUserDataDir -UserDataDir $Profile.UserDataDir)
        if ($remaining.Count -eq 0) { break }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 200
    }

    $remaining = @(Get-CursorProcessIdsForUserDataDir -UserDataDir $Profile.UserDataDir)
    foreach ($procId in $remaining) {
        try {
            Stop-Process -Id $procId -Force -ErrorAction Stop
        }
        catch {
        }
    }

    $norm = $Profile.UserDataDir.TrimEnd('\', '/').ToLowerInvariant()
    if ($script:FocusCycleByDir.ContainsKey($norm)) {
        [void]$script:FocusCycleByDir.Remove($norm)
    }

    Request-DeferredGridRefresh
    return $true
}

function Edit-Profile {
    param([Parameter(Mandatory)][PSCustomObject]$Profile)

    if (-not (Test-CursorInstallReady)) { return $false }

    $result = Show-ProfileDialog -Existing $Profile
    if ($result) {
        $Profile.Name = $result.Name
        $Profile.UserDataDir = $result.UserDataDir
        $Profile.ProjectPath = $result.ProjectPath
        $Profile.Notes = $result.Notes
        if ($null -eq $Profile.psobject.Properties['RunProxied']) {
            $Profile | Add-Member -MemberType NoteProperty -Name 'RunProxied' -Value $result.RunProxied -Force
        } else {
            $Profile.RunProxied = $result.RunProxied
        }
        Save-Profiles -Profiles $script:Profiles
        Update-ProfileGrid
        return $true
    }
    return $false
}

function Remove-Profile {
    param([Parameter(Mandatory)][PSCustomObject]$Profile)

    $instanceCounts = Get-UserDataDirInstanceCounts
    $instanceCount = Get-ProfileInstanceCount -UserDataDir $Profile.UserDataDir -InstanceCounts $instanceCounts
    if ($instanceCount -gt 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Close all running Cursor windows for '$($Profile.Name)' ($instanceCount instance$(if ($instanceCount -ne 1) { 's' })) before deleting it. Use Close in the Actions column.",
            'Profile is running',
            'OK',
            'Warning') | Out-Null
        return $false
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Delete profile '$($Profile.Name)'?",
        'Confirm delete',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }

    $deleteFolder = [System.Windows.Forms.MessageBox]::Show(
        "Also delete the profile's data folder?`n$($Profile.UserDataDir)`n`nThis permanently removes its login, extensions and settings.",
        'Delete data folder',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)

    if ($deleteFolder -eq [System.Windows.Forms.DialogResult]::Yes -and (Test-Path $Profile.UserDataDir)) {
        try {
            Remove-Item -Path $Profile.UserDataDir -Recurse -Force
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Failed to delete folder: $($_.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null
        }
    }

    $script:Profiles = Normalize-ProfilesList -Profiles @($script:Profiles | Where-Object { $_.Id -ne $Profile.Id })
    Save-Profiles -Profiles $script:Profiles
    Update-ProfileGrid
    return $true
}

function Invoke-GridProfileAction {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Profile,
        [Parameter(Mandatory)][string]$ActionName
    )

    switch ($ActionName) {
        'ActStart' {
            if (-not (Test-CursorInstallReady)) { return }
            try {
                Start-CursorProfileInstance -Profile $Profile
                Request-DeferredGridRefresh
            }
            catch {
                $profileName = if ($Profile -and $Profile.Name) { $Profile.Name } else { 'profile' }
                [System.Windows.Forms.MessageBox]::Show(
                    "Failed to start profile '$profileName':`n`n$($_.Exception.Message)",
                    'Launch Error',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
        }
        'ActFocus' {
            [void](Invoke-FocusCursorProfile -Profile $Profile)
        }
        'ActClose' {
            [void](Invoke-CloseAllCursorProfileInstances -Profile $Profile)
        }
        'ActFolder' {
            [void](Open-ProfileUserDataDir -Profile $Profile)
        }
        'ActEdit' {
            [void](Edit-Profile -Profile $Profile)
        }
        'ActDelete' {
            [void](Remove-Profile -Profile $Profile)
        }
    }
}

function Sync-GridActionInstallState {
    if (-not $grid -or -not $grid.Columns.Contains('ActStart')) { return }

    $startEnabled = (Get-CursorInstallInfo).IsInstalled
    $wantReadOnly = -not $startEnabled
    $actionFore = if ($startEnabled) { $script:UiTextPrimary } else { $script:UiIdleColor }

    foreach ($row in $grid.Rows) {
        if ($row.IsNewRow) { continue }
        $startCell = $row.Cells['ActStart']
        if ($startCell.ReadOnly -ne $wantReadOnly) {
            $startCell.ReadOnly = $wantReadOnly
        }
        if ($startCell.Style.ForeColor -ne $actionFore) {
            $startCell.Style.ForeColor = $actionFore
        }
    }
}

function Start-CursorProcessWatchers {
    param(
        [System.Windows.Forms.Form]$OwnerForm,
        [System.Windows.Forms.Timer]$DebounceTimer
    )

    $handler = [System.Management.EventArrivedEventHandler]{
        param($sender, $e)
        if ($OwnerForm.IsDisposed -or $script:UiShuttingDown) { return }
        if ($OwnerForm.InvokeRequired) {
            [void]$OwnerForm.BeginInvoke([Action]{
                if ($script:UiShuttingDown) { return }
                try {
                    $DebounceTimer.Stop()
                    $DebounceTimer.Start()
                }
                catch { }
            })
        }
        else {
            try {
                $DebounceTimer.Stop()
                $DebounceTimer.Start()
            }
            catch { }
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

    if ($Profile -is [System.Array]) {
        if ($Profile.Count -eq 1) {
            $Profile = $Profile[0]
        }
        else {
            throw "Start expected a single profile, but received $($Profile.Count) profiles."
        }
    }

    if (-not (Test-IsProfileObject $Profile)) {
        throw 'Start expected a valid profile object.'
    }

    $cursor = Find-CursorExecutable
    if (-not $cursor) {
        if (-not (Test-CursorInstallReady)) { return }
        $cursor = Find-CursorExecutable
        if (-not $cursor) { return }
    }

    if (-not (Test-Path -LiteralPath $Profile.UserDataDir)) {
        New-Item -ItemType Directory -Path $Profile.UserDataDir -Force | Out-Null
    }

    $projectPath = ''
    if ($null -ne $Profile.ProjectPath) {
        $projectPath = [string]$Profile.ProjectPath
        $projectPath = $projectPath.Trim()
    }

    $projectExists = $false
    if (-not [string]::IsNullOrWhiteSpace($projectPath)) {
        if (Test-Path -LiteralPath $projectPath) {
            $projectExists = $true
        }
        else {
            [System.Windows.Forms.MessageBox]::Show(
                "Project path not found, opening without a folder:`n$projectPath",
                'Warning',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    }

    $userDataArg = "--user-data-dir=`"$($Profile.UserDataDir)`""

    $useProxy = $false
    $extraArgs = @()
    $proxyEnv = @{}
    if ($Profile.RunProxied) {
        $proxyRunning = Test-AgentStoryProxyRunning

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
                    $proxyRunning = Test-AgentStoryProxyRunning
                }
                else {
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

        $useProxy = [bool]$proxyRunning
        $extraArgs = Get-CursorProxyLaunchArgs -UseProxy:$useProxy
        $proxyEnv = Get-CursorProxyEnvironmentVariables -UseProxy:$useProxy
    }

    Update-CursorProfileProxySettings -UserDataDir $Profile.UserDataDir -EnableProxy:$useProxy

    $launchEnv = Merge-Hashtables @(
        (Get-CursorProfileIdentityEnvironmentVariables -Profile $Profile),
        $proxyEnv
    )

    $instanceCounts = Get-UserDataDirInstanceCounts
    $runningCount = Get-ProfileInstanceCount -UserDataDir $Profile.UserDataDir -InstanceCounts $instanceCounts

    # Cursor/VS Code reuses the existing window when the same folder is already open,
    # even with --new-window. Open an empty window, then --add the project folder.
    if ($runningCount -gt 0 -and $projectExists) {
        Start-CursorProfileProcess -ExecutablePath $cursor -ArgumentList (@($userDataArg, '--new-window') + $extraArgs) -Environment $launchEnv -Profile $Profile | Out-Null
        Start-Sleep -Milliseconds 800
        Start-CursorProfileProcess -ExecutablePath $cursor -ArgumentList (@($userDataArg, '--add', $projectPath) + $extraArgs) -Environment $launchEnv -Profile $Profile -RegisterProfile:$false | Out-Null
        return
    }

    $argList = @($userDataArg, '--new-window') + $extraArgs
    if ($projectExists) {
        $argList += $projectPath
    }

    Start-CursorProfileProcess -ExecutablePath $cursor -ArgumentList $argList -Environment $launchEnv -Profile $Profile | Out-Null
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
    $dlg.Size = New-Object System.Drawing.Size(500, 394)
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

    $y += 38

    # Run proxied checkbox
    $chkProxy = New-Object System.Windows.Forms.CheckBox
    $chkProxy.Text = 'Run proxied (Route traffic through Agent Story proxy)'
    $chkProxy.Location = New-Object System.Drawing.Point($fieldX, $y)
    $chkProxy.Size = New-Object System.Drawing.Size($fieldWidth, 24)
    $chkProxy.ForeColor = $script:UiTextPrimary
    if ($isEdit) { $chkProxy.Checked = [bool]$Existing.RunProxied }
    $dlg.Controls.Add($chkProxy)

    $y += 34

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
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::None
    $btnOk.Add_Click({
        if ([string]::IsNullOrWhiteSpace($txtName.Text)) {
            [System.Windows.Forms.MessageBox]::Show('Profile name is required.', 'Validation', 'OK', 'Warning') | Out-Null
            return
        }
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    })
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
        RunProxied  = $chkProxy.Checked
    }
}

# ---------------------------------------------------------------------------
# Grid model (view sync)
# ---------------------------------------------------------------------------

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
        Notes       = $Profile.Notes
        IsRunning   = $isRunning
        RunProxied  = [bool]$Profile.RunProxied
    }
}

function Build-GridModel {
    $instanceCounts = Get-UserDataDirInstanceCounts
    $order = New-Object 'System.Collections.Generic.List[string]'
    $rowsById = @{}

    foreach ($p in Get-ProfilesList) {
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
        $A.Notes -eq $B.Notes -and
        $A.RunProxied -eq $B.RunProxied
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

    if ([string]$cells['Name'].Value -ne $ModelRow.Name) {
        $cells['Name'].Value = $ModelRow.Name
    }
    if ([string]$cells['UserDataDir'].Value -ne $ModelRow.UserDataDir) {
        $cells['UserDataDir'].Value = $ModelRow.UserDataDir
    }
    if ([string]$cells['Instances'].Value -ne [string]$ModelRow.Instances) {
        $cells['Instances'].Value = [string]$ModelRow.Instances
    }
    if ([string]$cells['Status'].Value -ne $ModelRow.Status) {
        $cells['Status'].Value = $ModelRow.Status
    }
    if ([string]$cells['Notes'].Value -ne $ModelRow.Notes) {
        $cells['Notes'].Value = $ModelRow.Notes
    }
    if ($cells['Proxy'].Value -ne $ModelRow.RunProxied) {
        $cells['Proxy'].Value = $ModelRow.RunProxied
    }
    $statusColor = if ($ModelRow.IsRunning) { $script:RunningGridForeColor } else { $script:UiIdleColor }
    if ($cells['Status'].Style.ForeColor -ne $statusColor) {
        $cells['Status'].Style.ForeColor = $statusColor
    }
    if ($cells['Instances'].Style.ForeColor -ne $foreColor) {
        $cells['Instances'].Style.ForeColor = $foreColor
    }

    foreach ($actionName in @('ActStart', 'ActFocus', 'ActClose', 'ActFolder', 'ActEdit', 'ActDelete')) {
        if (-not $grid.Columns.Contains($actionName)) { continue }
        $actionCell = $cells[$actionName]
        $rowBack = if ($Row.Index % 2 -eq 1) { $script:UiGridAltRow } else { $script:UiPanelColor }
        if ($actionCell.Style.BackColor -ne $rowBack) {
            $actionCell.Style.BackColor = $rowBack
        }
        if ($actionCell.Style.SelectionBackColor -ne $rowBack) {
            $actionCell.Style.SelectionBackColor = $rowBack
        }
    }

    if ($grid.Columns.Contains('ActStart')) {
        $startCell = $cells['ActStart']
        $startEnabled = (Get-CursorInstallInfo).IsInstalled
        $wantReadOnly = -not $startEnabled
        if ($startCell.ReadOnly -ne $wantReadOnly) {
            $startCell.ReadOnly = $wantReadOnly
        }
        $startFore = if ($startEnabled) { $script:UiTextPrimary } else { $script:UiIdleColor }
        if ($startCell.Style.ForeColor -ne $startFore) {
            $startCell.Style.ForeColor = $startFore
        }
    }

    foreach ($actionName in @('ActFocus', 'ActClose')) {
        if (-not $grid.Columns.Contains($actionName)) { continue }
        $actionCell = $cells[$actionName]
        $actionEnabled = $ModelRow.IsRunning
        $wantReadOnly = -not $actionEnabled
        if ($actionCell.ReadOnly -ne $wantReadOnly) {
            $actionCell.ReadOnly = $wantReadOnly
        }
        $actionFore = if ($actionEnabled) { $script:UiTextPrimary } else { $script:UiIdleColor }
        if ($actionCell.Style.ForeColor -ne $actionFore) {
            $actionCell.Style.ForeColor = $actionFore
        }
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
                $emptyCells = @(1..$grid.Columns.Count | ForEach-Object { '' })
                $rowIdx = $grid.Rows.Add($emptyCells)
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
    return Get-ProfilesList | Where-Object { $_.Id -eq $id } | Select-Object -First 1
}

function Get-ProfileFromGridRow {
    param([Parameter(Mandatory)][int]$RowIndex)

    if ($RowIndex -lt 0 -or $RowIndex -ge $grid.Rows.Count) { return $null }
    $id = $grid.Rows[$RowIndex].Tag
    if (-not $id) { return $null }
    return Get-ProfilesList | Where-Object { $_.Id -eq $id } | Select-Object -First 1
}

function Start-ProfileFromGridRow {
    param([Parameter(Mandatory)][int]$RowIndex)

    $profile = Get-ProfileFromGridRow -RowIndex $RowIndex
    if (-not $profile) { return $false }
    if (-not (Test-CursorInstallReady)) { return $false }
    try {
        Start-CursorProfileInstance -Profile $profile
        Request-DeferredGridRefresh
        return $true
    }
    catch {
        $profileName = if ($profile.Name) { $profile.Name } else { 'profile' }
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to start profile '$profileName':`n`n$($_.Exception.Message)",
            'Launch Error',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return $false
    }
}

function Open-ProfileUserDataDir {
    param([Parameter(Mandatory)][PSCustomObject]$Profile)

    $dir = [string]$Profile.UserDataDir
    if ([string]::IsNullOrWhiteSpace($dir)) {
        [System.Windows.Forms.MessageBox]::Show('This profile has no user-data-dir path.', 'No folder', 'OK', 'Information') | Out-Null
        return $false
    }

    if (-not (Test-Path $dir)) {
        try {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Could not create folder:`n$dir`n`n$($_.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null
            return $false
        }
    }

    try {
        Start-Process -FilePath 'explorer.exe' -ArgumentList @($dir)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not open folder:`n$dir`n`n$($_.Exception.Message)", 'Error', 'OK', 'Error') | Out-Null
        return $false
    }

    return $true
}

# ---------------------------------------------------------------------------
# Main window
# ---------------------------------------------------------------------------

if ($FunctionsOnly) { return }

function Show-StartupFailure {
    param(
        [Parameter(Mandatory)][string]$Message
    )

    try {
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            (Get-AppWindowTitle),
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch {
        Write-Error $Message
    }
}

function Invoke-UiRefreshSafe {
    param(
        [Parameter(Mandatory)][scriptblock]$Action
    )

    if ($script:UiShuttingDown) { return }
    if ($form -and $form.IsDisposed) { return }

    try {
        & $Action
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        # Runspace stopping during shutdown — ignore.
    }
    catch {
        Write-Warning "UI refresh failed: $($_.Exception.Message)"
    }
}

$script:StartupFailed = $false
try {
Assert-LaunchPathsReady
Ensure-ProfilesRoot
Load-AppSettings
Set-UiThemePalette -ThemeName (Get-EffectiveUiThemeName)

$script:Profiles = Normalize-ProfilesList -Profiles @(Load-Profiles)

$form = New-Object System.Windows.Forms.Form
$form.Text = Get-AppWindowTitle
$form.Size = New-Object System.Drawing.Size(980, 520)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(900, 420)
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

$script:CheckUpdateLink = New-Object System.Windows.Forms.LinkLabel
$script:CheckUpdateLink.AutoSize = $true
$script:CheckUpdateLink.Dock = [System.Windows.Forms.DockStyle]::Right
$script:CheckUpdateLink.Padding = New-Object System.Windows.Forms.Padding(0, 7, 0, 0)
$script:CheckUpdateLink.ForeColor = $script:UiTextMuted
$script:CheckUpdateLink.LinkColor = $script:UiAccent
$script:CheckUpdateLink.ActiveLinkColor = $script:UiAccentHover
$script:CheckUpdateLink.VisitedLinkColor = $script:UiAccent
$script:CheckUpdateLink.BackColor = $script:UiPanelColor
$script:CheckUpdateLink.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
Set-CheckUpdateLinkDisplay
$script:CheckUpdateLink.Add_LinkClicked({
    $script:CheckUpdateLink.Enabled = $false
    $form.UseWaitCursor = $true
    try {
        Invoke-CheckForAppUpdate
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not check for updates:`n$($_.Exception.Message)",
            'Update check failed',
            'OK',
            'Error') | Out-Null
    }
    finally {
        $form.UseWaitCursor = $false
        $script:CheckUpdateLink.Enabled = $true
    }
})

$script:CursorInstallLink = New-Object System.Windows.Forms.LinkLabel
$script:CursorInstallLink.AutoSize = $true
$script:CursorInstallLink.Dock = [System.Windows.Forms.DockStyle]::Right
$script:CursorInstallLink.Padding = New-Object System.Windows.Forms.Padding(0, 7, 12, 0)
$script:CursorInstallLink.BackColor = $script:UiPanelColor
$script:CursorInstallLink.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$script:CursorInstallLink.Add_LinkClicked({
    $info = Get-CursorInstallInfo
    if ($info.IsInstalled -and $info.HasCli) { return }
    Show-CursorInstallDialog
    Update-CursorInstallUi
})
[void](Get-CursorInstallInfo -ForceRefresh)
Set-CursorInstallLinkDisplay

$statusPanel.Controls.Add($script:CheckUpdateLink)
$statusPanel.Controls.Add($script:CursorInstallLink)
$statusPanel.Controls.Add($lblStatus)

$toolbarPanel = New-Object System.Windows.Forms.Panel
$toolbarPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$toolbarPanel.Height = 94
$toolbarPanel.BackColor = $script:UiPanelColor
$toolbarPanel.Padding = New-Object System.Windows.Forms.Padding(14, 8, 14, 8)

$script:ToolbarTable = New-Object System.Windows.Forms.TableLayoutPanel
$script:ToolbarTable.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:ToolbarTable.RowCount = 2
$script:ToolbarTable.ColumnCount = 1
$script:ToolbarTable.Margin = New-Object System.Windows.Forms.Padding 0
$script:ToolbarTable.Padding = New-Object System.Windows.Forms.Padding 0
[void]$script:ToolbarTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38)))
[void]$script:ToolbarTable.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38)))
[void]$script:ToolbarTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))

$script:ProfileTable = New-Object System.Windows.Forms.TableLayoutPanel
$script:ProfileTable.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:ProfileTable.RowCount = 1
$script:ProfileTable.ColumnCount = 2
$script:ProfileTable.Margin = New-Object System.Windows.Forms.Padding 0
$script:ProfileTable.Padding = New-Object System.Windows.Forms.Padding 0
[void]$script:ProfileTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 58)))
[void]$script:ProfileTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))

$script:LblProfilesSection = New-ToolbarSectionLabel -Text 'Profiles'
$script:ProfileFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$script:ProfileFlow.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:ProfileFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$script:ProfileFlow.WrapContents = $false
$script:ProfileFlow.Margin = New-Object System.Windows.Forms.Padding 0
$script:ProfileFlow.Padding = New-Object System.Windows.Forms.Padding 0, 4, 0, 0
$script:ProfileFlow.AutoSize = $false

$script:ProfileTable.Controls.Add($script:LblProfilesSection, 0, 0)
$script:ProfileTable.Controls.Add($script:ProfileFlow, 1, 0)
$script:ToolbarTable.Controls.Add($script:ProfileTable, 0, 0)

$script:LaunchTable = New-Object System.Windows.Forms.TableLayoutPanel
$script:LaunchTable.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:LaunchTable.RowCount = 1
$script:LaunchTable.ColumnCount = 2
$script:LaunchTable.Margin = New-Object System.Windows.Forms.Padding 0
$script:LaunchTable.Padding = New-Object System.Windows.Forms.Padding 0
[void]$script:LaunchTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 430)))
[void]$script:LaunchTable.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))

$script:ThemeFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$script:ThemeFlow.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:ThemeFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$script:ThemeFlow.WrapContents = $false
$script:ThemeFlow.Margin = New-Object System.Windows.Forms.Padding 0
$script:ThemeFlow.Padding = New-Object System.Windows.Forms.Padding 0, 4, 0, 0

$script:LblLaunchHint = New-Object System.Windows.Forms.Label
$script:LblLaunchHint.Text = 'Double-click a row to start  |  Actions: Start, Focus, Close, Folder, Edit, Del'
$script:LblLaunchHint.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:LblLaunchHint.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$script:LblLaunchHint.ForeColor = $script:UiTextMuted
$script:LblLaunchHint.BackColor = $script:UiPanelColor
$script:LblLaunchHint.Margin = New-Object System.Windows.Forms.Padding 8, 0, 8, 0
$script:LblLaunchHint.AutoEllipsis = $true

$script:LaunchTable.Controls.Add($script:ThemeFlow, 0, 0)
$script:LaunchTable.Controls.Add($script:LblLaunchHint, 1, 0)
$script:ToolbarTable.Controls.Add($script:LaunchTable, 0, 1)
$toolbarPanel.Controls.Add($script:ToolbarTable)

$toolbarSep = New-Object System.Windows.Forms.Panel
$toolbarSep.Dock = [System.Windows.Forms.DockStyle]::Bottom
$toolbarSep.Height = 1
$toolbarSep.BackColor = $script:UiBorderColor

$contentPanel = New-Object System.Windows.Forms.Panel
$contentPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$contentPanel.BackColor = $script:UiBackColor
$contentPanel.Padding = New-Object System.Windows.Forms.Padding(14, 14, 14, 14)

$gridHost = New-Object System.Windows.Forms.Panel
$gridHost.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridHost.BackColor = $script:UiPanelColor
$gridHost.Padding = New-Object System.Windows.Forms.Padding(1)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Dock = [System.Windows.Forms.DockStyle]::Fill
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.RowHeadersVisible = $false
$grid.EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditProgrammatically

[void]$grid.Columns.Add('Name', 'Name')
[void]$grid.Columns.Add('UserDataDir', 'User Data Dir')
[void]$grid.Columns.Add('Instances', 'Instances')
[void]$grid.Columns.Add('Status', 'Status')

$colProxy = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$colProxy.Name = 'Proxy'
$colProxy.HeaderText = 'Proxy'
$colProxy.Width = 45
$colProxy.MinimumWidth = 45
$colProxy.FillWeight = 40
$colProxy.ReadOnly = $true
$colProxy.DefaultCellStyle.Alignment = [System.Drawing.ContentAlignment]::MiddleCenter
[void]$grid.Columns.Add($colProxy)

[void]$grid.Columns.Add('Notes', 'Notes')
Add-GridActionColumns -TargetGrid $grid

$grid.Columns['Name'].ReadOnly = $true
$grid.Columns['UserDataDir'].ReadOnly = $true
$grid.Columns['Instances'].ReadOnly = $true
$grid.Columns['Status'].ReadOnly = $true
$grid.Columns['Proxy'].ReadOnly = $true
$grid.Columns['Notes'].ReadOnly = $true

$grid.Columns['Name'].FillWeight = 90
$grid.Columns['UserDataDir'].FillWeight = 180
$grid.Columns['Instances'].FillWeight = 45
$grid.Columns['Instances'].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleCenter
$grid.Columns['Status'].FillWeight = 55
$grid.Columns['Notes'].FillWeight = 100

# Reduce paint flicker during frequent status updates.
$grid.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance, NonPublic').SetValue($grid, $true, $null)
Apply-DataGridTheme -TargetGrid $grid

$gridHost.Controls.Add($grid)
$contentPanel.Controls.Add($gridHost)
$form.Controls.Add($contentPanel)
$form.Controls.Add($toolbarSep)
$form.Controls.Add($toolbarPanel)
$form.Controls.Add($statusPanel)

$script:GridModel = $null
$script:DefaultGridForeColor = $script:UiTextPrimary
$script:RunningGridForeColor = $script:UiRunningColor

$btnAdd = New-ToolbarButton -Text 'Add'
$btnRefresh = New-ToolbarButton -Text 'Refresh'
$script:sepAgentStory = New-ToolbarFlowSeparator
$script:btnAgentStory = New-ToolbarButton -Text 'Start Agent Story' -Width 132
$script:lblAgentStoryStatus = New-Object System.Windows.Forms.Label
$script:lblAgentStoryStatus.Text = "$([char]0x25CB) Agent Story: Stopped"
$script:lblAgentStoryStatus.ForeColor = $script:UiTextMuted
$script:lblAgentStoryStatus.BackColor = $script:UiPanelColor
$script:lblAgentStoryStatus.AutoSize = $true
$script:lblAgentStoryStatus.Margin = New-Object System.Windows.Forms.Padding 0, 6, 8, 0
$script:lblAgentStoryStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

$script:lnkAgentStoryOpen = New-Object System.Windows.Forms.LinkLabel
$script:lnkAgentStoryOpen.Text = 'Open dashboard'
$script:lnkAgentStoryOpen.AutoSize = $true
$script:lnkAgentStoryOpen.Visible = $false
$script:lnkAgentStoryOpen.Enabled = $false
$script:lnkAgentStoryOpen.BackColor = $script:UiPanelColor
$script:lnkAgentStoryOpen.LinkColor = $script:UiAccent
$script:lnkAgentStoryOpen.ActiveLinkColor = $script:UiAccentHover
$script:lnkAgentStoryOpen.VisitedLinkColor = $script:UiAccent
$script:lnkAgentStoryOpen.Margin = New-Object System.Windows.Forms.Padding 0, 6, 8, 0
$script:lnkAgentStoryOpen.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$script:lnkAgentStoryOpen.Add_LinkClicked({
    [void](Open-AgentStoryDashboard)
})

$script:ProfileFlow.Controls.AddRange(@(
    $btnAdd,
    $btnRefresh,
    $script:sepAgentStory,
    $script:btnAgentStory,
    $script:lblAgentStoryStatus,
    $script:lnkAgentStoryOpen
))

$script:ThemeLabel = New-Object System.Windows.Forms.Label
$script:ThemeLabel.Text = 'Theme:'
$script:ThemeLabel.AutoSize = $true
$script:ThemeLabel.ForeColor = $script:UiTextMuted
$script:ThemeLabel.BackColor = $script:UiPanelColor
$script:ThemeLabel.Margin = New-Object System.Windows.Forms.Padding 0, 6, 4, 0
$script:ThemeLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

$script:ThemeCombo = New-Object System.Windows.Forms.ComboBox
$script:ThemeCombo.DropDownStyle = 'DropDownList'
$script:ThemeCombo.Size = New-Object System.Drawing.Size(118, 23)
$script:ThemeCombo.Margin = New-Object System.Windows.Forms.Padding 0, 4, 0, 0
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
$script:ThemeFlow.Controls.AddRange(@($script:ThemeLabel, $script:ThemeCombo))

$script:ChkMinimizeToTray = New-Object System.Windows.Forms.CheckBox
$script:ChkMinimizeToTray.Text = 'Minimize to tray'
$script:ChkMinimizeToTray.AutoSize = $true
$script:ChkMinimizeToTray.Margin = New-Object System.Windows.Forms.Padding 12, 6, 0, 0
$script:ChkMinimizeToTray.ForeColor = $script:UiTextPrimary
$script:ChkMinimizeToTray.BackColor = $script:UiPanelColor
$script:ChkMinimizeToTray.Add_CheckedChanged({
    if ($script:AppOptionsCheckSync) { return }
    Set-AppMinimizeToTrayPreference -Enabled $script:ChkMinimizeToTray.Checked -Persist
})

$script:ChkAutoStartWithWindows = New-Object System.Windows.Forms.CheckBox
$script:ChkAutoStartWithWindows.Text = 'Start with Windows'
$script:ChkAutoStartWithWindows.AutoSize = $true
$script:ChkAutoStartWithWindows.Margin = New-Object System.Windows.Forms.Padding 12, 6, 0, 0
$script:ChkAutoStartWithWindows.ForeColor = $script:UiTextPrimary
$script:ChkAutoStartWithWindows.BackColor = $script:UiPanelColor
$script:ChkAutoStartWithWindows.Add_CheckedChanged({
    if ($script:AppOptionsCheckSync) { return }
    Set-AppAutoStartPreference -Enabled $script:ChkAutoStartWithWindows.Checked -Persist
})

$script:ThemeFlow.Controls.AddRange(@($script:ChkMinimizeToTray, $script:ChkAutoStartWithWindows))
Sync-AppOptionsCheckboxes

Apply-ToolbarTheme

$btnAdd.Add_Click({
    if (-not (Test-CursorInstallReady)) { return }

    $result = Show-ProfileDialog -Existing $null
    if ($result) {
        if (Get-ProfilesList | Where-Object { $_.Name -eq $result.Name }) {
            [System.Windows.Forms.MessageBox]::Show("A profile named '$($result.Name)' already exists.", 'Duplicate name', 'OK', 'Warning') | Out-Null
            return
        }
        $newProfile = New-ProfileObject -Name $result.Name -UserDataDir $result.UserDataDir -ProjectPath $result.ProjectPath -Notes $result.Notes -RunProxied $result.RunProxied
        $script:Profiles = Normalize-ProfilesList -Profiles (@(Get-ProfilesList) + $newProfile)
        Save-Profiles -Profiles $script:Profiles
        Update-ProfileGrid
    }
})

$btnRefresh.Add_Click({
    [void](Get-CursorInstallInfo -ForceRefresh)
    Update-CursorInstallUi
    Update-ProfileGrid
})

$script:btnAgentStory.Add_Click({
    if (Test-AgentStoryAnyRunning) {
        Stop-AgentStory
    }
    else {
        [void](Start-AgentStoryProxy)
    }
})

$grid.Add_CellContentClick({
    param($sender, $e)
    if ($e.RowIndex -lt 0) { return }

    $column = $grid.Columns[$e.ColumnIndex]
    if ($column -isnot [System.Windows.Forms.DataGridViewButtonColumn]) { return }

    $profile = Get-ProfileFromGridRow -RowIndex $e.RowIndex
    if (-not $profile) { return }

    Invoke-GridProfileAction -Profile $profile -ActionName $column.Name
})

$grid.Add_CellDoubleClick({
    param($s, $e)
    if ($e.RowIndex -lt 0) { return }
    if ($grid.Columns[$e.ColumnIndex] -is [System.Windows.Forms.DataGridViewButtonColumn]) { return }
    [void](Start-ProfileFromGridRow -RowIndex $e.RowIndex)
})

$processEventDebounce = New-Object System.Windows.Forms.Timer
$processEventDebounce.Interval = 500
$script:ProcessEventDebounceTimer = $processEventDebounce
$processEventDebounce.Add_Tick({
    Invoke-UiRefreshSafe {
        $processEventDebounce.Stop()
        Update-ProfileGrid
    }
})

$refreshTimer = New-Object System.Windows.Forms.Timer
$refreshTimer.Interval = 2000
$refreshTimer.Add_Tick({
    Invoke-UiRefreshSafe {
        if (Test-UiSystemThemeChanged) {
            Set-UiThemePreference -Preference $script:UiThemePreference
        }
        Update-ProfileGrid
        Update-AgentStoryUiState
    }
})
$refreshTimer.Start()

Start-CursorProcessWatchers -OwnerForm $form -DebounceTimer $processEventDebounce

$form.Add_Resize({
    if ($script:TrayMinimizeSync) { return }
    if (-not $script:MinimizeToTray) { return }
    if ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized) { return }
    Hide-MainWindowToTray
})

$form.Add_FormClosing({
    param($sender, $e)

    if ($script:UiShuttingDown) { return }

    if ($script:MinimizeToTray -and -not $script:UiExitConfirmed -and $e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
        $e.Cancel = $true
        Hide-MainWindowToTray
        return
    }

    if (-not $script:UiExitConfirmed) {
        if (-not (Confirm-AppExitIfNeeded)) {
            $e.Cancel = $true
            return
        }
        $script:UiExitConfirmed = $true
    }

    $script:UiShuttingDown = $true
    $refreshTimer.Stop()
    $processEventDebounce.Stop()
    Stop-CursorProcessWatchers
    if ($script:TrayNotifyIcon) {
        $script:TrayNotifyIcon.Visible = $false
        $script:TrayNotifyIcon.Dispose()
        $script:TrayNotifyIcon = $null
    }
    Stop-AgentStory
})

[void](Get-CursorInstallInfo -ForceRefresh)
Update-CursorInstallUi

Update-ProfileGrid
Update-AgentStoryUiState

if ($StartMinimized -and $script:MinimizeToTray) {
    $form.Add_Shown({
        if ($script:MinimizeToTray) {
            Hide-MainWindowToTray
        }
    })
}

[void]$form.ShowDialog()
}
catch {
    Show-StartupFailure -Message "Cursor Profile Manager failed to start:`n`n$($_.Exception.Message)"
    $script:StartupFailed = $true
}

if ($script:StartupFailed) {
    exit 1
}
