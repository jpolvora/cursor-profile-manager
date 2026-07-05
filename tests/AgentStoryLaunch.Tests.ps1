#Requires -Version 5.1

. "$PSScriptRoot\Bootstrap.ps1"

Describe 'Agent Story database paths' {
    Context 'Get-AgentStoryDatabasePaths' {
        It 'returns empty when Agent Story root is missing' {
            (Get-AgentStoryDatabasePaths -AgentStoryRoot '').Count | Should Be 0
        }

        It 'returns db, wal, and shm paths under server' {
            $tempRoot = Join-Path $env:TEMP ("cpm-agent-story-" + [guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path (Join-Path $tempRoot 'server') -Force | Out-Null
            try {
                $paths = Get-AgentStoryDatabasePaths -AgentStoryRoot $tempRoot
                $paths.Count | Should Be 3
                $paths[0] | Should Match '\\server\\agent-story\.db$'
                $paths[1] | Should Match '\\server\\agent-story\.db-wal$'
                $paths[2] | Should Match '\\server\\agent-story\.db-shm$'
            }
            finally {
                Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Remove-AgentStoryDatabaseFiles' {
        It 'deletes existing database files and skips missing ones' {
            $tempRoot = Join-Path $env:TEMP ("cpm-agent-story-" + [guid]::NewGuid().ToString())
            $serverDir = Join-Path $tempRoot 'server'
            New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
            $dbPath = Join-Path $serverDir 'agent-story.db'
            $walPath = "$dbPath-wal"
            try {
                Set-Content -Path $dbPath -Value 'test' -Encoding ASCII
                Set-Content -Path $walPath -Value 'wal' -Encoding ASCII

                $result = Remove-AgentStoryDatabaseFiles -DatabasePaths (Get-AgentStoryDatabasePaths -AgentStoryRoot $tempRoot)
                $result.Deleted.Count | Should Be 2
                $result.Failed.Count | Should Be 0
                Test-Path -LiteralPath $dbPath | Should Be $false
                Test-Path -LiteralPath $walPath | Should Be $false
            }
            finally {
                Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

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

        It 'returns alternative pass-through URL on port 8081' {
            Get-CursorProxyUrl -ProxyType 'alternative' | Should Be 'http://127.0.0.1:8081'
        }
    }

    Context 'Get-ProfileProxyType' {
        It 'defaults missing ProxyType to default' {
            $profile = New-TestProfile -Name 'plain'
            Get-ProfileProxyType -Profile $profile | Should Be 'default'
        }

        It 'reads alternative ProxyType from profile' {
            $profile = New-TestProfile -Name 'alt' -RunProxied $true
            $profile | Add-Member -NotePropertyName ProxyType -NotePropertyValue 'alternative' -Force
            Get-ProfileProxyType -Profile $profile | Should Be 'alternative'
        }
    }

    Context 'Get-CursorProxyLaunchArgs alternative' {
        It 'uses localhost-only bypass and omits ignore-certificate-errors' {
            $launchArgs = Get-CursorProxyLaunchArgs -UseProxy:$true -ProxyType 'alternative'
            $launchArgs.Count | Should Be 2
            $launchArgs[0] | Should Be '--proxy-server=http://127.0.0.1:8081'
            $launchArgs[1] | Should Be '--proxy-bypass-list=localhost;127.0.0.1'
        }
    }

    Context 'Get-CursorProxyLaunchArgs' {
        It 'returns empty args when proxy is disabled' {
            $launchArgs = Get-CursorProxyLaunchArgs -UseProxy:$false
            $launchArgs.Count | Should Be 0
        }

        It 'returns Chromium proxy flags when proxy is enabled' {
            $launchArgs = Get-CursorProxyLaunchArgs -UseProxy:$true
            $launchArgs.Count | Should Be 3
            $launchArgs[0] | Should Be '--proxy-server=http://127.0.0.1:8080'
            $launchArgs[1] | Should Be '--proxy-bypass-list=localhost;127.0.0.1;.github.com;github.com;.gitlab.com;gitlab.com;.bitbucket.org;bitbucket.org'
            $launchArgs[2] | Should Be '--ignore-certificate-errors'
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
            $envVars.ALL_PROXY | Should Be 'http://127.0.0.1:8080'
            $envVars.GLOBAL_AGENT_HTTP_PROXY | Should Be 'http://127.0.0.1:8080'
            $envVars.GLOBAL_AGENT_HTTPS_PROXY | Should Be 'http://127.0.0.1:8080'
            $envVars.NODE_TLS_REJECT_UNAUTHORIZED | Should Be '0'
            $envVars.NO_PROXY | Should Be 'localhost,127.0.0.1,.github.com,github.com,.gitlab.com,gitlab.com,.bitbucket.org,bitbucket.org'
        }
    }

    Context 'Update-CursorProfileArgvProxy' {
        It 'writes proxy runtime args to argv.json when enabled' {
            $tempDir = Join-Path $env:TEMP ("cpm-argv-" + [guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            try {
                Update-CursorProfileArgvProxy -UserDataDir $tempDir -EnableProxy:$true
                $argvPath = Get-CursorProfileArgvPath -UserDataDir $tempDir
                Test-Path $argvPath | Should Be $true
                $argv = Read-JsonObjectHashtableFromFileAllowBools -Path $argvPath
                $argv['proxy-server'] | Should Be 'http://127.0.0.1:8080'
                $argv['proxy-bypass-list'] | Should Be $script:CursorProxyBypassList
                $argv['ignore-certificate-errors'] | Should Be $true
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'removes proxy runtime args from argv.json when disabled' {
            $tempDir = Join-Path $env:TEMP ("cpm-argv-" + [guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            try {
                Update-CursorProfileArgvProxy -UserDataDir $tempDir -EnableProxy:$true
                Update-CursorProfileArgvProxy -UserDataDir $tempDir -EnableProxy:$false
                $argvPath = Get-CursorProfileArgvPath -UserDataDir $tempDir
                Test-Path $argvPath | Should Be $false
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'preserves unrelated argv.json keys when toggling proxy' {
            $tempDir = Join-Path $env:TEMP ("cpm-argv-" + [guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            try {
                Write-JsonObjectHashtableToFileNoBom -Path (Get-CursorProfileArgvPath -UserDataDir $tempDir) -Data @{
                    'enable-crash-reporter' = $true
                }
                Update-CursorProfileArgvProxy -UserDataDir $tempDir -EnableProxy:$true
                $argv = Read-JsonObjectHashtableFromFileAllowBools -Path (Get-CursorProfileArgvPath -UserDataDir $tempDir)
                $argv['enable-crash-reporter'] | Should Be $true
                $argv['proxy-server'] | Should Be 'http://127.0.0.1:8080'
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
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
                $settings['http.proxySupport'] | Should Be 'on'
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
                $settings.ContainsKey('http.proxySupport') | Should Be $false
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'skips proxy update when settings.json is not valid JSON' {
            $tempDir = Join-Path $env:TEMP ("cpm-proxy-settings-" + [guid]::NewGuid().ToString())
            New-Item -ItemType Directory -Path (Join-Path $tempDir 'User') -Force | Out-Null
            try {
                $settingsPath = Get-CursorProfileUserSettingsPath -UserDataDir $tempDir
                $invalidJson = '{ "editor.fontSize": 14, // trailing comment }'
                Set-Content -Path $settingsPath -Value $invalidJson -Encoding UTF8
                Update-CursorProfileProxySettings -UserDataDir $tempDir -EnableProxy:$true
                $after = (Get-Content -Raw -Path $settingsPath -Encoding UTF8).TrimEnd()
                $after | Should Be $invalidJson
                $after.Contains('http.proxy') | Should Be $false
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
