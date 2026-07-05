#Requires -Version 5.1

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'Bootstrap.ps1')
. (Join-Path $here 'TestHelpers.ps1')

Describe 'Grid model' {

    Context 'New-GridRowModel' {
        It 'marks idle profiles with zero instances' {
            $profile = New-TestProfile -Name 'idle-profile'
            $row = New-GridRowModel -Profile $profile -InstanceCount 0

            $row.IsRunning | Should Be $false
            $row.Instances | Should Be 0
            $row.Status | Should Be $UiStatusIdle
        }

        It 'marks running profiles with a positive instance count' {
            $profile = New-TestProfile -Name 'running-profile'
            $row = New-GridRowModel -Profile $profile -InstanceCount 2

            $row.IsRunning | Should Be $true
            $row.Instances | Should Be 2
            $row.Status | Should Be $UiStatusRunning
        }

        It 'includes RunProxied in row model' {
            $profile = New-TestProfile -Name 'proxied' -RunProxied $true
            $row = New-GridRowModel -Profile $profile -InstanceCount 0
            $row.RunProxied | Should Be $true
        }
    }

    Context 'Test-GridRowModelEqual and Test-GridModelEqual' {
        It 'detects row differences' {
            $profile = New-TestProfile -Name 'same'
            $rowA = New-GridRowModel -Profile $profile -InstanceCount 0
            $rowB = New-GridRowModel -Profile $profile -InstanceCount 1

            Test-GridRowModelEqual -A $rowA -B $rowB | Should Be $false
        }

        It 'detects RunProxied differences' {
            $profileA = New-TestProfile -Name 'same' -RunProxied $false
            $profileB = New-TestProfile -Name 'same' -RunProxied $true
            $rowA = New-GridRowModel -Profile $profileA -InstanceCount 0
            $rowB = New-GridRowModel -Profile $profileB -InstanceCount 0
            Test-GridRowModelEqual -A $rowA -B $rowB | Should Be $false
        }

        It 'detects model order differences' {
            $profileA = New-TestProfile -Name 'a'
            $profileB = New-TestProfile -Name 'b'
            $rowA = New-GridRowModel -Profile $profileA -InstanceCount 0
            $rowB = New-GridRowModel -Profile $profileB -InstanceCount 0

            $modelA = [PSCustomObject]@{
                Order    = @($profileA.Id, $profileB.Id)
                RowsById = @{
                    $profileA.Id = $rowA
                    $profileB.Id = $rowB
                }
            }
            $modelB = [PSCustomObject]@{
                Order    = @($profileB.Id, $profileA.Id)
                RowsById = @{
                    $profileA.Id = $rowA
                    $profileB.Id = $rowB
                }
            }

            Test-GridModelEqual -A $modelA -B $modelB | Should Be $false
        }

        It 'returns true for identical models' {
            $profile = New-TestProfile -Name 'same'
            $row = New-GridRowModel -Profile $profile -InstanceCount 0
            $model = [PSCustomObject]@{
                Order    = @($profile.Id)
                RowsById = @{ $profile.Id = $row }
            }

            Test-GridModelEqual -A $model -B $model | Should Be $true
        }
    }

    Context 'Get-ProfileInstanceCount' {
        It 'normalizes path separators and casing' {
            $counts = @{
                'c:\profiles\work' = 2
            }

            Get-ProfileInstanceCount -UserDataDir 'C:\Profiles\Work\' -InstanceCounts $counts | Should Be 2
        }

        It 'returns zero when the profile path is not running' {
            Get-ProfileInstanceCount -UserDataDir 'C:\missing' -InstanceCounts @{} | Should Be 0
        }
    }

    Context 'Build-GridModel' {
        It 'builds rows for configured profiles' {
            $script:Profiles = @(
                (New-TestProfile -Name 'one' -UserDataDir 'C:\profiles\one'),
                (New-TestProfile -Name 'two' -UserDataDir 'C:\profiles\two')
            )

            $model = Build-GridModel

            $model.Order.Count | Should Be 2
            $model.RowsById[$script:Profiles[0].Id].Name | Should Be 'one'
            $model.RowsById[$script:Profiles[1].Id].Name | Should Be 'two'
        }
    }
}
