#Requires -Version 5.1

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'Bootstrap.ps1')
. (Join-Path $here 'TestHelpers.ps1')

Describe 'Cursor process command-line parsing' {

    Context 'Get-NormalizedUserDataDirFromCommandLine' {
        It 'parses equals-form paths' {
            $dir = Get-NormalizedUserDataDirFromCommandLine -CommandLine 'Cursor.exe --user-data-dir="C:\Profiles\Work" --new-window'
            $dir | Should Be 'c:\profiles\work'
        }

        It 'parses space-form paths' {
            $dir = Get-NormalizedUserDataDirFromCommandLine -CommandLine 'Cursor.exe --user-data-dir C:\Profiles\Work --new-window'
            $dir | Should Be 'c:\profiles\work'
        }

        It 'returns null when user-data-dir is missing' {
            Get-NormalizedUserDataDirFromCommandLine -CommandLine 'Cursor.exe --new-window' | Should BeNullOrEmpty
        }
    }

    Context 'Get-UserDataDirInstanceCountsFromProcessRecords' {
        It 'returns empty counts for no processes' {
            $counts = Get-UserDataDirInstanceCountsFromProcessRecords -ProcessRecords @()
            $counts.Count | Should Be 0
        }

        It 'counts a single main process as one window' {
            $dir = 'c:\profiles\one'
            $records = @(
                (New-TestCursorProcessRecord -ProcessId 100 -CommandLine "Cursor.exe --user-data-dir=`"$dir`" --new-window")
            )

            $counts = Get-UserDataDirInstanceCountsFromProcessRecords -ProcessRecords $records
            $counts[$dir] | Should Be 1
        }

        It 'counts renderer processes as additional windows' {
            $dir = 'c:\profiles\one'
            $records = @(
                (New-TestCursorProcessRecord -ProcessId 100 -CommandLine "Cursor.exe --user-data-dir=`"$dir`" --new-window"),
                (New-TestCursorProcessRecord -ProcessId 101 -ParentProcessId 100 -CommandLine "Cursor.exe --type=renderer --user-data-dir=`"$dir`""),
                (New-TestCursorProcessRecord -ProcessId 102 -ParentProcessId 100 -CommandLine "Cursor.exe --type=renderer --user-data-dir=`"$dir`"")
            )

            $counts = Get-UserDataDirInstanceCountsFromProcessRecords -ProcessRecords $records
            $counts[$dir] | Should Be 2
        }

        It 'ignores renderer processes without a matching main process' {
            $dir = 'c:\profiles\orphan'
            $records = @(
                (New-TestCursorProcessRecord -ProcessId 200 -CommandLine "Cursor.exe --type=renderer --user-data-dir=`"$dir`"")
            )

            $counts = Get-UserDataDirInstanceCountsFromProcessRecords -ProcessRecords $records
            $counts.ContainsKey($dir) | Should Be $false
        }
    }
}
