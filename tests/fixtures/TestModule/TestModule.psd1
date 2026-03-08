@{
    RootModule        = 'TestModule.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '9dc6c759-5ea0-4d9e-9392-947de76810f2'
    Author            = 'PowerShellBuild Contributors'
    CompanyName       = 'Community'
    Copyright         = '(c) PowerShellBuild Contributors. All rights reserved.'
    Description       = 'Minimal shared fixture module for integration tests.'
    PowerShellVersion = '3.0'
    RequiredModules   = @()
    FunctionsToExport = @('Get-TestFixtureMessage')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('tests','fixtures')
        }
    }
}
