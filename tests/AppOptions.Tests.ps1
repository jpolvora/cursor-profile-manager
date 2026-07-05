#Requires -Version 5.1

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'Bootstrap.ps1')
. (Join-Path $here 'TestHelpers.ps1')

Describe 'App options helpers' {
    Context 'Get-AppLaunchArguments' {
        It 'includes the manager script path' {
            $args = Get-AppLaunchArguments
            $args | Should Match 'cursor-profile-manager\.ps1'
            $args | Should Match '-WindowStyle Hidden'
        }

        It 'adds -StartMinimized for auto-start when minimize-to-tray is enabled' {
            $script:MinimizeToTray = $true
            $args = Get-AppLaunchArguments -ForAutoStart
            $args | Should Match '-StartMinimized'

            $script:MinimizeToTray = $false
            $args = Get-AppLaunchArguments -ForAutoStart
            $args | Should Not Match '-StartMinimized'
        }
    }
}
