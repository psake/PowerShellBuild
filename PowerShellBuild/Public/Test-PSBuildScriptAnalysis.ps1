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

        'None' reports findings without ever failing the build. 'Information', 'Warning', and
        'Error' fail on a finding at that severity or higher. 'Any' fails on any diagnostic
        record at all, regardless of severity.

        PSScriptAnalyzer also emits ParseError records for files that do not parse. Those are
        counted alongside Error, so a file that cannot be parsed fails every threshold except
        'None'.
    .PARAMETER SettingsPath
        Path to ScriptAnalyzer settings to use.
    .EXAMPLE
        PS> Test-PSBuildScriptAnalysis -Path ./Output/MyModule/0.1.0 -SeverityThreshold Error

        Run ScriptAnalyzer on built module in ./Output/MyModule/0.1.0. Throw error if any errors are found.
    .EXAMPLE
        PS> Test-PSBuildScriptAnalysis -Path ./Output/MyModule/0.1.0 -SeverityThreshold Any

        Run ScriptAnalyzer on built module in ./Output/MyModule/0.1.0. Throw error if any
        diagnostic record is returned, regardless of its severity.
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory)]
        [string]$Path,

        [ValidateSet('None', 'Error', 'Warning', 'Information', 'Any')]
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

    # PSScriptAnalyzer runs its script rules in parallel against a process-wide, unsynchronised
    # singleton, so a rule can crash on an internal race that has nothing to do with the code
    # under analysis (PSScriptAnalyzer#1538, #1351 -- both open, deferred to 2.0). A re-run
    # succeeds, so retry rather than letting a random red build reach the consumer. The analyzer
    # isolates a failed rule and still returns every other rule's findings, so a crash is not by
    # itself a reason to fail. See psake/PowerShellBuild#147.
    #
    # Errors are captured rather than allowed to surface during the retries, because a consumer
    # with $ErrorActionPreference = 'Stop' would otherwise terminate on the first crash and never
    # reach the second attempt. Whatever remains after the final attempt is re-emitted below, so
    # a persistent failure behaves exactly as it did before this retry existed.
    $maximumAttempt = 3
    for ($attempt = 1; $attempt -le $maximumAttempt; $attempt++) {
        $analysisErrors = @()
        $analysisResult = Invoke-ScriptAnalyzer @invokeScriptAnalyzerParameters `
            -Verbose:$VerbosePreference -ErrorAction SilentlyContinue -ErrorVariable analysisErrors

        # Only the analyzer's own rule crashes are worth retrying. Anything else is a real
        # failure that a second attempt will not change.
        $ruleErrors = @($analysisErrors).Where({ $_.FullyQualifiedErrorId -like 'RULE_ERROR*' })
        if ($ruleErrors.Count -eq 0 -or $attempt -eq $maximumAttempt) {
            break
        }

        Write-Warning ($LocalizedData.ScriptAnalyzerRuleErrorRetry -f $attempt, $maximumAttempt, $ruleErrors[0].Exception.Message)
    }

    # Surface anything the final attempt still reported, honouring the caller's error preference.
    foreach ($analysisError in @($analysisErrors)) {
        Write-Error -ErrorRecord $analysisError
    }

    # A single diagnostic record comes back as a scalar rather than a collection, and Windows
    # PowerShell 5.1 does not expose .Where() or .Count on every scalar type. Wrapping in @()
    # guarantees collection semantics on both engines.
    $analysisRecords = @($analysisResult)
    # ParseError is a fourth PSScriptAnalyzer severity, reported for a file that does not parse
    # at all. It is counted with Error: a file the engine cannot read is at least as severe as
    # an analyzer error, and leaving it out let it escape every threshold.
    $errorCount = ($analysisRecords.Where({ $_.Severity -in @('Error', 'ParseError') })).Count
    $warningCount = ($analysisRecords.Where({ $_.Severity -eq 'Warning' })).Count
    $informationCount = ($analysisRecords.Where({ $_.Severity -eq 'Information' })).Count

    if ($analysisRecords.Count -gt 0) {
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
        'Any' {
            if ($analysisRecords.Count -gt 0) {
                throw $LocalizedData.ScriptAnalyzerIssues
            }
        }
        default {
            if ($analysisRecords.Count -ne 0) {
                throw $LocalizedData.ScriptAnalyzerIssues
            }
        }
    }
}
