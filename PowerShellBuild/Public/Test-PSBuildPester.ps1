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
    .PARAMETER ModuleManifest
        Path to module manifest to import during test
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
    .PARAMETER CodeCoverageOutputFile
        Output path (relative to Pester tests directory) to store code coverage results to.
    .PARAMETER CodeCoverageOutputFileFormat
        Code coverage result output format. Currently, only 'JaCoCo' is supported by Pester.
    .PARAMETER ImportModule
        Import module from OutDir prior to running Pester tests.
    .PARAMETER SkipRemainingOnFailure
        Skip remaining tests after failure for selected scope. Options are None, Run, Container and Block. Default: None.
    .PARAMETER OutputVerbosity
        The verbosity of output, options are None, Normal, Detailed and Diagnostic. Default is Detailed.
    .EXAMPLE
        PS> Test-PSBuildPester -Path ./tests -ModuleName MyModule -OutputPath ./out/testResults.xml

        Run Pester tests in ./tests and save results to ./out/testResults.xml
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory)]
        [string]$Path,

        [string]$ModuleName,

        [string]$ModuleManifest,

        [string]$OutputPath,

        [string]$OutputFormat = 'NUnit2.5',

        [switch]$CodeCoverage,

        [double]$CodeCoverageThreshold,

        [string[]]$CodeCoverageFiles = @(),

        [string]$CodeCoverageOutputFile = 'coverage.xml',

        [string]$CodeCoverageOutputFileFormat = 'JaCoCo',

        [switch]$ImportModule,

        [ValidateSet('None', 'Run', 'Container', 'Block')]
        [string]$SkipRemainingOnFailure = 'None',

        [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
        [string]$OutputVerbosity = 'Detailed'
    )

    # Respect an already-loaded Pester so callers can pin a specific version; importing again
    # would load the newest installed Pester on top of it, which crashes when two Pester
    # versions are installed side by side. Only load Pester ourselves when none is loaded.
    $loadedPester = Get-Module -Name Pester
    if (-not $loadedPester) {
        $loadedPester = Import-Module -Name Pester -MinimumVersion 5.0.0 -ErrorAction Stop -PassThru
    }
    if ($loadedPester.Version -lt [version]'5.0.0') {
        throw ($LocalizedData.PesterVersionNotSupported -f $loadedPester.Version)
    }

    try {
        if ($ImportModule) {
            if (-not (Test-Path $ModuleManifest)) {
                Write-Error ($LocalizedData.UnableToFindModuleManifest -f $ModuleManifest)
            } else {
                # Remove any previously imported project modules and import from the output dir
                Get-Module $ModuleName | Remove-Module -Force -ErrorAction SilentlyContinue
                Import-Module $ModuleManifest -Force
            }
        }

        Push-Location -LiteralPath $Path

        $configuration = [PesterConfiguration]::Default
        $configuration.Output.Verbosity = $OutputVerbosity
        $configuration.Run.PassThru = $true
        $configuration.Run.SkipRemainingOnFailure = $SkipRemainingOnFailure
        $configuration.TestResult.Enabled = -not [string]::IsNullOrEmpty($OutputPath)
        $configuration.TestResult.OutputPath = $OutputPath
        $configuration.TestResult.OutputFormat = $OutputFormat

        if ($CodeCoverage.IsPresent) {
            $configuration.CodeCoverage.Enabled = $true
            if ($CodeCoverageFiles.Count -gt 0) {
                $configuration.CodeCoverage.Path = $CodeCoverageFiles
            }
            $configuration.CodeCoverage.OutputPath = $CodeCoverageOutputFile
            $configuration.CodeCoverage.OutputFormat = $CodeCoverageOutputFileFormat
        }

        $testResult = Invoke-Pester -Configuration $configuration -Verbose:$VerbosePreference

        # Gate on the run's aggregate result rather than FailedCount alone. A failed
        # BeforeAll/AfterAll or a container that errors during discovery leaves
        # FailedCount at 0, but Pester still marks the overall Result as 'Failed'.
        if ($testResult.Result -eq 'Failed') {
            throw $LocalizedData.PesterTestsFailed
        }

        if ($CodeCoverage.IsPresent) {
            Write-Host ("`n{0}:`n" -f $LocalizedData.CodeCoverage) -ForegroundColor Yellow
            if (Test-Path $CodeCoverageOutputFile) {
                $textInfo = (Get-Culture).TextInfo
                [xml]$testCoverage = Get-Content $CodeCoverageOutputFile
                $ccReport = $testCoverage.report.counter.ForEach({
                        $total = [int]$_.missed + [int]$_.covered
                        $percent = [Math]::Truncate([int]$_.covered / $total)
                        [PSCustomObject]@{
                            name    = $textInfo.ToTitleCase($_.Type.ToLower())
                            percent = $percent
                        }
                    })

                $ccFailMsgs = @()
                $ccReport.ForEach({
                        '{0}: [{1}]: {2:p}' -f $LocalizedData.Type, $_.name, $_.percent
                        if ($_.percent -lt $CodeCoverageThreshold) {
                            $ccFailMsgs += ($LocalizedData.CodeCoverageLessThanThreshold -f $_.name, $_.percent, $CodeCoverageThreshold)
                        }
                    })
                Write-Host "`n"
                $ccFailMsgs.Foreach({
                        Write-Error $_
                    })
            } else {
                Write-Error ($LocalizedData.CodeCoverageCodeCoverageFileNotFound -f $CodeCoverageOutputFile)
            }
        }
    } finally {
        Pop-Location
        # ModuleName is optional; Remove-Module with an empty -Name raises a parameter-binding
        # error that -ErrorAction SilentlyContinue cannot suppress.
        if ($ModuleName) {
            Remove-Module -Name $ModuleName -ErrorAction SilentlyContinue
        }
    }
}
