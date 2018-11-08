function Test-PSBuildScriptAnalysis {
    <#
    .SYNOPSIS
        Run PSScriptAnalyzer tests against a module.
    .DESCRIPTION
        Run PSScriptAnalyzer tests against a module.
    .PARAMETER Path
        Path to PowerShell module directory to run ScriptAnalyser on.
    .PARAMETER SeverityThreshold
        Fail ScriptAnalyser test if any issues are found with this threshold or higher.
    .PARAMETER SettingsPath
        Path to ScriptAnalyser settings to use.
    .EXAMPLE
        PS> Test-PSBuildScriptAnalysis -Path ./Output/Mymodule/0.1.0 -SeverityThreshold Error

        Run ScriptAnalyzer on built module in ./Output/Mymodule/0.1.0. Throw error if any errors are found.
    #>
    [cmdletbinding()]
    param(
        [parameter(Mandatory)]
        [string]$Path,

        [ValidateSet('None', 'Error', 'Warning', 'Information')]
        [string]$SeverityThreshold,

        [string]$SettingsPath
    )

    Write-Verbose "SeverityThreshold set to: $SeverityThreshold"

    $analysisResult = Invoke-ScriptAnalyzer -Path $Path -Settings $SettingsPath -Recurse -Verbose:$VerbosePreference
    $errors   = ($analysisResult.where({$_Severity -eq 'Error'})).Count
    $warnings = ($analysisResult.where({$_Severity -eq 'Warning'})).Count
    $infos    = ($analysisResult.where({$_Severity -eq 'Information'})).Count

    if ($analysisResult) {
        Write-Host 'PSScriptAnalyzer results:' -ForegroundColor Yellow
        $analysisResult | Format-Table -AutoSize
    }

    switch ($SeverityThreshold) {
        'None' {
            return
        }
        'Error' {
            if ($errors -gt 0) {
                throw 'One or more ScriptAnalyzer errors were found!'
            }
        }
        'Warning' {
            if ($errors -gt 0 -or $warnings -gt 0) {
                throw 'One or more ScriptAnalyzer warnings were found!'
            }
        }
        'Information' {
            if ($errors -gt 0 -or $warnings -gt 0 -or $infos -gt 0) {
                throw 'One or more ScriptAnalyzer warnings were found!'
            }
        }
        default {
            if ($analysisResult.Count -ne 0) {
                throw 'One or more ScriptAnalyzer issues were found!'
            }
        }
    }
}
