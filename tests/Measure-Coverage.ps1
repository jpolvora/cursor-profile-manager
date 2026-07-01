#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$mainScript = Join-Path $repoRoot 'cursor-profile-manager.ps1'
$testFiles = Get-ChildItem -Path $PSScriptRoot -Filter '*.Tests.ps1'

$scriptLines = Get-Content -LiteralPath $mainScript
$functions = @{}
$current = $null
$start = 0
for ($i = 0; $i -lt $scriptLines.Count; $i++) {
    $lineNo = $i + 1
    if ($scriptLines[$i] -match '^function\s+([A-Za-z0-9-]+)\s*\{') {
        if ($current) {
            $functions[$current] = @{ Start = $start; End = $lineNo - 1 }
        }
        $current = $Matches[1]
        $start = $lineNo
    }
}
if ($current) {
    $functions[$current] = @{ Start = $start; End = $scriptLines.Count }
}

function Get-FunctionBodyLines {
    param([string]$Name)
    if (-not $functions.ContainsKey($Name)) { return 0 }
    $range = $functions[$Name]
    $count = 0
    for ($ln = $range.Start; $ln -le $range.End; $ln++) {
        $text = $scriptLines[$ln - 1].Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text.StartsWith('#')) { continue }
        $count++
    }
    return $count
}

$calledBy = @{}
foreach ($name in $functions.Keys) {
    $calledBy[$name] = New-Object 'System.Collections.Generic.HashSet[string]'
}

foreach ($name in $functions.Keys) {
    $range = $functions[$name]
    for ($ln = $range.Start; $ln -le $range.End; $ln++) {
        $line = $scriptLines[$ln - 1]
        foreach ($match in [regex]::Matches($line, '\b([A-Z][a-z]+-[A-Za-z0-9]+)\b')) {
            $callee = $match.Groups[1].Value
            if ($functions.ContainsKey($callee) -and $callee -ne $name) {
                [void]$calledBy[$name].Add($callee)
            }
        }
    }
}

$directlyTested = New-Object 'System.Collections.Generic.HashSet[string]'
$testContent = ($testFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName }) -join "`n"
foreach ($match in [regex]::Matches($testContent, '\b([A-Z][a-z]+-[A-Za-z0-9]+)\b')) {
    $fn = $match.Groups[1].Value
    if ($functions.ContainsKey($fn)) {
        [void]$directlyTested.Add($fn)
    }
}

$exercised = New-Object 'System.Collections.Generic.HashSet[string]'
$queue = New-Object 'System.Collections.Generic.Queue[string]'
foreach ($fn in $directlyTested) {
    $queue.Enqueue($fn)
    [void]$exercised.Add($fn)
}
while ($queue.Count -gt 0) {
    $fn = $queue.Dequeue()
    foreach ($callee in $calledBy[$fn]) {
        if (-not $exercised.Contains($callee)) {
            [void]$exercised.Add($callee)
            $queue.Enqueue($callee)
        }
    }
}

$startupLines = $functions.ContainsKey('Initialize-Win32AppFocus') | Out-Null
$bootstrapEnd = $functions['Initialize-Win32AppFocus'].Start - 1
$guiStart = 0
for ($i = 0; $i -lt $scriptLines.Count; $i++) {
    if ($scriptLines[$i] -match 'if \(\$FunctionsOnly\) \{ return \}') {
        $guiStart = $i + 1
        break
    }
}

$totalLogicLines = 0
$coveredLogicLines = 0
$rows = foreach ($name in ($functions.Keys | Sort-Object)) {
    $lines = Get-FunctionBodyLines -Name $name
    $totalLogicLines += $lines
    $isDirect = $directlyTested.Contains($name)
    $isIndirect = $exercised.Contains($name) -and -not $isDirect
    $covered = $exercised.Contains($name)
    if ($covered) { $coveredLogicLines += $lines }
    $tier = if ($isDirect) { 'direct' } elseif ($isIndirect) { 'indirect' } else { 'none' }

    [PSCustomObject]@{
        Function = $name
        Lines = $lines
        Tier = $tier
    }
}

