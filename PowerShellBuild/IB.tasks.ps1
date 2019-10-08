Remove-Variable -Name PSBPreference -Scope Script -Force -ErrorAction Ignore
Set-Variable -Name PSBPreference -Option ReadOnly -Scope Script -Value (. (Join-Path -Path $PSScriptRoot -ChildPath build.properties.ps1))

# Synopsis: Initialize build environment variables
task Init {
    Initialize-PSBuild -UseBuildHelpers -BuildEnvironment $PSBPreference
}

# Synopsis: Clears module output directory
task Clean Init, {
    Clear-PSBuildOutputFolder -Path $PSBPreference.Build.ModuleOutDir
}

# Synopsis: Builds module based on source directory
task StageFiles Clean, {
    $buildParams = @{
        Path               = $PSBPreference.General.SrcRootDir
        ModuleName         = $PSBPreference.General.ModuleName
        DestinationPath    = $PSBPreference.Build.ModuleOutDir
        Exclude            = $PSBPreference.Build.Exclude
        Compile            = $PSBPreference.Build.CompileModule
        Culture            = $PSBPreference.Help.DefaultLocale
    }

    if ($PSBPreference.Help.ConvertReadMeToAboutHelp) {
        $readMePath = Get-ChildItem -Path $PSBPreference.General.ProjectRoot -Include 'readme.md', 'readme.markdown', 'readme.txt' -Depth 1 |
            Select-Object -First 1
        if ($readMePath) {
            $buildParams.ReadMePath = $readMePath
        }
    }

    'CompileHeader', 'CompileFooter', 'CompileScriptHeader', 'CompileScriptFooter' | ForEach-Object {
        if ($PSBPreference.Build.Keys -contains $_) {
            $buildParams.$_ = $PSBPreference.Build.$_
        }
    }

    Build-PSBuildModule @buildParams
}

# Synopsis: Builds module and generate help documentation
Task Build $($PSBPreference.Build.Dependencies -join ", ")

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
task Analyze Build, {
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
task Pester Build -If $pesterPreReqs, {
    $pesterParams = @{
        Path                  = $PSBPreference.Test.RootDir
        ModuleName            = $PSBPreference.General.ModuleName
        OutputPath            = $PSBPreference.Test.OutputFile
        OutputFormat          = $PSBPreference.Test.OutputFormat
        CodeCoverage          = $PSBPreference.Test.CodeCoverage.Enabled
        CodeCoverageThreshold = $PSBPreference.Test.CodeCoverage.Threshold
        CodeCoverageFiles     = $PSBPreference.Test.CodeCoverage.Files
    }
    Test-PSBuildPester @pesterParams
}

# Synopsis: Execute Pester and ScriptAnalyzer tests
task Test Pester, Analyze, {
}

# Synopsis: Builds help documentation
task BuildHelp GenerateMarkdown, GenerateMAML, {}

$genMarkdownPreReqs = {
    $result = $true
    if (-not (Get-Module platyPS -ListAvailable)) {
        Write-Warning "platyPS module is not installed. Skipping [$($task.name)] task."
        $result = $false
    }
    $result
}

# Synopsis: Generates PlatyPS markdown files from module help
task GenerateMarkdown StageFiles, {
    $buildMDParams = @{
        ModulePath = $PSBPreference.Build.ModuleOutDir
        ModuleName = $PSBPreference.General.ModuleName
        DocsPath   = $PSBPreference.Docs.RootDir
        Locale     = $PSBPreference.Help.DefaultLocale
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
task GenerateMAML GenerateMarkdown, {
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
task GenerateUpdatableHelp BuildHelp, {
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
