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
    }
}
