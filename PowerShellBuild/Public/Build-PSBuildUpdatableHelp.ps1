function Build-PSBuildUpdatableHelp {
    <#
    .SYNOPSIS
        Create updatable help .cab file based on PlatyPS markdown help.
    .DESCRIPTION
        Create updatable help .cab file based on PlatyPS markdown help.
    .PARAMETER DocsPath
        Path to PlatyPS markdown help files.
    .PARAMETER OutputPath
        Path to create updatable help .cab file in.
    .EXAMPLE
        PS> Build-PSBuildUpdatableHelp -DocsPath ./docs -OutputPath ./Output/UpdatableHelp

        Create help .cab file based on PlatyPS markdown help.
    #>
    [cmdletbinding()]
    param(
        [parameter(Mandatory)]
        [string]$DocsPath,

        [parameter(Mandatory)]
        [string]$OutputPath
    )

    if ($null -ne $IsWindows -and -not $IsWindows) {
        Write-Warning 'MakeCab.exe is only available on Windows. Cannot create help cab.'
        return
    }

    $helpLocales = (Get-ChildItem -Path $DocsPath -Directory).Name

    # Create updatable help output directory
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item $OutputPath -ItemType Directory -Verbose:$VerbosePreference > $null
    } else {
        Write-Verbose "Directory already exists [$OutputPath]."
        Get-ChildItem $OutputPath | Remove-Item -Recurse -Force -Verbose:$VerbosePreference
    }

    # Generate updatable help files.  Note: this will currently update the version number in the module's MD
    # file in the metadata.
    foreach ($locale in $helpLocales) {
        $cabParams = @{
            CabFilesFolder  = [IO.Path]::Combine($moduleOutDir, $locale)
            LandingPagePath = "$DocsPath/$locale/$ModuleName.md"
            OutputFolder    = $OutputPath
            Verbose         = $VerbosePreference
        }
        New-ExternalHelpCab @cabParams > $null
    }
}
