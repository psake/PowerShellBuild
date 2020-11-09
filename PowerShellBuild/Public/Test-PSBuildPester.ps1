function Test-PSBuildPester {
    <#
    .SYNOPSIS
        Execute Pester tests for module.
    .DESCRIPTION
        Execute Pester tests for module.
    .PARAMETER Path
        Directory Pester tests to execute.
    .PARAMETER ModuleName
        Name of Module to test.
    .PARAMETER OutputPath
        Output path to store Pester test results to.
    .PARAMETER OutputFormat
        Test result output format (NUnit).
    .PARAMETER CodeCoverage
        Switch to indicate that code coverage should be calculated.
    .PARAMETER CodeCoverageThreshold
        Threshold required to pass code coverage test (.90 = 90%).
    .PARAMETER CodeCoverageFiles
        Array of files to validate code coverage for.
    .PARAMETER ImportModule
        Import module from OutDir prior to running Pester tests.
    .EXAMPLE
        PS> Test-PSBuildPester -Path ./tests -ModuleName Mymodule -OutputPath ./out/testResults.xml

        Run Pester tests in ./tests and save results to ./out/testResults.xml
    #>
    [cmdletbinding()]
    param(
        [parameter(Mandatory)]
        [string]$Path,

        [string]$ModuleName,

        [string]$OutputPath,

        [string]$OutputFormat = 'NUnit2.5',

        [switch]$CodeCoverage,

        [double]$CodeCoverageThreshold,

        [string[]]$CodeCoverageFiles = @(),

        [switch]$ImportModule
    )

    if (-not (Get-Module -Name Pester)) {
        Import-Module -Name Pester -ErrorAction Stop
    }

    try {
        if ($ImportModule) {
            # Remove any previously imported project modules and import from the output dir
            $ModuleOutputManifest = [IO.Path]::Combine($env:BHBuildOutput, "$($ModuleName).psd1")
            Get-Module $ModuleName | Remove-Module -Force
            Import-Module $ModuleOutputManifest -Force
        }

        Push-Location -LiteralPath $Path

        Import-Module Pester -MinimumVersion 5.0.0
        $configuration = [PesterConfiguration]::Default
        $configuration.Output.Verbosity        = 'Detailed'
        $configuration.Run.PassThru            = $false
        $configuration.TestResult.Enabled      = -not [string]::IsNullOrEmpty($OutputPath)
        $configuration.TestResult.OutputPath   = $OutputPath
        $configuration.TestResult.OutputFormat = $OutputFormat

        if ($CodeCoverage.IsPresent) {
            $configuration.CodeCoverage.Enabled = $true
            if ($CodeCoverageFiles.Count -gt 0) {
                $configuration.CodeCoverage.Path = $CodeCoverageFiles
            }
            $configuration.CodeCoverage.OutputPath = 'coverage.xml'
        }

        $testResult = Invoke-Pester -Configuration $configuration -Verbose:$VerbosePreference

        if ($testResult.FailedCount -gt 0) {
            throw 'One or more Pester tests failed'
        }

        if ($CodeCoverage.IsPresent) {
            Write-Host "`nCode Coverage:`n" -ForegroundColor Yellow
            if (Test-Path coverage.xml) {
                $textInfo = (Get-Culture).TextInfo
                [xml]$testCoverage = Get-Content coverage.xml
                $ccReport = $testCoverage.report.counter.ForEach({
                    $total = [int]$_.missed + [int]$_.covered
                    $perc  = [Math]::Truncate([int]$_.covered / $total)
                    [pscustomobject]@{
                        name    = $textInfo.ToTitleCase($_.Type.ToLower())
                        percent = $perc
                    }
                })

                $ccfail     = $false
                $ccFailMsgs = @()
                $ccReport.ForEach({
                    'Code coverage type [{0}] on specified files: {1:p}' -f $_.name, $_.percent
                    if ($_.percent -lt $CodeCoverageThreshold) {
                        $ccFail      = $true
                        $ccFailMsgs += ('Code coverage: [{0}] is [{1:p}], which is less than the threshold of [{2:p}]' -f $_.name, $_.percent, $CodeCoverageThreshold)
                    }
                })
                if ($ccFail) {
                    throw $ccFailMsgs
                }
            } else {
                Write-Error 'coverage.xml not found'
            }
        }
    } finally {
        Pop-Location
        Remove-Module $ModuleName -ErrorAction SilentlyContinue
    }
}
