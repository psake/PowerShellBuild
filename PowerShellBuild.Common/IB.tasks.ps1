
# Load in build settings
 . (Join-Path -Path $PSScriptRoot -ChildPath build.properties.ps1)
$useBuildHelpers       = $true
$scriptAnalysisEnabled = $true

# Synopsis: Initialize Invoke-Build
task init {
    Initialize-PSBuild -UseBuildHelpers:$useBuildHelpers
}

# Synopsis: Clean output directory
task Clean init, {
    Clear-PSBuildOutputFolder -Path $moduleOutDir
}

# Synopsis: Build module
task StageFiles Clean, {
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

# Synopsis: Build module
task Build StageFiles

# Synopsis: Execute PSScriptAnalyzer tests
task Analyze Build -if $scriptAnalysisEnabled, {
    $analyzeParams = @{
        Path              = $moduleOutDir
        SeverityThreshold = $scriptAnalysisFailBuildOnSeverityLevel
        SettingsPath      = $scriptAnalyzerSettingsPath
    }
    Test-PSBuildScriptAnalysis @analyzeParams
}

# Synopsis: Execute Pester tests
task Pester Build, {
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
}

# Synopsis: Execute Pester and ScriptAnalyzer tests
task Test Pester, Analyze

# Synopsis: Build the module, including help
task BuildHelp Build, GenerateMarkdown, GenerateMAML

# Synopsis: Generate markdown help documentation using PlatyPS
task GenerateMarkdown Build, {
    Build-PSBuildMarkdown -ModulePath $moduleOutDir -ModuleName $moduleName -DocsPath $docsRootDir -Locale $defaultLocale
}

# Synopsis: Generate module MAML help from markdown source
task GenerateMAML GenerateMarkdown, {
    Build-PSBuildMAMLHelp -Path $docsRootDir -DestinationPath $moduleOutDir
}

task . Build
