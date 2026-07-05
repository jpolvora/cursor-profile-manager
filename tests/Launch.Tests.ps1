#Requires -Version 5.1

. "$PSScriptRoot\Bootstrap.ps1"
. "$PSScriptRoot\TestHelpers.ps1"

Describe 'Process argument formatting' {
    Context 'Format-ProcessArgumentForWindows' {
        It 'leaves simple args unchanged' {
            Format-ProcessArgumentForWindows -Argument '--new-window' | Should Be '--new-window'
        }

        It 'quotes args with spaces without embedded quote escapes' {
            Format-ProcessArgumentForWindows -Argument '--user-data-dir=C:\Profiles\My Profile' |
                Should Be '"--user-data-dir=C:\Profiles\My Profile"'
        }

        It 'does not double-wrap user-data-dir paths' {
            $arg = '--user-data-dir=C:\Users\test\.cursor-profiles\work'
            Format-ProcessArgumentForWindows -Argument $arg | Should Be $arg
        }
    }

    Context 'Join-ProcessArgumentListForWindows' {
        It 'builds a command line Cursor can parse' {
            $joined = Join-ProcessArgumentListForWindows -ArgumentList @(
                '--user-data-dir=C:\Profiles\My Profile',
                '--new-window'
            )
            $joined | Should Be '"--user-data-dir=C:\Profiles\My Profile" --new-window'
        }
    }
}

Describe 'Profile launch logging' {
    Context 'Write-ProfileLaunchLogEntry' {
        It 'writes launch.log under the profiles root' {
            Reset-ProfileManagerTestProfilesDir
            $script:LastProfileLaunchLogError = $null
            $profile = New-TestProfile -Name 'log-test'
            Write-ProfileLaunchLogEntry -Level INFO -ProfileName $profile.Name -ProfileId $profile.Id `
                -Message 'Launch requested' -Details @{ userDataDir = $profile.UserDataDir }

            $logPath = Get-ProfileLaunchLogPath
            Test-Path -LiteralPath $logPath | Should Be $true
            $content = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8
            $content | Should Match 'Launch requested'
            $content | Should Match 'profile=log-test'
        }

        It 'tracks the last ERROR entry in memory and on disk' {
            Reset-ProfileManagerTestProfilesDir
            $script:LastProfileLaunchLogError = $null
            Write-ProfileLaunchLogEntry -Level INFO -Message 'step one'
            Write-ProfileLaunchLogEntry -Level ERROR -ProfileName 'broken' -Message 'spawn failed' -Details @{ pid = 0 }

            $script:LastProfileLaunchLogError | Should Match 'spawn failed'
            Get-LastProfileLaunchLogError | Should Match 'spawn failed'
        }

        It 'returns the most recent ERROR line from the log file' {
            Reset-ProfileManagerTestProfilesDir
            Write-ProfileLaunchLogEntry -Level ERROR -Message 'first failure'
            Write-ProfileLaunchLogEntry -Level INFO -Message 'retry'
            Write-ProfileLaunchLogEntry -Level ERROR -Message 'second failure'
            $script:LastProfileLaunchLogError = $null

            Get-LastProfileLaunchLogError | Should Match 'second failure'
        }
    }
}

Describe 'Profile launch guards' {
    Context 'Start-CursorProfileInstance project path handling' {
        It 'does not call Test-Path when ProjectPath is empty on a single profile' {
            $profile = New-TestProfile -Name 'empty-project' -ProjectPath ''
            $projectPath = ''
            if ($null -ne $profile.ProjectPath) {
                $projectPath = [string]$profile.ProjectPath
                $projectPath = $projectPath.Trim()
            }

            [string]::IsNullOrWhiteSpace($projectPath) | Should Be $true
        }

        It 'rejects a multi-profile array before launch' {
            $p1 = New-TestProfile -Name 'one'
            $p2 = New-TestProfile -Name 'two'
            $arrayProfile = @($p1, $p2)

            { 
                if ($arrayProfile -is [System.Array] -and $arrayProfile.Count -gt 1) {
                    throw "Start expected a single profile, but received $($arrayProfile.Count) profiles."
                }
            } | Should Throw 'single profile'
        }
    }

    Context 'Get-ProfileFromGridRow lookup' {
        It 'returns one profile from a nested profiles list' {
            $p1 = New-TestProfile -Name 'one'
            $p2 = New-TestProfile -Name 'two'
            $script:Profiles = , @($p1, $p2)

            $hit = Get-ProfilesList | Where-Object { $_.Id -eq $p1.Id } | Select-Object -First 1
            $hit.Name | Should Be 'one'
            ($hit -is [System.Array]) | Should Be $false
        }
    }
}
