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
# Every invocation runs in a background job. That is not incidental: platyPS 0.14.2 and
# Microsoft.PowerShell.PlatyPS 1.x each load their own YamlDotNet.dll through NestedModules,
# with different assembly identities, so whichever imports second fails with "Assembly with
# same name is already loaded". A separate runspace does not escape it; only a separate
# process does. Once the migration starts, the old and new implementations can only be
# exercised in the same test run through subprocesses. See Invoke-PSBuildCommandInJob in
# fixtures/FixtureHelpers.psm1.
#
# The fixture is copied into $TestDrive rather than built in place, so nothing under tests/
# is mutated and Pester handles cleanup.

BeforeDiscovery {
    # The psake PreConditions on the docs tasks gate on exactly this, so the tests behave the
    # same way the shipped tasks do: absent platyPS means skipped, not failed.
    $script:platyPSAvailable = [bool](Get-Module -Name 'platyPS' -ListAvailable)

    # Build-PSBuildUpdatableHelp returns early on non-Windows, and Windows PowerShell 5.1 has
    # no $IsWindows at all, so it takes the Windows path there. Resolved at discovery because
    # both branches below are -Skip: conditions.
    $script:onWindows = $IsWindows -or $null -eq $IsWindows
}

Describe 'Help building functions' -Skip:(-not $script:platyPSAvailable) {

    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:builtModulePath = [IO.Path]::Combine($script:moduleRoot, 'Output', 'PowerShellBuild')

        Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'fixtures', 'FixtureHelpers.psm1')) -Force
    }

    AfterAll {
        Remove-Module -Name 'FixtureHelpers' -Force -ErrorAction SilentlyContinue
    }

    Context 'Build-PSBuildMarkdown' {

        BeforeAll {
            $script:markdownScenario = New-PSBuildDocsScenario -Path $TestDrive -Name 'markdown'
            $markdownJobParameter = @{
                ModulePath  = $script:builtModulePath
                CommandName = 'Build-PSBuildMarkdown'
                Parameter   = New-PSBuildMarkdownParameter -Scenario $script:markdownScenario
            }
            $script:markdownResult = Invoke-PSBuildCommandInJob @markdownJobParameter
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
            $landingPageName = '{0}.md' -f $script:markdownScenario.ModuleName
            Join-Path -Path $script:markdownScenario.LocalePath -ChildPath $landingPageName |
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
            $markdownPath = Join-Path -Path $script:markdownScenario.LocalePath -ChildPath 'Get-Widget.md'
            Get-Content -Path $markdownPath -Raw | Should -Match 'schema:\s*2\.0\.0'
        }
    }

    Context 'Build-PSBuildMAMLHelp' {

        BeforeAll {
            $script:mamlScenario = New-PSBuildDocsScenario -Path $TestDrive -Name 'maml'
            $mamlMarkdownJobParameter = @{
                ModulePath  = $script:builtModulePath
                CommandName = 'Build-PSBuildMarkdown'
                Parameter   = New-PSBuildMarkdownParameter -Scenario $script:mamlScenario
            }
            $null = Invoke-PSBuildCommandInJob @mamlMarkdownJobParameter

            $mamlJobParameter = @{
                ModulePath  = $script:builtModulePath
                CommandName = 'Build-PSBuildMAMLHelp'
                Parameter   = @{
                    Path            = $script:mamlScenario.DocsPath
                    DestinationPath = $script:mamlScenario.OutputPath
                }
            }
            $script:mamlResult = Invoke-PSBuildCommandInJob @mamlJobParameter
        }

        It 'completes without error' {
            $script:mamlResult.ErrorMessage | Should -BeNullOrEmpty
            $script:mamlResult.Threw | Should -BeFalse
        }

        It 'writes the MAML help file into a locale directory under the destination' {
            $script:mamlScenario.MamlPath | Should -Exist
        }

        It 'produces MAML describing the exported commands' {
            $maml = Get-Content -Path $script:mamlScenario.MamlPath -Raw
            $maml | Should -Match 'Get-Widget'
            $maml | Should -Match 'Set-Widget'
        }
    }

    Context 'Build-PSBuildUpdatableHelp' {

        BeforeAll {
            $script:cabScenario = New-PSBuildDocsScenario -Path $TestDrive -Name 'cab'
            $cabMarkdownJobParameter = @{
                ModulePath  = $script:builtModulePath
                CommandName = 'Build-PSBuildMarkdown'
                Parameter   = New-PSBuildMarkdownParameter -Scenario $script:cabScenario
            }
            $null = Invoke-PSBuildCommandInJob @cabMarkdownJobParameter

            $cabMamlJobParameter = @{
                ModulePath  = $script:builtModulePath
                CommandName = 'Build-PSBuildMAMLHelp'
                Parameter   = @{
                    Path            = $script:cabScenario.DocsPath
                    DestinationPath = $script:cabScenario.OutputPath
                }
            }
            $null = Invoke-PSBuildCommandInJob @cabMamlJobParameter

            $cabJobParameter = @{
                ModulePath  = $script:builtModulePath
                CommandName = 'Build-PSBuildUpdatableHelp'
                Parameter   = @{
                    DocsPath   = $script:cabScenario.DocsPath
                    OutputPath = $script:cabScenario.UpdatableHelpPath
                    Module     = $script:cabScenario.ModuleName
                }
            }
            $script:cabResult = Invoke-PSBuildCommandInJob @cabJobParameter
        }

        It 'declines to run on platforms without makecab' -Skip:$script:onWindows {
            $script:cabResult.Threw | Should -BeFalse
            $script:cabScenario.UpdatableHelpPath | Should -Not -Exist
        }

        It 'creates the output directory' -Skip:(-not $script:onWindows) {
            # This much works today: the directory is created before the cab step throws.
            $script:cabScenario.UpdatableHelpPath | Should -Exist
        }

        It 'fails parameter binding on the cab step' -Skip:(-not $script:onWindows) {
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
            Get-ChildItem -Path $script:cabScenario.UpdatableHelpPath -Filter '*.cab' |
                Should -Not -BeNullOrEmpty
        }

        It 'produces the help info manifest' -Skip {
            # Skipped pending psake/PowerShellBuild#169. See above.
            Get-ChildItem -Path $script:cabScenario.UpdatableHelpPath -Filter '*HelpInfo.xml' |
                Should -Not -BeNullOrEmpty
        }
    }
}
