Describe 'Clear-PSBuildOutputFolder' {

    BeforeAll {
        $script:moduleName = 'PowerShellBuild'
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module ([IO.Path]::Combine($script:moduleRoot, 'Output', $script:moduleName)) -Force
    }

    It 'removes the target folder when it exists' {
        $path = Join-Path -Path $TestDrive -ChildPath 'OutputFolder'
        New-Item -Path $path -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path -Path $path -ChildPath 'artifact.txt') -ItemType File -Force | Out-Null

        Clear-PSBuildOutputFolder -Path $path

        $path | Should -Not -Exist
    }

    It 'does not throw when the target folder does not exist' {
        $path = Join-Path -Path $TestDrive -ChildPath 'MissingFolder'

        { Clear-PSBuildOutputFolder -Path $path } | Should -Not -Throw
    }

    It 'rejects paths with 3 or fewer characters' {
        { Clear-PSBuildOutputFolder -Path 'abc' } | Should -Throw
    }
}
