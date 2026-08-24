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
    # same way the shipped tasks do: an absent module means skipped, not failed.
    $script:platyPSAvailable = [bool](Get-Module -Name 'Microsoft.PowerShell.PlatyPS' -ListAvailable)

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

        It 'produces markdown carrying the 1.x schema marker' {
            # 0.14.x front matter carried "schema: 2.0.0". 1.x replaces it with a dated schema
            # version and a document type, so this pins the migration rather than just passing
            # either way.
            $markdownPath = Join-Path -Path $script:markdownScenario.LocalePath -ChildPath 'Get-Widget.md'
            $markdown = Get-Content -Path $markdownPath -Raw
            $markdown | Should -Match 'PlatyPS schema version:'
            $markdown | Should -Match 'document type:\s*cmdlet'
            $markdown | Should -Not -Match 'schema:\s*2\.0\.0'
        }

        It 'keeps the markdown directly under the locale directory' {
            # New-MarkdownCommandHelp writes to <OutputFolder>/<ModuleName>. The function
            # flattens that back out, so a nested module directory here means the flattening
            # regressed and every downstream path assumption breaks with it.
            Join-Path -Path $script:markdownScenario.LocalePath -ChildPath $script:markdownScenario.ModuleName |
                Should -Not -Exist
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

        # Pins the documented intermediate state, not the destination. The cabinet pipeline
        # migrates in #152 together with the three defects in #169 that stopped this function
        # ever succeeding. Until then it must fail quietly rather than throw, and above all it
        # must not name a platyPS 0.14.2 command: resolving one autoloads that module, and a
        # session holding it can no longer import Microsoft.PowerShell.PlatyPS at all.
        It 'returns without throwing' {
            $script:cabResult.Threw | Should -BeFalse
            $script:cabResult.ErrorMessage | Should -BeNullOrEmpty
        }

        It 'writes nothing' {
            $script:cabScenario.UpdatableHelpPath | Should -Not -Exist
        }
    }
}
