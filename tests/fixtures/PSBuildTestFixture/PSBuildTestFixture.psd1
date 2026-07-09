@{
    RootModule        = 'PSBuildTestFixture.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '1bc197fe-a274-4d34-965d-862f9a8fe7b7'
    Author            = 'psake contributors'
    CompanyName       = 'Community'
    Copyright         = '(c) psake contributors. All rights reserved.'
    Description       = 'Minimal fixture module consumed by the PowerShellBuild integration tests. Not published.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-Widget'
        'Set-Widget'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('PowerShellBuild', 'TestFixture')
        }
    }
}
