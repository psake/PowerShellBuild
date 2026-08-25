@{
    RootModule        = 'TestModule.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'f6b27f39-d2fd-4620-b895-9dc1ac4e7768'
    Author            = 'Brandon Olin'
    CompanyName       = 'Community'
    Copyright         = '(c) Brandon Olin. All rights reserved.'
    Description       = 'Test module for PowerShellBuild'
    PowerShellVersion = '3.0'
    RequiredModules   = @()
    FunctionsToExport = '*'
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    # Updatable help is resolved through this URI. It is a placeholder: the fixture
    # is never published, but New-HelpCabinetFile refuses to write a HelpInfo.xml
    # without one, so the cabinet tests need it present.
    HelpInfoUri       = 'https://example.com/testmodule/help'

    PrivateData       = @{
        PSData = @{
            # Tags = @()
            # LicenseUri = ''
            # ProjectUri = ''
            # IconUri = ''
            # ReleaseNotes = ''
        }
    }
}
