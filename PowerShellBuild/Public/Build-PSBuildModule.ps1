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
    .PARAMETER ModuleManifestPath
        The path of the module manifest.
    .PARAMETER Compile
        Switch to indicate if separete function files should be concatenated into monolithic .PSM1 file.
    .PARAMETER ReadMePath
        Path to project README. If present, this will become the "about_<ModuleName>.help.txt" file in the build module.
    .PARAMETER Exclude
        Array of files to exclude from copying into built module.
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

        [string]$ModuleManifestPath,

        [switch]$Compile,

        [string]$ReadMePath,

        [string[]]$Exclude = @(),

        [string]$Culture = (Get-UICulture).Name
    )

    if (-not (Test-Path -LiteralPath $DestinationPath)) {
        New-Item -Path $DestinationPath -ItemType Directory -Verbose:$VerbosePreference > $null
    }

    # Copy "non-processed files"
    Get-ChildItem -Path $Path -Include '*.psm1', '*.psd1', '*.ps1xml' -Depth 1 | Copy-Item -Destination $DestinationPath -Force

    # Copy README as about_<modulename>.help.txt
    if (-not [string]::IsNullOrEmpty($ReadMePath)) {
        $culturePath = Join-Path -Path $DestinationPath -ChildPath $Culture
        $aboutModulePath = Join-Path -Path $culturePath -ChildPath "about_$($ModuleName).help.txt"
        if(-not (Test-Path $culturePath -PathType Container)) {
            New-Item $culturePath -Type Directory -Force > $null
            Copy-Item -LiteralPath $ReadMePath -Destination $aboutModulePath -Force
        }
    }

    # Copy source files to destination and optionally combine *.ps1 files into the PSM1
    if ($Compile.IsPresent) {
        $rootModule = Join-Path -Path $DestinationPath -ChildPath "$ModuleName.psm1"
        $allScripts = Get-ChildItem -Path $Path -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue
        $allScripts | ForEach-Object {
            $srcFile = Resolve-Path $_.FullName -Relative
            Write-Verbose "Adding $srcFile to PSM1"
            Get-Content $srcFile
        } | Add-Content -Path $rootModule -Encoding utf8
    } else{
        $copyParams = @{
            Path        = (Join-Path -Path $Path -ChildPath '*')
            Destination = $DestinationPath
            Recurse     = $true
            Exclude     = $Exclude
            Force       = $true
            Verbose     = $VerbosePreference
        }
        Copy-Item @copyParams
    }

    # Export public functions in manifest if there are any public functions
    $publicFunctions = Get-ChildItem $Path/Public/*.ps1 -Recurse -ErrorAction SilentlyContinue
    if ($publicFunctions) {
        if (Test-Path -Path $ModuleManifestPath) {
            $outputManifest = $ModuleManifestPath
        } else {
            $outputManifest = Join-Path -Path $DestinationPath -ChildPath "$ModuleName.psd1"
        }
        Update-Metadata -Path $OutputManifest -PropertyName FunctionsToExport -Value $publicFunctions.BaseName
    }
}
