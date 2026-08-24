# Baseline coverage for the three help-building functions (psake/PowerShellBuild#149).
#
# Build-PSBuildMarkdown, Build-PSBuildMAMLHelp, and Build-PSBuildUpdatableHelp have had no
# tests. The repository does not run its own docs tasks either -- the root psakeFile.ps1 goes
# Init -> Clean -> Build -> Analyze -> Pester -> Publish and never invokes GenerateMarkdown,
# GenerateMAML, or GenerateUpdatableHelp -- so nothing observes these functions today. That
# makes the PlatyPS 1.x migration (#105) a rewrite of three uncovered functions. This file is
# the red-before-green baseline they regress against, written against the CURRENT platyPS
# 0.14.2 behavior.
#
# Every invocation runs in a Start-Job subprocess. That is not incidental: platyPS 0.14.2 and
# Microsoft.PowerShell.PlatyPS 1.x each load their own YamlDotNet.dll through NestedModules,
# with different assembly identities, so whichever imports second fails with "Assembly with
# same name is already loaded". A separate runspace does not escape it; only a separate
# process does. Once the migration starts, the old and new implementations can only be
# exercised in the same test run through subprocesses.
#
# The fixture is copied into $TestDrive rather than built in place, so nothing under tests/
# is mutated and Pester handles cleanup.

BeforeDiscovery {
    # The psake PreConditions on the docs tasks gate on exactly this, so the tests behave the
    # same way the shipped tasks do: absent platyPS means skipped, not failed.
    $script:platyPSAvailable = [bool](Get-Module -Name 'platyPS' -ListAvailable)
}

