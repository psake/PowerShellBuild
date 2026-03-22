function ConvertTo-PSBuildLLMOutput {
    <#
    .SYNOPSIS
        Converts Pester test results to structured JSON optimized for LLM consumption.
    .DESCRIPTION
        Takes a Pester TestResult (PassThru) object and produces a concise JSON structure
        containing a summary and an array of failure details. Designed for machine consumption
        where only actionable information (failures) matters.
    .PARAMETER TestResult
        The Pester test result object returned by Invoke-Pester with -PassThru.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$TestResult
    )

    $failures = [System.Collections.Generic.List[object]]::new()

    foreach ($container in $TestResult.Containers) {
        Get-FailedTestsFromBlock -Blocks $container.Blocks -ContainerName $container.Name -Failures $failures
    }

    $output = [ordered]@{
        summary  = [ordered]@{
            total    = $TestResult.TotalCount
            passed   = $TestResult.PassedCount
            failed   = $TestResult.FailedCount
            skipped  = $TestResult.SkippedCount
            duration = [Math]::Round($TestResult.Duration.TotalSeconds, 2)
        }
        failures = $failures.ToArray()
    }

    $output | ConvertTo-Json -Depth 10
}

function Get-FailedTestsFromBlock {
    <#
    .SYNOPSIS
        Recursively collects failed tests from Pester block hierarchy.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Blocks,
        [string]$ContainerName,
        [System.Collections.Generic.List[object]]$Failures
    )

    foreach ($block in $Blocks) {
        foreach ($test in $block.Tests) {
            if ($test.Result -eq 'Failed') {
                $errorMessage = if ($test.ErrorRecord -and $test.ErrorRecord.Count -gt 0) {
                    $test.ErrorRecord[0].DisplayErrorMessage
                } elseif ($test.ErrorRecord) {
                    "$($test.ErrorRecord)"
                } else {
                    'Unknown error'
                }

                $file = $null
                $line = $null
                if ($test.ScriptBlock -and $test.ScriptBlock.File) {
                    $file = $test.ScriptBlock.File
                    $line = $test.ScriptBlock.StartPosition.StartLine
                }

                $Failures.Add([ordered]@{
                    test      = $test.ExpandedPath
                    container = $ContainerName
                    file      = $file
                    line      = $line
                    error     = $errorMessage
                    duration  = [Math]::Round($test.Duration.TotalMilliseconds, 1)
                })
            }
        }

        # Recurse into nested blocks
        if ($block.Blocks -and $block.Blocks.Count -gt 0) {
            Get-FailedTestsFromBlock -Blocks $block.Blocks -ContainerName $ContainerName -Failures $Failures
        }
    }
}
