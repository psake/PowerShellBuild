
# ------------------ Basic project settings analysis properties ---------------------------

# Use BuildHelpers module to normalize CI environment variables
$useBuildHelpers = $true

# Root directory for the project
if ($useBuildHelpers) {
    $projectRoot = $env:BHProjectPath
} else {
    $projectRoot = $psake.context.originalDirectory
}

# Root directory of PowerShell module
if ($useBuildHelpers) {
    Import-Module -Name BuildHelpers
    Set-BuildEnvironment -Force
    $srcRootDir = $env:BHPSModulePath
} else {
    if (Test-Path (Join-Path -Path $psake.context.originalDirectory -ChildPath src)) {
        $srcRootDir = Join-Path -Path $psake.context.originalDirectory -ChildPath src
    } else {
        $srcRootDir = Join-Path -Path $psake.context.originalDirectory
    }
}

# Output directory when building a module
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$outDir = Join-Path -Path $psake.context.originalDirectory -ChildPath Output

# The name of the module. This should match the basename of the PSD1 file
if ($useBuildHelpers) {
    $moduleName = $env:BHProjectName
} else {
    $moduleName = Get-Item $srcRootDir/*.psd1 |
        Where-Object { $null -ne (Test-ModuleManifest -Path $_ -ErrorAction SilentlyContinue) } |
        Select-Object -First 1 | Foreach-Object BaseName
}

# Module version
if ($useBuildHelpers) {
    $moduleVersion = (Import-PowerShellDataFile -Path $env:BHPSModuleManifest).ModuleVersion
} else {
    $moduleVersion = (Get-Item $srcRootDir/*.psd1 | Select-Object -First | Import-PowerShellDataFile).ModuleVersion
}

# Default Locale used for help generation, defaults to en-US
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$defaultLocale = 'en-US'


# ------------------ Script analysis properties ---------------------------

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

# -------------------- File catalog properties ----------------------------

# Enable/disable generation of a catalog (.cat) file for the module.
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$catalogGenerationEnabled = $true

# Select the hash version to use for the catalog file: 1 for SHA1 (compat with Windows 7 and
# Windows Server 2008 R2), 2 for SHA2 to support only newer Windows versions.
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$catalogVersion = 2

# ---------------------- Testing properties -------------------------------

# Enable/disable Pester tests
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$testingEnabled = $true

# Directory containing Pester tests
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$testRootDir = Join-Path -Path $projectRoot -ChildPath tests

# Enable/disable Pester code coverage reporting.
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
$codeCoverageEnabled = $false

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