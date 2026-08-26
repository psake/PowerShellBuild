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
    # Updatable help is resolved through this URI. It is a placeholder: the fixture
    # is never published, but New-HelpCabinetFile refuses to write a HelpInfo.xml
    # without one, so the cabinet tests need it present.
    HelpInfoUri       = 'https://example.com/psbuildtestfixture/help'

    PrivateData       = @{
        PSData = @{
            Tags = @('PowerShellBuild', 'TestFixture')
        }
    }
}
