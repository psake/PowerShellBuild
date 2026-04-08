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

    $analysisResult = Invoke-ScriptAnalyzer -Path $Path -Settings $SettingsPath -Recurse -Verbose:$VerbosePreference
    $errors = ($analysisResult.where({ $_.Severity -eq 'Error' })).Count
    $warnings = ($analysisResult.where({ $_.Severity -eq 'Warning' })).Count
    $infos = ($analysisResult.where({ $_.Severity -eq 'Information' })).Count

    if ($analysisResult) {
        Write-Host $LocalizedData.PSScriptAnalyzerResults -ForegroundColor Yellow
        $analysisResult | Format-Table -AutoSize
    }

    switch ($SeverityThreshold) {
        'None' {
            return
        }
        'Error' {
            if ($errors -gt 0) {
                throw $LocalizedData.ScriptAnalyzerErrors
            }
        }
        'Warning' {
            if ($errors -gt 0 -or $warnings -gt 0) {
                throw $LocalizedData.ScriptAnalyzerWarnings
            }
        }
        'Information' {
            if ($errors -gt 0 -or $warnings -gt 0 -or $infos -gt 0) {
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
