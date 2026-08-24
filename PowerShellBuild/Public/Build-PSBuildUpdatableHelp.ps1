function Build-PSBuildUpdatableHelp {
    <#
    .SYNOPSIS
        Create updatable help .cab file based on PlatyPS markdown help.
    .DESCRIPTION
        Create updatable help .cab file based on PlatyPS markdown help.

        Not implemented against PlatyPS 1.x yet. The cabinet pipeline is migrated in
        psake/PowerShellBuild#152 along with the three defects in #169 that prevented this
        function from ever succeeding. Until then it reports that updatable help was skipped
        and returns without writing anything.
    .PARAMETER DocsPath
        Path to PlatyPS markdown help files.
    .PARAMETER OutputPath
        Path to create updatable help .cab file in.
    .PARAMETER Module
        Name of the module to create a .cab file for. Defaults to the
        $ModuleName variable from the parent scope.
    .EXAMPLE
        PS> Build-PSBuildUpdatableHelp -DocsPath ./docs -OutputPath ./Output/UpdatableHelp

        Reports that updatable help is not available and returns.
    #>
    # The parameters are unused only because the body is stubbed. They stay so the public
    # signature does not change twice -- once here and again when #152 restores the body.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    [CmdletBinding()]
    param(
        [parameter(Mandatory)]
        [string]$DocsPath,

        [parameter(Mandatory)]
        [string]$OutputPath,

        [string]$Module = $ModuleName
    )

    # Deliberately references no PlatyPS command. Naming New-ExternalHelpCab here is enough to
    # make PowerShell autoload platyPS 0.14.2 on any session that resolves it, and once that
    # module is loaded, Microsoft.PowerShell.PlatyPS can no longer be imported in the same
    # process -- both ship their own YamlDotNet with different assembly identities. Leaving the
    # old call in place would poison every session that still has 0.14.2 installed, which is
    # every consumer part-way through the upgrade.
    Write-Warning $LocalizedData.UpdatableHelpNotMigrated
}
