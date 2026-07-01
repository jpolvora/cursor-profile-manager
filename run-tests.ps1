#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the Cursor Profile Manager unit test suite (Pester 3.x+).
#>
param()

$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$testsPath = Join-Path $repoRoot 'tests'

if (-not (Test-Path -LiteralPath $testsPath)) {
    Write-Error "Tests folder not found: $testsPath"
}

if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Error 'Pester is required. Install with: Install-Module Pester -Scope CurrentUser'
}

Import-Module Pester -Force

. (Join-Path $testsPath 'TestHelpers.ps1')

Push-Location $repoRoot
try {
    $result = Invoke-Pester -Path $testsPath -PassThru -Strict
}
finally {
    Pop-Location
    if (Get-Command Restore-ProfileManagerTestHarness -ErrorAction SilentlyContinue) {
        Restore-ProfileManagerTestHarness
    }
}

Write-Host ''
Write-Host ("Passed: {0}  Failed: {1}  Total: {2}" -f $result.PassedCount, $result.FailedCount, $result.TotalCount)

if ($result.FailedCount -gt 0) {
    exit 1
}

exit 0
