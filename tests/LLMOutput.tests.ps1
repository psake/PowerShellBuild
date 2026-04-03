BeforeAll {
    Set-BuildEnvironment -Force
    $manifest        = Import-PowerShellDataFile -Path $env:BHPSModuleManifest
    $outputDir       = Join-Path -Path $ENV:BHProjectPath -ChildPath 'Output'
    $outputModDir    = Join-Path -Path $outputDir -ChildPath $env:BHProjectName
    $outputModVerDir = Join-Path -Path $outputModDir -ChildPath $manifest.ModuleVersion
    Import-Module (Join-Path $outputModVerDir "$($env:BHProjectName).psd1") -Force
}

Describe 'ConvertTo-PSBuildLLMOutput' {
    BeforeAll {
        # Create a mock Pester test result object that mimics Invoke-Pester -PassThru output
        $mockFailedTest = [PSCustomObject]@{
            Result        = 'Failed'
            ExpandedPath  = 'Describe > Context > It should work'
            ScriptBlock   = [PSCustomObject]@{
                File          = 'C:\tests\example.tests.ps1'
                StartPosition = [PSCustomObject]@{
                    StartLine = 42
                }
            }
            ErrorRecord   = @(
                [PSCustomObject]@{
                    DisplayErrorMessage = 'Expected 5, but got 3.'
                }
            )
            Duration      = [timespan]::FromMilliseconds(123.4)
        }

        $mockPassedTest = [PSCustomObject]@{
            Result        = 'Passed'
            ExpandedPath  = 'Describe > Context > It should also work'
            ScriptBlock   = [PSCustomObject]@{
                File          = 'C:\tests\example.tests.ps1'
                StartPosition = [PSCustomObject]@{
                    StartLine = 50
                }
            }
            ErrorRecord   = $null
            Duration      = [timespan]::FromMilliseconds(10.5)
        }

        $mockBlock = [PSCustomObject]@{
            Tests  = @($mockPassedTest, $mockFailedTest)
            Blocks = @()
        }

        $mockContainer = [PSCustomObject]@{
            Name   = 'example.tests.ps1'
            Blocks = @($mockBlock)
        }

        $script:mockTestResult = [PSCustomObject]@{
            TotalCount   = 2
            PassedCount  = 1
            FailedCount  = 1
            SkippedCount = 0
            Duration     = [timespan]::FromSeconds(1.5)
            Containers   = @($mockContainer)
        }
    }

    It 'Produces valid JSON' {
        $output = ConvertTo-PSBuildLLMOutput -TestResult $script:mockTestResult
        { $output | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Contains summary with expected keys' {
        $output = ConvertTo-PSBuildLLMOutput -TestResult $script:mockTestResult
        $parsed = $output | ConvertFrom-Json
        $parsed.summary.total | Should -Be 2
        $parsed.summary.passed | Should -Be 1
        $parsed.summary.failed | Should -Be 1
        $parsed.summary.skipped | Should -Be 0
        $parsed.summary.duration | Should -BeGreaterThan 0
    }

    It 'Contains failure details with required fields' {
        $output = ConvertTo-PSBuildLLMOutput -TestResult $script:mockTestResult
        $parsed = $output | ConvertFrom-Json
        $parsed.failures | Should -HaveCount 1
        $failure = $parsed.failures[0]
        $failure.test | Should -Be 'Describe > Context > It should work'
        $failure.container | Should -Be 'example.tests.ps1'
        $failure.error | Should -Be 'Expected 5, but got 3.'
        $failure.file | Should -Be 'C:\tests\example.tests.ps1'
        $failure.line | Should -Be 42
    }

    Context 'All tests pass' {
        BeforeAll {
            $passOnlyBlock = [PSCustomObject]@{
                Tests  = @($mockPassedTest)
                Blocks = @()
            }
            $passOnlyContainer = [PSCustomObject]@{
                Name   = 'passing.tests.ps1'
                Blocks = @($passOnlyBlock)
            }
            $script:passingResult = [PSCustomObject]@{
                TotalCount   = 1
                PassedCount  = 1
                FailedCount  = 0
                SkippedCount = 0
                Duration     = [timespan]::FromSeconds(0.5)
                Containers   = @($passOnlyContainer)
            }
        }

        It 'Returns empty failures array when all tests pass' {
            $output = ConvertTo-PSBuildLLMOutput -TestResult $script:passingResult
            $parsed = $output | ConvertFrom-Json
            $parsed.failures | Should -HaveCount 0
            $parsed.summary.failed | Should -Be 0
        }
    }
}
