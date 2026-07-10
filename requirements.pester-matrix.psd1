# Install-only dependencies. The bootstrap in build.ps1 installs this file WITHOUT importing:
# these modules exist so the Test-PSBuildPester integration tests can pin them inside
# subprocesses, and importing a second Pester major into the bootstrap session would crash
# with a Pester.dll version conflict against the Pester version from requirements.psd1.
@{
    PSDependOptions = @{
        Target = 'CurrentUser'
    }
    # Newest Pester 5.x, installed side by side with the pinned 6.x so the shipped
    # Test-PSBuildPester function is verified against both supported majors.
    PesterLegacy    = @{
        Name       = 'Pester'
        Version    = '5.9.0'
        Parameters = @{
            SkipPublisherCheck = $true
        }
    }
}
