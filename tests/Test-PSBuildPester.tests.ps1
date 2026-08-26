# Integration tests for Test-PSBuildPester (psake/PowerShellBuild#102).
#
# Test-PSBuildPester wraps Invoke-Pester, so these tests are Pester-testing-Pester. Every
# invocation runs in a Start-Job subprocess, which keeps the inner run's Pester state out of the
# outer framework's. The job runner lives in fixtures/FixtureHelpers.psm1, shared with the other
# test files that need a fresh session.
#
# This was a two-major matrix until #172 raised the floor to Pester 6. It still discovers the
# version rather than hardcoding one, so the loop below is what would grow back if a second
# supported major ever returned.
#
# The crash fixtures are generated into $TestDrive at runtime, never checked in, so the
# repository's own Pester run can never discover them (see #97 for the convention).

BeforeDiscovery {
    # Newest installed Pester of each supported major. Pester 6 is the only supported major
    # since #172; an absent one simply produces no matrix legs, which fails loudly below rather
    # than passing with nothing run.
    $script:innerPesterVersions = @(
        foreach ($majorVersion in 6) {
            $newestOfMajor = Get-Module -Name 'Pester' -ListAvailable |
                Where-Object { $_.Version.Major -eq $majorVersion } |
                Sort-Object -Property 'Version' -Descending |
                Select-Object -First 1
            if ($newestOfMajor) {
                $newestOfMajor.Version.ToString()
            }
        }
    )
    if ($script:innerPesterVersions.Count -eq 0) {
        throw 'No supported Pester major (6.x) is installed; Test-PSBuildPester cannot be verified.'
    }
}

Describe 'Test-PSBuildPester' {

    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:builtModulePath = [IO.Path]::Combine($script:moduleRoot, 'Output', 'PowerShellBuild')

        Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'fixtures', 'FixtureHelpers.psm1')) -Force

        # Scenario directories, generated at runtime.
        $script:healthyPath = Join-Path -Path $TestDrive -ChildPath 'healthy'
        $script:failingTestPath = Join-Path -Path $TestDrive -ChildPath 'failingtest'
        $script:beforeAllCrashPath = Join-Path -Path $TestDrive -ChildPath 'beforeallcrash'
        $script:discoveryCrashPath = Join-Path -Path $TestDrive -ChildPath 'discoverycrash'
        $script:coveragePath = Join-Path -Path $TestDrive -ChildPath 'coverage'
        $script:outputPath = Join-Path -Path $TestDrive -ChildPath 'out'
        foreach ($directory in @(
                $script:healthyPath
                $script:failingTestPath
                $script:beforeAllCrashPath
                $script:discoveryCrashPath
                $script:coveragePath
                $script:outputPath
            )) {
            New-Item -Path $directory -ItemType Directory -Force > $null
        }

        Set-Content -Path (Join-Path -Path $script:healthyPath -ChildPath 'Healthy.tests.ps1') -Value @'
Describe 'Healthy suite' {
    It 'passes' {
        1 | Should -Be 1
    }
}
'@

        Set-Content -Path (Join-Path -Path $script:failingTestPath -ChildPath 'FailingTest.tests.ps1') -Value @'
Describe 'Suite with a failing test' {
    It 'fails' {
        1 | Should -Be 2
    }
}
'@

        Set-Content -Path (Join-Path -Path $script:beforeAllCrashPath -ChildPath 'BeforeAllCrash.tests.ps1') -Value @'
Describe 'Suite with a broken setup' {
    BeforeAll {
        throw 'BeforeAll exploded'
    }

    It 'never executes' {
        1 | Should -Be 1
    }
}
'@

        Set-Content -Path (Join-Path -Path $script:discoveryCrashPath -ChildPath 'DiscoveryCrash.tests.ps1') -Value @'
throw 'file exploded during discovery'

Describe 'Unreachable suite' {
    It 'is never discovered' {
        1 | Should -Be 1
    }
}
'@

        # Coverage scenario: tests exercising the fixture module, with coverage measured on the
        # fixture's public functions.
        $script:fixturePath = Copy-PSBuildTestFixture -Destination $TestDrive
        $fixtureManifestPath = Join-Path -Path $script:fixturePath -ChildPath 'PSBuildTestFixture.psd1'
        Set-Content -Path (Join-Path -Path $script:coveragePath -ChildPath 'Coverage.tests.ps1') -Value @"
BeforeAll {
    Import-Module -Name '$fixtureManifestPath' -Force
}

