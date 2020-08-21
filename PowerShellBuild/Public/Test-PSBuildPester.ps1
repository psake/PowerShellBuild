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
    .PARAMETER CodeCoverageOutputFile
        Output path to store Pester code coverage results to..
    .PARAMETER CodeCoverageOutputFileFormat
        code coverage result output format (JoCoCo).
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

        [string]$OutputFormat = 'NUnitXml',

        [switch]$CodeCoverage,

        [double]$CodeCoverageThreshold,

        [string[]]$CodeCoverageFiles = @(),

        [string]$CodeCoverageOutputFile,

        [string]$CodeCoverageOutputFileFormat,

        [switch]$ImportModule
    )

    if (-not (Get-Module -Name Pester)) {
        Import-Module -Name Pester -ErrorAction Stop
    }

    try {
        if ($ImportModule) {
            $ModuleOutputManifest = Join-Path -Path $env:BHBuildOutput -ChildPath "$($ModuleName).psd1"
            # Remove any previously imported project modules
            Get-Module $ModuleName | Remove-Module -Force
            # Import recently built project module from BHBuildOutput
            Import-Module $ModuleOutputManifest -Force
        }

        Push-Location -LiteralPath $Path
        $pesterParams = @{
            PassThru = $true
            Verbose  = $VerbosePreference
        }
        if (-not [string]::IsNullOrEmpty($OutputPath)) {
            $pesterParams.OutputFile   = $OutputPath
            $pesterParams.OutputFormat = $OutputFormat
        }

        # To control the Pester code coverage, a boolean $CodeCoverageEnabled is used.
        if ($CodeCoverage.IsPresent) {
            $pesterParams.CodeCoverage = $CodeCoverageFiles
            $pesterParams.CodeCoverageOutputFile = $CodeCoverageOutputFile
            $pesterParams.CodeCoverageOutputFileFormat = $CodeCoverageOutputFileFormat
        }

        $testResult = Invoke-Pester @pesterParams

        if ($testResult.FailedCount -gt 0) {
            throw 'One or more Pester tests failed'
        }

        if ($CodeCoverage.IsPresent) {
            $testCoverage = [int]($testResult.CodeCoverage.NumberOfCommandsExecuted / $testResult.CodeCoverage.NumberOfCommandsAnalyzed)
            'Pester code coverage on specified files: {0:p}' -f $testCoverage
            if ($testCoverage -lt $CodeCoverageThreshold) {
                throw 'Code coverage is less than threshold of {0:p}' -f $CodeCoverageThreshold
            }
        }
    } finally {
        Pop-Location
        Remove-Module $ModuleName -ErrorAction SilentlyContinue
    }
}
