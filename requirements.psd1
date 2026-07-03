@{
    PSDependOptions  = @{
        Target = 'CurrentUser'
    }
    BuildHelpers     = '2.0.16'
    Pester           = @{
        Version    = '5.8.0'
        Parameters = @{
            SkipPublisherCheck = $true
        }
    }
    psake            = '4.9.0'
    PSScriptAnalyzer = '1.25.0'
    InvokeBuild      = '5.8.1'
    platyPS          = '0.14.2'
}
