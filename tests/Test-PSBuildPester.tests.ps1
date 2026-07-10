# Integration tests for Test-PSBuildPester (psake/PowerShellBuild#102).
#
# Test-PSBuildPester wraps Invoke-Pester, so these tests are Pester-testing-Pester. Every
# invocation runs in a Start-Job subprocess: two Pester versions cannot coexist in one session,
# and the subprocess lets each test pin the inner Pester version independently of the outer
# framework. The scenarios run against every installed Pester major (5.x and 6.x) to verify the
# shipped function keeps supporting Pester 5 consumers.
#
# The crash fixtures are generated into $TestDrive at runtime, never checked in, so the
# repository's own Pester run can never discover them (see #97 for the convention).

BeforeDiscovery {
    # Newest installed Pester of each supported major version. CI installs 6.x (Pester) and
    # 5.x (PesterLegacy) via requirements.psd1; locally, absent majors simply produce fewer
    # matrix legs.
    $script:innerPesterVersions = @(
        foreach ($majorVersion in 5, 6) {
            $newestOfMajor = Get-Module -Name 'Pester' -ListAvailable |
                Where-Object { $_.Version.Major -eq $majorVersion } |
                Sort-Object -Property 'Version' -Descending |
                Select-Object -First 1
            if ($newestOfMajor) {
                $newestOfMajor.Version.ToString()
            }
        }
    )
}

Describe 'Test-PSBuildPester' {

    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:builtModulePath = [IO.Path]::Combine($script:moduleRoot, 'Output', 'PowerShellBuild')

        Import-Module -Name ([IO.Path]::Combine($PSScriptRoot, 'fixtures', 'FixtureHelpers.psm1')) -Force

        # Runs Test-PSBuildPester in a subprocess with a pinned inner Pester version and reports
        # what happened. Returns an object with Threw, ErrorMessage, and the Pester version that
        # was loaded in the subprocess after the call.
        function script:Invoke-TestPSBuildPesterJob {
            param(
                [string]$InnerPesterVersion,
                [string]$Path,
                [hashtable]$AdditionalParameters = @{}
            )

            $job = Start-Job -ScriptBlock {
                param($innerPesterVersion, $builtModulePath, $path, $additionalParameters)

                Import-Module -Name 'Pester' -RequiredVersion $innerPesterVersion -ErrorAction Stop
                Import-Module -Name $builtModulePath -Force -ErrorAction Stop

                $testPSBuildPesterParameters = @{
                    Path            = $path
                    OutputVerbosity = 'None'
                    ErrorAction     = 'Stop'
                }
                foreach ($key in $additionalParameters.Keys) {
                    $testPSBuildPesterParameters[$key] = $additionalParameters[$key]
                }

                $threw = $false
                $errorMessage = $null
                try {
                    Test-PSBuildPester @testPSBuildPesterParameters
                } catch {
                    $threw = $true
                    $errorMessage = $_.Exception.Message
                }

                [PSCustomObject]@{
                    Threw                = $threw
                    ErrorMessage         = $errorMessage
                    LoadedPesterVersions = @((Get-Module -Name 'Pester').Version.ToString())
                }
            } -ArgumentList $InnerPesterVersion, $script:builtModulePath, $Path, $AdditionalParameters

            $jobResult = $job | Wait-Job | Receive-Job
            Remove-Job -Job $job -Force
            $jobResult
        }

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
            $result = Invoke-TestPSBuildPesterJob -InnerPesterVersion $script:innerVersion -Path $script:healthyPath

            $result.Threw | Should -BeFalse
        }

        It 'fails the build when a test fails' {
            # Regression: #52
            $result = Invoke-TestPSBuildPesterJob -InnerPesterVersion $script:innerVersion -Path $script:failingTestPath

            $result.Threw | Should -BeTrue
            $result.ErrorMessage | Should -Match 'Pester tests failed'
        }

        It 'fails the build when a setup block throws' {
            # Regression: #128 / #133 (FailedCount alone misses failed blocks)
            $result = Invoke-TestPSBuildPesterJob -InnerPesterVersion $script:innerVersion -Path $script:beforeAllCrashPath

            $result.Threw | Should -BeTrue
            $result.ErrorMessage | Should -Match 'Pester tests failed'
        }

        It 'fails the build when a test file errors during discovery' {
            # Regression: #128 / #133 (FailedCount alone misses failed containers)
            $result = Invoke-TestPSBuildPesterJob -InnerPesterVersion $script:innerVersion -Path $script:discoveryCrashPath

            $result.Threw | Should -BeTrue
            $result.ErrorMessage | Should -Match 'Pester tests failed'
        }

        It 'writes test results to the requested output path' {
            $testResultsPath = Join-Path -Path $script:outputPath -ChildPath "testResults-$script:innerVersion.xml"
            $additionalParameters = @{
                OutputPath = $testResultsPath
            }
            $result = Invoke-TestPSBuildPesterJob -InnerPesterVersion $script:innerVersion -Path $script:healthyPath -AdditionalParameters $additionalParameters

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
            $result = Invoke-TestPSBuildPesterJob -InnerPesterVersion $script:innerVersion -Path $script:coveragePath -AdditionalParameters $additionalParameters

            $result.Threw | Should -BeFalse
            $coverageOutputPath | Should -Exist
            [xml]$coverageReport = Get-Content -Path $coverageOutputPath -Raw
            $coverageReport.report | Should -Not -BeNullOrEmpty
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
            $result = Invoke-TestPSBuildPesterJob -InnerPesterVersion $script:newestInnerVersion -Path $script:healthyPath

            $result.Threw | Should -BeFalse
            $result.ErrorMessage | Should -BeNullOrEmpty
        }

        It 'honors the Pester version that is already loaded' -Skip:($script:innerPesterVersions.Count -lt 2) {
            # Regression: an unconditional Import-Module Pester -MinimumVersion 5.0.0 loaded the
            # newest installed Pester on top of an already-loaded older one, which crashes with a
            # Pester.dll version conflict when 5.x and 6.x are installed side by side.
            $result = Invoke-TestPSBuildPesterJob -InnerPesterVersion $script:oldestInnerVersion -Path $script:healthyPath

            $result.Threw | Should -BeFalse
            $result.LoadedPesterVersions | Should -Be @($script:oldestInnerVersion)
        }
    }
}
