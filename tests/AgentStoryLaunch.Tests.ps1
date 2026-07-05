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
    Context 'Get-CursorProxyLaunchArgs' {
        It 'returns empty args when proxy is disabled' {
            $launchArgs = Get-CursorProxyLaunchArgs -UseProxy:$false
            $launchArgs.Count | Should Be 0
        }

        It 'returns proxy flags when proxy is enabled' {
            $launchArgs = Get-CursorProxyLaunchArgs -UseProxy:$true
            $launchArgs.Count | Should Be 2
            $launchArgs[0] | Should Be '--proxy-server=http://127.0.0.1:8080'
            $launchArgs[1] | Should Be '--ignore-certificate-errors'
        }
    }
}
