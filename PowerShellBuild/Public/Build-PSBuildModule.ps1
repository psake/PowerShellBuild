# spell-checker:ignore modulename
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
        "about_<ModuleName>.help.txt" file in the build module.
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

        [string[]]$CompileDirectories = @(),

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

    # Copy "non-processed files"
    $getChildItemSplat = @{
        Path    = $Path
        Include = '*.psm1', '*.psd1', '*.ps1xml'
        Depth   = 1
    }
    Get-ChildItem @getChildItemSplat |
        Copy-Item -Destination $DestinationPath -Force
    foreach ($dir in $CopyDirectories) {
        $copyPath = [IO.Path]::Combine($Path, $dir)
        Copy-Item -Path $copyPath -Destination $DestinationPath -Recurse -Force
    }

    # Copy README as about_<modulename>.help.txt
    if (-not [string]::IsNullOrEmpty($ReadMePath)) {
        $culturePath = [IO.Path]::Combine($DestinationPath, $Culture)
        $aboutModulePath = [IO.Path]::Combine(
            $culturePath,
            "about_$($ModuleName).help.txt"
        )
        if (-not (Test-Path $culturePath -PathType Container)) {
            New-Item $culturePath -Type Directory -Force > $null
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
        '' | Out-File -FilePath $rootModule -Encoding 'utf8'

        if ($CompileHeader) {
            $CompileHeader | Add-Content -Path $rootModule -Encoding 'utf8'
        }

        $resolvedCompileDirectories = $CompileDirectories | ForEach-Object {
            [IO.Path]::Combine($Path, $_)
        }
        $getChildItemSplat = @{
            Path        = $resolvedCompileDirectories
            Filter      = '*.ps1'
            File        = $true
            Recurse     = $true
            ErrorAction = 'SilentlyContinue'
        }
        $allScripts = Get-ChildItem @getChildItemSplat

        $allScripts = $allScripts | Remove-ExcludedItem -Exclude $Exclude

        $addContentSplat = @{
            Path     = $rootModule
            Encoding = 'utf8'
        }
        $allScripts | ForEach-Object {
            $srcFile = Resolve-Path $_.FullName -Relative
            Write-Verbose ($LocalizedData.AddingFileToPsm1 -f $srcFile)

            if ($CompileScriptHeader) {
                Write-Output $CompileScriptHeader
            }

            Get-Content $srcFile

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
