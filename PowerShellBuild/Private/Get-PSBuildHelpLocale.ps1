function Get-PSBuildHelpLocale {
    <#
    .SYNOPSIS
        Return the directories under a docs path that are help locales.
    .DESCRIPTION
        The docs path is the conventional home for a project's documentation, not just its
        generated help, so it commonly holds directories that were never meant for PlatyPS --
        images, guides, an api folder. Treating every subdirectory as a help locale makes the
        help tasks report on directories the consumer never offered them, which is
        psake/PowerShellBuild#124.

        A directory is reported as a locale when either signal holds:

        - Its name is a culture the runtime knows. This is the ordinary case and needs
          nothing from a previous build.
        - Built help already exists for it under ModulePath. Windows PowerShell 5.1 knows a
          smaller set of cultures than PowerShell 7 -- zh-Hans-CN, for one, is absent -- so
          the name test alone would drop a working locale on the older host. Output from the
          MAML step is proof the directory is a locale regardless of what the culture table
          says.

        Neither signal is a guarantee: a directory named for one of the three-letter language
        codes is reported as a locale even if it holds no help at all. That is the safe way to
        be wrong. Callers already handle a locale that turns out to have nothing to build, and
        over-reporting costs a warning where under-reporting silently drops a consumer's help.
    .PARAMETER Path
        Path to the docs tree whose subdirectories are being classified.
    .PARAMETER ModulePath
        Path to the built module. Its subdirectories are the locales the MAML step has
        already written help for. Optional; without it only the culture name test applies.
    .EXAMPLE
        PS> Get-PSBuildHelpLocale -Path ./docs -ModulePath ./Output/MyModule/1.0.0

        Returns en-US from a docs tree holding en-US, images, and guides.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [string]
        $ModulePath
    )

    # Enumerated once per session rather than per call. The table does not change while the
    # process is running and building it is the expensive part of this function.
    if ($null -eq $script:PSBuildKnownCultureName) {
        $script:PSBuildKnownCultureName = [System.Globalization.CultureInfo]::GetCultures(
            [System.Globalization.CultureTypes]::AllCultures
        ).Name
    }

    foreach ($directory in (Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue)) {
        # -in is case insensitive, which matters on case sensitive file systems where a docs
        # tree may well be committed as en-us.
        if ($directory.Name -in $script:PSBuildKnownCultureName) {
            $directory.Name
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($ModulePath)) {
            $builtHelpPath = [IO.Path]::Combine($ModulePath, $directory.Name)
            if (Test-Path -LiteralPath $builtHelpPath -PathType Container) {
                $directory.Name
            }
        }
    }
}
