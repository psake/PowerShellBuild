#requires -module InvokeBuild,Psake

Describe 'Invoke-Build Tasks' {
    BeforeAll {
        $manifest           = Import-PowerShellDataFile -Path $env:BHPSModuleManifest
        $outputDir          = [IO.Path]::Combine($ENV:BHProjectPath, 'Output')
        $outputModDir       = [IO.Path]::Combine($outputDir, $env:BHProjectName)
        $outputModVerDir    = [IO.Path]::Combine($outputModDir, $manifest.ModuleVersion)
        $ibTasksFilePath    = [IO.Path]::Combine($outputModVerDir, 'IB.tasks.ps1')
        $psakeFilePath      = [IO.Path]::Combine($outputModVerDir, 'psakeFile.ps1')
    }

    $IBTasksResult = $null
    It 'IB.tasks.ps1 exists' {
        Test-Path $IBTasksFilePath | Should -Be $true
    }

    It 'Parseable by invoke-build' {
        # Run IB in job to not pollute the environment
        # Invoke-Build whatif still outputs in Appveyor in Pester even when directed to out-null. This doesn't happen locally. Redirecting all output to null
        $IBTasksResult = Start-Job -ScriptBlock {
            Invoke-Build -File $using:IBTasksFilePath -Whatif -Result IBTasksResult -ErrorAction Stop *>$null
            $IBTasksResult
        } | Wait-Job | Receive-Job

        $IBTasksResult | Should -Not -BeNullOrEmpty
    }
    It 'Contains all the tasks that were in the Psake file' {
        # Run psake in job to not pollute the environment
        $psakeTaskNames = Start-Job -ScriptBlock {
            Invoke-PSake -docs -buildfile $using:psakeFilePath | Where-Object name -notmatch '^(default|\?)$' | ForEach-Object name
        } | Wait-Job | Receive-Job

        $IBTaskNames = $IBTasksResult.all.name
        foreach ($taskItem in $psakeTaskNames) {
            if ($taskitem -notin $IBTaskNames) {
                throw "Task $taskitem was not successfully converted by Convert-PSAke"
            }
        }
        $Psaketasknames | Should -Not -BeNullOrEmpty
    }
}
