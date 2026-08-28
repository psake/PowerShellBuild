function Build-PSBuildMarkdown {
    <#
    .SYNOPSIS
        Creates PlatyPS markdown documents based on comment-based help of module.
    .DESCRIPTION
        Creates PlatyPS markdown documents based on comment-based help of module.

        Existing command markdown is refreshed in place with Update-MarkdownCommandHelp so
        hand-written prose survives, and markdown for commands that have no document yet is
        generated with New-MarkdownCommandHelp.
    .PARAMETER ModulePath
        The path to the module
    .PARAMETER ModuleName
        The name of the module.
    .PARAMETER DocsPath
        The path where PlatyPS markdown docs will be saved.
    .PARAMETER Locale
        The locale to save the markdown docs.
    .PARAMETER Overwrite
        Overwrite existing markdown files and use comment based help as the source of truth.
    .PARAMETER ExcludeDontShow
        Exclude the parameters marked with `DontShow` in the parameter attribute from the help content.
    .PARAMETER UseFullTypeName
        Indicates that the target document will use a full type name instead of a short name for parameters.
    .EXAMPLE
        PS> Build-PSBuildMarkdown -ModulePath ./output/MyModule/0.1.0 -ModuleName MyModule -DocsPath ./docs -Locale en-US

        Analysis the comment-based help of the MyModule module and create markdown documents under ./docs/en-US.
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory)]
        [string]$ModulePath,

        [parameter(Mandatory)]
        [string]$ModuleName,

        [parameter(Mandatory)]
        [string]$DocsPath,

        [parameter(Mandatory)]
        [string]$Locale,

        [parameter(Mandatory)]
        [bool]$Overwrite,

        [parameter(Mandatory)]
        [bool]$ExcludeDontShow,

        [parameter(Mandatory)]
        [bool]$UseFullTypeName
    )

    # Record every copy of the module the caller already had loaded, so the finally block can
    # put the session back the way it was found. Two separate things reach a caller's module
    # otherwise: -Force evicts a copy loaded from this same path before the finally block is
    # ever reached, and the removal that used to run there was by name, which takes every
    # loaded copy regardless of who imported it or from where (psake/PowerShellBuild#221).
    #
    # -Force nevertheless stays. Without it, importing an already-loaded module is a no-op that
    # returns the cached PSModuleInfo, so ExportedCommands would describe the previous build's
    # command surface and the generated markdown would silently document a stale module.
    #
    # -Global is deliberately absent. Microsoft.PowerShell.PlatyPS resolves the module through
    # the PSModuleInfo passed as -ModuleInfo below rather than by name, so it never performs a
    # session-state lookup that -Global would serve. The generated markdown is byte-for-byte
    # identical without it, and the import stops reaching into the caller's session state.
    $previouslyLoadedModule = @(Get-Module -Name $ModuleName)
    $moduleInfo = Import-Module "$ModulePath/$ModuleName.psd1" -Force -PassThru

    try {
        if ($moduleInfo.ExportedCommands.Count -eq 0) {
            Write-Warning $LocalizedData.NoCommandsExported
            return
        }

        $localePath = [IO.Path]::Combine($DocsPath, $Locale)
        if (-not (Test-Path -LiteralPath $localePath)) {
            New-Item -Path $localePath -ItemType Directory -Force > $null
        }

        # Refresh first. Update-MarkdownCommandHelp merges the module's current surface into
        # existing documents and preserves hand-written prose, where regenerating would
        # discard it. -NoBackup keeps it from littering the docs tree with .md.bak files.
        # Module landing pages are a different document type and are left alone.
        $existingMarkdown = @(
            Get-ChildItem -LiteralPath $localePath -Filter '*.md' -File -ErrorAction SilentlyContinue
        )
        if ($existingMarkdown.Count -gt 0) {
            $existingCommandMarkdown = @(
                $existingMarkdown.Where({
                        (Measure-PlatyPSMarkdown -LiteralPath $_.FullName).Filetype -match 'CommandHelp'
                    })
            )
            if ($existingCommandMarkdown.Count -gt 0) {
                Update-MarkdownCommandHelp -LiteralPath $existingCommandMarkdown.FullName -NoBackup > $null
            }
        }

        # New-MarkdownCommandHelp always writes to <OutputFolder>/<ModuleName>, and without
        # -Force it skips existing files with a warning rather than an error. Generating into
        # an empty staging directory and moving the results keeps the documented
        # <DocsPath>/<Locale> layout and keeps Overwrite meaning what it did before.
        $stagingPath = [IO.Path]::Combine(
            [IO.Path]::GetTempPath(),
            [IO.Path]::GetRandomFileName()
        )
        try {
            $newMarkdownParams = @{
                ModuleInfo   = $moduleInfo
                OutputFolder = $stagingPath
                Locale       = $Locale
                # The landing page is what carries the module GUID, locale, and help
                # version into the updatable-help cabinet. 0.14.x never produced one,
                # which is why Build-PSBuildUpdatableHelp could not work.
                WithModulePage = $true
                # PlatyPS 1.x defaults this front matter key to "<Module>-Help.xml", where
                # 0.14.x wrote "<Module>-help.xml". The key is what Export-MamlCommandHelp
                # names the MAML file after, so pinning it here keeps the markdown, the MAML
                # file name, and any existing .ExternalHelp directive in agreement -- and
                # keeps help resolving on case-sensitive file systems. Renaming after export
                # would fix the file name while leaving the front matter disagreeing with it.
                Metadata     = @{ 'external help file' = "$ModuleName-help.xml" }
                # Compared explicitly rather than passing $VerbosePreference through. The
                # preference is an ActionPreference, and converting it to a switch uses the
                # underlying number, so Stop and Inquire turn verbose output on even though
                # neither asked for it.
                Verbose      = ($VerbosePreference -eq 'Continue')
            }
            if ($ExcludeDontShow) {
                $newMarkdownParams.ExcludeDontShow = $true
            }
            # The sense of this option inverted in PlatyPS 1.x: full type names are now the
            # default and abbreviation is the switch, so the old setting maps to its absence.
            if (-not $UseFullTypeName) {
                $newMarkdownParams.AbbreviateParameterTypeName = $true
            }
            New-MarkdownCommandHelp @newMarkdownParams > $null

            $generatedPath = [IO.Path]::Combine($stagingPath, $ModuleName)
            $generatedMarkdown = @(
                Get-ChildItem -LiteralPath $generatedPath -Filter '*.md' -File -ErrorAction SilentlyContinue
            )
            foreach ($markdownFile in $generatedMarkdown) {
                $destinationPath = Join-Path -Path $localePath -ChildPath $markdownFile.Name
                $isModuleLandingPage = $markdownFile.BaseName -eq $ModuleName

                # The landing page is always replaced. It is generated content -- an index of
                # the module's commands, plus the module GUID and locale that the cabinet step
                # stamps its .cab name from -- so a copy left in place goes stale the moment a
                # command is added or removed. PlatyPS has no refresh that would preserve an
                # edited body either: Update-MarkdownModuleFile rewrites it wholesale. Command
                # help is different, and is skipped here because it was already refreshed in
                # place above, where hand-written prose survives.
                if (-not $isModuleLandingPage -and (Test-Path -LiteralPath $destinationPath) -and -not $Overwrite) {
                    continue
                }

                Move-Item -LiteralPath $markdownFile.FullName -Destination $destinationPath -Force
            }
        } finally {
            Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Error ($LocalizedData.FailedToGenerateMarkdownHelp -f $_)
    } finally {
        # Remove only the instance this function imported. The zero-export path above returns
        # from inside the try block, which still runs this, so a module with no exported
        # commands generates nothing and leaves the caller's session untouched all the same.
        Remove-Module -ModuleInfo $moduleInfo -Force -ErrorAction SilentlyContinue

        # Restored into the global session state, because that is where a caller's copy lives.
        # An import issued from inside this module without -Global would only reach
        # PowerShellBuild's own session state, and the caller would still see nothing.
        foreach ($restoredModule in $previouslyLoadedModule) {
            Import-Module -ModuleInfo $restoredModule -Global -ErrorAction SilentlyContinue
        }
    }
}
