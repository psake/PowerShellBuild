@{
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseToExportFieldsInManifest',
        'PSUseDeclaredVarsMoreThanAssignments',
        # This throws a warning on Build verb, which is valid as of PSv6
        'PSUseApprovedVerbs'
    )
    Rules        = @{
        # Don't trip on the task alias. It's by design
        PSAvoidUsingCmdletAliases = @{
            Whitelist = @('task')
        }
    }
}
