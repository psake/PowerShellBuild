
Set-BuildEnvironment -Force

function Initialize-PSBuild {
    [cmdletbinding()]
    param(
        [switch]$UseBuildHelpers
    )

    Set-BuildEnvironment -Force

    Write-Host 'Build System Details:' -ForegroundColor Yellow
    $psVersion          = $PSVersionTable.PSVersion.ToString()
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

        [double]$CodeCoverageThreshold,

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
            if ($testCoverage -lt $CodeCoverageThreshold) {
                throw 'Code coverage is less than threshold of {0:p}' -f $CodeCoverageThreshold
            }
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

        [string]$ModuleName,

        [string]$ModuleManifestPath,

        [switch]$Compile,

        [string]$ReadMePath,

        [string[]]$Exclude = @(),

        [string]$Culture = (Get-UICulture).Name
    )

    if (-not (Test-Path -LiteralPath $DestinationPath)) {
        New-Item -Path $DestinationPath -ItemType Directory -Verbose:$VerbosePreference > $null
    }

    # Copy "non-processed files"
    Get-ChildItem -Path $Path -Include '*.psm1', '*.psd1', '*.ps1xml' -Depth 1 | Copy-Item -Destination $DestinationPath -Force

    # Copy README as about_<modulename>.help.txt
    if (-not [string]::IsNullOrEmpty($ReadMePath)) {
        $culturePath = Join-Path -Path $DestinationPath -ChildPath $Culture
        $aboutModulePath = Join-Path -Path $culturePath -ChildPath "about_$($ModuleName).help.txt"
        if(-not (Test-Path $culturePath -PathType Container)) {
            New-Item $culturePath -Type Directory -Force > $null
            Copy-Item -LiteralPath $ReadMePath -Destination $aboutModulePath -Force
        }
    }

    # Copy source files to destination and optionally combine *.ps1 files into the PSM1
    if ($Compile.IsPresent) {
        $rootModule = Join-Path -Path $DestinationPath -ChildPath "$ModuleName.psm1"
        $allScripts = Get-ChildItem -Path $Path -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue
        $allScripts | ForEach-Object {
            $srcFile = Resolve-Path $_.FullName -Relative
            Write-Verbose "Adding $srcFile to PSM1"
            Get-Content $srcFile
        } | Set-Content -Path $rootModule -Encoding utf8
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

    # Export public functions in manifest if there are any public functions
    $publicFunctions = Get-ChildItem $Path/Public/*.ps1 -Recurse -ErrorAction SilentlyContinue
    if ($publicFunctions) {
        $outputManifest = Join-Path -Path $DestinationPath -ChildPath "$ModuleName.psd1"
        Update-Metadata -Path $OutputManifest -PropertyName FunctionsToExport -Value $publicFunctions.BaseName
    }
}

function Build-PSBuildMarkdown {
    [cmdletbinding()]
    param(
        [string]$ModulePath,

        [string]$ModuleName,

        [string]$DocsPath,

        [string]$Locale
    )

    $moduleInfo = Import-Module "$ModulePath/$ModuleName.psd1" -Global -Force -PassThru

    try {
        if ($moduleInfo.ExportedCommands.Count -eq 0) {
            Write-Warning 'No commands have been exported. Skipping markdown generation.'
            return
        }

        if (-not (Test-Path -LiteralPath $DocsPath)) {
            New-Item -Path $DocsPath -ItemType Directory > $null
        }

        if (Get-ChildItem -LiteralPath $DocsPath -Filter *.md -Recurse) {
            Get-ChildItem -LiteralPath $DocsPath -Directory | ForEach-Object {
                Update-MarkdownHelp -Path $_.FullName -Verbose:$VerbosePreference > $null
            }
        }

        # ErrorAction set to SilentlyContinue so this command will not overwrite an existing MD file.
        $newMDParams = @{
            Module         = $ModuleName
            Locale         = $Locale
            OutputFolder   = (Join-Path $DocsPath $Locale)
            WithModulePage = $true
            ErrorAction    = 'SilentlyContinue'
            Verbose        = $VerbosePreference
        }
        New-MarkdownHelp @newMDParams > $null
    }
    finally {
        Remove-Module $moduleName
    }
}

function Build-PSBuildMAMLHelp {
    [cmdletbinding()]
    param(
        [string]$Path,

        [string]$DestinationPath
    )

    $helpLocales = (Get-ChildItem -Path $Path -Directory).Name

    # Generate the module's primary MAML help file
    foreach ($locale in $helpLocales) {
        $externalHelpParams = @{
            Path        = Join-Path $Path $locale
            OutputPath  = Join-Path $DestinationPath $locale
            Force       = $true
            ErrorAction = 'SilentlyContinue'
            Verbose     = $VerbosePreference
        }
        New-ExternalHelp @externalHelpParams > $null
    }
}

function Build-PSBuildUpdatableHelp {
    [cmdletbinding()]
    param(
        [string]$DocsPath,

        [string]$OutputPath
    )

    if ($null -ne $IsWindows -and -not $IsWindows) {
        Write-Warning 'MakeCab.exe is only available on Windows. Cannot create help cab.'
        return
    }

    $helpLocales = (Get-ChildItem -Path $DocsPath -Directory).Name

    # Create updatable help output directory
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item $OutputPath -ItemType Directory -Verbose:$VerbosePreference > $null
    } else {
        Write-Verbose "Directory already exists [$OutputPath]."
        Get-ChildItem $OutputPath | Remove-Item -Recurse -Force -Verbose:$VerbosePreference
    }

    # Generate updatable help files.  Note: this will currently update the version number in the module's MD
    # file in the metadata.
    foreach ($locale in $helpLocales) {
        $cabParams = @{
            CabFilesFolder  = Join-Path $moduleOutDir $locale
            LandingPagePath = "$DocsPath/$locale/$ModuleName.md"
            OutputFolder    = $OutputPath
            Verbose         = $VerbosePreference
        }
        New-ExternalHelpCab @cabParams > $null
    }
}

Export-ModuleMember -Function *

# $psakeTaskAlias = 'PowerShellBuild.Common.psake.tasks'
# Set-Alias -Name $psakeTaskAlias -Value $PSScriptRoot/psakeFile.ps1
# Export-ModuleMember -Alias $psakeTaskAlias

# Invoke-Build task aliases
$ibAlias = 'PowerShellBuild.Common.IB.Tasks'
Set-Alias -Name $ibAlias -Value $PSScriptRoot/IB.tasks.ps1
Export-ModuleMember -Alias $ibAlias
