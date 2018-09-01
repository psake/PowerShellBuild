@{
    RootModule        = 'PowerShellBuild.Common'
    ModuleVersion     = '0.1.0'
    GUID              = '15431eb8-be2d-4154-b8ad-4cb68a488e3d'
    Author            = 'Brandon Olin'
    CompanyName       = 'Community'
    Copyright         = '(c) Brandon Olin. All rights reserved.'
    Description       = 'A common psake and Invoke-Build task module for PowerShell projects'
    PowerShellVersion = '3.0'
    RequiredModules   = @('BuildHelpers')
    FunctionsToExport = '*'
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('*tasks')
    PrivateData       = @{
        PSData = @{
            Tags         = @('psake', 'build')
            LicenseUri   = 'https://raw.githubusercontent.com/psake/PowerShellBuild.Common/master/LICENSE'
            ProjectUri   = 'https://github.com/psake/PowerShellBuild.Common'
            IconUri      = 'https://raw.githubusercontent.com/psake/PowerShellBuild.Common/master/media/psaketaskmodule-256x256.png'
            ReleaseNotes = 'https://raw.githubusercontent.com/psake/PowerShellBuild.Common/master/CHANGELOG.md'
        }
    }
}
