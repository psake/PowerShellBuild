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

Describe 'Settings referenced by the task files' {

    # The task files read settings by path out of $PSBPreference, and a path that does not
    # exist evaluates to $null rather than failing. Splatted onto a [string] parameter that
    # becomes an empty string -- not the parameter's default -- so a misspelled setting is
    # silently ignored and the documented option does nothing.
    #
    # That is psake/PowerShellBuild#178: IB.tasks.ps1 read Test.CodeCoverage.OutputFormat
    # while build.properties.ps1 defines OutputFileFormat, so Invoke-Build consumers had no
    # working code coverage format. The comparison only ran between the two task files by
    # task NAME, which cannot see a divergence inside a task body.

    BeforeAll {
        $script:moduleSourcePath = [IO.Path]::Combine(
            (Split-Path -Path $PSScriptRoot -Parent), 'PowerShellBuild'
        )
        $script:defaultPreference = . ([IO.Path]::Combine($script:moduleSourcePath, 'build.properties.ps1'))

        function script:Test-PreferencePath {
            param($Root, [string[]]$Segment)
            $node = $Root
            foreach ($name in $Segment) {
                if ($node -is [System.Collections.IDictionary] -and $node.Contains($name)) {
                    $node = $node[$name]
                } else {
                    return $false
                }
            }
            $true
        }

        # Two references are expected not to resolve, both deliberately:
        #   Build.Keys           - the hashtable's own Keys property, used to enumerate it
        #   Build.Dependencies   - removed from the defaults on purpose; IB.tasks.ps1 reads it
        #                          only to detect a consumer who set it, and throws a
        #                          NotSupportedException explaining what to do instead
        $script:allowedUnresolvable = @('Build.Keys', 'Build.Dependencies')
    }

    It 'every setting <_> reads resolves against build.properties.ps1' -ForEach @(
        'IB.tasks.ps1'
        'psakeFile.ps1'
    ) {
        $taskFileContent = Get-Content -Path ([IO.Path]::Combine($script:moduleSourcePath, $_)) -Raw
        $referencedPath = [regex]::Matches(
            $taskFileContent, '\$PSBPreference((?:\.[A-Za-z_][A-Za-z0-9_]*)+)'
        ).ForEach({ $_.Groups[1].Value.TrimStart('.') }) | Sort-Object -Unique

        $referencedPath | Should -Not -BeNullOrEmpty -Because 'the regex must still match something'

        $unresolvable = $referencedPath.Where({
                $_ -notin $script:allowedUnresolvable -and
                -not (Test-PreferencePath -Root $script:defaultPreference -Segment ($_ -split '\.'))
            })

        $unresolvable -join ', ' | Should -BeNullOrEmpty
    }
}
