# spell-checker:ignore Reqs
# Load in build settings
Remove-Variable -Name PSBPreference -Scope Script -Force -ErrorAction Ignore
Set-Variable -Name PSBPreference -Option ReadOnly -Scope Script -Value (. ([IO.Path]::Combine($PSScriptRoot, 'build.properties.ps1')))

Properties {}

FormatTaskName {
    param($taskName)
    Write-Host 'Task: ' -ForegroundColor Cyan -NoNewline
    Write-Host $taskName.ToUpper() -ForegroundColor Blue
}

#region Task Dependencies
if ($null -eq $PSBCleanDependency) {
    $PSBCleanDependency = @('Init')
}
if ($null -eq $PSBStageFilesDependency) {
    $PSBStageFilesDependency = @('Clean')
}
if ($null -eq $PSBBuildDependency) {
    $PSBBuildDependency = @('StageFiles', 'BuildHelp')
}
if ($null -eq $PSBAnalyzeDependency) {
    $PSBAnalyzeDependency = @('Build')
}
if ($null -eq $PSBPesterDependency) {
    $PSBPesterDependency = @('Build')
}
if ($null -eq $PSBTestDependency) {
    $PSBTestDependency = @('Pester', 'Analyze')
}
if ($null -eq $PSBBuildHelpDependency) {
    $PSBBuildHelpDependency = @('GenerateMarkdown', 'GenerateMAML')
}
if ($null -eq $PSBGenerateMarkdownDependency) {
    $PSBGenerateMarkdownDependency = @('StageFiles')
}
if ($null -eq $PSBGenerateMAMLDependency) {
    $PSBGenerateMAMLDependency = @('GenerateMarkdown')
}
if ($null -eq $PSBGenerateUpdatableHelpDependency) {
    $PSBGenerateUpdatableHelpDependency = @('BuildHelp')
}
if ($null -eq $PSBPublishDependency) {
    $PSBPublishDependency = @('Test')
}
if ($null -eq $PSBSignModuleDependency) {
    $PSBSignModuleDependency = @('Build')
}
if ($null -eq $PSBBuildCatalogDependency) {
    $PSBBuildCatalogDependency = @('SignModule')
}
if ($null -eq $PSBSignCatalogDependency) {
    $PSBSignCatalogDependency = @('BuildCatalog')
}
if ($null -eq $PSBSignDependency) {
    $PSBSignDependency = @('SignCatalog')
}
#endregion Task Dependencies

# This psake file is meant to be referenced from another
# Can't have two 'default' tasks
# Task default -depends Test

Task Init {
    Initialize-PSBuild -UseBuildHelpers -BuildEnvironment $PSBPreference
} -Description 'Initialize build environment variables'

Task Clean -Depends $PSBCleanDependency {
    Clear-PSBuildOutputFolder -Path $PSBPreference.Build.ModuleOutDir
} -Description 'Clears module output directory'

Task StageFiles -Depends $PSBStageFilesDependency {
    $buildParams = @{
        Path               = $PSBPreference.General.SrcRootDir
        ModuleName         = $PSBPreference.General.ModuleName
        DestinationPath    = $PSBPreference.Build.ModuleOutDir
        Exclude            = $PSBPreference.Build.Exclude
        Compile            = $PSBPreference.Build.CompileModule
        CompileDirectories = $PSBPreference.Build.CompileDirectories
        CopyDirectories    = $PSBPreference.Build.CopyDirectories
        Culture            = $PSBPreference.Help.DefaultLocale
    }

    if ($PSBPreference.Help.ConvertReadMeToAboutHelp) {
        $readMePath = Get-ChildItem -Path $PSBPreference.General.ProjectRoot -Include 'readme.md', 'readme.markdown', 'readme.txt' -Depth 1 |
            Select-Object -First 1
        if ($readMePath) {
            $buildParams.ReadMePath = $readMePath
        }
    }

    # only add these configuration values to the build parameters if they have been been set
    'CompileHeader', 'CompileFooter', 'CompileScriptHeader', 'CompileScriptFooter' | ForEach-Object {
        if ($PSBPreference.Build.Keys -contains $_) {
            $buildParams.$_ = $PSBPreference.Build.$_
        }
    }

    Build-PSBuildModule @buildParams
} -Description 'Builds module based on source directory'

