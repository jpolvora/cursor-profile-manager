#Requires -Version 5.1
<#
.SYNOPSIS
    Creates a Desktop shortcut for the Cursor Profile Manager GUI.

.DESCRIPTION
    Builds a .lnk on the current user's Desktop that launches
    cursor-profile-manager.ps1 silently (no console window), using
    Cursor's own icon when available. Re-run anytime to repair/recreate
    the shortcut after moving this folder.

.PARAMETER Name
    Shortcut display name (without .lnk). Default: "Cursor Profile Manager".

.EXAMPLE
    .\install-desktop-shortcut.ps1
#>
param(
    [string]$Name = 'Cursor Profile Manager'
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$TargetPs1 = Join-Path $RepoRoot 'cursor-profile-manager.ps1'

if (-not (Test-Path $TargetPs1)) {
    throw "Could not find cursor-profile-manager.ps1 next to this script ($RepoRoot)."
}

function Find-CursorIcon {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\cursor\Cursor.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Cursor\Cursor.exe')
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

$DesktopPath = [Environment]::GetFolderPath('Desktop')
$ShortcutPath = Join-Path $DesktopPath "$Name.lnk"

$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($ShortcutPath)

# powershell.exe with -WindowStyle Hidden so no console flashes when launching the GUI
$shortcut.TargetPath = (Get-Command powershell.exe).Source
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TargetPs1`""
$shortcut.WorkingDirectory = $RepoRoot
$shortcut.Description = 'Manage and launch isolated Cursor IDE profiles'
$shortcut.WindowStyle = 7  # minimized, just in case a window flashes

$iconSource = Find-CursorIcon
if ($iconSource) {
    $shortcut.IconLocation = "$iconSource,0"
}

$shortcut.Save()

Write-Host "Shortcut created: $ShortcutPath"
if ($iconSource) {
    Write-Host "Icon source: $iconSource"
}
else {
    Write-Warning 'Cursor.exe not found for icon; shortcut uses the default PowerShell icon.'
}
