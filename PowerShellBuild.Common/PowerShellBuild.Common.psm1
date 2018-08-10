
Set-BuildEnvironment -Force

function Initialize-PSBuild {
    [cmdletbinding()]
    param(
        [switch]$UseBuildHelpers
    )

    Write-Host 'Build System Details:' -ForegroundColor Yellow
    $psVersion          = $PSVersionTable.PSVersion.Major
    $buildModuleName    = $MyInvocation.MyCommand.Module.Name
    $buildModuleVersion = $MyInvocation.MyCommand.Module.Version
    "Build Module:       $buildModuleName`:$buildModuleVersion"
    "PowerShell Version: $psVersion"

    if ($UseBuildHelpers.IsPresent) {
        $nl = [System.Environment]::NewLine
        "$nl`Environment variables:"
        (Get-Item ENV:BH*).Foreach({
            '{0,-20}{1}' -f $_.name, $_.value
        })
    }
}

function Clear-PSBuildOutputFolder {
    [CmdletBinding()]
    param(
        # Maybe a bit paranoid but this task nuked \ on my laptop. Good thing I was not running as admin.
        [ValidateScript({
            if ($_.Length -le 3) {
                throw "`$Path [$_] must be longer than 3 characters."
            }
            $true
        })]
        [string]$Path
    )

    if (Test-Path -Path $Path) {
        Remove-Item -Path $Path -Recurse -Force -Verbose:$false
    }
}

function Test-PSBuildScriptAnalysis {
    [cmdletbinding()]
    param(
        [string]$Path,

        [string]$SeverityThreshold,

        [string]$SettingsPath
    )

    Write-Verbose "SeverityThreshold set to: $SeverityThreshold"

    $analysisResult = Invoke-ScriptAnalyzer -Path $Path -Settings $SettingsPath -Recurse -Verbose:$VerbosePreference
    $errors   = ($analysisResult.where({$_Severity -eq 'Error'})).Count
    $warnings = ($analysisResult.where({$_Severity -eq 'Warning'})).Count

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
        default {
            if ($analysisResult.Count -ne 0) {
                throw 'One or more ScriptAnalyzer issues were found!'
            }
        }
    }
}

function Test-PSBuildPester {
    [cmdletbinding()]
    param(
        [string]$Path,

        [string]$ModuleName,

        [string]$OutputPath,

        [string]$OutputFormat,

        [switch]$CodeCoverage,

        [string[]]$CodeCoverageFiles = @()
    )

    if (-not (Get-Module -Name Pester -ListAvailable)) {
        Import-Module -Name Pester -ErrorAction Stop
    }

    try {
        Push-Location -LiteralPath $Path
        $pesterParams = @{
            PassThru = $true
            Verbose  = $VerbosePreference
        }
        if (-not [string]::IsNullOrEmpty($OutputPath)) {
            $pesterParams = @{
                OutputFile   = $OutputPath
                OutputFormat = $OutputFormat
            }
        }

        # To control the Pester code coverage, a boolean $CodeCoverageEnabled is used.
        if ($CodeCoverage.IsPresent) {
            $pesterParams.CodeCoverage = $CodeCoverageFiles
        }

        $testResult = Invoke-Pester @pesterParams

        if ($testResult.FailedCount -gt 0) {
            throw 'One or more Pester tests failed'
        }

        if ($CodeCoverage.IsPresent) {
            $testCoverage = [int]($testResult.CodeCoverage.NumberOfCommandsExecuted / $testResult.CodeCoverage.NumberOfCommandsAnalyzed)
            'Pester code coverage on specified files: {0:p}' -f $testCoverage
        }
    } finally {
        Pop-Location
        Remove-Module $ModuleName -ErrorAction SilentlyContinue
    }
}

function Build-PSBuildModule {
    [cmdletbinding()]
    param(
        [string]$Path,

        [string]$DestinationPath,

        [switch]$Compile,

        [string[]]$Exclude = @()
    )

    if (-not (Test-Path -LiteralPath $DestinationPath)) {
        New-Item -Path $DestinationPath -ItemType Directory -Verbose:$VerbosePreference > $null
    }

    if ($Compile.IsPresent) {
        # TODO
    } else{
        $copyParams = @{
            Path        = (Join-Path -Path $Path -ChildPath '*')
            Destination = $DestinationPath
            Recurse     = $true
            Exclude     = $Exclude
            Force       = $true
            Verbose     = $VerbosePreference
        }
        Copy-Item @copyParams
    }
}
