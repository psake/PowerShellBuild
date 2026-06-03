@{
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseToExportFieldsInManifest'
        'PSUseDeclaredVarsMoreThanAssignments'
    )
    Rules = @{
        # Don't trip on the task alias. It's by design
        PSAvoidUsingCmdletAliases = @{
            Whitelist = @('task')
        }

        # Cross-version compatibility guardrails. PowerShellBuild still supports
        # Windows PowerShell 5.1 (Desktop) per the manifest, so these rules flag any
        # syntax, command, or type that would not work on the lowest supported engine.
        # PSUseCompatibleSyntax checks against the target language versions regardless
        # of the engine the analyzer runs under, so a PowerShell 7+-only construct (for
        # example the ternary operator) is caught even when the analyzer runs from pwsh.
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
        PSUseCompatibleCommands = @{
            Enable         = $true
            TargetProfiles = @(
                'win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
                'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core'
            )
        }
        PSUseCompatibleTypes = @{
            Enable         = $true
            TargetProfiles = @(
                'win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
                'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core'
            )
        }
    }
}
