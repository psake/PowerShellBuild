function Test-PSBuildPester {
    <#
    .SYNOPSIS
        Execute Pester tests for module.
    .DESCRIPTION
        Execute Pester tests for module. Supports individual parameter configuration,
        external PesterConfiguration files, and direct PesterConfiguration object passthrough.
        Includes an LLM output mode that produces structured JSON with only failure details.
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
    .PARAMETER OutputMode
        Controls how test results are presented. 'Detailed' (default) shows full Pester output.
        'Minimal' shows only failures in a compact format. 'LLM' suppresses console output and
        emits structured JSON optimized for machine consumption.
    .PARAMETER PesterConfigurationPath
        Path to an external PesterConfiguration .psd1 file. When set, loaded as the base
        PesterConfiguration with explicit parameter values overlaid on top.
    .PARAMETER Configuration
        A pre-built PesterConfiguration object. When provided, individual Pester parameters
        are ignored and this configuration is used directly.
    .EXAMPLE
        PS> Test-PSBuildPester -Path ./tests -ModuleName MyModule -OutputPath ./out/testResults.xml

        Run Pester tests in ./tests and save results to ./out/testResults.xml
    .EXAMPLE
        PS> Test-PSBuildPester -Path ./tests -ModuleName MyModule -OutputMode LLM

        Run Pester tests with structured JSON output optimized for LLM consumption
    .EXAMPLE
        PS> Test-PSBuildPester -Path ./tests -Configuration $myConfig

        Run Pester tests using a pre-built PesterConfiguration object
    #>
    [CmdletBinding(DefaultParameterSetName = 'Individual')]
    param(
        [parameter(Mandatory)]
        [string]$Path,

        [string]$ModuleName,

        [string]$ModuleManifest,

        [Parameter(ParameterSetName = 'Individual')]
        [string]$OutputPath,

        [Parameter(ParameterSetName = 'Individual')]
        [string]$OutputFormat = 'NUnit2.5',

        [Parameter(ParameterSetName = 'Individual')]
        [switch]$CodeCoverage,

        [Parameter(ParameterSetName = 'Individual')]
        [double]$CodeCoverageThreshold,

        [Parameter(ParameterSetName = 'Individual')]
        [string[]]$CodeCoverageFiles = @(),

        [Parameter(ParameterSetName = 'Individual')]
        [string]$CodeCoverageOutputFile = 'coverage.xml',

        [Parameter(ParameterSetName = 'Individual')]
        [string]$CodeCoverageOutputFileFormat = 'JaCoCo',

        [switch]$ImportModule,

        [Parameter(ParameterSetName = 'Individual')]
        [ValidateSet('None', 'Run', 'Container', 'Block')]
        [string]$SkipRemainingOnFailure = 'None',

        [Parameter(ParameterSetName = 'Individual')]
        [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
        [string]$OutputVerbosity = 'Detailed',

        [ValidateSet('Detailed', 'Minimal', 'LLM')]
        [string]$OutputMode = 'Detailed',

        [Parameter(ParameterSetName = 'Individual')]
        [string]$PesterConfigurationPath,

        [Parameter(ParameterSetName = 'Configuration')]
        [object]$Configuration
    )

    if (-not (Get-Module -Name Pester)) {
        Import-Module -Name Pester -ErrorAction Stop
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

        Import-Module Pester -MinimumVersion 5.0.0

        # Build PesterConfiguration based on parameter set
        if ($PSCmdlet.ParameterSetName -eq 'Configuration' -and $Configuration) {
            $configuration = $Configuration
        } elseif ($PesterConfigurationPath) {
            # Load external config file as base, overlay explicit params
            if (-not (Test-Path $PesterConfigurationPath)) {
                Write-Error ($LocalizedData.InvalidPesterConfigPath -f $PesterConfigurationPath)
                return
            }
            Write-Verbose ($LocalizedData.PesterConfigLoaded -f $PesterConfigurationPath)
            $configData = Import-PowerShellDataFile -Path $PesterConfigurationPath
            $configuration = [PesterConfiguration]$configData
            # Overlay explicit parameter values on top of file-based config
            $configuration.Run.PassThru = $true
            if ($OutputMode -eq 'LLM') {
                $configuration.Output.Verbosity = 'None'
            } elseif ($OutputMode -eq 'Minimal') {
                $configuration.Output.Verbosity = 'Normal'
            }
        } else {
            # Build from individual parameters (backward-compatible path)
            $configuration = [PesterConfiguration]::Default

            # Apply OutputMode overrides to verbosity
            switch ($OutputMode) {
                'LLM' {
                    $configuration.Output.Verbosity = 'None'
                }
                'Minimal' {
                    $configuration.Output.Verbosity = 'Normal'
                }
                default {
                    $configuration.Output.Verbosity = $OutputVerbosity
                }
            }

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
        }

        $testResult = Invoke-Pester -Configuration $configuration -Verbose:$VerbosePreference

        # Post-process results based on OutputMode
        switch ($OutputMode) {
            'LLM' {
                $jsonOutput = ConvertTo-PSBuildLLMOutput -TestResult $testResult
                Write-Output $jsonOutput
            }
            'Minimal' {
                if ($testResult.FailedCount -gt 0) {
                    foreach ($container in $testResult.Containers) {
                        foreach ($block in $container.Blocks) {
                            _WriteMinimalFailures -Block $block -ContainerName $container.Name
                        }
                    }
                }
            }
        }

        if ($testResult.FailedCount -gt 0) {
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

        # Always return the test result object for programmatic access
        $testResult
    } finally {
        Pop-Location
        Remove-Module $ModuleName -ErrorAction SilentlyContinue
    }
}

function _WriteMinimalFailures {
    <#
    .SYNOPSIS
        Recursively writes minimal failure lines from Pester blocks.
    #>
    [CmdletBinding()]
    param(
        [object]$Block,
        [string]$ContainerName
    )

    foreach ($test in $Block.Tests) {
        if ($test.Result -eq 'Failed') {
            $errorMsg = if ($test.ErrorRecord -and $test.ErrorRecord.Count -gt 0) {
                $test.ErrorRecord[0].DisplayErrorMessage
            } else {
                "$($test.ErrorRecord)"
            }
            $file = if ($test.ScriptBlock.File) { $test.ScriptBlock.File } else { $ContainerName }
            $line = if ($test.ScriptBlock.StartPosition) { $test.ScriptBlock.StartPosition.StartLine } else { 0 }
            Write-Host ($LocalizedData.MinimalFailureLine -f $test.ExpandedPath, $file, $line, $errorMsg) -ForegroundColor Red
        }
    }

    foreach ($childBlock in $Block.Blocks) {
        _WriteMinimalFailures -Block $childBlock -ContainerName $ContainerName
    }
}
