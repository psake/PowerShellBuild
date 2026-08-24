Describe 'Initialize-PSBuild' {

    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name ([IO.Path]::Combine($script:moduleRoot, 'Output', 'PowerShellBuild')) -Force
    }

    BeforeEach {
        $script:originalProjectPath = $env:BHProjectPath
        $script:originalProjectName = $env:BHProjectName
        $env:BHProjectPath = Join-Path -Path $TestDrive -ChildPath 'ExampleProject'
        $env:BHProjectName = 'ExampleModule'

        $script:buildEnvironment = @{
            Build   = @{
                OutDir      = 'Output'
                ModuleOutDir = $null
            }
            General = @{
                ModuleVersion = '1.2.3'
            }
        }

        Mock -CommandName 'Set-BuildEnvironment' -ModuleName 'PowerShellBuild'
    }

    AfterEach {
        if ($null -eq $script:originalProjectPath) {
            Remove-Item -Path 'Env:BHProjectPath' -ErrorAction SilentlyContinue
        }
        else {
            $env:BHProjectPath = $script:originalProjectPath
        }

        if ($null -eq $script:originalProjectName) {
            Remove-Item -Path 'Env:BHProjectName' -ErrorAction SilentlyContinue
        }
        else {
            $env:BHProjectName = $script:originalProjectName
        }
    }

    It 'resolves a relative output path below the project root' {
        Initialize-PSBuild -BuildEnvironment $script:buildEnvironment

        $expectedModuleOutputPath = [IO.Path]::Combine(
            $env:BHProjectPath,
            'Output',
            $env:BHProjectName,
            $script:buildEnvironment.General.ModuleVersion
        )
        $script:buildEnvironment.Build.ModuleOutDir | Should -Be $expectedModuleOutputPath

        $shouldInvokeParameters = @{
            CommandName     = 'Set-BuildEnvironment'
            ModuleName      = 'PowerShellBuild'
            Times           = 1
            Exactly         = $true
            ParameterFilter = {
                $BuildOutput -eq $expectedModuleOutputPath -and $Force
            }
        }
        Should -Invoke @shouldInvokeParameters
    }

    It 'resolves a project-rooted output path at the configured location' {
        $projectOutputPath = [IO.Path]::Combine($env:BHProjectPath, 'Output')
        $script:buildEnvironment.Build.OutDir = $projectOutputPath

        Initialize-PSBuild -BuildEnvironment $script:buildEnvironment

        $expectedModuleOutputPath = [IO.Path]::Combine(
            $projectOutputPath,
            $env:BHProjectName,
            $script:buildEnvironment.General.ModuleVersion
        )
        $script:buildEnvironment.Build.ModuleOutDir | Should -Be $expectedModuleOutputPath

        $shouldInvokeParameters = @{
            CommandName     = 'Set-BuildEnvironment'
            ModuleName      = 'PowerShellBuild'
            Times           = 1
            Exactly         = $true
            ParameterFilter = {
                $BuildOutput -eq $expectedModuleOutputPath -and $Force
            }
        }
        Should -Invoke @shouldInvokeParameters
    }
}
