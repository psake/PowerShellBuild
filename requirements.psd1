@{
    PSDependOptions  = @{
        Target = 'CurrentUser'
    }
    BuildHelpers     = '2.0.16'
    Pester           = @{
        Version    = '6.0.0'
        Parameters = @{
            SkipPublisherCheck = $true
        }
    }
    # Newest Pester 5.x, installed side by side with 6.0.0 so the Test-PSBuildPester
    # integration tests can verify the shipped function against both supported majors.
    PesterLegacy     = @{
        Name       = 'Pester'
        Version    = '5.9.0'
        Parameters = @{
            SkipPublisherCheck = $true
        }
    }
    psake            = '4.9.0'
    PSScriptAnalyzer = '1.25.0'
    InvokeBuild      = '5.8.1'
    platyPS          = '0.14.2'
}
