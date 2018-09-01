
#region Basic project settings

Set-BuildEnvironment -Force

# Root directory for the project
$projectRoot = $env:BHProjectPath

# Root directory for the module
$srcRootDir = $env:BHPSModulePath

# The name of the module. This should match the basename of the PSD1 file
$moduleName = $env:BHProjectName

# Module version
$moduleVersion = (Import-PowerShellDataFile -Path $env:BHPSModuleManifest).ModuleVersion

# Module manifest path
$moduleManifestPath = $env:BHPSModuleManifest

# Output directory when building a module
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$outDir = Join-Path -Path $projectRoot -ChildPath Output

# Module output directory
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$moduleOutDir = "$outDir/$moduleName/$moduleVersion"

# Controls whether to "compile" module into single PSM1 or not
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$compileModule = $false

[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$updatableHelpOutDir = Join-Path $OutDir UpdatableHelp

# Default Locale used for help generation, defaults to en-US
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$defaultLocale = (Get-UICulture).Name

# Convert project readme into the module about file
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$convertReadMeToAboutHelp = $false
#endregion

#region Script Analysis

# Enable/disable use of PSScriptAnalyzer to perform script analysis
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$scriptAnalysisEnabled = $true

# When PSScriptAnalyzer is enabled, control which severity level will generate a build failure.
# Valid values are Error, Warning, Information and None.  "None" will report errors but will not
# cause a build failure.  "Error" will fail the build only on diagnostic records that are of
# severity error.  "Warning" will fail the build on Warning and Error diagnostic records.
# "Any" will fail the build on any diagnostic record, regardless of severity.
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
[ValidateSet('Error', 'Warning', 'Any', 'None')]
$scriptAnalysisFailBuildOnSeverityLevel = 'Error'

# Path to the PSScriptAnalyzer settings file.
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$scriptAnalyzerSettingsPath = Join-Path $PSScriptRoot -ChildPath ScriptAnalyzerSettings.psd1
#endregion

#region File catalog

# Enable/disable generation of a catalog (.cat) file for the module.
# [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
# $catalogGenerationEnabled = $true

# # Select the hash version to use for the catalog file: 1 for SHA1 (compat with Windows 7 and
# # Windows Server 2008 R2), 2 for SHA2 to support only newer Windows versions.
# [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
# $catalogVersion = 2
#endregion

#region Testing

# Enable/disable Pester tests
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$testingEnabled = $true

# Directory containing Pester tests
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$testRootDir = Join-Path -Path $projectRoot -ChildPath tests

# Enable/disable Pester code coverage reporting.
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$codeCoverageEnabled = $false

# Fail Pester code coverage test if below this threshold
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$codeCoverageThreshold = .75

# CodeCoverageFiles specifies the files to perform code coverage analysis on. This property
# acts as a direct input to the Pester -CodeCoverage parameter, so will support constructions
# like the ones found here: https://github.com/pester/Pester/wiki/Code-Coverage.
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$codeCoverageFiles = @(
    Join-Path -Path $srcRootDir -ChildPath '*.ps1'
    Join-Path -Path $srcRootDir -ChildPath '*.psm1'
)

# Specifies an output file path to send to Invoke-Pester's -OutputFile parameter.
# This is typically used to write out test results so that they can be sent to a CI
# system like AppVeyor.
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$testOutputFile = $null

# Specifies the test output format to use when the TestOutputFile property is given
# a path.  This parameter is passed through to Invoke-Pester's -OutputFormat parameter.
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$testOutputFormat = 'NUnitXml'
#endregion

#region Documentation
# Directory PlatyPS markdown documentation will be saved to
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$docsRootDir = Join-Path -Path $projectRoot -ChildPath 'docs'

#endregion
