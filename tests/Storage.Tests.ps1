#Requires -Version 5.1

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'Bootstrap.ps1')
. (Join-Path $here 'TestHelpers.ps1')

Describe 'Profile and settings storage' {
    BeforeEach {
        Reset-ProfileManagerTestProfilesDir
    }

    Context 'New-ProfileObject' {
        It 'creates a profile with required fields' {
            $profile = New-TestProfile -Name 'work' -UserDataDir 'C:\profiles\work' -ProjectPath 'C:\src\app' -Notes 'main account'

            $profile.Name | Should Be 'work'
            $profile.UserDataDir | Should Be 'C:\profiles\work'
            $profile.ProjectPath | Should Be 'C:\src\app'
            $profile.Notes | Should Be 'main account'
            $profile.Id | Should Not BeNullOrEmpty
            $profile.CreatedAt | Should Not BeNullOrEmpty
        }
    }

    Context 'Load-Profiles and Save-Profiles' {
        It 'returns an empty list when profiles.json is missing' {
            $profiles = Load-Profiles
            $profiles.Count | Should Be 0
        }

        It 'round-trips profiles through profiles.json' {
            $profile = New-TestProfile -Name 'alpha'
            Save-Profiles -Profiles @($profile)

            $loaded = @(Load-Profiles)
            $loaded.Count | Should Be 1
            $loaded[0].Name | Should Be 'alpha'
            $loaded[0].Id | Should Be $profile.Id
        }

        It 'adds missing RunProxied property on load' {
            $json = '[{"Id":"test-123","Name":"test-load","UserDataDir":"C:\\temp","ProjectPath":"","Notes":"","CreatedAt":"2026-07-05T12:00:00"}]'
            $badPath = Join-Path $global:ProfileManagerTestProfilesDir 'profiles.json'
            Set-Content -Path $badPath -Value $json -Encoding UTF8

            $loaded = @(Load-Profiles)
            $loaded.Count | Should Be 1
            $loaded[0].RunProxied | Should Be $false
        }

        It 'returns an empty list when profiles.json is corrupt' {
            $badPath = Join-Path $global:ProfileManagerTestProfilesDir 'profiles.json'
            Set-Content -Path $badPath -Value '{ not valid json' -Encoding UTF8

            $profiles = Load-Profiles
            $profiles.Count | Should Be 0
        }
    }

    Context 'Normalize-ProfilesList' {
        It 'flattens a nested profiles array' {
            $p1 = New-TestProfile -Name 'one'
            $p2 = New-TestProfile -Name 'two'
            $nested = , @($p1, $p2)

            $flat = Normalize-ProfilesList -Profiles $nested
            $flat.Count | Should Be 2
            $flat[0].Name | Should Be 'one'
            $flat[1].Name | Should Be 'two'
        }

        It 'returns an empty list for null input' {
            (Normalize-ProfilesList -Profiles $null).Count | Should Be 0
        }
    }

    Context 'Load-AppSettings' {
        It 'loads a saved theme preference' {
            $settingsPath = Join-Path $global:ProfileManagerTestProfilesDir 'settings.json'
            @{ Theme = 'dark' } | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8

            $script:UiThemePreference = 'default'
            Load-AppSettings

            $script:UiThemePreference | Should Be 'dark'
        }

        It 'ignores invalid theme values' {
            $settingsPath = Join-Path $global:ProfileManagerTestProfilesDir 'settings.json'
            @{ Theme = 'neon' } | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8

            $script:UiThemePreference = 'light'
            Load-AppSettings

            $script:UiThemePreference | Should Be 'light'
        }

        It 'loads minimize-to-tray and auto-start preferences' {
            $settingsPath = Join-Path $global:ProfileManagerTestProfilesDir 'settings.json'
            @{
                Theme                = 'default'
                MinimizeToTray       = $true
                AutoStartWithWindows = $true
            } | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8

            $script:MinimizeToTray = $false
            $script:AutoStartWithWindows = $false
            Load-AppSettings

            $script:MinimizeToTray | Should Be $true
            $script:AutoStartWithWindows | Should Be $true
        }
    }
}
