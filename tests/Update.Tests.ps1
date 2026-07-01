#Requires -Version 5.1

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'Bootstrap.ps1')
. (Join-Path $here 'TestHelpers.ps1')

Describe 'In-app update helpers' {

    Context 'Get-RemoteUpdateRawUrl' {
        It 'builds the GitHub raw URL for managed files' {
            $url = Get-RemoteUpdateRawUrl -FileName 'cursor-profile-manager.ps1'
            $url | Should Match '^https://raw\.githubusercontent\.com/.+/cursor-profile-manager\.ps1$'
        }
    }

    Context 'Save-UpdateStagingFiles' {
        It 'writes staged files with expected encodings' {
            $stagingDir = Join-Path $TestDrive 'update-staging'
            $files = @{
                'cursor-profile-manager.ps1' = '# test script'
                'cursor-profile-manager.bat' = '@echo off'
            }

            Save-UpdateStagingFiles -FilesByName $files -StagingDir $stagingDir

            Test-Path (Join-Path $stagingDir 'cursor-profile-manager.ps1') | Should Be $true
            Test-Path (Join-Path $stagingDir 'cursor-profile-manager.bat') | Should Be $true
            Get-Content -Raw -Path (Join-Path $stagingDir 'cursor-profile-manager.ps1') | Should Be '# test script'
        }
    }
}
