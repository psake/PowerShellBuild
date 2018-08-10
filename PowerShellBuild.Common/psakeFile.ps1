properties {
    # Load in build settings
    . (Join-Path -Path $PSScriptRoot -ChildPath psakeProperties.ps1)

    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
    $moduleOutDir = "$outDir/$moduleName/$moduleVersion"

    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
    $scriptAnalysisEnabled = $true

}

FormatTaskName {
    param($taskName)
    Write-Host 'Task: ' -ForegroundColor Cyan -NoNewline
    Write-Host $taskName.ToUpper() -ForegroundColor Blue
}

# This psake file is meant to be referenced from another
# Can't have two 'default' tasks
# Task default -depends Test

Task Init {
    Initialize-PSBuild -UseBuildHelpers:$useBuildHelpers
}

Task Clean -depends Init -requiredVariables moduleOutDir {
    Clear-PSBuildOutputFolder -Path $moduleOutDir
}

Task StageFiles -depends Clean -requiredVariables moduleOutDir, srcRootDir {
    Build-PSBuildModule -Path $srcRootDir -DestinationPath $moduleOutDir -Exclude $Exclude
}

Task Build -depends Init, Clean, StageFiles {

    # Copy source files to output


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
Task Analyze -depends Build -requiredVariables $reqVars -precondition $analyzePreReqs {
    $analyzeParams = @{
        Path              = $moduleOutDir
        SeverityThreshold = $scriptAnalysisFailBuildOnSeverityLevel
        SettingsPath      = $scriptAnalyzerSettingsPath
    }
    Test-PSBuildScriptAnalysis @analyzeParams
} -description 'Execute PSScriptAnalyzer tests'

$pesterReqVars = @(
    'testRootDir', 'moduleName', 'testOutputFormat', 'codeCoverageEnabled', 'codeCoverageFiles'
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
Task Pester -depends Build -requiredVariables $pesterReqVars -precondition $pesterPreReqs {
    $pesterParams = @{
        Path              = $testRootDir
        ModuleName        = $moduleName
        OutputPath        = $testOutputFile
        OutputFormat      = $testOutputFormat
        CodeCoverage      = $codeCoverageEnabled
        CodeCoverageFiles = $codeCoverageFiles
    }
    Test-PSBuildPester @pesterParams
} -description 'Execute Pester tests'

task Test -depends Pester, Analyze {
} -description 'Execute Pester and ScriptAnalyzer tests'

Task ? -description 'Lists the available tasks' {
    'Available tasks:'
    $psake.context.Peek().Tasks.Keys | Sort-Object
}