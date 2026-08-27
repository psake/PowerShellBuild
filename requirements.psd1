@{
    PSDependOptions  = @{
        Target = 'CurrentUser'
    }
    BuildHelpers     = '2.0.16'
    Pester           = @{
        Version    = '6.1.0'
        Parameters = @{
            SkipPublisherCheck = $true
        }
    }
    psake            = '5.0.4'
    PSScriptAnalyzer = '1.25.0'
    InvokeBuild      = '5.14.23'
    PlatyPS          = @{
        Name    = 'Microsoft.PowerShell.PlatyPS'
        Version = '1.0.3'
    }
}
