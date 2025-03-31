BuildHelpers\Set-BuildEnvironment -Force

$outDir = [IO.Path]::Combine($env:BHProjectPath, 'Output')
$moduleVersion = (Import-PowerShellDataFile -Path $env:BHPSModuleManifest).ModuleVersion

[ordered]@{
    General = @{
        # Root directory for the project
        ProjectRoot = $env:BHProjectPath

        # Root directory for the module
        SrcRootDir = $env:BHPSModulePath

        # The name of the module. This should match the basename of the PSD1 file
        ModuleName = $env:BHProjectName

        # Module version
        ModuleVersion = $moduleVersion

        # Module manifest path
        ModuleManifestPath = $env:BHPSModuleManifest
    }
    Build = @{

        Dependencies = @('StageFiles', 'BuildHelp')

        # Output directory when building a module
        OutDir = $outDir

        # Module output directory
        # This will be computed in 'Initialize-PSBuild' so we can allow the user to
        # override the top-level 'OutDir' above and compute the full path to the module internally
        ModuleOutDir = $null

        # Controls whether to "compile" module into single PSM1 or not
        CompileModule = $false

        # List of directories that if CompileModule is $true, will be concatenated into the PSM1
        CompileDirectories = @('Enum', 'Classes', 'Private', 'Public')

        # List of directories that will always be copied "as is" to output directory
        CopyDirectories = @()

        # List of files (regular expressions) to exclude from output directory
        Exclude = @()
    }
    Test = @{
        # Enable/disable Pester tests
        Enabled = $true

        # Directory containing Pester tests
        RootDir = [IO.Path]::Combine($env:BHProjectPath, 'tests')

        # Specifies an output file path to send to Invoke-Pester's -OutputFile parameter.
        # This is typically used to write out test results so that they can be sent to a CI system
        # This path is relative to the directory containing Pester tests
        OutputFile = [IO.Path]::Combine($env:BHProjectPath, 'testResults.xml')

        # Specifies the test output format to use when the TestOutputFile property is given
        # a path.  This parameter is passed through to Invoke-Pester's -OutputFormat parameter.
        OutputFormat = 'NUnitXml'

        ScriptAnalysis = @{
            # Enable/disable use of PSScriptAnalyzer to perform script analysis
            Enabled = $true

            # When PSScriptAnalyzer is enabled, control which severity level will generate a build failure.
            # Valid values are Error, Warning, Information and None.  "None" will report errors but will not
            # cause a build failure.  "Error" will fail the build only on diagnostic records that are of
            # severity error.  "Warning" will fail the build on Warning and Error diagnostic records.
            # "Any" will fail the build on any diagnostic record, regardless of severity.
            FailBuildOnSeverityLevel = 'Error'

            # Path to the PSScriptAnalyzer settings file.
            SettingsPath = [IO.Path]::Combine($PSScriptRoot, 'ScriptAnalyzerSettings.psd1')
        }

        # Import module from OutDir prior to running Pester tests.
        ImportModule = $false

        CodeCoverage = @{
            # Enable/disable Pester code coverage reporting.
            Enabled = $false

            # Fail Pester code coverage test if below this threshold
            Threshold = .75

            # CodeCoverageFiles specifies the files to perform code coverage analysis on. This property
            # acts as a direct input to the Pester -CodeCoverage parameter, so will support constructions
            # like the ones found here: https://pester.dev/docs/usage/code-coverage.
            Files = @()

            # Path to write code coverage report to
            OutputFile = [IO.Path]::Combine($env:BHProjectPath, 'codeCoverage.xml')

            # The code coverage output format to use
            OutputFileFormat = 'JaCoCo'
        }
    }
    Help = @{
        # Path to updateable help CAB
        UpdatableHelpOutDir = [IO.Path]::Combine($outDir, 'UpdatableHelp')

        # Default Locale used for help generation, defaults to en-US
        # Get-UICulture doesn't return a name on Linux so default to en-US
        DefaultLocale = if (-not (Get-UICulture).Name) { 'en-US' } else { (Get-UICulture).Name }

        # Convert project readme into the module about file
        ConvertReadMeToAboutHelp = $false
    }
    Docs = @{
        # Directory PlatyPS markdown documentation will be saved to
        RootDir = [IO.Path]::Combine($env:BHProjectPath, 'docs')

        # Whether to overwrite existing markdown files and use comment based help as the source of truth
        Overwrite = $false
    }
    Publish = @{
        # PowerShell repository name to publish modules to
        PSRepository = 'PSGallery'

        # API key to authenticate to PowerShell repository with
        PSRepositoryApiKey = $env:PSGALLERY_API_KEY

        # Credential to authenticate to PowerShell repository with
        PSRepositoryCredential = $null
    }
}

# Enable/disable generation of a catalog (.cat) file for the module.
# [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
# $catalogGenerationEnabled = $true

# # Select the hash version to use for the catalog file: 1 for SHA1 (compat with Windows 7 and
# # Windows Server 2008 R2), 2 for SHA2 to support only newer Windows versions.
# [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
# $catalogVersion = 2