Describe 'Coverage target' {
    It 'calls Get-Widget' {
        (Get-Widget -Name 'Sprocket').Name | Should -Be 'Sprocket'
    }
}
"@
    }

    AfterAll {
        Remove-Module -Name 'FixtureHelpers' -Force -ErrorAction SilentlyContinue
    }

    Context 'with inner Pester <_>' -ForEach $script:innerPesterVersions {

        BeforeAll {
            $script:innerVersion = $_
        }

        It 'succeeds for a healthy suite' {
            $result = Invoke-TestPSBuildPesterInJob -ModulePath $script:builtModulePath -InnerPesterVersion $script:innerVersion -Path $script:healthyPath

            $result.Threw | Should -BeFalse
        }

        It 'fails the build when a test fails' {
            # Regression: #52
            $result = Invoke-TestPSBuildPesterInJob -ModulePath $script:builtModulePath -InnerPesterVersion $script:innerVersion -Path $script:failingTestPath

            $result.Threw | Should -BeTrue
            $result.ErrorMessage | Should -Match 'Pester tests failed'
        }

        It 'fails the build when a setup block throws' {
            # Regression: #128 / #133 (FailedCount alone misses failed blocks)
            $result = Invoke-TestPSBuildPesterInJob -ModulePath $script:builtModulePath -InnerPesterVersion $script:innerVersion -Path $script:beforeAllCrashPath

            $result.Threw | Should -BeTrue
            $result.ErrorMessage | Should -Match 'Pester tests failed'
        }

        It 'fails the build when a test file errors during discovery' {
            # Regression: #128 / #133 (FailedCount alone misses failed containers)
            $result = Invoke-TestPSBuildPesterInJob -ModulePath $script:builtModulePath -InnerPesterVersion $script:innerVersion -Path $script:discoveryCrashPath

            $result.Threw | Should -BeTrue
            $result.ErrorMessage | Should -Match 'Pester tests failed'
        }

        It 'writes test results to the requested output path' {
            $testResultsPath = Join-Path -Path $script:outputPath -ChildPath "testResults-$script:innerVersion.xml"
            $additionalParameters = @{
                OutputPath = $testResultsPath
            }
            $result = Invoke-TestPSBuildPesterInJob -ModulePath $script:builtModulePath -InnerPesterVersion $script:innerVersion -Path $script:healthyPath -AdditionalParameter $additionalParameters

            $result.Threw | Should -BeFalse
            $testResultsPath | Should -Exist
        }

        It 'writes code coverage in the requested format to the requested path' {
            # Regression: #62
            $coverageOutputPath = Join-Path -Path $script:outputPath -ChildPath "coverage-$script:innerVersion.xml"
            $additionalParameters = @{
                CodeCoverage                 = $true
                CodeCoverageFiles            = @(Join-Path -Path $script:fixturePath -ChildPath 'Public/*.ps1')
                CodeCoverageOutputFile       = $coverageOutputPath
                CodeCoverageOutputFileFormat = 'JaCoCo'
            }
            $result = Invoke-TestPSBuildPesterInJob -ModulePath $script:builtModulePath -InnerPesterVersion $script:innerVersion -Path $script:coveragePath -AdditionalParameter $additionalParameters

            $result.Threw | Should -BeFalse
            $coverageOutputPath | Should -Exist
            [xml]$coverageReport = Get-Content -Path $coverageOutputPath -Raw
            $coverageReport.report | Should -Not -BeNullOrEmpty
        }

        # The coverage scenario exercises only Get-Widget while measuring both public fixture
        # functions, so measured coverage is always partial: comfortably above 1% and well
        # below 99%. Asserting from both sides pins the reported value to a fraction between
        # 0 and 1 -- a truncated 0 fails the first test, and a 0-to-100 scale fails the second.
        It 'passes when measured coverage is above the code coverage threshold' {
            # Regression: #138
            $coverageOutputPath = Join-Path -Path $script:outputPath -ChildPath "coverage-above-threshold-$script:innerVersion.xml"
            $additionalParameters = @{
                CodeCoverage           = $true
                CodeCoverageFiles      = @(Join-Path -Path $script:fixturePath -ChildPath 'Public/*.ps1')
                CodeCoverageOutputFile = $coverageOutputPath
                CodeCoverageThreshold  = 0.01
            }
            $result = Invoke-TestPSBuildPesterInJob -ModulePath $script:builtModulePath -InnerPesterVersion $script:innerVersion -Path $script:coveragePath -AdditionalParameter $additionalParameters

            $result.Threw | Should -BeFalse
        }

        It 'fails when measured coverage is below the code coverage threshold' {
            # Regression: #138
            $coverageOutputPath = Join-Path -Path $script:outputPath -ChildPath "coverage-below-threshold-$script:innerVersion.xml"
            $additionalParameters = @{
                CodeCoverage           = $true
                CodeCoverageFiles      = @(Join-Path -Path $script:fixturePath -ChildPath 'Public/*.ps1')
                CodeCoverageOutputFile = $coverageOutputPath
                CodeCoverageThreshold  = 0.99
            }
            $result = Invoke-TestPSBuildPesterInJob -ModulePath $script:builtModulePath -InnerPesterVersion $script:innerVersion -Path $script:coveragePath -AdditionalParameter $additionalParameters

            $result.Threw | Should -BeTrue
            $result.ErrorMessage | Should -Match 'less than the threshold'
        }
    }

    # BeforeDiscovery variables are not visible during the run phase, so the discovered version
    # list is handed to the run phase through -ForEach.
    Context 'Regressions independent of the inner Pester version' -ForEach @(
        @{ AvailableVersions = $script:innerPesterVersions }
    ) {

        BeforeAll {
            $script:newestInnerVersion = $AvailableVersions | Select-Object -Last 1
            $script:oldestInnerVersion = $AvailableVersions | Select-Object -First 1
        }

        It 'does not error when ModuleName is not provided' {
            # Regression: the finally block called Remove-Module with an empty -Name, which
            # raised a parameter-binding error that -ErrorAction SilentlyContinue cannot
            # suppress.
            $result = Invoke-TestPSBuildPesterInJob -ModulePath $script:builtModulePath -InnerPesterVersion $script:newestInnerVersion -Path $script:healthyPath

            $result.Threw | Should -BeFalse
            $result.ErrorMessage | Should -BeNullOrEmpty
        }

        It 'honors the Pester version that is already loaded' -Skip:($script:innerPesterVersions.Count -lt 2) {
            # Regression: an unconditional Import-Module Pester -MinimumVersion 5.0.0 loaded the
            # newest installed Pester on top of an already-loaded older one, which crashes with a
            # Pester.dll version conflict when 5.x and 6.x are installed side by side.
            $result = Invoke-TestPSBuildPesterInJob -ModulePath $script:builtModulePath -InnerPesterVersion $script:oldestInnerVersion -Path $script:healthyPath

            $result.Threw | Should -BeFalse
            $result.LoadedModuleVersion['Pester'] | Should -Be @($script:oldestInnerVersion)
        }
    }
}
