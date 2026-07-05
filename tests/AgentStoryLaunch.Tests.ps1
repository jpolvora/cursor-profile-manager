#Requires -Version 5.1

. "$PSScriptRoot\Bootstrap.ps1"

Describe 'Agent Story dashboard URL' {
    Context 'Get-AgentStoryUiUrl' {
        It 'returns the default localhost dashboard URL' {
            $previous = $env:AGENT_STORY_UI_URL
            try {
                Remove-Item Env:AGENT_STORY_UI_URL -ErrorAction SilentlyContinue
                Get-AgentStoryUiUrl | Should Be 'http://localhost:5173/'
            }
            finally {
                if ($null -ne $previous) {
                    $env:AGENT_STORY_UI_URL = $previous
                }
                else {
                    Remove-Item Env:AGENT_STORY_UI_URL -ErrorAction SilentlyContinue
                }
            }
        }

        It 'honors AGENT_STORY_UI_URL when set' {
            $previous = $env:AGENT_STORY_UI_URL
            try {
                $env:AGENT_STORY_UI_URL = 'http://127.0.0.1:5173/dashboard'
                Get-AgentStoryUiUrl | Should Be 'http://127.0.0.1:5173/dashboard'
            }
            finally {
                if ($null -ne $previous) {
                    $env:AGENT_STORY_UI_URL = $previous
                }
                else {
                    Remove-Item Env:AGENT_STORY_UI_URL -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

Describe 'Agent Story run state' {
    Context 'Resolve-AgentStoryRunState' {
        It 'returns Stopped when nothing is running' {
            Resolve-AgentStoryRunState -ProxyProcessAlive:$false -UiProcessAlive:$false `
                -ProxyPort8080:$false -ApiPort3001:$false -UiPort5173:$false | Should Be 'Stopped'
        }

        It 'returns Running when proxy and UI ports are listening' {
            Resolve-AgentStoryRunState -ProxyProcessAlive:$false -UiProcessAlive:$false `
                -ProxyPort8080:$true -ApiPort3001:$true -UiPort5173:$true | Should Be 'Running'
        }

        It 'returns Running when tracked processes are alive' {
            Resolve-AgentStoryRunState -ProxyProcessAlive:$true -UiProcessAlive:$true `
                -ProxyPort8080:$false -ApiPort3001:$false -UiPort5173:$false | Should Be 'Running'
        }

        It 'returns Partial when only proxy side is up' {
            Resolve-AgentStoryRunState -ProxyProcessAlive:$false -UiProcessAlive:$false `
                -ProxyPort8080:$true -ApiPort3001:$true -UiPort5173:$false | Should Be 'Partial'
        }

        It 'returns Partial when only UI port is listening' {
            Resolve-AgentStoryRunState -ProxyProcessAlive:$false -UiProcessAlive:$false `
                -ProxyPort8080:$false -ApiPort3001:$false -UiPort5173:$true | Should Be 'Partial'
        }
    }
}

Describe 'Cursor proxy launch helpers' {
    Context 'Get-CursorProxyUrl' {
        It 'returns the default proxy URL' {
            $previous = $env:AGENT_STORY_PROXY_URL
            try {
                Remove-Item Env:AGENT_STORY_PROXY_URL -ErrorAction SilentlyContinue
                Get-CursorProxyUrl | Should Be 'http://127.0.0.1:8080'
            }
            finally {
                if ($null -ne $previous) {
                    $env:AGENT_STORY_PROXY_URL = $previous
                }
                else {
                    Remove-Item Env:AGENT_STORY_PROXY_URL -ErrorAction SilentlyContinue
                }
            }
        }

        It 'honors AGENT_STORY_PROXY_URL when set' {
            $previous = $env:AGENT_STORY_PROXY_URL
            try {
                $env:AGENT_STORY_PROXY_URL = 'http://127.0.0.1:9090'
                Get-CursorProxyUrl | Should Be 'http://127.0.0.1:9090'
            }
            finally {
                if ($null -ne $previous) {
                    $env:AGENT_STORY_PROXY_URL = $previous
                }
                else {
                    Remove-Item Env:AGENT_STORY_PROXY_URL -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context 'Get-CursorProxyLaunchArgs' {
        It 'returns empty args when proxy is disabled' {
            $launchArgs = Get-CursorProxyLaunchArgs -UseProxy:$false
            $launchArgs.Count | Should Be 0
        }

        It 'returns Chromium proxy flags when proxy is enabled' {
            $launchArgs = Get-CursorProxyLaunchArgs -UseProxy:$true
            $launchArgs.Count | Should Be 2
            $launchArgs[0] | Should Be '--proxy-server=http://127.0.0.1:8080'
            $launchArgs[1] | Should Be '--ignore-certificate-errors'
        }
    }

    Context 'Get-CursorProxyEnvironmentVariables' {
        It 'returns empty when proxy is disabled' {
            (Get-CursorProxyEnvironmentVariables -UseProxy:$false).Count | Should Be 0
        }

        It 'returns Node proxy env vars when proxy is enabled' {
            $envVars = Get-CursorProxyEnvironmentVariables -UseProxy:$true
            $envVars.HTTP_PROXY | Should Be 'http://127.0.0.1:8080'
            $envVars.HTTPS_PROXY | Should Be 'http://127.0.0.1:8080'
            $envVars.NODE_TLS_REJECT_UNAUTHORIZED | Should Be '0'
            $envVars.NO_PROXY | Should Be 'localhost,127.0.0.1'
        }
    }

    Context 'Update-CursorProfileProxySettings' {
        It 'writes http.proxy settings when enabled' {
            $tempDir = Join-Path $env:TEMP ("cpm-proxy-settings-" + [guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            try {
                Update-CursorProfileProxySettings -UserDataDir $tempDir -EnableProxy:$true
                $settingsPath = Get-CursorProfileUserSettingsPath -UserDataDir $tempDir
                Test-Path $settingsPath | Should Be $true
                $settings = Read-JsonObjectHashtableFromFile -Path $settingsPath
                $settings['http.proxy'] | Should Be 'http://127.0.0.1:8080'
                $settings['http.proxyStrictSSL'] | Should Be $false
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'removes proxy settings when disabled' {
            $tempDir = Join-Path $env:TEMP ("cpm-proxy-settings-" + [guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            try {
                Update-CursorProfileProxySettings -UserDataDir $tempDir -EnableProxy:$true
                Update-CursorProfileProxySettings -UserDataDir $tempDir -EnableProxy:$false
                $settings = Read-JsonObjectHashtableFromFile -Path (Get-CursorProfileUserSettingsPath -UserDataDir $tempDir)
                $settings.ContainsKey('http.proxy') | Should Be $false
                $settings.ContainsKey('http.proxyStrictSSL') | Should Be $false
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Profile context marker and identity env' {
        It 'writes a context marker with profile and project fields' {
            $profile = New-TestProfile -Name 'marker-test' -ProjectPath 'L:\source\demo' -RunProxied $true
            $tempDir = Join-Path $env:TEMP ("cpm-marker-" + [guid]::NewGuid().ToString())
            $profile.UserDataDir = $tempDir
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            try {
                Write-CursorProfileContextMarker -Profile $profile -MainProcessId 1234
                $markerPath = Get-CursorProfileContextMarkerPath -UserDataDir $tempDir
                Test-Path $markerPath | Should Be $true
                $raw = Get-Content -Raw -Path $markerPath -Encoding UTF8 | ConvertFrom-Json
                $raw.profileId | Should Be $profile.Id
                $raw.profileName | Should Be 'marker-test'
                $raw.projectPath | Should Be 'L:\source\demo'
                $raw.mainProcessId | Should Be 1234
                $bytes = [System.IO.File]::ReadAllBytes($markerPath)
                ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $false
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'includes profile identity environment variables' {
            $profile = New-TestProfile -Name 'env-test' -ProjectPath 'L:\source\demo'
            $envVars = Get-CursorProfileIdentityEnvironmentVariables -Profile $profile
            $envVars.CURSOR_PROFILE_MANAGER_ID | Should Be $profile.Id
            $envVars.CURSOR_PROFILE_MANAGER_NAME | Should Be 'env-test'
            $envVars.CURSOR_PROFILE_MANAGER_USER_DATA_DIR | Should Be $profile.UserDataDir
            $envVars.CURSOR_PROFILE_MANAGER_PROJECT_PATH | Should Be 'L:\source\demo'
        }
    }
}
