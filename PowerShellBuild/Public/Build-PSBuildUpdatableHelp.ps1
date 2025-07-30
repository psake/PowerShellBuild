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
    .PARAMETER Module
        Name of the module to create a .cab file for. Defaults to the
        $ModuleName variable from the parent scope.
    .EXAMPLE
        PS> Build-PSBuildUpdatableHelp -DocsPath ./docs -OutputPath ./Output/UpdatableHelp

        Create help .cab file based on PlatyPS markdown help.
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory)]
        [string]$DocsPath,

        [parameter(Mandatory)]
        [string]$OutputPath,

        [string]$Module = $ModuleName
    )

    if ($null -ne $IsWindows -and -not $IsWindows) {
        Write-Warning $LocalizedData.MakeCabNotAvailable
        return
    }

    $helpLocales = (Get-ChildItem -Path $DocsPath -Directory).Name

    # Create updatable help output directory
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        $newItemSplat = @{
            ItemType = 'Directory'
            Verbose  = $VerbosePreference
            Path     = $OutputPath
        }
        New-Item @newItemSplat > $null
    } else {
        Write-Verbose ($LocalizedData.DirectoryAlreadyExists -f $OutputPath)
        $removeItemSplat = @{
            Recurse = $true
            Force   = $true
            Verbose = $VerbosePreference
        }
        Get-ChildItem $OutputPath | Remove-Item @removeItemSplat
    }

    # Generate updatable help files. Note: this will currently update the
    # version number in the module's MD file in the metadata.
    foreach ($locale in $helpLocales) {
        $cabParams = @{
            CabFilesFolder  = [IO.Path]::Combine($moduleOutDir, $locale)
            LandingPagePath = [IO.Path]::Combine(
                $DocsPath,
                $locale,
                "$Module.md"
            )
            OutputFolder    = $OutputPath
            Verbose         = $VerbosePreference
        }
        New-ExternalHelpCab @cabParams > $null
    }
}
