@{
    RootModule        = 'PowerShellBuild.psm1'
    ModuleVersion     = '0.5.0'
    GUID              = '15431eb8-be2d-4154-b8ad-4cb68a488e3d'
    Author            = 'Brandon Olin'
    CompanyName       = 'Community'
    Copyright         = '(c) Brandon Olin. All rights reserved.'
    Description       = 'A common psake and Invoke-Build task module for PowerShell projects'
    PowerShellVersion = '3.0'
    RequiredModules   = @(
        @{ModuleName = 'BuildHelpers'; ModuleVersion = '2.0.16'}
        @{ModuleName = 'Pester';       ModuleVersion = '5.1.1'}
        @{ModuleName = 'platyPS';      ModuleVersion = '0.14.1'}
        @{ModuleName = 'psake';        ModuleVersion = '4.9.0'}
    )
    FunctionsToExport = @(
        'Build-PSBuildMAMLHelp'
        'Build-PSBuildMarkdown'
        'Build-PSBuildModule'
        'Build-PSBuildUpdatableHelp'
        'Clear-PSBuildOutputFolder'
        'Initialize-PSBuild'
        'Publish-PSBuildModule'
        'Test-PSBuildPester'
        'Test-PSBuildScriptAnalysis'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('*tasks')
    PrivateData       = @{
        PSData = @{
            Prerelease   = 'beta1'
            Tags         = @('psake', 'build', 'InvokeBuild')
            LicenseUri   = 'https://raw.githubusercontent.com/psake/PowerShellBuild/master/LICENSE'
            ProjectUri   = 'https://github.com/psake/PowerShellBuild'
            IconUri      = 'https://raw.githubusercontent.com/psake/PowerShellBuild/master/media/psaketaskmodule-256x256.png'
            ReleaseNotes = 'https://raw.githubusercontent.com/psake/PowerShellBuild/master/CHANGELOG.md'
        }
    }
}
