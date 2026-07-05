. "$PSScriptRoot\Bootstrap.ps1"

Describe 'Find-AgentStoryRoot' {
    It 'resolves agent-story under InstallRoot' {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $script:InstallRoot = $repoRoot
        $expected = Join-Path $repoRoot 'agent-story'
        if (-not (Test-Path $expected)) {
            Set-ItResult -Inconclusive -Because "agent-story folder not present at $expected"
            return
        }
        $root = Find-AgentStoryRoot
        $root | Should Be $expected
    }
}
