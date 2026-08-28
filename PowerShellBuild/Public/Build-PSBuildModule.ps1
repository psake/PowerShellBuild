# spell-checker:ignore modulename Bini Pashto
function Build-PSBuildModule {
    <#
    .SYNOPSIS
        Builds a PowerShell module based on source directory
    .DESCRIPTION
        Builds a PowerShell module based on source directory and optionally
        concatenates public/private functions from separate files into
        monolithic .PSM1 file.
    .PARAMETER Path
        The source module path.
    .PARAMETER DestinationPath
        Destination path to write "built" module to.
    .PARAMETER ModuleName
        The name of the module.
    .PARAMETER Compile
        Switch to indicate if separate function files should be concatenated
        into monolithic .PSM1 file.
    .PARAMETER CompileHeader
        String that will be at the top of your PSM1 file.
    .PARAMETER CompileFooter
        String that will be added to the bottom of your PSM1 file.
    .PARAMETER CompileScriptHeader
        String that will be added to your PSM1 file before each script file.
    .PARAMETER CompileScriptFooter
        String that will be added to your PSM1 file after each script file.
    .PARAMETER ReadMePath
        Path to project README. If present, this will become the
        "about_<ModuleName>.help.txt" file in the build module. A hand-written
        about topic in the source tree's culture directory takes precedence over
        it, in both compile and non-compile mode, and a warning reports that the
        readme was not used.
    .PARAMETER CompileDirectories
        List of directories containing .ps1 files that will also be compiled
        into the PSM1.
    .PARAMETER CopyDirectories
        List of directories that will copying "as-is" into the build module.
    .PARAMETER Exclude
        Array of files (regular expressions) to exclude from copying into built
        module.
    .PARAMETER Culture
        UI Culture. This is used to determine what culture directory to store
        "about_<ModuleName>.help.txt" in.
    .EXAMPLE
        $buildParams = @{
            Path               = ./MyModule
            DestinationPath    = ./Output/MoModule/0.1.0
            ModuleName         = MyModule
            Exclude            = @()
            Compile            = $false
            Culture            = (Get-UICulture).Name
        }
        Build-PSBuildModule @buildParams

        Build module from source directory './MyModule' and save to
        '/Output/MoModule/0.1.0'
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory)]
        [string]$Path,

        [parameter(Mandatory)]
        [string]$DestinationPath,

        [parameter(Mandatory)]
        [string]$ModuleName,

        [switch]$Compile,

        [string]$CompileHeader,

        [string]$CompileFooter,

        [string]$CompileScriptHeader,

        [string]$CompileScriptFooter,

        [string]$ReadMePath,

        # Defaulted rather than left empty. Get-ChildItem -Path @() binds nothing and
        # falls back to the current location, so -Compile with no directories recursed
        # the caller's working directory into the built module and still reported
        # success. This is the value build.properties.ps1 supplies, so a direct call now
        # behaves like the task path. See psake/PowerShellBuild#206.
        [string[]]$CompileDirectories = @('Enum', 'Classes', 'Private', 'Public'),

        [string[]]$CopyDirectories = @(),

        [string[]]$Exclude = @(),

        [string]$Culture = (Get-UICulture).Name
    )

    if (-not (Test-Path -LiteralPath $DestinationPath)) {
        $newItemSplat = @{
            Path     = $DestinationPath
            ItemType = 'Directory'
            Verbose  = $VerbosePreference
        }
        New-Item @newItemSplat > $null
    }

    # Copy "non-processed files". This stages the module's loose root files -- the manifest, the
    # root module, and any format or type data -- and nothing else. Anything below the root is
    # CopyDirectories' job, or the culture staging below.
    #
    # Both halves of this splat matter, and either one on its own is wrong. -Depth 1 implied
    # recursion one level down, so a localized en-US/Messages.psd1 matched and Copy-Item wrote it
    # flat into the output root, where nothing reads it (psake/PowerShellBuild#211). Windows
    # PowerShell 5.1 makes that worse: -Depth combined with -Include degrades to a full -Recurse
    # there, so files at any depth were flattened into the root and same-named files at different
    # depths collided. Removing -Depth alone matches nothing at all, because without recursion
    # -Include filters against the leaf of -Path rather than against that directory's children --
    # so the trailing wildcard has to be added at the same time.
    $getChildItemSplat = @{
        Path    = [IO.Path]::Combine($Path, '*')
        Include = '*.psm1', '*.psd1', '*.ps1xml'
    }
    Get-ChildItem @getChildItemSplat |
        Copy-Item -Destination $DestinationPath -Force
    foreach ($dir in $CopyDirectories) {
        $copyPath = [IO.Path]::Combine($Path, $dir)
        Copy-Item -Path $copyPath -Destination $DestinationPath -Recurse -Force
    }

    # A module's culture directory carries its localized data and its about topics. Compile mode
    # stages the loose root files and CopyDirectories and nothing else, so a hand-written
    # en-US/about_<Module>.help.txt was left behind and the built module shipped without its about
    # topic while the build reported success. Naming the culture directory in CopyDirectories was
    # the only way to ship one, and that setting reads as an escape hatch for extra content rather
    # than as the mechanism help travels by. See psake/PowerShellBuild#210.
    #
    # Non-compile mode needs none of this: the bulk copy below already brings the whole source
    # tree, culture directories included.
    if ($Compile.IsPresent) {
        foreach ($localeName in (Get-PSBuildHelpLocale -Path $Path)) {
            # Already staged verbatim by the loop above.
            if ($localeName -in $CopyDirectories) {
                continue
            }

            # Get-PSBuildHelpLocale deliberately over-reports: a directory counts as a locale when
            # its name is a culture the runtime knows, whether or not it holds any help. That is
            # the safe way to be wrong where the cost is a warning, and the unsafe way here --
            # 'bin' is a real culture name (Bini) and 'ps' is Pashto, so staging on the name alone
            # would copy a binary directory into the shipped module. Content is what decides: an
            # about topic, MAML help, or localized data is what makes a directory a culture
            # directory rather than a directory that happens to share a name with one.
            $localePath = [IO.Path]::Combine($Path, $localeName)
            $getChildItemSplat = @{
                Path        = [IO.Path]::Combine($localePath, '*')
                Include     = 'about_*.help.txt', '*-help.xml', '*.psd1'
                File        = $true
                ErrorAction = 'SilentlyContinue'
            }
            $localeContent = Get-ChildItem @getChildItemSplat | Select-Object -First 1
            if (-not $localeContent) {
                continue
            }

            Copy-Item -Path $localePath -Destination $DestinationPath -Recurse -Force
        }
    }

    # Copy README as about_<modulename>.help.txt
    if (-not [string]::IsNullOrEmpty($ReadMePath)) {
        $culturePath = [IO.Path]::Combine($DestinationPath, $Culture)
        $aboutModulePath = [IO.Path]::Combine(
            $culturePath,
            "about_$($ModuleName).help.txt"
        )

        # A hand-written about topic in the source tree wins over the readme, in both modes.
        # The two modes used to disagree by accident of statement ordering: non-compile mode's
        # bulk copy runs after this block and overwrote the readme-derived file, while in compile
        # mode the readme landed last and replaced whatever CopyDirectories had staged. Same two
        # inputs, opposite results, decided by a setting that has nothing to do with help. See
        # psake/PowerShellBuild#212.
        #
        # Source wins because no conversion happens here: this is a plain copy of the Markdown
        # readme, which satisfies none of the TOPIC and four-space-indent structure Get-Help
        # documents for an about topic. Letting the readme win would replace a conformant help
        # file with raw Markdown. Warned about rather than done silently, because
        # ConvertReadMeToAboutHelp is an explicit instruction that is not being carried out.
        #
        # Tested against the source tree, not the output: non-compile mode has not copied the
        # source about topic yet at this point, so the output cannot answer the question in
        # either mode. This is a narrower guard than the one psake/PowerShellBuild#207 removed --
        # that one skipped the copy whenever the culture *directory* existed, whatever was in it.
        $sourceAboutModulePath = [IO.Path]::Combine(
            $Path,
            $Culture,
            "about_$($ModuleName).help.txt"
        )
        if (Test-Path -LiteralPath $sourceAboutModulePath -PathType Leaf) {
            Write-Warning (
                $LocalizedData.SourceAboutTopicOverridesReadMe -f $sourceAboutModulePath, $ReadMePath
            )
        } else {
            # The guard belongs to New-Item alone. With the copy inside it, an existing
            # culture directory meant no about help file was written at all -- and
            # CopyDirectories runs above, so naming the culture directory there was enough
            # to suppress it silently. That is psake/PowerShellBuild#207. The Force below was
            # already here and unreachable; this restores the overwrite it was written for.
            if (-not (Test-Path -LiteralPath $culturePath -PathType Container)) {
                New-Item -Path $culturePath -ItemType Directory -Force > $null
            }

            $copyItemSplat = @{
                LiteralPath = $ReadMePath
                Destination = $aboutModulePath
                Force       = $true
            }
            Copy-Item @copyItemSplat
        }
    }

    # Copy source files to destination and optionally combine *.ps1 files
    # into the PSM1
    if ($Compile.IsPresent) {
        $rootModule = [IO.Path]::Combine($DestinationPath, "$ModuleName.psm1")

        # Grab the contents of the copied over PSM1
        # This will be appended to the end of the finished PSM1
        $psm1Contents = Get-Content -Path $rootModule -Raw

        # Because that content is appended last, an Export-ModuleMember call inside it runs
        # after the concatenated functions, and the module's effective export set is the
        # intersection of that call and FunctionsToExport in the manifest. Compiling copies no
        # function directories to the output, so the scaffold loader that almost every module
        # template generates discovers nothing and exports nothing, while the manifest still
        # names every public function and the build still succeeds. Warned about rather than
        # rewritten: what the consumer's root module should do instead depends on the module.
        # See psake/PowerShellBuild#201.
        #
        # Found by parsing rather than by matching text, so that the command named in a
        # comment or quoted in a here-string -- including a comment explaining why the loader
        # deliberately does not call it -- is not reported as a call. A line-anchored regex
        # gets the single-line # comment right and still fires inside a <# #> block or a
        # here-string, because it cannot see that the line it anchored on is not code.
        $rootModuleAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $psm1Contents, [ref] $null, [ref] $null
        )
        $exportModuleMemberCall = $rootModuleAst.FindAll(
            {
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Export-ModuleMember'
            },
            $true
        )
        if ($exportModuleMemberCall) {
            $sourceRootModule = [IO.Path]::Combine($Path, "$ModuleName.psm1")
            Write-Warning (
                $LocalizedData.ExportModuleMemberInSourceRootModule -f $sourceRootModule
            )
        }

        '' | Out-File -FilePath $rootModule -Encoding 'utf8'

        if ($CompileHeader) {
            $CompileHeader | Add-Content -Path $rootModule -Encoding 'utf8'
        }

        $resolvedCompileDirectories = $CompileDirectories | ForEach-Object {
            [IO.Path]::Combine($Path, $_)
        }
        # An empty compile list leaves -Path null, and Get-ChildItem treats null or empty as
        # "not supplied" and falls back to the current location -- so this would recurse the
        # working directory and concatenate every .ps1 under it into the root module, while
        # the build reported success. PowerShell/PowerShell#17793 is Won't Fix, with the
        # working group's advice being to validate in the caller, so the guard belongs here.
        #
        # The parameter default covers an omitted argument. This covers an explicit empty
        # array, which is what both task files forward when a consumer sets
        # $PSBPreference.Build.CompileDirectories = @(). See psake/PowerShellBuild#206.
        $allScripts = @()
        if ($resolvedCompileDirectories) {
            $getChildItemSplat = @{
                Path        = $resolvedCompileDirectories
                Filter      = '*.ps1'
                File        = $true
                Recurse     = $true
                ErrorAction = 'SilentlyContinue'
            }
            $allScripts = Get-ChildItem @getChildItemSplat
        }

        # Compiling to an empty set produces a root module holding only its header, the
        # appended source .psm1, and its footer -- a plausible artifact with every function
        # missing. Warned about rather than treated as an error: wrapping an already-complete
        # .psm1 in a header and footer is a coherent thing to ask for.
        if (-not $allScripts) {
            Write-Warning ($LocalizedData.NoScriptsToCompile -f ($CompileDirectories -join ', '))
        }

        $allScripts = $allScripts | Remove-ExcludedItem -Exclude $Exclude

        $addContentSplat = @{
            Path     = $rootModule
            Encoding = 'utf8'
        }
        $allScripts | ForEach-Object {
            # Read through the full path. This used to read through a path resolved relative to
            # the current location, which is not something every current location can express.
            # On Windows PowerShell 5.1 a source file on another drive resolves to a path like
            # .\C:\src\Public\Get-Widget.ps1, and a source outside the current PSDrive's root to
            # a ..\ path that cannot climb past that root. Neither can be read back, so
            # Get-Content silently returned nothing for every file and the compiled .psm1 came
            # out holding its headers and footers and none of the functions -- while the build
            # reported success. It is reachable whenever the build runs from a different drive
            # than the module source, which is how the Windows PowerShell 5.1 CI job is laid out.
            $sourceFilePath = $_.FullName
            Write-Verbose ($LocalizedData.AddingFileToPsm1 -f $sourceFilePath)

            if ($CompileScriptHeader) {
                Write-Output $CompileScriptHeader
            }

            # -LiteralPath, not -Path: the value is a FullName, and -Path reads [ ] * ? as
            # wildcards. A source file named Get-Widget[1].ps1, or any checkout under a
            # directory like repo[main], would then match nothing and be dropped from the
            # compiled module in silence -- the same failure this full-path read exists to
            # prevent, reached a different way.
            Get-Content -LiteralPath $sourceFilePath

            if ($CompileScriptFooter) {
                Write-Output $CompileScriptFooter
            }
        } | Add-Content @addContentSplat

        $psm1Contents | Add-Content @addContentSplat

        if ($CompileFooter) {
            $CompileFooter | Add-Content @addContentSplat
        }
    } else {
        # Copy everything over, then remove stuff that should have been excluded
        # It's just easier this way
        $copyParams = @{
            Path        = [IO.Path]::Combine($Path, '*')
            Destination = $DestinationPath
            Recurse     = $true
            Force       = $true
            Verbose     = $VerbosePreference
        }
        Copy-Item @copyParams
        $allItems = Get-ChildItem -Path $DestinationPath -Recurse
        $toRemove = foreach ($item in $allItems) {
            foreach ($regex in $Exclude) {
                if ($item -match $regex) {
                    $item
                }
            }
        }
        $toRemove | Remove-Item -Recurse -Force -ErrorAction 'Ignore'
    }

    # Export public functions in manifest if there are any public functions
    $getChildItemSplat = @{
        Recurse     = $true
        ErrorAction = 'SilentlyContinue'
        Path        = "$Path/Public/*.ps1"
    }
    $publicFunctions = Get-ChildItem @getChildItemSplat
    if ($publicFunctions) {
        $outputManifest = [IO.Path]::Combine(
            $DestinationPath,
            "$ModuleName.psd1"
        )
        $updateMetadataSplat = @{
            Path         = $OutputManifest
            PropertyName = 'FunctionsToExport'
            Value        = $publicFunctions.BaseName
        }
        Update-Metadata @updateMetadataSplat
    }
}
