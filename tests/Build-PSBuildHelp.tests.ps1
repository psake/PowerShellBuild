# Unit coverage for the three help-building functions (psake/PowerShellBuild#149).
#
# These functions had no tests of their own before #149. They were not entirely unobserved,
# though: build.tests.ps1 builds tests/TestModule through -FromModule PowerShellBuild, whose
# Build task depends on BuildHelp, so GenerateMarkdown and GenerateMAML have been exercised
# end to end all along and "Has MAML help XML" pinned the output layout. What was missing was
# coverage of the functions directly, with specific options, and anything at all for
# GenerateUpdatableHelp -- which is not in the default Build chain.
#
# The file began as a red-before-green baseline against platyPS 0.14.2 and now asserts the
# PlatyPS 1.x behavior the migration produces. The task wiring, which no function-level test
# can reach, is covered in build.tests.ps1.
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

        It 'writes a module landing page named for the module' {
            # The cabinet step reads the module GUID, locale, and help version from this page.
            # Its absence was defect 1 of psake/PowerShellBuild#169.
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

    Context 'Build-PSBuildUpdatableHelp' -Skip:(-not $script:onWindows) {

        BeforeAll {
            $script:cabScenario = New-PSBuildDocsScenario -Path $TestDrive -Name 'cab'

            $cabMarkdownJobParameter = @{
                ModulePath  = $script:builtModulePath
                CommandName = 'Build-PSBuildMarkdown'
                Parameter   = New-PSBuildMarkdownParameter -Scenario $script:cabScenario
            }
            $null = Invoke-PSBuildCommandInJob @cabMarkdownJobParameter

            # MAML has to land in the module directory, because that is where the cabinet step
            # reads it from -- the same path the GenerateUpdatableHelp task supplies.
            $cabMamlJobParameter = @{
                ModulePath  = $script:builtModulePath
                CommandName = 'Build-PSBuildMAMLHelp'
                Parameter   = @{
                    Path            = $script:cabScenario.DocsPath
                    DestinationPath = $script:cabScenario.ModulePath
                }
            }
            $null = Invoke-PSBuildCommandInJob @cabMamlJobParameter

            $cabJobParameter = @{
                ModulePath  = $script:builtModulePath
                CommandName = 'Build-PSBuildUpdatableHelp'
                Parameter   = @{
                    DocsPath   = $script:cabScenario.DocsPath
                    OutputPath = $script:cabScenario.UpdatableHelpPath
                    ModulePath = $script:cabScenario.ModulePath
                    Module     = $script:cabScenario.ModuleName
                }
            }
            $script:cabResult = Invoke-PSBuildCommandInJob @cabJobParameter
        }

        It 'completes without error' {
            $script:cabResult.ErrorMessage | Should -BeNullOrEmpty
            $script:cabResult.Threw | Should -BeFalse
        }

        It 'produces a cabinet file' {
            Get-ChildItem -Path $script:cabScenario.UpdatableHelpPath -Filter '*.cab' |
                Should -Not -BeNullOrEmpty
        }

        It 'produces the help info manifest' {
            # Written only when the manifest declares a HelpInfoUri. Without one the cabinet is
            # still produced and this file is not, which is output that looks complete and is
            # useless to Update-Help.
            Get-ChildItem -Path $script:cabScenario.UpdatableHelpPath -Filter '*HelpInfo.xml' |
                Should -Not -BeNullOrEmpty
        }

        It 'names the cabinet for the module, its GUID, and the locale' {
            $manifestPath = Join-Path -Path $script:cabScenario.ModulePath -ChildPath (
                '{0}.psd1' -f $script:cabScenario.ModuleName
            )
            $moduleGuid = (Import-PowerShellDataFile -Path $manifestPath).GUID
            $expectedName = '{0}_{1}_{2}_HelpContent.cab' -f
                $script:cabScenario.ModuleName, $moduleGuid, $script:cabScenario.Locale

            @(Get-ChildItem -Path $script:cabScenario.UpdatableHelpPath -Filter '*.cab')[0].Name |
                Should -Be $expectedName
        }
    }

    Context 'Build-PSBuildUpdatableHelp refuses to half-produce' -Skip:(-not $script:onWindows) {

        It 'declines when the manifest declares no HelpInfoUri' {
            # New-HelpCabinetFile writes the cabinet and its zip, then fails before writing the
            # HelpInfo.xml that Update-Help needs to find them. Stopping first is the whole
            # point of the guard, so this asserts nothing at all was written.
            $scenario = New-PSBuildDocsScenario -Path $TestDrive -Name 'nouri'
            $manifestPath = Join-Path -Path $scenario.ModulePath -ChildPath (
                '{0}.psd1' -f $scenario.ModuleName
            )
            (Get-Content -Path $manifestPath -Raw) -replace "(?m)^\s*HelpInfoUri.*$", '' |
                Set-Content -Path $manifestPath

            $guardJobParameter = @{
                ModulePath  = $script:builtModulePath
                CommandName = 'Build-PSBuildUpdatableHelp'
                Parameter   = @{
                    DocsPath   = $scenario.DocsPath
                    OutputPath = $scenario.UpdatableHelpPath
                    ModulePath = $scenario.ModulePath
                    Module     = $scenario.ModuleName
                }
            }
            $result = Invoke-PSBuildCommandInJob @guardJobParameter

            $result.Threw | Should -BeFalse
            $scenario.UpdatableHelpPath | Should -Not -Exist
        }
    }
}
