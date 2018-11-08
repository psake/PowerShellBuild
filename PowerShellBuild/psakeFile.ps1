properties {
    # Load in build settings
    . (Join-Path -Path $PSScriptRoot -ChildPath build.properties.ps1)

    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
    $scriptAnalysisEnabled = $true

    $CompileModule = $true

    $convertReadMeToAboutHelp = $true
}

FormatTaskName {
    param($taskName)
    Write-Host 'Task: ' -ForegroundColor Cyan -NoNewline
    Write-Host $taskName.ToUpper() -ForegroundColor Blue
}

# This psake file is meant to be referenced from another
# Can't have two 'default' tasks
# Task default -depends Test

task Init {
    Initialize-PSBuild -UseBuildHelpers
}

task Clean -depends Init -requiredVariables moduleOutDir {
    Clear-PSBuildOutputFolder -Path $moduleOutDir
}

task StageFiles -depends Clean -requiredVariables moduleOutDir, srcRootDir {
    $buildParams = @{
        Path               = $srcRootDir
        DestinationPath    = $moduleOutDir
        ModuleName         = $moduleName
        ModuleManifestPath = $moduleManifestPath
        Exclude            = $Exclude
        Compile            = $compileModule
        Culture            = $defaultLocale
    }

    if ($convertReadMeToAboutHelp) {
        $readMePath = Get-ChildItem -Path $projectRoot -Include 'readme.md', 'readme.markdown', 'readme.txt' -Depth 1 |
            Select-Object -First 1
        if ($readMePath) {
            $buildParams.ReadMePath = $readMePath
        }
    }
    Build-PSBuildModule @buildParams
}

task Build -depends Init, Clean, StageFiles {
}

$reqVars = @(
    'moduleOutDir', 'scriptAnalysisEnabled', 'scriptAnalysisFailBuildOnSeverityLevel', 'scriptAnalyzerSettingsPath'
)
$analyzePreReqs = {
    $result = $true
    if (-not $scriptAnalysisEnabled) {
        Write-Warning 'Script analysis is not enabled.'
        $result = $false
    }
    if (-not (Get-Module -Name PSScriptAnalyzer -ListAvailable)) {
        Write-Warning 'PSScriptAnalyzer module is not installed'
        $result = $false
    }
    $result
}
task Analyze -depends Build -requiredVariables $reqVars -precondition $analyzePreReqs {
    $analyzeParams = @{
        Path              = $moduleOutDir
        SeverityThreshold = $scriptAnalysisFailBuildOnSeverityLevel
        SettingsPath      = $scriptAnalyzerSettingsPath
    }
    Test-PSBuildScriptAnalysis @analyzeParams
} -description 'Execute PSScriptAnalyzer tests'

$pesterReqVars = @(
    'testRootDir', 'moduleName', 'testOutputFormat', 'codeCoverageEnabled', 'codeCoverageThreshold', 'codeCoverageFiles'
)
$pesterPreReqs = {
    $result = $true
    if (-not $testingEnabled) {
        Write-Warning 'Pester testing is not enabled.'
        $result = $false
    }
    if (-not (Get-Module -Name Pester -ListAvailable)) {
        Write-Warning 'Pester module is not installed'
        $result = $false
    }
    if (-not (Test-Path -Path $testRootDir)) {
        Write-Warning "Test directory [$testRootDir] not found"
        $result = $false
    }
    return $result
}
task Pester -depends Build -requiredVariables $pesterReqVars -precondition $pesterPreReqs {
    $pesterParams = @{
        Path                  = $testRootDir
        ModuleName            = $moduleName
        OutputPath            = $testOutputFile
        OutputFormat          = $testOutputFormat
        CodeCoverage          = $codeCoverageEnabled
        CodeCoverageThreshold = $codeCoverageThreshold
        CodeCoverageFiles     = $codeCoverageFiles
    }
    Test-PSBuildPester @pesterParams
} -description 'Execute Pester tests'

task Test -depends Pester, Analyze {
} -description 'Execute Pester and ScriptAnalyzer tests'

task BuildHelp -depends Build, GenerateMarkdown, GenerateMAML {}

$genMarkdownVars = @(
    'docsRootDir', 'defaultLocale', 'moduleName', 'moduleOutDir')
$genMarkdownPreReqs = {
    $result = $true
    if (-not (Get-Module platyPS -ListAvailable)) {
        Write-Warning "platyPS module is not installed. Skipping [$($psake.context.currentTaskName)] task."
        $result = $false
    }
    $result
}
task GenerateMarkdown -depends Build -requiredVariables $genMarkdownVars -precondition $genMarkdownPreReqs {
    Build-PSBuildMarkdown -ModulePath $moduleOutDir -ModuleName $moduleName -DocsPath $docsRootDir -Locale $defaultLocale
}

$genHelpFilesPreReqs = {
    $result = $true
    if (-not (Get-Module platyPS -ListAvailable)) {
        Write-Warning "platyPS module is not installed. Skipping [$($psake.context.currentTaskName)] task."
        $result = $false
    }
    $result
}
task GenerateMAML -depends GenerateMarkdown -requiredVariables docsRootDir, moduleOutDir -precondition $genHelpFilesPreReqs {
    Build-PSBuildMAMLHelp -Path $docsRootDir -DestinationPath $moduleOutDir
}

$genUpdatableHelpVars = @(
    'docsRootDir', 'moduleName', 'updatableHelpOutDir'
)
$genUpdatableHelpPreReqs = {
    $result = $true
    if (-not (Get-Module platyPS -ListAvailable)) {
        Write-Warning "platyPS module is not installed. Skipping [$($psake.context.currentTaskName)] task."
        $result = $false
    }
    $result
}
task GenerateUpdatableHelp -depends BuildHelp -requiredVariables $genUpdatableHelpVars -precondition $genUpdatableHelpPreReqs {
    Build-PSBuildUpdatableHelp -DocsPath $docsRootDir -OutputPath $updatableHelpOutDir
}

task ? -description 'Lists the available tasks' {
    'Available tasks:'
    $psake.context.Peek().Tasks.Keys | Sort-Object
}
