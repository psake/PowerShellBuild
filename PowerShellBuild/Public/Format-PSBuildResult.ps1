function Format-PSBuildResult {
    <#
    .SYNOPSIS
        Formats a PsakeBuildResult for human, CI, or LLM consumption.
    .DESCRIPTION
        Takes a PsakeBuildResult object from psake 5.0.0's Invoke-psake and formats it
        according to the specified output format. Useful for CI pipelines, LLM-driven
        builds, and human-readable summaries.
    .PARAMETER Result
        The PsakeBuildResult object returned by Invoke-psake.
    .PARAMETER Format
        Output format. 'Human' (default) produces a readable table. 'JSON' produces
        structured JSON with task durations and cache hits. 'GitHubActions' emits
        workflow command annotations.
    .EXAMPLE
        PS> $result = Invoke-psake -buildFile ./psakeFile.ps1
        PS> Format-PSBuildResult -Result $result

        Format the build result as a human-readable table.
    .EXAMPLE
        PS> $result = Invoke-psake -buildFile ./psakeFile.ps1
        PS> Format-PSBuildResult -Result $result -Format JSON

        Format the build result as structured JSON.
    .EXAMPLE
        PS> $result = Invoke-psake -buildFile ./psakeFile.ps1
        PS> Format-PSBuildResult -Result $result -Format GitHubActions

        Format the build result with GitHub Actions workflow annotations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Result,

        [ValidateSet('Human', 'JSON', 'GitHubActions')]
        [string]$Format = 'Human'
    )

    process {
        switch ($Format) {
            'Human' {
                $status = if ($Result.Success) { 'SUCCEEDED' } else { 'FAILED' }
                Write-Host "`nBuild $status" -ForegroundColor $(if ($Result.Success) { 'Green' } else { 'Red' })
                Write-Host "Duration: $([Math]::Round($Result.Duration.TotalSeconds, 2))s`n"

                if ($Result.TaskResults) {
                    $tableData = $Result.TaskResults | ForEach-Object {
                        [PSCustomObject]@{
                            Task     = $_.Name
                            Status   = $_.Status
                            Duration = '{0:N2}s' -f $_.Duration.TotalSeconds
                            Cached   = if ($_.Cached) { 'Yes' } else { 'No' }
                        }
                    }
                    $tableData | Format-Table -AutoSize
                }

                if (-not $Result.Success -and $Result.ErrorMessage) {
                    Write-Host "Error: $($Result.ErrorMessage)" -ForegroundColor Red
                }
            }
            'JSON' {
                $jsonData = [ordered]@{
                    success  = $Result.Success
                    duration = [Math]::Round($Result.Duration.TotalSeconds, 2)
                }

                if ($Result.TaskResults) {
                    $jsonData.tasks = @($Result.TaskResults | ForEach-Object {
                        [ordered]@{
                            name     = $_.Name
                            status   = $_.Status
                            duration = [Math]::Round($_.Duration.TotalSeconds, 2)
                            cached   = [bool]$_.Cached
                        }
                    })
                }

                if (-not $Result.Success -and $Result.ErrorMessage) {
                    $jsonData.error = $Result.ErrorMessage
                }

                $jsonData | ConvertTo-Json -Depth 5
            }
            'GitHubActions' {
                if ($Result.TaskResults) {
                    foreach ($taskResult in $Result.TaskResults) {
                        if ($taskResult.Status -eq 'Failed') {
                            Write-Host "::error title=Task '$($taskResult.Name)' failed::$($taskResult.ErrorMessage)"
                        } elseif ($taskResult.Cached) {
                            Write-Host "::notice title=Task '$($taskResult.Name)' cached::Skipped (cached)"
                        }
                    }
                }

                if ($Result.Success) {
                    Write-Host "::notice title=Build succeeded::Completed in $([Math]::Round($Result.Duration.TotalSeconds, 2))s"
                } else {
                    Write-Host "::error title=Build failed::$($Result.ErrorMessage)"
                }
            }
        }
    }
}
