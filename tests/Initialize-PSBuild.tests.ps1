Describe 'Initialize-PSBuild' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../PowerShellBuild/PowerShellBuild.psd1" -Force
    }

    BeforeEach {
        $script:capturedBuildOutput = $null
        Mock -CommandName Set-BuildEnvironment -MockWith {
            param($BuildOutput)
            $script:capturedBuildOutput = $BuildOutput
        }

        $env:BHProjectPath = '/repo/project'
        $env:BHProjectName = 'DemoModule'

        $script:baseEnvironment = @{
            Build = @{
                OutDir = 'out'
            }
            General = @{
                ModuleVersion = '1.2.3'
            }
        }
    }

    It 'sets ModuleOutDir under BHProjectPath when OutDir is relative' {
        $envCopy = $script:baseEnvironment.PSObject.Copy()
        Initialize-PSBuild -BuildEnvironment $script:baseEnvironment

        $expected = [IO.Path]::Combine('/repo/project', 'out', 'DemoModule', '1.2.3')
        $script:baseEnvironment.Build.ModuleOutDir | Should -Be $expected
        $script:capturedBuildOutput | Should -Be $expected
        Assert-MockCalled Set-BuildEnvironment -Times 1 -Exactly
    }

    It 'keeps OutDir-rooted path when OutDir already starts with BHProjectPath (case-insensitive)' {
        $script:baseEnvironment.Build.OutDir = '/REPO/PROJECT/out'

        Initialize-PSBuild -BuildEnvironment $script:baseEnvironment

        $expected = [IO.Path]::Combine('/REPO/PROJECT/out', 'DemoModule', '1.2.3')
        $script:baseEnvironment.Build.ModuleOutDir | Should -Be $expected
        $script:capturedBuildOutput | Should -Be $expected
        Assert-MockCalled Set-BuildEnvironment -Times 1 -Exactly
    }

    It 'prints BuildHelpers environment section only when UseBuildHelpers is present' {
        Mock -CommandName Get-Item -MockWith { @() }
        Mock -CommandName Write-Host

        Initialize-PSBuild -BuildEnvironment $script:baseEnvironment
        Assert-MockCalled Write-Host -Times 2 -Exactly

        Initialize-PSBuild -BuildEnvironment $script:baseEnvironment -UseBuildHelpers
        Assert-MockCalled Write-Host -Times 5
    }
}