$pct = if ($totalLogicLines -gt 0) { [math]::Round(100.0 * $coveredLogicLines / $totalLogicLines, 1) } else { 0 }
$guiLines = $scriptLines.Count - $guiStart + 1

Write-Host '=== Code coverage estimate (function-level) ==='
Write-Host ''
Write-Host ("Main script lines (total):           {0}" -f $scriptLines.Count)
Write-Host ("GUI bootstrap block (untested):      ~{0} lines (after -FunctionsOnly guard)" -f $guiLines)
Write-Host ("Function body lines (non-blank):     {0}" -f $totalLogicLines)
Write-Host ("Function body lines exercised:       {0}" -f $coveredLogicLines)
Write-Host ("Estimated function-line coverage:    {0}%" -f $pct)
Write-Host ("Functions total:                     {0}" -f $functions.Count)
Write-Host ("Functions directly tested:           {0}" -f $directlyTested.Count)
Write-Host ("Functions exercised (incl indirect): {0}" -f $exercised.Count)
Write-Host ("Functions not exercised:             {0}" -f ($functions.Count - $exercised.Count))
Write-Host ''

Write-Host '=== By tier ==='
$rows | Group-Object Tier | Sort-Object Name | ForEach-Object {
    $lineSum = ($_.Group | Measure-Object -Property Lines -Sum).Sum
    Write-Host ("{0}: {1} functions, {2} lines" -f $_.Name, $_.Count, $lineSum)
}

Write-Host ''
Write-Host '=== Directly tested functions ==='
$directlyTested | Sort-Object | ForEach-Object { Write-Host "  $_" }

Write-Host ''
Write-Host '=== Indirectly exercised only ==='
$exercised | Where-Object { -not $directlyTested.Contains($_) } | Sort-Object | ForEach-Object { Write-Host "  $_" }

Write-Host ''
Write-Host '=== Not exercised (by area) ==='
$notExercised = $rows | Where-Object { $_.Tier -eq 'none' }
$areas = @{
    'Version / update' = 'Get-AppVersion|ConvertTo-AppVersion|Compare-AppVersion|Get-AppVersionUpdate|Get-Remote|Save-Update|Start-Deferred|Confirm-AppUpdate|Invoke-CheckForAppUpdate|Set-CheckUpdate'
    'Storage / profiles' = 'Load-Profiles|Save-Profiles|New-ProfileObject|Load-AppSettings|Save-AppSettings|Ensure-Profiles'
    'Grid model / view' = 'Grid|ProfileGrid|ProfileFromGrid|SelectedProfile|Start-ProfileFromGrid'
    'Process / launch' = 'UserDataDir|CursorProcess|CursorProfile|Focus|Close|Start-Cursor|Find-Cursor|Get-Cursor'
    'Theme / UI chrome' = 'UiTheme|Toolbar|DataGrid|Button|FormIcon|ThemeCombo|CheckUpdateLink|CursorInstall'
    'Win32 / single instance' = 'Win32|SingleInstance|ExistingAppWindow'
    'Dialogs / actions' = 'Show-|Edit-Profile|Remove-Profile|Invoke-Grid|Open-Profile|Test-CursorInstall'
    'WMI watchers' = 'ProcessWatcher|DeferredGridRefresh'
}
foreach ($area in $areas.Keys | Sort-Object) {
    $pattern = $areas[$area]
    $matches = @($notExercised | Where-Object { $_.Function -match $pattern })
    if ($matches.Count -gt 0) {
        Write-Host ''
        Write-Host "$area ($($matches.Count)):"
        $matches | ForEach-Object { Write-Host ("  {0} ({1} lines)" -f $_.Function, $_.Lines) }
    }
}

$reportPath = Join-Path $PSScriptRoot 'coverage-report.txt'
@(
    "Estimated function-line coverage: $pct% ($coveredLogicLines/$totalLogicLines lines across $($functions.Count) functions)"
    "Direct: $($directlyTested.Count) functions | Indirect: $($exercised.Count - $directlyTested.Count) | None: $($functions.Count - $exercised.Count)"
    ''
    ($rows | Format-Table -AutoSize | Out-String)
) | Set-Content -Path $reportPath -Encoding UTF8

Write-Host ''
Write-Host "Full report: $reportPath"
