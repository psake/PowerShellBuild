@{
    PSDependOptions = @{
        Target = 'CurrentUser'
    }

    BuildHelpers     = 'latest'
    Pester           = @{
        Version = '4.10.1'
        Parameters = @{
            SkipPublisherCheck = $true
        }
    }
    psake            = 'latest'
    PSScriptAnalyzer = 'latest'
    InvokeBuild      = 'latest'
    platyPS          = 'latest'
}
