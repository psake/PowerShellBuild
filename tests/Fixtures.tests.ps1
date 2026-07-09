BeforeAll {
    Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'fixtures', 'FixtureHelpers.psm1')) -Force
}

AfterAll {
    Remove-Module -Name 'FixtureHelpers' -Force -ErrorAction SilentlyContinue
}

Describe 'PSBuildTestFixture' {

    Context 'Copy helper' {

        It 'Copies the fixture into the destination and returns the copy path' {
            $fixturePath = Copy-PSBuildTestFixture -Destination $TestDrive

            $fixturePath | Should -Be (Join-Path -Path $TestDrive -ChildPath 'PSBuildTestFixture')
            $fixturePath | Should -Exist
        }

        It 'Copies the complete fixture layout' {
            $fixturePath = Copy-PSBuildTestFixture -Destination (Join-Path -Path $TestDrive -ChildPath 'layout')

            Join-Path -Path $fixturePath -ChildPath 'PSBuildTestFixture.psd1' | Should -Exist
            Join-Path -Path $fixturePath -ChildPath 'PSBuildTestFixture.psm1' | Should -Exist
            Join-Path -Path $fixturePath -ChildPath 'Public/Get-Widget.ps1' | Should -Exist
            Join-Path -Path $fixturePath -ChildPath 'Public/Set-Widget.ps1' | Should -Exist
            Join-Path -Path $fixturePath -ChildPath 'Private/Test-WidgetName.ps1' | Should -Exist
            Join-Path -Path $fixturePath -ChildPath 'excludeme.txt' | Should -Exist
        }
    }

    Context 'Fixture module' {

        BeforeAll {
            $script:fixturePath = Copy-PSBuildTestFixture -Destination (Join-Path -Path $TestDrive -ChildPath 'module')
            $script:fixtureManifestPath = Join-Path -Path $script:fixturePath -ChildPath 'PSBuildTestFixture.psd1'
        }

        AfterAll {
            Remove-Module -Name 'PSBuildTestFixture' -Force -ErrorAction SilentlyContinue
        }

        It 'Has a valid module manifest' {
            { Test-ModuleManifest -Path $script:fixtureManifestPath -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Imports from a test drive copy' {
            { Import-Module -Name $script:fixtureManifestPath -Force -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Exports exactly the two public functions' {
            $exportedCommands = (Get-Module -Name 'PSBuildTestFixture').ExportedFunctions.Keys | Sort-Object
            $exportedCommands | Should -Be @('Get-Widget', 'Set-Widget')
        }

        It 'Does not export the private helper' {
            (Get-Module -Name 'PSBuildTestFixture').ExportedFunctions.Keys | Should -Not -Contain 'Test-WidgetName'
        }

        It 'Public functions work end to end' {
            $widget = Get-Widget -Name 'Sprocket' -Quantity 5

            $widget.Name | Should -Be 'Sprocket'
            $widget.Quantity | Should -Be 5
        }

        It 'Public functions have complete comment-based help' -ForEach @('Get-Widget', 'Set-Widget') {
            $help = Get-Help -Name $_ -Full

            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
            $help.Examples.Example.Count | Should -BeGreaterOrEqual 1
        }
    }
}
