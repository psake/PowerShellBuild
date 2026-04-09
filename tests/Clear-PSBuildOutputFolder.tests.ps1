Describe 'Clear-PSBuildOutputFolder' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../PowerShellBuild/PowerShellBuild.psd1" -Force
    }

    It 'throws when Path is 3 chars or fewer' {
        { Clear-PSBuildOutputFolder -Path 'abc' } | Should -Throw
    }

    It 'removes an existing output folder recursively' {
        $tempRoot = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString())
        $outputPath = Join-Path -Path $tempRoot -ChildPath 'output-folder'
        $nestedDir = Join-Path -Path $outputPath -ChildPath 'nested'

        New-Item -ItemType Directory -Path $nestedDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path -Path $nestedDir -ChildPath 'artifact.txt') -Force | Out-Null

        $outputPath | Should -Exist

        Clear-PSBuildOutputFolder -Path $outputPath

        $outputPath | Should -Not -Exist
    }

    It 'does nothing when the target path does not exist' {
        $missingPath = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ("missing-" + [guid]::NewGuid().ToString())

        { Clear-PSBuildOutputFolder -Path $missingPath } | Should -Not -Throw
    }
}
