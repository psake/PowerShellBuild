BeforeAll {
    Set-BuildEnvironment -Force
    $manifest        = Import-PowerShellDataFile -Path $env:BHPSModuleManifest
    $outputDir       = Join-Path -Path $ENV:BHProjectPath -ChildPath 'Output'
    $outputModDir    = Join-Path -Path $outputDir -ChildPath $env:BHProjectName
    $outputModVerDir = Join-Path -Path $outputModDir -ChildPath $manifest.ModuleVersion
    Import-Module (Join-Path $outputModVerDir "$($env:BHProjectName).psd1") -Force
}

Describe 'Format-PSBuildResult' {
    BeforeAll {
        $script:mockTaskResults = @(
            [PSCustomObject]@{
                Name     = 'Init'
                Status   = 'Executed'
                Duration = [timespan]::FromSeconds(0.5)
                Cached   = $false
            },
            [PSCustomObject]@{
                Name     = 'Build'
                Status   = 'Executed'
                Duration = [timespan]::FromSeconds(2.3)
                Cached   = $false
            },
            [PSCustomObject]@{
                Name     = 'StageFiles'
                Status   = 'Skipped'
                Duration = [timespan]::FromSeconds(0.01)
                Cached   = $true
            }
        )
    }

    Context 'Successful build' {
        BeforeAll {
            $script:successResult = [PSCustomObject]@{
                Success      = $true
                Duration     = [timespan]::FromSeconds(3.5)
                TaskResults  = $script:mockTaskResults
                ErrorMessage = $null
            }
        }

        It 'JSON format produces valid JSON' {
            $output = Format-PSBuildResult -Result $script:successResult -Format JSON
            { $output | ConvertFrom-Json } | Should -Not -Throw
        }

        It 'JSON format includes success flag' {
            $output = Format-PSBuildResult -Result $script:successResult -Format JSON
            $parsed = $output | ConvertFrom-Json
            $parsed.success | Should -BeTrue
        }

        It 'JSON format includes task details' {
            $output = Format-PSBuildResult -Result $script:successResult -Format JSON
            $parsed = $output | ConvertFrom-Json
            $parsed.tasks | Should -HaveCount 3
            $parsed.tasks[2].cached | Should -BeTrue
        }

        It 'JSON format includes duration' {
            $output = Format-PSBuildResult -Result $script:successResult -Format JSON
            $parsed = $output | ConvertFrom-Json
            $parsed.duration | Should -BeGreaterThan 0
        }
    }

    Context 'Failed build' {
        BeforeAll {
            $failedTask = [PSCustomObject]@{
                Name         = 'Test'
                Status       = 'Failed'
                Duration     = [timespan]::FromSeconds(1.0)
                Cached       = $false
                ErrorMessage = 'Pester tests failed'
            }

            $script:failedResult = [PSCustomObject]@{
                Success      = $false
                Duration     = [timespan]::FromSeconds(5.0)
                TaskResults  = @($failedTask)
                ErrorMessage = 'Build failed: Pester tests failed'
            }
        }

        It 'JSON format includes error for failed builds' {
            $output = Format-PSBuildResult -Result $script:failedResult -Format JSON
            $parsed = $output | ConvertFrom-Json
            $parsed.success | Should -BeFalse
            $parsed.error | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Parameter validation' {
        It 'Has a Format parameter with correct validate set' {
            $cmd = Get-Command Format-PSBuildResult
            $param = $cmd.Parameters['Format']
            $validateSet = $param.Attributes.Where({ $_ -is [System.Management.Automation.ValidateSetAttribute] })
            $validateSet.ValidValues | Should -Contain 'Human'
            $validateSet.ValidValues | Should -Contain 'JSON'
            $validateSet.ValidValues | Should -Contain 'GitHubActions'
        }

        It 'Accepts pipeline input for Result' {
            $cmd = Get-Command Format-PSBuildResult
            $cmd.Parameters['Result'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).ValueFromPipeline | Should -BeTrue
        }
    }
}
