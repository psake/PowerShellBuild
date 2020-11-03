function Build-PSBuildMAMLHelp {
    <#
    .SYNOPSIS
        Builds PowerShell MAML XML help file from PlatyPS markdown files
    .DESCRIPTION
        Builds PowerShell MAML XML help file from PlatyPS markdown files
    .PARAMETER Path
        The path to the PlatyPS markdown documents.
    .PARAMETER DestinationPath
        The path to the output module directory.
    .EXAMPLE
        PS> Build-PSBuildMAMLHelp -Path ./docs -Destination ./output/MyModule

        Uses PlatyPS to generate MAML XML help from markdown files in ./docs
        and saves the XML file to a directory under ./output/MyModule
    #>
    [cmdletbinding()]
    param(
        [parameter(Mandatory)]
        [string]$Path,

        [parameter(Mandatory)]
        [string]$DestinationPath
    )

    $helpLocales = (Get-ChildItem -Path $Path -Directory).Name

    # Generate the module's primary MAML help file
    foreach ($locale in $helpLocales) {
        $externalHelpParams = @{
            Path        = [IO.Path]::Combine($Path, $locale)
            OutputPath  = [IO.Path]::Combine($DestinationPath, $locale)
            Force       = $true
            ErrorAction = 'SilentlyContinue'
            Verbose     = $VerbosePreference
        }
        New-ExternalHelp @externalHelpParams > $null
    }
}
