BeforeAll {
    Set-BuildEnvironment -Force
    $manifest        = Import-PowerShellDataFile -Path $env:BHPSModuleManifest
    $outputDir       = Join-Path -Path $ENV:BHProjectPath -ChildPath 'Output'
    $outputModDir    = Join-Path -Path $outputDir -ChildPath $env:BHProjectName
    $outputModVerDir = Join-Path -Path $outputModDir -ChildPath $manifest.ModuleVersion
    Import-Module (Join-Path $outputModVerDir "$($env:BHProjectName).psd1") -Force
}

Describe 'Test-PSBuildPester PesterConfiguration support' {

    Context 'OutputMode parameter' {
        It 'Accepts Detailed as default' {
            $cmd = Get-Command Test-PSBuildPester
            $param = $cmd.Parameters['OutputMode']
            $param | Should -Not -BeNullOrEmpty
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues | Should -Contain 'Detailed'
        }

        It 'Accepts Minimal value' {
            $cmd = Get-Command Test-PSBuildPester
            $param = $cmd.Parameters['OutputMode']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues | Should -Contain 'Minimal'
        }

        It 'Accepts LLM value' {
            $cmd = Get-Command Test-PSBuildPester
            $param = $cmd.Parameters['OutputMode']
            $param.Attributes.Where({ $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues | Should -Contain 'LLM'
        }
    }

    Context 'PesterConfigurationPath parameter' {
        It 'Has a PesterConfigurationPath parameter' {
            $cmd = Get-Command Test-PSBuildPester
            $cmd.Parameters.Keys | Should -Contain 'PesterConfigurationPath'
        }

        It 'PesterConfigurationPath is a string' {
            $cmd = Get-Command Test-PSBuildPester
            $cmd.Parameters['PesterConfigurationPath'].ParameterType | Should -Be ([string])
        }
    }

    Context 'Configuration parameter' {
        It 'Has a Configuration parameter' {
            $cmd = Get-Command Test-PSBuildPester
            $cmd.Parameters.Keys | Should -Contain 'Configuration'
        }

        It 'Configuration belongs to the Configuration parameter set' {
            $cmd = Get-Command Test-PSBuildPester
            $paramSets = $cmd.Parameters['Configuration'].ParameterSets.Keys
            $paramSets | Should -Contain 'Configuration'
        }
    }

    Context 'Parameter sets' {
        It 'Has an Individual parameter set' {
            $cmd = Get-Command Test-PSBuildPester
            $cmd.ParameterSets.Name | Should -Contain 'Individual'
        }

        It 'Has a Configuration parameter set' {
            $cmd = Get-Command Test-PSBuildPester
            $cmd.ParameterSets.Name | Should -Contain 'Configuration'
        }

        It 'Default parameter set is Individual' {
            $cmd = Get-Command Test-PSBuildPester
            $cmd.DefaultParameterSet | Should -Be 'Individual'
        }
    }
}
