#requires -module InvokeBuild,Psake

# Shared by both of the drift guards below, so each stays runnable on its own filter.
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
}

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

Describe 'Settings documented in the README' {

    # The README settings table is what consumers actually read, and until now nothing tied it
    # back to the defaults. $PSBPreference.Docs.AlphabeticParamsOrder survived its removal in
    # psake/PowerShellBuild#105 there, and $PSBPreference.Build.Dependencies survived being
    # replaced by the $PSB{TaskName}Dependency variables in #72, back in 0.7.0.
    #
    # Both directions are asserted. The reverse one -- every defined setting is documented --
    # only became assertable once the sixteen $PSBPreference.Sign settings were added to the
    # table; the whole Sign section had shipped in 0.8.0 with no entry in the README at all.

    BeforeAll {
        # Documented settings that are deliberately absent from the defaults. Both task files
        # forward these to Build-PSBuildModule only when the consumer has added the key, so
        # defining them in build.properties.ps1 would inject empty strings into every
        # compiled PSM1 instead of leaving the parameter defaults alone.
        $script:documentedWithoutDefault = @(
            'Build.CompileHeader'
            'Build.CompileFooter'
            'Build.CompileScriptHeader'
            'Build.CompileScriptFooter'
        )

        # There is no matching allow-list for the reverse direction: every leaf of the defaults
        # is currently in the table. Build.ModuleOutDir is the one setting consumers must not
        # set, and it is documented anyway, with a description saying so -- which is the pattern
        # to follow for anything else that turns out to be internal. Silencing a setting here
        # instead would hide it from the very readers the table exists for.

        function script:Get-PreferenceLeafPath {
            # Walks the defaults and returns the dotted path of every leaf value. A nested
            # hashtable (Test.ScriptAnalysis, Test.CodeCoverage, Sign.Catalog) is a container
            # rather than a setting, so only the leaves beneath it are returned -- that is what
            # the README table documents, one row per settable value.
            param($Node, [string]$Prefix)

            foreach ($name in $Node.Keys) {
                $path = if ($Prefix) { "$Prefix.$name" } else { $name }
                if ($Node[$name] -is [System.Collections.IDictionary]) {
                    Get-PreferenceLeafPath -Node $Node[$name] -Prefix $path
                } else {
                    $path
                }
            }
        }

        $readMePath = [IO.Path]::Combine((Split-Path -Path $PSScriptRoot -Parent), 'README.md')
        $script:documentedPath = [regex]::Matches(
            (Get-Content -Path $readMePath -Raw),
            '(?m)^\|\s*\$PSBPreference((?:\.[A-Za-z_][A-Za-z0-9_]*)+)'
        ).ForEach({ $_.Groups[1].Value.TrimStart('.') }) | Sort-Object -Unique
    }

    It 'every setting the README table lists resolves against build.properties.ps1' {
        $script:documentedPath | Should -Not -BeNullOrEmpty -Because 'the regex must still match the table'

        $undefined = $script:documentedPath.Where({
                $_ -notin $script:documentedWithoutDefault -and
                -not (Test-PreferencePath -Root $script:defaultPreference -Segment ($_ -split '\.'))
            })

        $undefined -join ', ' | Should -BeNullOrEmpty
    }

    It 'every setting build.properties.ps1 defines is listed in the README table' {
        $definedPath = Get-PreferenceLeafPath -Node $script:defaultPreference | Sort-Object -Unique

        $definedPath | Should -Not -BeNullOrEmpty -Because 'the defaults must still be walkable'

        $undocumented = $definedPath.Where({ $_ -notin $script:documentedPath })

        $undocumented -join ', ' | Should -BeNullOrEmpty
    }
}
