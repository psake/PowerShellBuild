Remove-Variable -Name PSBPreference -Scope Script -Force -ErrorAction Ignore
Set-Variable -Name PSBPreference -Option ReadOnly -Scope Script -Value (. ([IO.Path]::Combine($PSScriptRoot, 'build.properties.ps1')))
$__DefaultBuildDependencies = $PSBPreference.Build.Dependencies

# Synopsis: Initialize build environment variables
Task Init {
    Initialize-PSBuild -UseBuildHelpers -BuildEnvironment $PSBPreference
}

# Synopsis: Clears module output directory
Task Clean Init, {
    Clear-PSBuildOutputFolder -Path $PSBPreference.Build.ModuleOutDir
}

# Synopsis: Builds module based on source directory
Task StageFiles Clean, {
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
}



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

# Synopsis: Execute PSScriptAnalyzer tests
Task Analyze -If (. $analyzePreReqs) Build, {
    $analyzeParams = @{
        Path              = $PSBPreference.Build.ModuleOutDir
        SeverityThreshold = $PSBPreference.Test.ScriptAnalysis.FailBuildOnSeverityLevel
        SettingsPath      = $PSBPreference.Test.ScriptAnalysis.SettingsPath
    }
    Test-PSBuildScriptAnalysis @analyzeParams
}

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

# Synopsis: Execute Pester tests
Task Pester -If (. $pesterPreReqs) Build, {
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
        CodeCoverageOutputFileFormat = $PSBPreference.Test.CodeCoverage.OutputFormat
        ImportModule                 = $PSBPreference.Test.ImportModule
        SkipRemainingOnFailure       = $PSBPreference.Test.SkipRemainingOnFailure
        OutputVerbosity              = $PSBPreference.Test.OutputVerbosity
    }
    Test-PSBuildPester @pesterParams
}



$genMarkdownPreReqs = {
    $result = $true
    if (-not (Get-Module platyPS -ListAvailable)) {
        Write-Warning "platyPS module is not installed. Skipping [$($task.name)] task."
        $result = $false
    }
    $result
}

# Synopsis: Generates PlatyPS markdown files from module help
Task GenerateMarkdown -if (. $genMarkdownPreReqs) StageFiles, {
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
}

$genHelpFilesPreReqs = {
    $result = $true
    if (-not (Get-Module platyPS -ListAvailable)) {
        Write-Warning "platyPS module is not installed. Skipping [$($task.name)] task."
        $result = $false
    }
    $result
}

# Synopsis: Generates MAML-based help from PlatyPS markdown files
Task GenerateMAML -if (. $genHelpFilesPreReqs) GenerateMarkdown, {
    Build-PSBuildMAMLHelp -Path $PSBPreference.Docs.RootDir -DestinationPath $PSBPreference.Build.ModuleOutDir
}

$genUpdatableHelpPreReqs = {
    $result = $true
    if (-not (Get-Module platyPS -ListAvailable)) {
        Write-Warning "platyPS module is not installed. Skipping [$($task.name)] task."
        $result = $false
    }
    $result
}

# Synopsis: Create updatable help .cab file based on PlatyPS markdown help
Task GenerateUpdatableHelp -if (. $genUpdatableHelpPreReqs) BuildHelp, {
    Build-PSBuildUpdatableHelp -DocsPath $PSBPreference.Docs.RootDir -OutputPath $PSBPreference.Help.UpdatableHelpOutDir
}

# Synopsis: Publish module to the defined PowerShell repository
Task Publish Test, {
    Assert ($PSBPreference.Publish.PSRepositoryApiKey -or $PSBPreference.Publish.PSRepositoryCredential) "API key or credential not defined to authenticate with [$($PSBPreference.Publish.PSRepository)] with."

    $publishParams = @{
        Path       = $PSBPreference.Build.ModuleOutDir
        Version    = $PSBPreference.General.ModuleVersion
        Repository = $PSBPreference.Publish.PSRepository
        Verbose    = $true #$VerbosePreference
    }
    if ($PSBPreference.Publish.PSRepositoryApiKey) {
        $publishParams.ApiKey = $PSBPreference.Publish.PSRepositoryApiKey
    }

    if ($PSBPreference.Publish.PSRepositoryCredential) {
        $publishParams.Credential = $PSBPreference.Publish.PSRepositoryCredential
    }

    Publish-PSBuildModule @publishParams
}


#region Summary Tasks

# Synopsis: Builds help documentation
Task BuildHelp GenerateMarkdown, GenerateMAML

Task Build {
    if ([String]$PSBPreference.Build.Dependencies -ne [String]$__DefaultBuildDependencies) {
        throw [NotSupportedException]'You cannot use $PSBPreference.Build.Dependencies with Invoke-Build. Please instead redefine the build task or your default task to include your dependencies. Example: Task . Dependency1,Dependency2,Build,Test or Task Build Dependency1,Dependency2,StageFiles'
    }
}, StageFiles, BuildHelp

# Synopsis: Execute Pester and ScriptAnalyzer tests
Task Test Analyze, Pester

Task . Build, Test

# Synopsis: Signs module files (*.psd1, *.psm1, *.ps1) with an Authenticode signature
Task SignModule -If {
    if (-not $PSBPreference.Sign.Enabled) {
        Write-Warning 'Module signing is not enabled.'
        return $false
    }
    if (-not (Get-Command -Name 'Set-AuthenticodeSignature' -ErrorAction Ignore)) {
        Write-Warning 'Set-AuthenticodeSignature is not available. Module signing requires Windows.'
        return $false
    }
    $true
} Build, {
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

    if ($null -eq $certificate) {
        throw $LocalizedData.NoCertificateFound
    }

    $signingParams = @{
        Path            = $PSBPreference.Build.ModuleOutDir
        Certificate     = $certificate
        TimestampServer = $PSBPreference.Sign.TimestampServer
        HashAlgorithm   = $PSBPreference.Sign.HashAlgorithm
        Include         = $PSBPreference.Sign.FilesToSign
    }
    Invoke-PSBuildModuleSigning @signingParams
}

# Synopsis: Creates a Windows catalog (.cat) file for the built module
Task BuildCatalog -If {
    if (-not ($PSBPreference.Sign.Enabled -and $PSBPreference.Sign.Catalog.Enabled)) {
        Write-Warning 'Catalog generation is not enabled.'
        return $false
    }
    if (-not (Get-Command -Name 'New-FileCatalog' -ErrorAction Ignore)) {
        Write-Warning 'New-FileCatalog is not available. Catalog generation requires Windows.'
        return $false
    }
    $true
} SignModule, {
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
}

# Synopsis: Signs the module catalog (.cat) file with an Authenticode signature
Task SignCatalog -If {
    if (-not ($PSBPreference.Sign.Enabled -and $PSBPreference.Sign.Catalog.Enabled)) {
        Write-Warning 'Catalog signing is not enabled.'
        return $false
    }
    if (-not (Get-Command -Name 'Set-AuthenticodeSignature' -ErrorAction Ignore)) {
        Write-Warning 'Set-AuthenticodeSignature is not available. Catalog signing requires Windows.'
        return $false
    }
    $true
} BuildCatalog, {
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

    if ($null -eq $certificate) {
        throw $LocalizedData.NoCertificateFound
    }

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
}

# Synopsis: Signs module files and catalog (meta task)
Task Sign SignModule, SignCatalog

#endregion Summary Tasks
