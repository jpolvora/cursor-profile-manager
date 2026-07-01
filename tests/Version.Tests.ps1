#Requires -Version 5.1

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'Bootstrap.ps1')
. (Join-Path $here 'TestHelpers.ps1')

Describe 'App version parsing and comparison' {

    Context 'Get-AppVersionIdFromScriptContent' {
        It 'reads the App-Version comment marker' {
            $content = @'
# App-Version: 2.0.1
$script:AppVersionId = '1.0.0'
'@
            Get-AppVersionIdFromScriptContent -Content $content | Should Be '2.0.1'
        }

        It 'falls back to the AppVersionId assignment' {
            $content = @'
$script:AppVersionId = '1.4.0'
'@
            Get-AppVersionIdFromScriptContent -Content $content | Should Be '1.4.0'
        }

        It 'returns null for blank content' {
            Get-AppVersionIdFromScriptContent -Content '' | Should BeNullOrEmpty
            Get-AppVersionIdFromScriptContent -Content $null | Should BeNullOrEmpty
        }
    }

    Context 'ConvertTo-AppVersionNumbers' {
        It 'parses dotted numeric versions' {
            $numbers = ConvertTo-AppVersionNumbers -VersionId '1.3.5'
            $numbers.Count | Should Be 3
            $numbers[0] | Should Be 1
            $numbers[1] | Should Be 3
            $numbers[2] | Should Be 5
        }

        It 'parses a single segment version' {
            $numbers = ConvertTo-AppVersionNumbers -VersionId '3'
            $numbers.Count | Should Be 1
            $numbers[0] | Should Be 3
        }

        It 'returns null for non-numeric segments' {
            ConvertTo-AppVersionNumbers -VersionId '1.3.beta' | Should BeNullOrEmpty
        }
    }

    Context 'Compare-AppVersionId' {
        It 'returns 0 when versions are equal' {
            Compare-AppVersionId -Left '1.3.5' -Right '1.3.5' | Should Be 0
        }

        It 'returns -1 when left is older' {
            Compare-AppVersionId -Left '1.3.4' -Right '1.3.5' | Should Be -1
        }

        It 'returns 1 when left is newer' {
            Compare-AppVersionId -Left '1.4.0' -Right '1.3.5' | Should Be 1
        }

        It 'treats missing segments as zero' {
            Compare-AppVersionId -Left '1.3' -Right '1.3.0' | Should Be 0
            Compare-AppVersionId -Left '1.3.1' -Right '1.3' | Should Be 1
        }

        It 'returns null when either version is invalid' {
            Compare-AppVersionId -Left 'bad' -Right '1.0.0' | Should BeNullOrEmpty
            Compare-AppVersionId -Left '1.0.0' -Right '' | Should BeNullOrEmpty
        }
    }

    Context 'Get-AppVersionUpdateStatus' {
        It 'marks missing local marker as outdated' {
            $status = Get-AppVersionUpdateStatus -LocalVersion '' -RemoteVersion '1.3.5'
            $status.NeedsUpdate | Should Be $true
            $status.CanForceUpdate | Should Be $false
        }

        It 'marks missing remote marker as outdated' {
            $status = Get-AppVersionUpdateStatus -LocalVersion '1.3.5' -RemoteVersion ''
            $status.NeedsUpdate | Should Be $true
            $status.CanForceUpdate | Should Be $false
        }

        It 'reports up to date when versions match' {
            $status = Get-AppVersionUpdateStatus -LocalVersion '1.3.5' -RemoteVersion '1.3.5'
            $status.NeedsUpdate | Should Be $false
            $status.CanForceUpdate | Should Be $true
        }

        It 'reports update available when remote is newer' {
            $status = Get-AppVersionUpdateStatus -LocalVersion '1.3.4' -RemoteVersion '1.3.5'
            $status.NeedsUpdate | Should Be $true
            $status.CanForceUpdate | Should Be $false
        }

        It 'allows force reinstall when local is newer than remote' {
            $status = Get-AppVersionUpdateStatus -LocalVersion '1.4.0' -RemoteVersion '1.3.5'
            $status.NeedsUpdate | Should Be $false
            $status.CanForceUpdate | Should Be $true
        }
    }
}
