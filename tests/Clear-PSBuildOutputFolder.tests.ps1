Describe 'Clear-PSBuildOutputFolder' {

    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name ([IO.Path]::Combine($script:moduleRoot, 'Output', 'PowerShellBuild')) -Force
    }

    It 'removes the output folder when it exists' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'Output'
        New-Item -Path $outputPath -ItemType Directory -Force > $null

        Clear-PSBuildOutputFolder -Path $outputPath

        Test-Path -Path $outputPath | Should -BeFalse
    }

    It 'does not throw when the output folder does not exist' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'MissingOutput'

        { Clear-PSBuildOutputFolder -Path $outputPath } | Should -Not -Throw
    }
}
