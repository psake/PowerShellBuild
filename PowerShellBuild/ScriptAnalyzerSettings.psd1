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

        # Cross-version compatibility guardrail. PowerShellBuild still supports Windows
        # PowerShell 5.1 (Desktop) per the manifest, so this flags syntax that would not
        # parse on the lowest supported engine. PSUseCompatibleSyntax checks against the
        # target language versions regardless of the engine the analyzer runs under, so a
        # PowerShell 7+-only construct (for example the ternary operator) is caught even
        # when the analyzer runs from pwsh.
        #
        # The profile-based PSUseCompatibleCommands / PSUseCompatibleTypes rules are
        # intentionally NOT enabled here: they produced false positives on this codebase
        # (provider dynamic parameters and required-module commands) and intermittently
        # threw a NullReferenceException inside Invoke-ScriptAnalyzer on some platforms,
        # which aborts the whole analysis. Core-only cmdlet/type usage is instead covered
        # by the Windows PowerShell 5.1 import-smoke CI job.
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
    }
}
