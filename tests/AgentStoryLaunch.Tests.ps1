#Requires -Version 5.1

. "$PSScriptRoot\Bootstrap.ps1"

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
