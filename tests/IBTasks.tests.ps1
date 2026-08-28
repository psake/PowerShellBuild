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

    # The oldest of this file's drift guards: a task added to psakeFile.ps1 and forgotten in
    # IB.tasks.ps1 reaches Invoke-Build consumers only, and neither the settings comparison nor
    # the signing comparison below can see a task that exists in one file and not the other.
    #
    # Both task runners are asked for their task names in a background job, because loading
    # either task file sets $PSBPreference read-only and calls Set-BuildEnvironment -Force,
    # neither of which belongs in the Pester session. Only serialized objects cross a job
    # boundary, so each job projects the names to strings before returning them -- see
    # psake/PowerShellBuild#215 for what came back when they did not.

    BeforeAll {
        $manifest                = Import-PowerShellDataFile -Path $env:BHPSModuleManifest
        $outputPath              = [IO.Path]::Combine($env:BHProjectPath, 'Output')
        $outputModulePath        = [IO.Path]::Combine($outputPath, $env:BHProjectName)
        $outputModuleVersionPath = [IO.Path]::Combine($outputModulePath, $manifest.ModuleVersion)
        $ibTasksFilePath         = [IO.Path]::Combine($outputModuleVersionPath, 'IB.tasks.ps1')
        $psakeFilePath           = [IO.Path]::Combine($outputModuleVersionPath, 'psakeFile.ps1')

        # Assigned here rather than in the 'Parseable by invoke-build' block below: each It runs
        # in its own scope, so a variable one It assigns is not there for the next one to read.
        $script:invokeBuildTaskName = Start-Job -ScriptBlock {
            # Invoke-Build -WhatIf still writes the task list under a CI host even when the
            # output is piped to Out-Null, so every stream is redirected away.
            Invoke-Build -File $using:ibTasksFilePath -WhatIf -Result invokeBuildResult -ErrorAction Stop *>$null

            # .All is an ordered dictionary keyed by task name, so $invokeBuildResult.All.Name
            # is a lookup for a key called 'Name' -- which no task file defines -- rather than
            # an enumeration of the task names. The keys are the task names.
            $invokeBuildResult.All.Keys | ForEach-Object { [string]$_ }
        } | Wait-Job | Receive-Job

        $script:psakeTaskName = Start-Job -ScriptBlock {
            # Get-PSakeScriptTasks returns task objects. Invoke-PSake -docs formats a table to
            # the output stream instead, so what crossed the job boundary was format records
            # with no Name property, and every name was $null.
            Get-PSakeScriptTasks -buildFile $using:psakeFilePath | ForEach-Object { [string]$_.Name }
        } | Wait-Job | Receive-Job
    }

    It 'IB.tasks.ps1 exists' {
        Test-Path $ibTasksFilePath | Should -Be $true
    }

    It 'Parseable by invoke-build' {
        $script:invokeBuildTaskName | Should -Not -BeNullOrEmpty -Because 'Invoke-Build must be able to load IB.tasks.ps1 and report its tasks'
    }

    It 'Contains all the tasks that were in the Psake file' {
        # 'default' and '?' are psake's own entry points rather than tasks converted from the
        # psake file; Invoke-Build spells its equivalent '.', and it is not compared either.
        $comparableTaskName = $script:psakeTaskName.Where({ $_ -notmatch '^(default|\?)$' })

        $comparableTaskName | Should -Not -BeNullOrEmpty -Because 'psake must still report the tasks psakeFile.ps1 defines'

        $missingFromInvokeBuild = $comparableTaskName.Where({ $_ -notin $script:invokeBuildTaskName })

        $missingFromInvokeBuild -join ', ' | Should -BeNullOrEmpty -Because 'IB.tasks.ps1 must define every task psakeFile.ps1 defines'
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

Describe 'Signing settings referenced by the task files' {

    # Both task files build a certificate parameter hashtable and splat it onto
    # Get-PSBuildCertificate, and until psake/PowerShellBuild#193 nothing compared the two
    # bodies. IB.tasks.ps1 never passed SkipValidation, so
    # $PSBPreference.Sign.SkipCertificateValidation was dead for every Invoke-Build consumer
    # while it worked for psake consumers. The task-name comparison above cannot see that,
    # because both files define the same tasks.
    #
    # The comparison is scoped to the $PSBPreference.Sign settings rather than every
    # $PSBPreference setting because the two files legitimately differ elsewhere: only
    # IB.tasks.ps1 reads Build.Dependencies, and only psakeFile.ps1 uses the
    # $PSB{TaskName}Dependency variables.

    BeforeAll {
        $script:moduleSourcePath = [IO.Path]::Combine(
            (Split-Path -Path $PSScriptRoot -Parent), 'PowerShellBuild'
        )

        function script:Get-SignSettingName {
            param([string]$FileName)

            $taskFileContent = Get-Content -Path (
                [IO.Path]::Combine($script:moduleSourcePath, $FileName)
            ) -Raw

            [regex]::Matches(
                $taskFileContent, '\$PSBPreference\.Sign((?:\.[A-Za-z_][A-Za-z0-9_]*)+)'
            ).ForEach({ $_.Groups[1].Value.TrimStart('.') }) | Sort-Object -Unique
        }
    }

    It 'reads the same $PSBPreference.Sign settings in both task files' {
        $psakeSetting = Get-SignSettingName -FileName 'psakeFile.ps1'
        $invokeBuildSetting = Get-SignSettingName -FileName 'IB.tasks.ps1'

        $psakeSetting | Should -Not -BeNullOrEmpty -Because 'the regex must still match something'

        $missingFromInvokeBuild = $psakeSetting.Where({ $_ -notin $invokeBuildSetting })
        $missingFromPsake = $invokeBuildSetting.Where({ $_ -notin $psakeSetting })

        $missingFromInvokeBuild -join ', ' | Should -BeNullOrEmpty -Because 'IB.tasks.ps1 must honour every signing setting psakeFile.ps1 honours'
        $missingFromPsake -join ', ' | Should -BeNullOrEmpty -Because 'psakeFile.ps1 must honour every signing setting IB.tasks.ps1 honours'
    }
}