Task Build -Depends $PSBBuildDependency -Description 'Builds module and generate help documentation'

$analyzePreReqs = {
    $result = $true
    if (-not $PSBPreference.Test.ScriptAnalysis.Enabled) {
        Write-Warning 'Script analysis is not enabled.'
        $result = $false
    }
    if (-not (Get-Module -Name PSScriptAnalyzer -ListAvailable)) {
        Write-Warning 'PSScriptAnalyzer module is not installed'
        $result = $false
    }
    $result
}
Task Analyze -Depends $PSBAnalyzeDependency -PreCondition $analyzePreReqs {
    $analyzeParams = @{
        Path              = $PSBPreference.Build.ModuleOutDir
        SeverityThreshold = $PSBPreference.Test.ScriptAnalysis.FailBuildOnSeverityLevel
        SettingsPath      = $PSBPreference.Test.ScriptAnalysis.SettingsPath
    }
    Test-PSBuildScriptAnalysis @analyzeParams
} -Description 'Execute PSScriptAnalyzer tests'

$pesterPreReqs = {
    $result = $true
    if (-not $PSBPreference.Test.Enabled) {
        Write-Warning 'Pester testing is not enabled.'
        $result = $false
    }
    if (-not (Get-Module -Name Pester -ListAvailable)) {
        Write-Warning 'Pester module is not installed'
        $result = $false
    }
    if (-not (Test-Path -Path $PSBPreference.Test.RootDir)) {
        Write-Warning "Test directory [$($PSBPreference.Test.RootDir)] not found"
        $result = $false
    }
    return $result
}
Task Pester -Depends $PSBPesterDependency -PreCondition $pesterPreReqs {
    $pesterParams = @{
        Path                         = $PSBPreference.Test.RootDir
        ModuleName                   = $PSBPreference.General.ModuleName
        ModuleManifest               = Join-Path $PSBPreference.Build.ModuleOutDir "$($PSBPreference.General.ModuleName).psd1"
        OutputPath                   = $PSBPreference.Test.OutputFile
        OutputFormat                 = $PSBPreference.Test.OutputFormat
        CodeCoverage                 = $PSBPreference.Test.CodeCoverage.Enabled
        CodeCoverageThreshold        = $PSBPreference.Test.CodeCoverage.Threshold
        CodeCoverageFiles            = $PSBPreference.Test.CodeCoverage.Files
        CodeCoverageOutputFile       = $PSBPreference.Test.CodeCoverage.OutputFile
        CodeCoverageOutputFileFormat = $PSBPreference.Test.CodeCoverage.OutputFileFormat
        ImportModule                 = $PSBPreference.Test.ImportModule
        SkipRemainingOnFailure       = $PSBPreference.Test.SkipRemainingOnFailure
        OutputVerbosity              = $PSBPreference.Test.OutputVerbosity
    }
    Test-PSBuildPester @pesterParams
} -Description 'Execute Pester tests'

Task Test -Depends $PSBTestDependency {
} -Description 'Execute Pester and ScriptAnalyzer tests'

Task BuildHelp -Depends $PSBBuildHelpDependency {} -Description 'Builds help documentation'

$genMarkdownPreReqs = {
    $result = $true
    if (-not (Get-Module platyPS -ListAvailable)) {
        Write-Warning "platyPS module is not installed. Skipping [$($psake.context.currentTaskName)] task."
        $result = $false
    }
    $result
}
Task GenerateMarkdown -Depends $PSBGenerateMarkdownDependency -PreCondition $genMarkdownPreReqs {
    $buildMDParams = @{
        ModulePath            = $PSBPreference.Build.ModuleOutDir
        ModuleName            = $PSBPreference.General.ModuleName
        DocsPath              = $PSBPreference.Docs.RootDir
        Locale                = $PSBPreference.Help.DefaultLocale
        Overwrite             = $PSBPreference.Docs.Overwrite
        AlphabeticParamsOrder = $PSBPreference.Docs.AlphabeticParamsOrder
        ExcludeDontShow       = $PSBPreference.Docs.ExcludeDontShow
        UseFullTypeName       = $PSBPreference.Docs.UseFullTypeName
    }
    Build-PSBuildMarkdown @buildMDParams
} -Description 'Generates PlatyPS markdown files from module help'

