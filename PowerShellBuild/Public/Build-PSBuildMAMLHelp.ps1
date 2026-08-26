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
    [CmdletBinding()]
    param(
        [parameter(Mandatory)]
        [string]$Path,

        [parameter(Mandatory)]
        [string]$DestinationPath
    )

    $helpLocales = (Get-ChildItem -Path $Path -Directory).Name

    # Generate the module's primary MAML help file
    foreach ($locale in $helpLocales) {
        $localePath = [IO.Path]::Combine($Path, $locale)

        # Only command documents can be exported. A module landing page imports without
        # complaint but fails on export, and that failure aborts the whole batch and writes
        # nothing, so it has to be filtered out rather than caught.
        $commandMarkdownPath = @(
            Measure-PlatyPSMarkdown -Path ([IO.Path]::Combine($localePath, '*.md')) |
                Where-Object { $_.Filetype -match 'CommandHelp' } |
                Select-Object -ExpandProperty 'FilePath'
        )
        if ($commandMarkdownPath.Count -eq 0) {
            continue
        }

        # Export-MamlCommandHelp writes to <OutputFolder>/<ModuleName>/<external help file>,
        # a level deeper than PowerShell looks and with the file name taken from the
        # document's front matter. Export to a staging directory and move the results so the
        # published layout stays <DestinationPath>/<locale>/<ModuleName>-help.xml, which is
        # where every consumer's existing .ExternalHelp directive already points.
        $stagingPath = [IO.Path]::Combine(
            [IO.Path]::GetTempPath(),
            [IO.Path]::GetRandomFileName()
        )
        try {
            $mamlFile = @(
                Import-MarkdownCommandHelp -Path $commandMarkdownPath |
                    Export-MamlCommandHelp -OutputFolder $stagingPath -Force -Verbose:($VerbosePreference -eq 'Continue')
            )

            $localeDestinationPath = [IO.Path]::Combine($DestinationPath, $locale)
            if (-not (Test-Path -LiteralPath $localeDestinationPath)) {
                New-Item -Path $localeDestinationPath -ItemType Directory -Force > $null
            }

            foreach ($file in $mamlFile) {
                # The file name is whatever the document's "external help file" front matter
                # says, which Build-PSBuildMarkdown pins to the 0.14.x casing. Renaming here
                # instead would leave the markdown and the MAML disagreeing about the name.
                $destinationFilePath = Join-Path -Path $localeDestinationPath -ChildPath $file.Name
                Move-Item -LiteralPath $file.FullName -Destination $destinationFilePath -Force
            }
        } finally {
            Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
