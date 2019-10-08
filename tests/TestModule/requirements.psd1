@{
    PSDependOptions = @{
        Target = 'CurrentUser'
    }
    'InvokeBuild' = @{
        Version = '5.5.1'
    }
    'Pester' = @{
        Version = '4.8.1'
        Parameters = @{
            SkipPublisherCheck = $true
        }
    }
    'psake' = @{
        Version = '4.8.0'
    }
    'BuildHelpers' = @{
        Version = '2.0.10'
    }
    'PowerShellBuild' = @{
        Version = '0.5.0'
    }
}
