Describe 'Test-PSBuildScriptAnalysis' {
    BeforeAll {
        Set-StrictMode -Version Latest

        . (Join-Path -Path $PSScriptRoot -ChildPath '../PowerShellBuild/Public/Test-PSBuildScriptAnalysis.ps1')

        $script:LocalizedData = @{
            SeverityThresholdSetTo = 'Severity threshold set to {0}'
            PSScriptAnalyzerResults = 'PSScriptAnalyzer results'
            ScriptAnalyzerErrors    = 'ScriptAnalyzer errors found'
            ScriptAnalyzerWarnings  = 'ScriptAnalyzer warnings found'
            ScriptAnalyzerIssues    = 'ScriptAnalyzer issues found'
        }
    }

    It 'calls Invoke-ScriptAnalyzer with the provided settings path' {
        Mock -CommandName Invoke-ScriptAnalyzer -MockWith {
            @()
        }

        Test-PSBuildScriptAnalysis -Path 'function Test-Me { "ok" }' -SeverityThreshold Error -SettingsPath 'tests/ScriptAnalyzerSettings.psd1'

        Should -Invoke -CommandName Invoke-ScriptAnalyzer -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'function Test-Me { "ok" }' -and
            $Settings -eq 'tests/ScriptAnalyzerSettings.psd1' -and
            $Recurse
        }
    }

    It 'passes when no results are returned at Error threshold' {
        Mock -CommandName Invoke-ScriptAnalyzer -MockWith {
            @()
        }

        {
            Test-PSBuildScriptAnalysis -Path 'function Test-Me { "ok" }' -SeverityThreshold Error
        } | Should -Not -Throw
    }

    It 'fails when an error is returned at Error threshold' {
        Mock -CommandName Invoke-ScriptAnalyzer -MockWith {
            @(
                [pscustomobject]@{
                    Severity   = 'Error'
                    RuleName   = 'TestRule'
                    ScriptName = 'inline.ps1'
                    Message    = 'Boom'
                    Line       = 1
                }
            )
        }

        {
            Test-PSBuildScriptAnalysis -Path 'function Test-Me { "ok" }' -SeverityThreshold Error
        } | Should -Throw
    }
}
