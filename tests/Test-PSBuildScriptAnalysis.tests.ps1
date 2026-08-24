# Unit tests for Test-PSBuildScriptAnalysis (psake/PowerShellBuild#96).
#
# The tests are layered:
#
#   1. Severity gating runs against a mocked Invoke-ScriptAnalyzer so every finding/threshold
#      combination is exercised deterministically. Real analysis cannot cover the whole matrix:
#      PSScriptAnalyzer rule severities can change between releases, and no rule in the default
#      rule set reliably emits an Information record.
#   2. A smaller end-to-end layer runs the real analyzer over scripts generated into $TestDrive,
#      proving the function is actually wired to PSScriptAnalyzer and honors a settings file.
#
# The generated scripts contain deliberate analyzer violations. They are written at runtime and
# never checked in, so the repository's own script analysis can never discover them (see #97).

Describe 'Test-PSBuildScriptAnalysis' {

    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module -Name ([IO.Path]::Combine($script:moduleRoot, 'Output', 'PowerShellBuild')) -Force

        $script:cleanPath = Join-Path -Path $TestDrive -ChildPath 'clean'
        $script:errorFindingPath = Join-Path -Path $TestDrive -ChildPath 'errorfinding'
        $script:warningFindingPath = Join-Path -Path $TestDrive -ChildPath 'warningfinding'
        foreach ($directory in @($script:cleanPath, $script:errorFindingPath, $script:warningFindingPath)) {
            New-Item -Path $directory -ItemType Directory -Force > $null
        }

        # No findings under the default rule set.
        Set-Content -Path (Join-Path -Path $script:cleanPath -ChildPath 'Clean.ps1') -Value @(
            'function Get-CleanResult {'
            '    [CmdletBinding()]'
            '    param()'
            ''
            "    Write-Output -InputObject 'clean'"
            '}'
        )

        # Triggers PSAvoidUsingConvertToSecureStringWithPlainText, an Error-severity rule.
        Set-Content -Path (Join-Path -Path $script:errorFindingPath -ChildPath 'ErrorFinding.ps1') -Value @(
            'function Get-ErrorFinding {'
            '    [CmdletBinding()]'
            '    param()'
            ''
            "    ConvertTo-SecureString -String 'plaintext' -AsPlainText -Force"
            '}'
        )

        # Triggers PSAvoidUsingWriteHost, a Warning-severity rule.
        Set-Content -Path (Join-Path -Path $script:warningFindingPath -ChildPath 'WarningFinding.ps1') -Value @(
            'function Get-WarningFinding {'
            '    [CmdletBinding()]'
            '    param()'
            ''
            "    Write-Host 'warning finding'"
            '}'
        )

        # An empty settings file leaves the default rule set in place.
        $script:defaultSettingsPath = Join-Path -Path $TestDrive -ChildPath 'DefaultSettings.psd1'
        Set-Content -Path $script:defaultSettingsPath -Value '@{}'

        # Excludes the only rule the warning fixture triggers, so a settings file that is
        # actually passed through to the analyzer produces no findings at all.
        $script:excludeWriteHostSettingsPath = Join-Path -Path $TestDrive -ChildPath 'ExcludeWriteHost.psd1'
        Set-Content -Path $script:excludeWriteHostSettingsPath -Value @(
            '@{'
            "    ExcludeRules = @('PSAvoidUsingWriteHost')"
            '}'
        )
    }

    Context 'Command surface' {

        It 'Is exported by the module' {
            Get-Command -Name 'Test-PSBuildScriptAnalysis' -Module 'PowerShellBuild' -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty
        }

        It 'Has a synopsis in the help' {
            (Get-Help -Name 'Test-PSBuildScriptAnalysis').Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'Has at least one example in the help' {
            (Get-Help -Name 'Test-PSBuildScriptAnalysis').Examples.Example | Should -Not -BeNullOrEmpty
        }

        It 'Requires the Path parameter' {
            $command = Get-Command -Name 'Test-PSBuildScriptAnalysis'
            $command.Parameters['Path'].Attributes.Where({ $_.TypeId.Name -eq 'ParameterAttribute' }).Mandatory |
                Should -Contain $true
        }

        It 'Accepts only the documented severity thresholds' {
            $command = Get-Command -Name 'Test-PSBuildScriptAnalysis'
            $validateSet = $command.Parameters['SeverityThreshold'].Attributes.Where({
                    $_.TypeId.Name -eq 'ValidateSetAttribute'
                })[0]
            ($validateSet.ValidValues | Sort-Object) -join ',' | Should -Be 'Any,Error,Information,None,Warning'
        }
    }

    Context 'Severity gating' {

        # Regression coverage for the gate that never fired: the severity counts were computed
        # from $_Severity (an undefined variable) rather than $_.Severity, so every count was
        # zero and the Error, Warning, and Information thresholds could never fail a build.
        #
        # Each mock returns a single record, which PowerShell unrolls to a scalar. That also
        # guards the collection semantics the function depends on: Windows PowerShell 5.1 does
        # not expose .Where() or .Count on every scalar type, so the analyzer result has to be
        # wrapped in @() before it is inspected.

        It 'Fails when a <FindingSeverity> finding meets the <Threshold> threshold' -ForEach @(
            @{ FindingSeverity = 'Error'; Threshold = 'Error' }
            @{ FindingSeverity = 'Error'; Threshold = 'Warning' }
            @{ FindingSeverity = 'Error'; Threshold = 'Information' }
            @{ FindingSeverity = 'Warning'; Threshold = 'Warning' }
            @{ FindingSeverity = 'Warning'; Threshold = 'Information' }
            @{ FindingSeverity = 'Information'; Threshold = 'Information' }
        ) {
            $mockFindings = @(
                [PSCustomObject]@{
                    Severity   = $FindingSeverity
                    RuleName   = "Fake${FindingSeverity}Rule"
                    ScriptName = 'Fake.ps1'
                    Message    = "A fake $FindingSeverity record"
                }
            )
            Mock -CommandName 'Invoke-ScriptAnalyzer' -ModuleName 'PowerShellBuild' -MockWith {
                $mockFindings
            }.GetNewClosure()

            $testParameters = @{
                Path              = $script:cleanPath
                SeverityThreshold = $Threshold
                SettingsPath      = $script:defaultSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Throw
        }

        It 'Passes when a <FindingSeverity> finding is below the <Threshold> threshold' -ForEach @(
            @{ FindingSeverity = 'Warning'; Threshold = 'Error' }
            @{ FindingSeverity = 'Information'; Threshold = 'Error' }
            @{ FindingSeverity = 'Information'; Threshold = 'Warning' }
        ) {
            $mockFindings = @(
                [PSCustomObject]@{
                    Severity   = $FindingSeverity
                    RuleName   = "Fake${FindingSeverity}Rule"
                    ScriptName = 'Fake.ps1'
                    Message    = "A fake $FindingSeverity record"
                }
            )
            Mock -CommandName 'Invoke-ScriptAnalyzer' -ModuleName 'PowerShellBuild' -MockWith {
                $mockFindings
            }.GetNewClosure()

            $testParameters = @{
                Path              = $script:cleanPath
                SeverityThreshold = $Threshold
                SettingsPath      = $script:defaultSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Not -Throw
        }

        It 'Reports but never fails at the None threshold for a <FindingSeverity> finding' -ForEach @(
            @{ FindingSeverity = 'Error' }
            @{ FindingSeverity = 'Warning' }
            @{ FindingSeverity = 'Information' }
        ) {
            $mockFindings = @(
                [PSCustomObject]@{
                    Severity   = $FindingSeverity
                    RuleName   = "Fake${FindingSeverity}Rule"
                    ScriptName = 'Fake.ps1'
                    Message    = "A fake $FindingSeverity record"
                }
            )
            Mock -CommandName 'Invoke-ScriptAnalyzer' -ModuleName 'PowerShellBuild' -MockWith {
                $mockFindings
            }.GetNewClosure()

            $testParameters = @{
                Path              = $script:cleanPath
                SeverityThreshold = 'None'
                SettingsPath      = $script:defaultSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Not -Throw
        }

        It 'Passes at the <Threshold> threshold when the analyzer reports nothing' -ForEach @(
            @{ Threshold = 'None' }
            @{ Threshold = 'Error' }
            @{ Threshold = 'Warning' }
            @{ Threshold = 'Information' }
        ) {
            Mock -CommandName 'Invoke-ScriptAnalyzer' -ModuleName 'PowerShellBuild' -MockWith { @() }

            $testParameters = @{
                Path              = $script:cleanPath
                SeverityThreshold = $Threshold
                SettingsPath      = $script:defaultSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Not -Throw
        }

        It 'Fails on any finding when no severity threshold is supplied' {
            $mockFindings = @(
                [PSCustomObject]@{
                    Severity   = 'Information'
                    RuleName   = 'FakeInformationRule'
                    ScriptName = 'Fake.ps1'
                    Message    = 'A fake Information record'
                }
            )
            Mock -CommandName 'Invoke-ScriptAnalyzer' -ModuleName 'PowerShellBuild' -MockWith {
                $mockFindings
            }.GetNewClosure()

            $testParameters = @{
                Path         = $script:cleanPath
                SettingsPath = $script:defaultSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Throw
        }

        It 'Analyzes the supplied path recursively' {
            Mock -CommandName 'Invoke-ScriptAnalyzer' -ModuleName 'PowerShellBuild' -MockWith { @() }

            $testParameters = @{
                Path              = $script:cleanPath
                SeverityThreshold = 'Error'
                SettingsPath      = $script:defaultSettingsPath
            }
            Test-PSBuildScriptAnalysis @testParameters

            $shouldInvokeParameters = @{
                CommandName     = 'Invoke-ScriptAnalyzer'
                ModuleName      = 'PowerShellBuild'
                Times           = 1
                Exactly         = $true
                ParameterFilter = {
                    $Path -eq $script:cleanPath -and
                    $Settings -eq $script:defaultSettingsPath -and
                    $Recurse
                }
            }
            Should -Invoke @shouldInvokeParameters
        }
    }

    Context 'ParseError severity' {

        # PSScriptAnalyzer's severity enum has four members; ParseError is reported for a file
        # that does not parse at all. It was counted by none of the thresholds, so the strictest
        # validated value (Information) still let an unparsable file through: the record was
        # printed in the results table and the build passed. It is now counted with Error.

        It 'Fails at the <Threshold> threshold when a ParseError record is returned' -ForEach @(
            @{ Threshold = 'Error' }
            @{ Threshold = 'Warning' }
            @{ Threshold = 'Information' }
            @{ Threshold = 'Any' }
        ) {
            Mock -CommandName 'Invoke-ScriptAnalyzer' -ModuleName 'PowerShellBuild' -MockWith {
                [PSCustomObject]@{
                    Severity   = 'ParseError'
                    RuleName   = 'FakeParseErrorRule'
                    ScriptName = 'Unparsable.ps1'
                    Message    = 'A fake ParseError record'
                }
            }

            $testParameters = @{
                Path              = $script:cleanPath
                SeverityThreshold = $Threshold
                SettingsPath      = $script:defaultSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Throw
        }

        It 'Still reports without failing at the None threshold' {
            Mock -CommandName 'Invoke-ScriptAnalyzer' -ModuleName 'PowerShellBuild' -MockWith {
                [PSCustomObject]@{
                    Severity   = 'ParseError'
                    RuleName   = 'FakeParseErrorRule'
                    ScriptName = 'Unparsable.ps1'
                    Message    = 'A fake ParseError record'
                }
            }

            $testParameters = @{
                Path              = $script:cleanPath
                SeverityThreshold = 'None'
                SettingsPath      = $script:defaultSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Not -Throw
        }
    }

    Context 'Any threshold' {

        # 'Any' was documented in build.properties.ps1 but missing from the ValidateSet, so
        # setting it failed parameter binding instead of doing what the documentation promised.

        It 'Fails on a <FindingSeverity> finding' -ForEach @(
            @{ FindingSeverity = 'Error' }
            @{ FindingSeverity = 'Warning' }
            @{ FindingSeverity = 'Information' }
        ) {
            $mockFindings = @(
                [PSCustomObject]@{
                    Severity   = $FindingSeverity
                    RuleName   = "Fake${FindingSeverity}Rule"
                    ScriptName = 'Fake.ps1'
                    Message    = "A fake $FindingSeverity record"
                }
            )
            Mock -CommandName 'Invoke-ScriptAnalyzer' -ModuleName 'PowerShellBuild' -MockWith {
                $mockFindings
            }.GetNewClosure()

            $testParameters = @{
                Path              = $script:cleanPath
                SeverityThreshold = 'Any'
                SettingsPath      = $script:defaultSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Throw
        }

        It 'Passes when there are no findings at all' {
            Mock -CommandName 'Invoke-ScriptAnalyzer' -ModuleName 'PowerShellBuild' -MockWith { }

            $testParameters = @{
                Path              = $script:cleanPath
                SeverityThreshold = 'Any'
                SettingsPath      = $script:defaultSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Not -Throw
        }
    }

    Context 'Analyzer rule crash retry' {

        # PSScriptAnalyzer can crash a rule on an internal race unrelated to the code being
        # analyzed (psake/PowerShellBuild#147). A re-run succeeds, so a RULE_ERROR is retried.
        # A consumer with $ErrorActionPreference = 'Stop' would otherwise get a random red build.

        It 'Retries and succeeds when a rule crashes once' {
            $script:analyzerAttempt = 0
            Mock -CommandName 'Invoke-ScriptAnalyzer' -ModuleName 'PowerShellBuild' -MockWith {
                $script:analyzerAttempt++
                if ($script:analyzerAttempt -eq 1) {
                    # Non-terminating, mirroring how the real cmdlet behaves under the
                    # -ErrorAction SilentlyContinue the function passes. The mock body would
                    # otherwise inherit $ErrorActionPreference = 'Stop' and throw on attempt one.
                    $ErrorActionPreference = 'SilentlyContinue'
                    Write-Error -Message 'Object reference not set to an instance of an object.' -ErrorId 'RULE_ERROR'
                }
            }

            $testParameters = @{
                Path              = $script:cleanPath
                SeverityThreshold = 'Error'
                SettingsPath      = $script:defaultSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters -WarningAction SilentlyContinue } |
                Should -Not -Throw

            Should -Invoke -CommandName 'Invoke-ScriptAnalyzer' -ModuleName 'PowerShellBuild' -Times 2 -Exactly
        }

        It 'Gives up after three attempts and surfaces the error' {
            Mock -CommandName 'Invoke-ScriptAnalyzer' -ModuleName 'PowerShellBuild' -MockWith {
                $ErrorActionPreference = 'SilentlyContinue'
                Write-Error -Message 'Object reference not set to an instance of an object.' -ErrorId 'RULE_ERROR'
            }

            $testParameters = @{
                Path              = $script:cleanPath
                SeverityThreshold = 'Error'
                SettingsPath      = $script:defaultSettingsPath
            }
            # A persistent failure must still reach the caller, so a consumer using
            # ErrorActionPreference = 'Stop' behaves exactly as it did before the retry existed.
            { Test-PSBuildScriptAnalysis @testParameters -WarningAction SilentlyContinue -ErrorAction Stop } |
                Should -Throw

            Should -Invoke -CommandName 'Invoke-ScriptAnalyzer' -ModuleName 'PowerShellBuild' -Times 3 -Exactly
        }

        It 'Does not retry an error that is not a rule crash' {
            Mock -CommandName 'Invoke-ScriptAnalyzer' -ModuleName 'PowerShellBuild' -MockWith {
                $ErrorActionPreference = 'SilentlyContinue'
                Write-Error -Message 'Some other analyzer failure.' -ErrorId 'SOME_OTHER_ERROR'
            }

            $testParameters = @{
                Path              = $script:cleanPath
                SeverityThreshold = 'Error'
                SettingsPath      = $script:defaultSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters -ErrorAction SilentlyContinue } |
                Should -Not -Throw

            Should -Invoke -CommandName 'Invoke-ScriptAnalyzer' -ModuleName 'PowerShellBuild' -Times 1 -Exactly
        }
    }

    Context 'End-to-end analysis' {

        It 'Fails a script with an Error-severity finding at the Error threshold' {
            $testParameters = @{
                Path              = $script:errorFindingPath
                SeverityThreshold = 'Error'
                SettingsPath      = $script:defaultSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Throw
        }

        It 'Passes a script with only a Warning-severity finding at the Error threshold' {
            $testParameters = @{
                Path              = $script:warningFindingPath
                SeverityThreshold = 'Error'
                SettingsPath      = $script:defaultSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Not -Throw
        }

        It 'Fails a script with a Warning-severity finding at the Warning threshold' {
            $testParameters = @{
                Path              = $script:warningFindingPath
                SeverityThreshold = 'Warning'
                SettingsPath      = $script:defaultSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Throw
        }

        It 'Passes a script with no findings at the Error threshold' {
            $testParameters = @{
                Path              = $script:cleanPath
                SeverityThreshold = 'Error'
                SettingsPath      = $script:defaultSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Not -Throw
        }

        # Exercises the no-threshold branch against a real empty result. The analyzer returns
        # nothing rather than an empty collection when it finds no issues, so this covers the
        # $null case that a mocked empty array cannot reproduce.
        It 'Passes a script with no findings when no severity threshold is supplied' {
            $testParameters = @{
                Path         = $script:cleanPath
                SettingsPath = $script:defaultSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Not -Throw
        }
    }

    Context 'Settings file handling' {

        It 'Honors a settings file that excludes the triggered rule' {
            $testParameters = @{
                Path              = $script:warningFindingPath
                SeverityThreshold = 'Warning'
                SettingsPath      = $script:excludeWriteHostSettingsPath
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Not -Throw
        }

        # Regression: an unsupplied SettingsPath was passed to the analyzer as -Settings '',
        # which PSScriptAnalyzer resolved against the current directory and rejected, so the
        # documented example (no -SettingsPath) failed with a path error instead of analyzing.
        It 'Analyzes with the default rule set when no settings path is supplied' {
            $testParameters = @{
                Path              = $script:cleanPath
                SeverityThreshold = 'Error'
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Not -Throw
        }

        It 'Still detects findings when no settings path is supplied' {
            $testParameters = @{
                Path              = $script:errorFindingPath
                SeverityThreshold = 'Error'
            }
            { Test-PSBuildScriptAnalysis @testParameters } | Should -Throw
        }
    }
}
