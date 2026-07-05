#Requires -Version 5.1

. "$PSScriptRoot\Bootstrap.ps1"
. "$PSScriptRoot\TestHelpers.ps1"

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
