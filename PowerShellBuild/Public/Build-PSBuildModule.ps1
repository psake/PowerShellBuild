function Build-PSBuildModule {
    <#
    .SYNOPSIS
        Builds a PowerShell module based on source directory
    .DESCRIPTION
        Builds a PowerShell module based on source directory and optionally concatenates
        public/private functions from separete files into monolithic .PSM1 file.
    .PARAMETER Path
        The source module path.
    .PARAMETER DestinationPath
        Destination path to write "built" module to.
    .PARAMETER ModuleName
        The name of the module.
    .PARAMETER Compile
        Switch to indicate if separete function files should be concatenated into monolithic .PSM1 file.
    .PARAMETER CompileHeader
        String that will be at the top of your PSM1 file.
    .PARAMETER CompileFooter
        String that will be added to the bottom of your PSM1 file.
    .PARAMETER CompileScriptHeader
        String that will be added to your PSM1 file before each script file.
    .PARAMETER CompileScriptFooter
        String that will be added to your PSM1 file beforeafter each script file.
    .PARAMETER ReadMePath
        Path to project README. If present, this will become the "about_<ModuleName>.help.txt" file in the build module.
    .PARAMETER CompileDirectories
        List of directories containing .ps1 files that will also be compiled into the PSM1.
    .PARAMETER CopyDirectories
        List of directories that will copying "as-is" into the build module.
    .PARAMETER Exclude
        Array of files (regular expressions) to exclude from copying into built module.
    .PARAMETER Culture
        UI Culture. This is used to determine what culture directory to store "about_<ModuleName>.help.txt" in.
    .EXAMPLE
        PS> $buildParams = @{
            Path               = ./MyModule
            DestinationPath    = ./Output/MoModule/0.1.0
            ModuleName         = MyModule
            Exclude            = @()
            Compile            = $false
            Culture            = (Get-UICulture).Name
        }
        PS> Build-PSBuildModule @buildParams

        Build module from source directory './MyModule' and save to '/Output/MoModule/0.1.0'
    #>
    [cmdletbinding()]
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
        New-Item -Path $DestinationPath -ItemType Directory -Verbose:$VerbosePreference > $null
    }

    # Copy "non-processed files"
    Get-ChildItem -Path $Path -Include '*.psm1', '*.psd1', '*.ps1xml' -Depth 1 | Copy-Item -Destination $DestinationPath -Force
    foreach ($dir in $CopyDirectories) {
        $copyPath = [IO.Path]::Combine($Path, $dir)
        Copy-Item -Path $copyPath -Destination $DestinationPath -Recurse -Force
    }

    # Copy README as about_<modulename>.help.txt
    if (-not [string]::IsNullOrEmpty($ReadMePath)) {
        $culturePath     = [IO.Path]::Combine($DestinationPath, $Culture)
        $aboutModulePath = [IO.Path]::Combine($culturePath, "about_$($ModuleName).help.txt")
        if(-not (Test-Path $culturePath -PathType Container)) {
            New-Item $culturePath -Type Directory -Force > $null
            Copy-Item -LiteralPath $ReadMePath -Destination $aboutModulePath -Force
        }
    }

    # Copy source files to destination and optionally combine *.ps1 files into the PSM1
    if ($Compile.IsPresent) {
        $rootModule = [IO.Path]::Combine($DestinationPath, "$ModuleName.psm1")

        # Grab the contents of the copied over PSM1
        # This will be appended to the end of the finished PSM1
        $psm1Contents = Get-Content -Path $rootModule -Raw
        '' | Out-File -FilePath $rootModule

        if ($CompileHeader) {
            $CompileHeader | Add-Content -Path $rootModule -Encoding utf8
        }

        $resolvedCompileDirectories = $CompileDirectories | ForEach-Object {
            [IO.Path]::Combine($Path, $_)
        }
        $allScripts = Get-ChildItem -Path $resolvedCompileDirectories -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue

        $allScripts = $allScripts | Remove-ExcludedItem -Exclude $Exclude

        $allScripts | ForEach-Object {
            $srcFile = Resolve-Path $_.FullName -Relative
            Write-Verbose "Adding [$srcFile] to PSM1"

            if ($CompileScriptHeader) {
                Write-Output $CompileScriptHeader
            }

            Get-Content $srcFile

            if ($CompileScriptFooter) {
                Write-Output $CompileScriptFooter
            }

        } | Add-Content -Path $rootModule -Encoding utf8

        $psm1Contents | Add-Content -Path $rootModule -Encoding utf8

        if ($CompileFooter) {
            $CompileFooter | Add-Content -Path $rootModule -Encoding utf8
        }
    } else{
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
        $toRemove | Remove-Item -Recurse -Force -ErrorAction Ignore
    }

    # Export public functions in manifest if there are any public functions
    $publicFunctions = Get-ChildItem $Path/Public/*.ps1 -Recurse -ErrorAction SilentlyContinue
    if ($publicFunctions) {
        $outputManifest = [IO.Path]::Combine($DestinationPath, "$ModuleName.psd1")
        Update-Metadata -Path $OutputManifest -PropertyName FunctionsToExport -Value $publicFunctions.BaseName
    }
}
