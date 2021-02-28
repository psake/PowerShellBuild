
# Load in build settings
Remove-Variable -Name PSBPreference -Scope Script -Force -ErrorAction Ignore
Set-Variable -Name PSBPreference -Option ReadOnly -Scope Script -Value (. ([IO.Path]::Combine($PSScriptRoot, 'build.properties.ps1')))

properties {}

FormatTaskName {
    param($taskName)
    Write-Host 'Task: ' -ForegroundColor Cyan -NoNewline
    Write-Host $taskName.ToUpper() -ForegroundColor Blue
}

# This psake file is meant to be referenced from another
# Can't have two 'default' tasks
# Task default -depends Test

task Init {
    Initialize-PSBuild -UseBuildHelpers -BuildEnvironment $PSBPreference
} -description 'Initialize build environment variables'

task Clean -depends Init {
    Clear-PSBuildOutputFolder -Path $PSBPreference.Build.ModuleOutDir
} -description 'Clears module output directory'

task StageFiles -depends Clean {
    $buildParams = @{
        Path                = $PSBPreference.General.SrcRootDir
        ModuleName          = $PSBPreference.General.ModuleName
        DestinationPath     = $PSBPreference.Build.ModuleOutDir
        Exclude             = $PSBPreference.Build.Exclude
        Compile             = $PSBPreference.Build.CompileModule
        CompileDirectories  = $PSBPreference.Build.CompileDirectories
        CopyDirectories     = $PSBPreference.Build.CopyDirectories
        Culture             = $PSBPreference.Help.DefaultLocale
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
} -description 'Builds module based on source directory'

task Build -depends $PSBPreference.Build.Dependencies -description 'Builds module and generate help documentation'

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
task Analyze -depends Build -precondition $analyzePreReqs {
    $analyzeParams = @{
        Path              = $PSBPreference.Build.ModuleOutDir
        SeverityThreshold = $PSBPreference.Test.ScriptAnalysis.FailBuildOnSeverityLevel
        SettingsPath      = $PSBPreference.Test.ScriptAnalysis.SettingsPath
    }
    Test-PSBuildScriptAnalysis @analyzeParams
} -description 'Execute PSScriptAnalyzer tests'

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
task Pester -depends Build -precondition $pesterPreReqs {
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
    }
    Test-PSBuildPester @pesterParams
} -description 'Execute Pester tests'

task Test -depends Pester, Analyze {
} -description 'Execute Pester and ScriptAnalyzer tests'

task BuildHelp -depends GenerateMarkdown, GenerateMAML {} -description 'Builds help documentation'

$genMarkdownPreReqs = {
    $result = $true
    if (-not (Get-Module platyPS -ListAvailable)) {
        Write-Warning "platyPS module is not installed. Skipping [$($psake.context.currentTaskName)] task."
        $result = $false
    }
    $result
}
task GenerateMarkdown -depends StageFiles -precondition $genMarkdownPreReqs {
    $buildMDParams = @{
        ModulePath = $PSBPreference.Build.ModuleOutDir
        ModuleName = $PSBPreference.General.ModuleName
        DocsPath   = $PSBPreference.Docs.RootDir
        Locale     = $PSBPreference.Help.DefaultLocale
    }
    Build-PSBuildMarkdown @buildMDParams
} -description 'Generates PlatyPS markdown files from module help'

$genHelpFilesPreReqs = {
    $result = $true
    if (-not (Get-Module platyPS -ListAvailable)) {
        Write-Warning "platyPS module is not installed. Skipping [$($psake.context.currentTaskName)] task."
        $result = $false
    }
    $result
}
task GenerateMAML -depends GenerateMarkdown -precondition $genHelpFilesPreReqs {
    Build-PSBuildMAMLHelp -Path $PSBPreference.Docs.RootDir -DestinationPath $PSBPreference.Build.ModuleOutDir
} -description 'Generates MAML-based help from PlatyPS markdown files'

$genUpdatableHelpPreReqs = {
    $result = $true
    if (-not (Get-Module platyPS -ListAvailable)) {
        Write-Warning "platyPS module is not installed. Skipping [$($psake.context.currentTaskName)] task."
        $result = $false
    }
    $result
}
task GenerateUpdatableHelp -depends BuildHelp -precondition $genUpdatableHelpPreReqs {
    Build-PSBuildUpdatableHelp -DocsPath $PSBPreference.Docs.RootDir -OutputPath $PSBPreference.Help.UpdatableHelpOutDir
} -description 'Create updatable help .cab file based on PlatyPS markdown help'

task Publish -depends Test {
    Assert -conditionToCheck ($PSBPreference.Publish.PSRepositoryApiKey -or $PSBPreference.Publish.PSRepositoryCredential) -failureMessage "API key or credential not defined to authenticate with [$($PSBPreference.Publish.PSRepository)] with."

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
} -description 'Publish module to the defined PowerShell repository'

task ? -description 'Lists the available tasks' {
    'Available tasks:'
    $psake.context.Peek().Tasks.Keys | Sort-Object
}