Describe 'Help building functions' -Skip:(-not $script:platyPSAvailable) {

    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:builtModulePath = [IO.Path]::Combine($script:moduleRoot, 'Output', 'PowerShellBuild')

        Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'fixtures', 'FixtureHelpers.psm1')) -Force

        $script:fixtureName = 'PSBuildTestFixture'
        $script:locale = 'en-US'

        # Runs one PowerShellBuild command in a subprocess and reports what happened rather
        # than throwing, so a failure shows up as an assertion on ErrorMessage instead of an
        # opaque job error. The timeout matters: a hung job would otherwise stall CI with no
        # output, which is the failure mode psake/PowerShellBuild#167 produced.
        function script:Invoke-PSBuildCommandJob {
            param(
                [Parameter(Mandatory)]
                [string]$CommandName,

                [Parameter(Mandatory)]
                [hashtable]$Parameter,

                [int]$TimeoutSecond = 300
            )

            $job = Start-Job -ScriptBlock {
                param($builtModulePath, $commandName, $parameter)

                Import-Module -Name $builtModulePath -Force -ErrorAction Stop

                $threw = $false
                $errorMessage = $null
                $commandOutput = @()
                try {
                    $commandOutput = @(& $commandName @parameter -ErrorAction Stop)
                } catch {
                    $threw = $true
                    $errorMessage = $_.Exception.Message
                }

                [PSCustomObject]@{
                    Threw        = $threw
                    ErrorMessage = $errorMessage
                    Output       = $commandOutput
                }
            } -ArgumentList $script:builtModulePath, $CommandName, $Parameter

            $completed = $job | Wait-Job -Timeout $TimeoutSecond
            if (-not $completed) {
                $job | Stop-Job
                Remove-Job -Job $job -Force
                return [PSCustomObject]@{
                    Threw        = $true
                    ErrorMessage = "$CommandName did not complete within $TimeoutSecond seconds."
                    Output       = @()
                }
            }

            $jobResult = Receive-Job -Job $job
            Remove-Job -Job $job -Force
            $jobResult
        }

        # Builds an isolated project root holding a copy of the fixture module, and runs the
        # markdown step against it. Returns the paths the later steps consume.
        function script:New-DocsScenario {
            param(
                [Parameter(Mandatory)]
                [string]$Name
            )

            $projectRoot = Join-Path -Path $TestDrive -ChildPath $Name
            $modulePath = Copy-PSBuildTestFixture -Destination $projectRoot

            [PSCustomObject]@{
                ProjectRoot = $projectRoot
                ModulePath  = $modulePath
                DocsPath    = Join-Path -Path $projectRoot -ChildPath 'docs'
                LocalePath  = [IO.Path]::Combine($projectRoot, 'docs', $script:locale)
                OutputPath  = Join-Path -Path $projectRoot -ChildPath 'Output'
            }
        }

        function script:New-MarkdownParameter {
            param(
                [Parameter(Mandatory)]
                $Scenario,

                [bool]$Overwrite = $false
            )

            @{
                ModulePath            = $Scenario.ModulePath
                ModuleName            = $script:fixtureName
                DocsPath              = $Scenario.DocsPath
                Locale                = $script:locale
                Overwrite             = $Overwrite
                AlphabeticParamsOrder = $false
                ExcludeDontShow       = $false
                UseFullTypeName       = $false
            }
        }
    }

    AfterAll {
        Remove-Module -Name 'FixtureHelpers' -Force -ErrorAction SilentlyContinue
    }

    Context 'Build-PSBuildMarkdown' {

        BeforeAll {
            $script:markdownScenario = New-DocsScenario -Name 'markdown'
            $script:markdownResult = Invoke-PSBuildCommandJob -CommandName 'Build-PSBuildMarkdown' -Parameter (
                New-MarkdownParameter -Scenario $script:markdownScenario
            )
        }

        It 'completes without error' {
            $script:markdownResult.ErrorMessage | Should -BeNullOrEmpty
            $script:markdownResult.Threw | Should -BeFalse
        }

        It 'creates the locale directory under the docs path' {
            $script:markdownScenario.LocalePath | Should -Exist
        }

        It 'writes one markdown file per exported command' {
            foreach ($commandName in 'Get-Widget', 'Set-Widget') {
                Join-Path -Path $script:markdownScenario.LocalePath -ChildPath "$commandName.md" |
                    Should -Exist
            }
        }

        It 'writes a module landing page named for the module' -Skip {
            # Skipped: New-MarkdownHelp is called without -WithModulePage, so the landing page
            # is never produced. That is defect 1 of psake/PowerShellBuild#169 and the reason
            # Build-PSBuildUpdatableHelp cannot run at all. Unskip when #169 is fixed.
            Join-Path -Path $script:markdownScenario.LocalePath -ChildPath "$script:fixtureName.md" |
                Should -Exist
        }

        It 'does not document private functions' {
            Join-Path -Path $script:markdownScenario.LocalePath -ChildPath 'Test-WidgetName.md' |
                Should -Not -Exist
        }

        It 'produces markdown carrying the 0.14.x schema marker' {
            # The 0.14.x front matter carries "external help file" and "schema: 2.0.0". The 1.x
            # schema drops the latter, so this assertion is the tripwire that says the
            # migration in #150 actually changed the output format.
            $markdown = Get-Content -Path (
                Join-Path -Path $script:markdownScenario.LocalePath -ChildPath 'Get-Widget.md'
            ) -Raw
            $markdown | Should -Match 'schema:\s*2\.0\.0'
        }
    }

    Context 'Build-PSBuildMAMLHelp' {

        BeforeAll {
            $script:mamlScenario = New-DocsScenario -Name 'maml'
            $null = Invoke-PSBuildCommandJob -CommandName 'Build-PSBuildMarkdown' -Parameter (
                New-MarkdownParameter -Scenario $script:mamlScenario
            )
            $script:mamlResult = Invoke-PSBuildCommandJob -CommandName 'Build-PSBuildMAMLHelp' -Parameter @{
                Path            = $script:mamlScenario.DocsPath
                DestinationPath = $script:mamlScenario.OutputPath
            }
        }

        It 'completes without error' {
            $script:mamlResult.ErrorMessage | Should -BeNullOrEmpty
            $script:mamlResult.Threw | Should -BeFalse
        }

        It 'writes the MAML help file into a locale directory under the destination' {
            [IO.Path]::Combine($script:mamlScenario.OutputPath, $script:locale, "$script:fixtureName-help.xml") |
                Should -Exist
        }

        It 'produces MAML describing the exported commands' {
            $maml = Get-Content -Path (
                [IO.Path]::Combine($script:mamlScenario.OutputPath, $script:locale, "$script:fixtureName-help.xml")
            ) -Raw
            $maml | Should -Match 'Get-Widget'
            $maml | Should -Match 'Set-Widget'
        }
    }

    Context 'Build-PSBuildUpdatableHelp' {

        BeforeAll {
            $script:cabScenario = New-DocsScenario -Name 'cab'
            $null = Invoke-PSBuildCommandJob -CommandName 'Build-PSBuildMarkdown' -Parameter (
                New-MarkdownParameter -Scenario $script:cabScenario
            )
            $null = Invoke-PSBuildCommandJob -CommandName 'Build-PSBuildMAMLHelp' -Parameter @{
                Path            = $script:cabScenario.DocsPath
                DestinationPath = $script:cabScenario.OutputPath
            }
            $script:updatableHelpOutputPath = Join-Path -Path $script:cabScenario.OutputPath -ChildPath 'UpdatableHelp'
            $script:cabResult = Invoke-PSBuildCommandJob -CommandName 'Build-PSBuildUpdatableHelp' -Parameter @{
                DocsPath   = $script:cabScenario.DocsPath
                OutputPath = $script:updatableHelpOutputPath
                Module     = $script:fixtureName
            }
        }

        It 'declines to run on platforms without makecab' -Skip:($IsWindows -or $null -eq $IsWindows) {
            # Guarded by "$null -ne $IsWindows -and -not $IsWindows" in the function, so
            # Windows PowerShell 5.1 (where $IsWindows does not exist) never takes this path.
            $script:cabResult.Threw | Should -BeFalse
            $script:updatableHelpOutputPath | Should -Not -Exist
        }

        It 'creates the output directory' -Skip:(-not ($IsWindows -or $null -eq $IsWindows)) {
            # This much works today: the directory is created before the cab step throws.
            $script:updatableHelpOutputPath | Should -Exist
        }

        It 'fails parameter binding on the cab step' -Skip:(-not ($IsWindows -or $null -eq $IsWindows)) {
            # Pins the CURRENT broken behavior so the baseline is honest about what happens,
            # and so fixing psake/PowerShellBuild#169 forces this test to be revisited rather
            # than leaving a silent pass. Delete this test when #169 is fixed; the two below
            # replace it.
            #
            # Either of two independent defects can surface first, depending on the order
            # PowerShell binds the splatted parameters: LandingPagePath points at a module page
            # that is never generated, and CabFilesFolder is built from the undefined
            # $moduleOutDir, which collapses to the bare locale name. Asserting on one of them
            # specifically makes this test flaky, so it accepts either.
            $script:cabResult.Threw | Should -BeTrue
            $script:cabResult.ErrorMessage | Should -Match 'LandingPagePath|CabFilesFolder'
        }

        It 'produces a cabinet file' -Skip {
            # Skipped pending psake/PowerShellBuild#169. This is the acceptance criterion for
            # that fix and for the #152 migration, written now so it is not written twice.
            Get-ChildItem -Path $script:updatableHelpOutputPath -Filter '*.cab' |
                Should -Not -BeNullOrEmpty
        }

        It 'produces the help info manifest' -Skip {
            # Skipped pending psake/PowerShellBuild#169. See above.
            Get-ChildItem -Path $script:updatableHelpOutputPath -Filter '*HelpInfo.xml' |
                Should -Not -BeNullOrEmpty
        }
    }
}
