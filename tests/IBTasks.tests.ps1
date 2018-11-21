#requires -module InvokeBuild,Psake
$manifest           = Import-PowerShellDataFile -Path $env:BHPSModuleManifest
$outputDir          = Join-Path -Path $ENV:BHProjectPath -ChildPath 'Output'
$outputModDir       = Join-Path -Path $outputDir -ChildPath $env:BHProjectName
$outputModVerDir    = Join-Path -Path $outputModDir -ChildPath $manifest.ModuleVersion
$ibTasksFilePath    = Join-Path -Path $outputModVerDir -ChildPath 'IB.tasks.ps1'
$psakeFilePath       = Join-Path -Path $outputModVerDir -ChildPath 'psakeFile.ps1'

Describe 'Invoke-Build Conversion' {
    $IBTasksResult = $null
    It 'IB.tasks.ps1 exists' {
        Test-Path $ibTasksFilePath | Should Be $true
    }
    It 'Parseable by invoke-build' {
        #Invoke-Build whatif still outputs in Appveyor in Pester even when directed to out-null. this doesn't happen locally. Using a job as a workaround.
        $IBTasksResult = Start-Job -ScriptBlock {
            Invoke-Build -file $USING:ibtasksFilePath -whatif -result IBTasksResult | Out-Null
            $IBTasksResult
        } | wait-job | receive-job
        $IBTasksResult | Should Not BeNullOrEmpty
    }
    It 'Contains all the tasks that were in the Psake file' {
        #Invoke-PSake Fails in Pester Scope, have to run it in a completely separate runspace
        $psakeTaskNames = Start-Job -ScriptBlock {
            Invoke-PSake -docs -buildfile $USING:psakeFilePath | where name -notmatch '^(default|\?)$' | % name
        } | wait-job | receive-job

        $IBTaskNames = $IBTasksResult.all.name
        foreach ($taskItem in $psakeTaskNames) {
            if ($taskitem -notin $IBTaskNames) {
                throw "Task $taskitem was not successfully converted by Convert-PSAke"
            }
        }
        $Psaketasknames | should Not BeNullOrEmpty
    }
}