$genHelpFilesPreReqs = {
    $result = $true
    if (-not (Get-Module platyPS -ListAvailable)) {
        Write-Warning "platyPS module is not installed. Skipping [$($psake.context.currentTaskName)] task."
        $result = $false
    }
    $result
}
Task GenerateMAML -Depends $PSBGenerateMAMLDependency -PreCondition $genHelpFilesPreReqs {
    Build-PSBuildMAMLHelp -Path $PSBPreference.Docs.RootDir -DestinationPath $PSBPreference.Build.ModuleOutDir
} -Description 'Generates MAML-based help from PlatyPS markdown files'

$genUpdatableHelpPreReqs = {
    $result = $true
    if (-not (Get-Module platyPS -ListAvailable)) {
        Write-Warning "platyPS module is not installed. Skipping [$($psake.context.currentTaskName)] task."
        $result = $false
    }
    $result
}
Task GenerateUpdatableHelp -Depends $PSBGenerateUpdatableHelpDependency -PreCondition $genUpdatableHelpPreReqs {
    Build-PSBuildUpdatableHelp -DocsPath $PSBPreference.Docs.RootDir -OutputPath $PSBPreference.Help.UpdatableHelpOutDir
} -Description 'Create updatable help .cab file based on PlatyPS markdown help'

Task Publish -Depends $PSBPublishDependency {
    Assert -ConditionToCheck ($PSBPreference.Publish.PSRepositoryApiKey -or $PSBPreference.Publish.PSRepositoryCredential) -FailureMessage "API key or credential not defined to authenticate with [$($PSBPreference.Publish.PSRepository)] with."

    $publishParams = @{
        Path       = $PSBPreference.Build.ModuleOutDir
        Version    = $PSBPreference.General.ModuleVersion
        Repository = $PSBPreference.Publish.PSRepository
        Verbose    = $VerbosePreference
    }
    if ($PSBPreference.Publish.PSRepositoryApiKey) {
        $publishParams.ApiKey = $PSBPreference.Publish.PSRepositoryApiKey
    }

    if ($PSBPreference.Publish.PSRepositoryCredential) {
        $publishParams.Credential = $PSBPreference.Publish.PSRepositoryCredential
    }

    Publish-PSBuildModule @publishParams
} -Description 'Publish module to the defined PowerShell repository'

$signModulePreReqs = {
    $result = $true
    if (-not $PSBPreference.Sign.Enabled) {
        Write-Warning 'Module signing is not enabled.'
        $result = $false
    }
    if (-not (Get-Command -Name 'Set-AuthenticodeSignature' -ErrorAction Ignore)) {
        Write-Warning 'Set-AuthenticodeSignature is not available. Module signing requires Windows.'
        $result = $false
    }
    $result
}
Task SignModule -Depends $PSBSignModuleDependency -PreCondition $signModulePreReqs {
    $certParams = @{
        CertificateSource         = $PSBPreference.Sign.CertificateSource
        CertStoreLocation         = $PSBPreference.Sign.CertStoreLocation
        CertificateEnvVar         = $PSBPreference.Sign.CertificateEnvVar
        CertificatePasswordEnvVar = $PSBPreference.Sign.CertificatePasswordEnvVar
    }
    if ($PSBPreference.Sign.Thumbprint) {
        $certParams.Thumbprint = $PSBPreference.Sign.Thumbprint
    }
    if ($PSBPreference.Sign.PfxFilePath) {
        $certParams.PfxFilePath = $PSBPreference.Sign.PfxFilePath
    }
    if ($PSBPreference.Sign.PfxFilePassword) {
        $certParams.PfxFilePassword = $PSBPreference.Sign.PfxFilePassword
    }

    $certificate = if ($PSBPreference.Sign.Certificate) {
        $PSBPreference.Sign.Certificate
    } else {
        Get-PSBuildCertificate @certParams
    }

    Assert ($null -ne $certificate) $LocalizedData.NoCertificateFound

    $signingParams = @{
        Path            = $PSBPreference.Build.ModuleOutDir
        Certificate     = $certificate
        TimestampServer = $PSBPreference.Sign.TimestampServer
        HashAlgorithm   = $PSBPreference.Sign.HashAlgorithm
        Include         = $PSBPreference.Sign.FilesToSign
    }
    Invoke-PSBuildModuleSigning @signingParams
} -Description 'Signs module files (*.psd1, *.psm1, *.ps1) with an Authenticode signature'

