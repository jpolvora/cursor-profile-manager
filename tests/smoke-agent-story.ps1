#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'cursor-profile-manager.ps1') -FunctionsOnly

$script:InstallRoot = $repoRoot
Stop-AgentStory
Start-Sleep -Milliseconds 500

$root = Find-AgentStoryRoot
Write-Host "Find-AgentStoryRoot => $root"
if (-not $root) { exit 1 }

$expected = Join-Path $repoRoot 'agent-story'
if ($root -ne (Resolve-Path $expected).Path) {
    Write-Error "Expected embedded path, got: $root"
}

$started = Start-AgentStoryProxy
Write-Host "Start-AgentStoryProxy => $started"
if (-not $started) { exit 1 }

Start-Sleep -Seconds 3

$proxyAlive = $false
$uiAlive = $false
if ($script:AgentStoryProxyProcess -and -not $script:AgentStoryProxyProcess.HasExited) { $proxyAlive = $true }
if ($script:AgentStoryUiProcess -and -not $script:AgentStoryUiProcess.HasExited) { $uiAlive = $true }

Write-Host "Proxy alive: $proxyAlive (PID $($script:AgentStoryProxyProcess.Id))"
Write-Host "UI alive: $uiAlive (PID $($script:AgentStoryUiProcess.Id))"

Stop-AgentStory

if (-not $proxyAlive) { exit 2 }
if (-not $uiAlive) { exit 3 }
exit 0
