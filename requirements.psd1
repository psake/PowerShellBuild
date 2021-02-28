@{
    PSDependOptions = @{
        Target = 'CurrentUser'
    }

    BuildHelpers     = '2.0.16'
    Pester           = @{
        MinimumVersion = '5.1.1'
        Parameters = @{
            SkipPublisherCheck = $true
        }
    }
    psake            = '4.9.0'
    PSScriptAnalyzer = '1.19.0'
    InvokeBuild      = '5.5.3'
    platyPS          = '0.14.1'
}
