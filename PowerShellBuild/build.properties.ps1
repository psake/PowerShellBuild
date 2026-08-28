# spell-checker:ignore PSGALLERY BHPS MAML
BuildHelpers\Set-BuildEnvironment -Force

$outDir = [IO.Path]::Combine($env:BHProjectPath, 'Output')
$moduleVersion = (Import-PowerShellDataFile -Path $env:BHPSModuleManifest).ModuleVersion

[ordered]@{
    General = @{
        # Root directory for the project
        ProjectRoot        = $env:BHProjectPath

        # Root directory for the module
        SrcRootDir         = $env:BHPSModulePath

        # The name of the module. This should match the basename of the PSD1 file
        ModuleName         = $env:BHProjectName

        # Module version
        ModuleVersion      = $moduleVersion

        # Module manifest path
        ModuleManifestPath = $env:BHPSModuleManifest
    }
    Build   = @{

        # "Dependencies" moved to TaskDependencies section

        # Output directory when building a module
        OutDir             = $outDir

        # Module output directory
        # This will be computed in 'Initialize-PSBuild' so we can allow the user to
        # override the top-level 'OutDir' above and compute the full path to the module internally
        ModuleOutDir       = $null

        # Controls whether to "compile" module into single PSM1 or not
        CompileModule      = $false

        # List of directories that if CompileModule is $true, will be concatenated into the PSM1
        CompileDirectories = @('Enum', 'Classes', 'Private', 'Public')

        # List of directories that will always be copied "as is" to output directory
        CopyDirectories    = @()

        # List of files (regular expressions) to exclude from output directory
        Exclude            = @()
    }
    Test    = @{
        # Enable/disable Pester tests
        Enabled                = $true

        # Directory containing Pester tests
        RootDir                = [IO.Path]::Combine($env:BHProjectPath, 'tests')

        # Specifies an output file path to send to Invoke-Pester's -OutputFile parameter.
        # This is typically used to write out test results so that they can be sent to a CI system
        # The default below is absolute. A relative path resolves against the directory
        # containing Pester tests, because Test-PSBuildPester pushes into it before running.
        OutputFile             = [IO.Path]::Combine($env:BHProjectPath, 'testResults.xml')

        # Specifies the test output format to use when the TestOutputFile property is given
        # a path.  This parameter is passed through to Invoke-Pester's -OutputFormat parameter.
        OutputFormat           = 'NUnitXml'

        ScriptAnalysis         = @{
            # Enable/disable use of PSScriptAnalyzer to perform script analysis
            Enabled                  = $true

            # When PSScriptAnalyzer is enabled, control which severity level will generate a build failure.
            # Valid values are None, Information, Warning, Error, and Any.
            #   "None"        reports findings but never fails the build.
            #   "Information" fails the build on Information, Warning, and Error records.
            #   "Warning"     fails the build on Warning and Error records.
            #   "Error"       fails the build on Error records.
            #   "Any"         fails the build on any diagnostic record, regardless of severity.
            # PSScriptAnalyzer also reports ParseError records for files that do not parse at all.
            # Those are counted with Error, so an unparsable file fails every level except "None".
            FailBuildOnSeverityLevel = 'Error'

            # Path to the PSScriptAnalyzer settings file.
            SettingsPath             = [IO.Path]::Combine($PSScriptRoot, 'ScriptAnalyzerSettings.psd1')
        }

        # Import module from OutDir prior to running Pester tests.
        ImportModule           = $false

        CodeCoverage           = @{
            # Enable/disable Pester code coverage reporting.
            Enabled          = $false

            # Fail Pester code coverage test if below this threshold
            Threshold        = .75

            # CodeCoverageFiles specifies the files to perform code coverage analysis on. This property
            # acts as a direct input to the Pester -CodeCoverage parameter, so will support constructions
            # like the ones found here: https://pester.dev/docs/usage/code-coverage.
            Files            = @()

            # Path to write code coverage report to
            OutputFile       = [IO.Path]::Combine($env:BHProjectPath, 'codeCoverage.xml')

            # The code coverage output format to use
            OutputFileFormat = 'JaCoCo'
        }

        # Skip remaining tests after failure for selected scope. Options are None, Run, Container and Block. Default: None.
        SkipRemainingOnFailure = 'None'

        # Set verbosity of output. Options are None, Normal, Detailed and Diagnostic. Default: Detailed.
        OutputVerbosity        = 'Detailed'
    }
    Help    = @{
        # Path to updatable help CAB
        UpdatableHelpOutDir      = [IO.Path]::Combine($outDir, 'UpdatableHelp')

        # Default Locale used for help generation, defaults to en-US
        # Get-UICulture doesn't return a name on Linux so default to en-US
        DefaultLocale            = if (-not (Get-UICulture).Name) { 'en-US' } else { (Get-UICulture).Name }

        # Convert project readme into the module about file
        ConvertReadMeToAboutHelp = $false
    }
    Docs    = @{
        # Directory PlatyPS markdown documentation will be saved to
        RootDir               = [IO.Path]::Combine($env:BHProjectPath, 'docs')

        # Whether to overwrite existing markdown files and use comment based help as the source of truth
        Overwrite             = $false

        # Exclude the parameters marked with `DontShow` in the parameter attribute from the help content.
        # Value passed to New-MarkdownCommandHelp.
        ExcludeDontShow       = $false

        # Indicates that the target document will use a full type name instead of a short name for parameters.
        # PlatyPS 1.x writes full type names by default, so $false is passed through as
        # New-MarkdownCommandHelp's -AbbreviateParameterTypeName switch.
        UseFullTypeName       = $false
    }
    Publish = @{
        # PowerShell repository name to publish modules to
        PSRepository           = 'PSGallery'

        # API key to authenticate to PowerShell repository with
        PSRepositoryApiKey     = $env:PSGALLERY_API_KEY

        # Credential to authenticate to PowerShell repository with
        PSRepositoryCredential = $null
    }
    Sign    = @{
        # Enable/disable Authenticode signing of module files. Must be $true for any
        # signing or catalog tasks to execute.
        Enabled                   = $false

        # Certificate source used to resolve the code-signing certificate.
        # Valid values:
        #   Auto      - Uses EnvVar if CertificateEnvVar is populated, otherwise falls back to Store.
        #               This is the recommended setting for pipelines that share a common psakeFile.
        #   Store     - Selects the first valid, unexpired code-signing certificate with a private
        #               key from the Windows certificate store (CertStoreLocation).
        #   Thumbprint - Like Store, but selects a specific certificate by Thumbprint.
        #   EnvVar    - Decodes a Base64-encoded PFX from the CertificateEnvVar environment
        #               variable. Common in GitHub Actions, Azure DevOps, and GitLab CI.
        #   PfxFile   - Loads a PFX/P12 file from PfxFilePath with an optional PfxFilePassword.
        CertificateSource         = 'Auto'

        # Windows certificate store path searched by Store and Thumbprint sources.
        CertStoreLocation         = 'Cert:\CurrentUser\My'

        # Specific certificate thumbprint to select (Thumbprint source only).
        Thumbprint                = $null

        # Name of the environment variable that holds the Base64-encoded PFX certificate.
        # Used by the EnvVar source and as the presence-detection key for Auto.
        CertificateEnvVar         = 'SIGNCERTIFICATE'

        # Name of the environment variable that holds the PFX password (EnvVar source).
        CertificatePasswordEnvVar = 'CERTIFICATEPASSWORD'

        # File system path to a PFX/P12 certificate file (PfxFile source).
        PfxFilePath               = $null

        # Password for the PFX file as a SecureString (PfxFile source).
        PfxFilePassword           = $null

        # A pre-resolved [System.Security.Cryptography.X509Certificates.X509Certificate2] object.
        # When set, CertificateSource is ignored and this certificate is used directly.
        # Useful for Azure Key Vault, HSM, or other custom certificate providers.
        Certificate               = $null

        # When true, relax the certificate validity checks. This is not
        # recommended for production use but can be useful in CI environments
        # where certificates are frequently renewed and rotated.
        #
        # The EnvVar and PfxFile sources load exactly one certificate, so every
        # check is skipped outright for them -- the private key check included.
        # A certificate without a private key cannot sign, so setting this for
        # those two sources defers that failure to Set-AuthenticodeSignature,
        # which reports it far less clearly.
        #
        # The Store and Thumbprint sources select one certificate out of many,
        # so the relaxation is a fallback rather than a blanket bypass: an
        # unexpired certificate is preferred whenever one exists, and an expired
        # one is returned only when no unexpired certificate was found. A
        # warning is emitted when that happens, and the Thumbprint source still
        # matches the requested thumbprint. These two sources always require a
        # private key, because it is part of how the certificate is selected
        # rather than a check layered on afterwards.
        SkipCertificateValidation = $false

        # Timestamp server URI embedded in Authenticode signatures, so a signature
        # stays valid after the signing certificate expires.
        #
        # This is passed to Set-AuthenticodeSignature -TimestampServer, which uses the
        # legacy Authenticode timestamp protocol -- the timestamp lands in the signature
        # as a PKCS#9 counter-signature (1.2.840.113549.1.9.6), not as an RFC 3161 token
        # (1.3.6.1.4.1.311.3.3.1). That is signtool's /t rather than /tr. Verified on both
        # PowerShell 7 and Windows PowerShell 5.1; see psake/PowerShellBuild#196.
        #
        # It matters when choosing a different provider: several publish separate
        # endpoints for the two protocols, and an RFC 3161 only endpoint will not answer
        # this request. The default below serves both.
        TimestampServer           = 'http://timestamp.digicert.com'

        # Authenticode hash algorithm. Valid values: SHA256, SHA384, SHA512, SHA1.
        HashAlgorithm             = 'SHA256'

        # Glob patterns of files to sign in the module output directory.
        FilesToSign               = @('*.psd1', '*.psm1', '*.ps1')

        Catalog                   = @{
            # Enable/disable Windows catalog (.cat) file creation and signing.
            # Requires Sign.Enabled = $true.
            Enabled  = $false

            # Catalog hash version.
            # 1 = SHA1, compatible with Windows 7 and Windows Server 2008 R2.
            # 2 = SHA2, required for Windows 8 / Server 2012 and newer.
            Version  = 2

            # Catalog file name. Defaults to '<ModuleName>.cat' when $null.
            FileName = $null
        }
    }
}
