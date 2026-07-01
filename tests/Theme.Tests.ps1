#Requires -Version 5.1

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'Bootstrap.ps1')
. (Join-Path $here 'TestHelpers.ps1')

Describe 'UI theme helpers' {

    Context 'Get-UiThemePreferenceIndex and Get-UiThemePreferenceFromIndex' {
        It 'maps default preference to index 0' {
            Get-UiThemePreferenceIndex -Preference 'default' | Should Be 0
            Get-UiThemePreferenceFromIndex -Index 0 | Should Be 'default'
        }

        It 'maps light and dark preferences' {
            Get-UiThemePreferenceIndex -Preference 'light' | Should Be 1
            Get-UiThemePreferenceFromIndex -Index 1 | Should Be 'light'
            Get-UiThemePreferenceIndex -Preference 'dark' | Should Be 2
            Get-UiThemePreferenceFromIndex -Index 2 | Should Be 'dark'
        }
    }

    Context 'Get-EffectiveUiThemeName' {
        It 'returns explicit light and dark preferences' {
            Get-EffectiveUiThemeName -Preference 'light' | Should Be 'light'
            Get-EffectiveUiThemeName -Preference 'dark' | Should Be 'dark'
        }
    }

    Context 'Get-UiThemePalettes and Set-UiThemePalette' {
        It 'defines light and dark palettes' {
            $palettes = Get-UiThemePalettes
            $palettes.ContainsKey('light') | Should Be $true
            $palettes.ContainsKey('dark') | Should Be $true
        }

        It 'applies palette colors to script theme variables' {
            Set-UiThemePalette -ThemeName 'dark'

            $script:UiEffectiveTheme | Should Be 'dark'
            $script:UiBackColor | Should Not BeNullOrEmpty
            $script:UiTextPrimary | Should Not BeNullOrEmpty
        }
    }
}