$buildCatalogPreReqs = {
    $result = $true
    if (-not ($PSBPreference.Sign.Enabled -and $PSBPreference.Sign.Catalog.Enabled)) {
        Write-Warning 'Catalog generation is not enabled.'
        $result = $false
    }
    if (-not (Get-Command -Name 'New-FileCatalog' -ErrorAction Ignore)) {
        Write-Warning 'New-FileCatalog is not available. Catalog generation requires Windows.'
        $result = $false
    }
    $result
}
Task BuildCatalog -Depends $PSBBuildCatalogDependency -PreCondition $buildCatalogPreReqs {
    $catalogFileName = if ($PSBPreference.Sign.Catalog.FileName) {
        $PSBPreference.Sign.Catalog.FileName
    } else {
        "$($PSBPreference.General.ModuleName).cat"
    }
    $catalogFilePath = Join-Path -Path $PSBPreference.Build.ModuleOutDir -ChildPath $catalogFileName

    $catalogParams = @{
        ModulePath      = $PSBPreference.Build.ModuleOutDir
        CatalogFilePath = $catalogFilePath
        CatalogVersion  = $PSBPreference.Sign.Catalog.Version
    }
    New-PSBuildFileCatalog @catalogParams
} -Description 'Creates a Windows catalog (.cat) file for the built module'

$signCatalogPreReqs = {
    $result = $true
    if (-not ($PSBPreference.Sign.Enabled -and $PSBPreference.Sign.Catalog.Enabled)) {
        Write-Warning 'Catalog signing is not enabled.'
        $result = $false
    }
    if (-not (Get-Command -Name 'Set-AuthenticodeSignature' -ErrorAction Ignore)) {
        Write-Warning 'Set-AuthenticodeSignature is not available. Catalog signing requires Windows.'
        $result = $false
    }
    $result
}
Task SignCatalog -Depends $PSBSignCatalogDependency -PreCondition $signCatalogPreReqs {
    $certParams = @{
        CertificateSource         = $PSBPreference.Sign.CertificateSource
        CertStoreLocation         = $PSBPreference.Sign.CertStoreLocation
        CertificateEnvVar         = $PSBPreference.Sign.CertificateEnvVar
        CertificatePasswordEnvVar = $PSBPreference.Sign.CertificatePasswordEnvVar
    }
    if ($PSBPreference.Sign.Thumbprint) {
        $certParams.Thumbprint = $PSBPreference.Sign.Thumbprint
    }
    if ($PSBPreference.Sign.PfxFilePath) {
        $certParams.PfxFilePath = $PSBPreference.Sign.PfxFilePath
    }
    if ($PSBPreference.Sign.PfxFilePassword) {
        $certParams.PfxFilePassword = $PSBPreference.Sign.PfxFilePassword
    }

    $certificate = if ($PSBPreference.Sign.Certificate) {
        $PSBPreference.Sign.Certificate
    } else {
        Get-PSBuildCertificate @certParams
    }

    Assert ($null -ne $certificate) $LocalizedData.NoCertificateFound

    $catalogFileName = if ($PSBPreference.Sign.Catalog.FileName) {
        $PSBPreference.Sign.Catalog.FileName
    } else {
        "$($PSBPreference.General.ModuleName).cat"
    }

    $signingParams = @{
        Path            = $PSBPreference.Build.ModuleOutDir
        Certificate     = $certificate
        TimestampServer = $PSBPreference.Sign.TimestampServer
        HashAlgorithm   = $PSBPreference.Sign.HashAlgorithm
        Include         = @($catalogFileName)
    }
    Invoke-PSBuildModuleSigning @signingParams
} -Description 'Signs the module catalog (.cat) file with an Authenticode signature'

Task Sign -Depends $PSBSignDependency {} -Description 'Signs module files and catalog (meta task)'

Task ? -Description 'Lists the available tasks' {
    'Available tasks:'
    $psake.context.Peek().Tasks.Keys | Sort-Object
}
