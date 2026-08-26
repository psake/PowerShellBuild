Describe 'Clear-PSBuildOutputFolder' {

    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name ([IO.Path]::Combine($script:moduleRoot, 'Output', 'PowerShellBuild')) -Force
    }

    It 'removes the output folder when it exists' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'Output'
        $nestedPath = Join-Path -Path $outputPath -ChildPath 'Nested'
        $nestedFilePath = Join-Path -Path $nestedPath -ChildPath 'marker.txt'
        New-Item -Path $outputPath -ItemType Directory -Force > $null
        New-Item -Path $nestedPath -ItemType Directory -Force > $null
        New-Item -Path $nestedFilePath -ItemType File -Force > $null

        Clear-PSBuildOutputFolder -Path $outputPath

        Test-Path -Path $outputPath | Should -BeFalse
    }

    It 'refuses a path short enough to be a drive root' {
        Mock -CommandName 'Test-Path' -ModuleName 'PowerShellBuild' -MockWith { $false }

        { Clear-PSBuildOutputFolder -Path 'C:\' } |
            Should -Throw -ExpectedMessage '*must be longer than 3 characters.*'
    }

    It 'does not throw when the output folder does not exist' {
        $outputPath = Join-Path -Path $TestDrive -ChildPath 'MissingOutput'

        { Clear-PSBuildOutputFolder -Path $outputPath } | Should -Not -Throw
    }
}
