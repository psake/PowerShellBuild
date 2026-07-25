function Test-PSBuildScriptAnalysis {
    <#
    .SYNOPSIS
        Run PSScriptAnalyzer tests against a module.
    .DESCRIPTION
        Run PSScriptAnalyzer tests against a module.
    .PARAMETER Path
        Path to PowerShell module directory to run ScriptAnalyzer on.
    .PARAMETER SeverityThreshold
        Fail ScriptAnalyzer test if any issues are found with this threshold or higher.
    .PARAMETER SettingsPath
        Path to ScriptAnalyzer settings to use.
    .EXAMPLE
        PS> Test-PSBuildScriptAnalysis -Path ./Output/MyModule/0.1.0 -SeverityThreshold Error

        Run ScriptAnalyzer on built module in ./Output/MyModule/0.1.0. Throw error if any errors are found.
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory)]
        [string]$Path,

        [ValidateSet('None', 'Error', 'Warning', 'Information')]
        [string]$SeverityThreshold,

        [string]$SettingsPath
    )

    Write-Verbose ($LocalizedData.SeverityThresholdSetTo -f $SeverityThreshold)

    $invokeScriptAnalyzerParameters = @{
        Path    = $Path
        Recurse = $true
    }
    # An unsupplied SettingsPath must not be forwarded. PSScriptAnalyzer resolves an empty
    # -Settings value against the current directory and fails before any analysis runs.
    if (-not [string]::IsNullOrWhiteSpace($SettingsPath)) {
        $invokeScriptAnalyzerParameters.Settings = $SettingsPath
    }

    $analysisResult = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters -Verbose:$VerbosePreference
    $errorCount = ($analysisResult.where({ $_.Severity -eq 'Error' })).Count
    $warningCount = ($analysisResult.where({ $_.Severity -eq 'Warning' })).Count
    $informationCount = ($analysisResult.where({ $_.Severity -eq 'Information' })).Count

    if ($analysisResult) {
        Write-Host $LocalizedData.PSScriptAnalyzerResults -ForegroundColor Yellow
        $analysisResult | Format-Table -AutoSize
    }

    switch ($SeverityThreshold) {
        'None' {
            return
        }
        'Error' {
            if ($errorCount -gt 0) {
                throw $LocalizedData.ScriptAnalyzerErrors
            }
        }
        'Warning' {
            if ($errorCount -gt 0 -or $warningCount -gt 0) {
                throw $LocalizedData.ScriptAnalyzerWarnings
            }
        }
        'Information' {
            if ($errorCount -gt 0 -or $warningCount -gt 0 -or $informationCount -gt 0) {
                throw $LocalizedData.ScriptAnalyzerWarnings
            }
        }
        default {
            if ($analysisResult.Count -ne 0) {
                throw $LocalizedData.ScriptAnalyzerIssues
            }
        }
    }
}
