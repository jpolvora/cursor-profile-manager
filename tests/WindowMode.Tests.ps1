#Requires -Version 5.1

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'Bootstrap.ps1')
. (Join-Path $here 'TestHelpers.ps1')

Describe 'Profile WindowMode helpers' {
    Context 'Get-ProfileWindowModeFromValue' {
        It 'defaults empty and invalid values to default' {
            Get-ProfileWindowModeFromValue -WindowMode '' | Should Be 'default'
            Get-ProfileWindowModeFromValue -WindowMode 'foo' | Should Be 'default'
            Get-ProfileWindowModeFromValue -WindowMode 'DEFAULT' | Should Be 'default'
        }

        It 'accepts classic and glass' {
            Get-ProfileWindowModeFromValue -WindowMode 'classic' | Should Be 'classic'
            Get-ProfileWindowModeFromValue -WindowMode 'glass' | Should Be 'glass'
            Get-ProfileWindowModeFromValue -WindowMode 'default' | Should Be 'default'
        }
    }

    Context 'Get-ProfileWindowMode' {
        It 'defaults missing WindowMode property to default' {
            $profile = New-TestProfile -Name 'plain'
            $profile.PSObject.Properties.Remove('WindowMode')
            Get-ProfileWindowMode -Profile $profile | Should Be 'default'
        }

        It 'reads classic and glass from profile' {
            $classic = New-TestProfile -Name 'classic' -WindowMode 'classic'
            $glass = New-TestProfile -Name 'glass' -WindowMode 'glass'
            Get-ProfileWindowMode -Profile $classic | Should Be 'classic'
            Get-ProfileWindowMode -Profile $glass | Should Be 'glass'
        }

        It 'defaults null profile to default' {
            Get-ProfileWindowMode -Profile $null | Should Be 'default'
        }
    }

    Context 'Index round-trip' {
        It 'maps index to mode and back' {
            Get-ProfileWindowModeFromIndex -Index 0 | Should Be 'default'
            Get-ProfileWindowModeFromIndex -Index 1 | Should Be 'classic'
            Get-ProfileWindowModeFromIndex -Index 2 | Should Be 'glass'
            Get-ProfileWindowModeFromIndex -Index 99 | Should Be 'default'

            Get-ProfileWindowModeIndex -WindowMode 'default' | Should Be 0
            Get-ProfileWindowModeIndex -WindowMode 'classic' | Should Be 1
            Get-ProfileWindowModeIndex -WindowMode 'glass' | Should Be 2
            Get-ProfileWindowModeIndex -WindowMode 'nope' | Should Be 0
        }
    }

    Context 'Get-CursorWindowModeLaunchArgs' {
        It 'returns empty array for default' {
            $args = @(Get-CursorWindowModeLaunchArgs -WindowMode 'default')
            $args.Count | Should Be 0
            ($args -contains '--classic') | Should Be $false
            ($args -contains '--glass') | Should Be $false
        }

        It 'returns --classic only for classic' {
            $args = @(Get-CursorWindowModeLaunchArgs -WindowMode 'classic')
            $args.Count | Should Be 1
            $args[0] | Should Be '--classic'
            ($args -contains '--glass') | Should Be $false
        }

        It 'returns --glass only for glass' {
            $args = @(Get-CursorWindowModeLaunchArgs -WindowMode 'glass')
            $args.Count | Should Be 1
            $args[0] | Should Be '--glass'
            ($args -contains '--classic') | Should Be $false
        }
    }

    Context 'New-ProfileObject WindowMode' {
        It 'defaults WindowMode to default' {
            $profile = New-ProfileObject -Name 'n' -UserDataDir 'C:\p' -ProjectPath '' -Notes ''
            $profile.WindowMode | Should Be 'default'
        }

        It 'stores explicit WindowMode values' {
            $classic = New-ProfileObject -Name 'c' -UserDataDir 'C:\c' -ProjectPath '' -Notes '' -WindowMode 'classic'
            $glass = New-ProfileObject -Name 'g' -UserDataDir 'C:\g' -ProjectPath '' -Notes '' -WindowMode 'glass'
            $classic.WindowMode | Should Be 'classic'
            $glass.WindowMode | Should Be 'glass'
        }

        It 'normalizes invalid WindowMode to default' {
            $profile = New-ProfileObject -Name 'bad' -UserDataDir 'C:\b' -ProjectPath '' -Notes '' -WindowMode 'nope'
            $profile.WindowMode | Should Be 'default'
        }
    }
}
