Describe 'Test-PSBuildPester' {
    BeforeAll {
        $moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '../PowerShellBuild/PowerShellBuild.psd1'
        Import-Module -Name $moduleManifestPath -Force
    }

    Context 'when tests pass' {
        It 'invokes Pester and returns a result object' {
            $testRoot = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ("psbuild-pester-pass-{0}" -f [guid]::NewGuid())
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

            @'
Describe "fixture pass" {
    It "passes" {
        1 | Should -Be 1
    }
}
'@ | Set-Content -Path (Join-Path -Path $testRoot -ChildPath 'fixture.pass.tests.ps1') -Encoding utf8

            $result = Test-PSBuildPester -Path $testRoot -OutputVerbosity None

            $result | Should -Not -BeNullOrEmpty
            $result.PassedCount | Should -Be 1

            Remove-Item -Path $testRoot -Recurse -Force
        }
    }

    Context 'when tests fail' {
        It 'throws to signal failure' {
            $testRoot = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ("psbuild-pester-fail-{0}" -f [guid]::NewGuid())
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

            @'
Describe "fixture fail" {
    It "fails" {
        1 | Should -Be 2
    }
}
'@ | Set-Content -Path (Join-Path -Path $testRoot -ChildPath 'fixture.fail.tests.ps1') -Encoding utf8

            { Test-PSBuildPester -Path $testRoot -OutputVerbosity None } | Should -Throw

            Remove-Item -Path $testRoot -Recurse -Force
        }
    }

    Context 'when code coverage is enabled' {
        It 'writes coverage results to the requested output path and format' {
            $testRoot = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ("psbuild-pester-coverage-{0}" -f [guid]::NewGuid())
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

            $targetFilePath = Join-Path -Path $testRoot -ChildPath 'target.ps1'
            @'
function Invoke-Target {
    'ok'
}
'@ | Set-Content -Path $targetFilePath -Encoding utf8

            @'
. "$PSScriptRoot/target.ps1"

Describe "fixture coverage" {
    It "invokes target" {
        Invoke-Target | Should -Be "ok"
    }
}
'@ | Set-Content -Path (Join-Path -Path $testRoot -ChildPath 'fixture.coverage.tests.ps1') -Encoding utf8

            $coverageOutputFile = 'coverage.xml'
            $null = Test-PSBuildPester -Path $testRoot -OutputVerbosity None -CodeCoverage -CodeCoverageThreshold 0 -CodeCoverageFiles @($targetFilePath) -CodeCoverageOutputFile $coverageOutputFile -CodeCoverageOutputFileFormat JaCoCo

            $coverageFilePath = Join-Path -Path $testRoot -ChildPath $coverageOutputFile
            $coverageFilePath | Should -Exist
            $coverageText = Get-Content -Path $coverageFilePath -Raw
            $coverageText | Should -Match '<report\b'

            Remove-Item -Path $testRoot -Recurse -Force
        }
    }
}
