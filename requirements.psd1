@{
    PSDependOptions = @{
        Target = 'CurrentUser'
    }
    BuildHelpers     = '2.0.16'
    Pester           = @{
        MinimumVersion = '5.6.1'
        Parameters = @{
            SkipPublisherCheck = $true
        }
    }
    psake            = '4.9.0'
    PSScriptAnalyzer = '1.19.1'
    InvokeBuild      = '5.8.1'
    platyPS          = '0.14.2'
}
