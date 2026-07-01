#Requires -Version 5.1

function Reset-ProfileManagerTestProfilesDir {
    if ([string]::IsNullOrWhiteSpace($global:ProfileManagerTestProfilesDir)) {
        return
    }
    if (Test-Path -LiteralPath $global:ProfileManagerTestProfilesDir) {
        Remove-Item -LiteralPath $global:ProfileManagerTestProfilesDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $global:ProfileManagerTestProfilesDir -Force | Out-Null
}

function Restore-ProfileManagerTestHarness {
    if ($global:ProfileManagerOriginalProfilesDir) {
        $env:CURSOR_PROFILES_DIR = $global:ProfileManagerOriginalProfilesDir
    }
    else {
        Remove-Item Env:CURSOR_PROFILES_DIR -ErrorAction SilentlyContinue
    }
}

function New-TestProfile {
    param(
        [string]$Name = 'test-profile',
        [string]$UserDataDir = 'C:\Test\profile-a',
        [string]$ProjectPath = '',
        [string]$Notes = ''
    )

    return New-ProfileObject -Name $Name -UserDataDir $UserDataDir -ProjectPath $ProjectPath -Notes $Notes
}

function New-TestCursorProcessRecord {
    param(
        [int]$ProcessId,
        [int]$ParentProcessId = 0,
        [string]$CommandLine
    )

    return [PSCustomObject]@{
        ProcessId       = $ProcessId
        ParentProcessId = $ParentProcessId
        CommandLine     = $CommandLine
    }
}
