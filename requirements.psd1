@{
    PSDependOptions = @{
        Target = 'CurrentUser'
    }

    BuildHelpers     = '2.0.15'
    Pester           = @{
        Version = '5.0.2'
        Parameters = @{
            SkipPublisherCheck = $true
        }
    }
    psake            = '4.9.0'
    PSScriptAnalyzer = '1.19.0'
    InvokeBuild      = '5.5.3'
    platyPS          = '0.14.0'
}
