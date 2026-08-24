# Install-only dependencies. The bootstrap in build.ps1 installs this file WITHOUT importing.
#
# Every entry here exists because importing it into the bootstrap session would break that
# session: two majors of the same module, or two modules that ship conflicting copies of the
# same assembly. They are installed so that tests and build tasks can load them deliberately,
# in a subprocess or at the point of use, rather than implicitly at bootstrap.
@{
    PSDependOptions = @{
        Target = 'CurrentUser'
    }

    # Newest Pester 5.x, installed side by side with the pinned 6.x so the shipped
    # Test-PSBuildPester function is verified against both supported majors. Importing a
    # second Pester major into this session would crash with a Pester.dll version conflict
    # against the Pester version from requirements.psd1.
    PesterLegacy    = @{
        Name       = 'Pester'
        Version    = '5.9.0'
        Parameters = @{
            SkipPublisherCheck = $true
        }
    }

    # PlatyPS 1.x, installed side by side with the platyPS 0.14.2 pin in requirements.psd1
    # for the migration in psake/PowerShellBuild#105. Both modules load their own copy of
    # YamlDotNet.dll through NestedModules, with different assembly identities -- 0.0.0.0
    # unsigned in platyPS 0.14.2, 15.0.0.0 signed here -- so whichever imports second fails
    # with "Assembly with same name is already loaded". The failure is symmetric: neither
    # import order works on PowerShell 7, and only a separate process escapes it.
    #
    # This entry is temporary. It moves into requirements.psd1 when the old module is
    # removed in psake/PowerShellBuild#153 and only one PlatyPS remains.
    PlatyPSNext     = @{
        Name    = 'Microsoft.PowerShell.PlatyPS'
        Version = '1.0.3'
    }
}
