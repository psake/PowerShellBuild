# Coverage for the rule that decides which directories under a docs tree are help locales
# (psake/PowerShellBuild#124).
#
# The helper is private, so these run through InModuleScope rather than the exported surface.
# That is deliberate: the rule is cheap to state and cheap to get wrong, and reaching it
# through Build-PSBuildUpdatableHelp would mean building a cabinet -- Windows only, several
# seconds, and a failure that says nothing about which half of the rule broke. The end-to-end
# behavior is asserted once in Build-PSBuildHelp.tests.ps1.
#
# Nothing here touches PlatyPS, so unlike the rest of the docs tests these need no background
# job to keep the two PlatyPS majors apart.

Describe 'Get-PSBuildHelpLocale' {

    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name ([IO.Path]::Combine($script:moduleRoot, 'Output', 'PowerShellBuild')) -Force
    }

    It 'returns a directory named for a culture' {
        $docsPath = Join-Path -Path $TestDrive -ChildPath 'culture-named'
        New-Item -Path (Join-Path -Path $docsPath -ChildPath 'en-US') -ItemType Directory -Force > $null

        InModuleScope -ModuleName 'PowerShellBuild' -Parameters @{ DocsPath = $docsPath } {
            param($DocsPath)
            Get-PSBuildHelpLocale -Path $DocsPath | Should -Be 'en-US'
        }
    }

    It 'ignores a directory that is neither a culture nor a built locale' {
        # The reported problem: a docs tree holds more than generated help, and every one of
        # these was previously treated as a locale.
        $docsPath = Join-Path -Path $TestDrive -ChildPath 'mixed'
        foreach ($name in 'en-US', 'images', 'guides', 'assets') {
            New-Item -Path (Join-Path -Path $docsPath -ChildPath $name) -ItemType Directory -Force > $null
        }

        InModuleScope -ModuleName 'PowerShellBuild' -Parameters @{ DocsPath = $docsPath } {
            param($DocsPath)
            Get-PSBuildHelpLocale -Path $DocsPath | Should -Be 'en-US'
        }
    }

    It 'ignores files at the docs root' {
        $docsPath = Join-Path -Path $TestDrive -ChildPath 'root-files'
        New-Item -Path (Join-Path -Path $docsPath -ChildPath 'en-US') -ItemType Directory -Force > $null
        Set-Content -Path (Join-Path -Path $docsPath -ChildPath 'README.md') -Value '# Read me'

        InModuleScope -ModuleName 'PowerShellBuild' -Parameters @{ DocsPath = $docsPath } {
            param($DocsPath)
            Get-PSBuildHelpLocale -Path $DocsPath | Should -Be 'en-US'
        }
    }

    It 'returns a directory the culture table does not know when built help exists for it' {
        # Windows PowerShell 5.1 knows a smaller set of cultures than PowerShell 7 --
        # zh-Hans-CN is in PowerShell 7's table and not in 5.1's -- so the name test alone
        # would drop a locale that has been building fine, on the older host only. Output
        # from the MAML step is the second signal that keeps that from happening.
        $docsPath = Join-Path -Path $TestDrive -ChildPath 'built-locale'
        $modulePath = Join-Path -Path $TestDrive -ChildPath 'built-locale-module'
        New-Item -Path (Join-Path -Path $docsPath -ChildPath 'zz-Custom') -ItemType Directory -Force > $null
        New-Item -Path (Join-Path -Path $modulePath -ChildPath 'zz-Custom') -ItemType Directory -Force > $null

        $parameter = @{ DocsPath = $docsPath; ModulePath = $modulePath }
        InModuleScope -ModuleName 'PowerShellBuild' -Parameters $parameter {
            param($DocsPath, $ModulePath)
            Get-PSBuildHelpLocale -Path $DocsPath -ModulePath $ModulePath | Should -Be 'zz-Custom'
        }
    }

    It 'does not treat a docs directory as a locale because a same-named file exists in the module' {
        # Test-Path alone would match a file. The signal is a built help directory, and a
        # module root has plenty of files in it that could collide with a docs directory name.
        $docsPath = Join-Path -Path $TestDrive -ChildPath 'file-collision'
        $modulePath = Join-Path -Path $TestDrive -ChildPath 'file-collision-module'
        New-Item -Path (Join-Path -Path $docsPath -ChildPath 'notes') -ItemType Directory -Force > $null
        New-Item -Path $modulePath -ItemType Directory -Force > $null
        Set-Content -Path (Join-Path -Path $modulePath -ChildPath 'notes') -Value 'not a locale'

        $parameter = @{ DocsPath = $docsPath; ModulePath = $modulePath }
        InModuleScope -ModuleName 'PowerShellBuild' -Parameters $parameter {
            param($DocsPath, $ModulePath)
            Get-PSBuildHelpLocale -Path $DocsPath -ModulePath $ModulePath | Should -BeNullOrEmpty
        }
    }

    It 'matches a culture name without regard to case' {
        # A docs tree committed as en-us builds on Windows and would stop building on a case
        # sensitive file system if the comparison were case sensitive.
        $docsPath = Join-Path -Path $TestDrive -ChildPath 'lowercase'
        New-Item -Path (Join-Path -Path $docsPath -ChildPath 'en-us') -ItemType Directory -Force > $null

        InModuleScope -ModuleName 'PowerShellBuild' -Parameters @{ DocsPath = $docsPath } {
            param($DocsPath)
            Get-PSBuildHelpLocale -Path $DocsPath | Should -Be 'en-us'
        }
    }

    It 'returns nothing for a docs path that does not exist' {
        # Reached whenever the docs tasks run before any documentation has been generated.
        $docsPath = Join-Path -Path $TestDrive -ChildPath 'absent'

        InModuleScope -ModuleName 'PowerShellBuild' -Parameters @{ DocsPath = $docsPath } {
            param($DocsPath)
            { Get-PSBuildHelpLocale -Path $DocsPath } | Should -Not -Throw
            Get-PSBuildHelpLocale -Path $DocsPath | Should -BeNullOrEmpty
        }
    }
}
