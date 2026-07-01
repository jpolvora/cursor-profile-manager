#Requires -Version 5.1

$repoRoot = Split-Path -Parent $PSScriptRoot
$mainScript = Join-Path $repoRoot 'cursor-profile-manager.ps1'
if (-not (Test-Path -LiteralPath $mainScript)) {
    throw "Main script not found: $mainScript"
}

if (-not $global:ProfileManagerTestProfilesDir) {
    $global:ProfileManagerOriginalProfilesDir = $env:CURSOR_PROFILES_DIR
    $global:ProfileManagerTestProfilesDir = Join-Path ([System.IO.Path]::GetTempPath()) 'cursor-profile-manager-unit-tests'
    if (Test-Path -LiteralPath $global:ProfileManagerTestProfilesDir) {
        Remove-Item -LiteralPath $global:ProfileManagerTestProfilesDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $global:ProfileManagerTestProfilesDir -Force | Out-Null
    $env:CURSOR_PROFILES_DIR = $global:ProfileManagerTestProfilesDir
}

. $mainScript -FunctionsOnly
