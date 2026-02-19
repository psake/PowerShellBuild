function New-PSBuildFileCatalog {
    <#
    .SYNOPSIS
        Creates a Windows catalog (.cat) file for a PowerShell module.
    .DESCRIPTION
        Wraps New-FileCatalog to generate a catalog file that records cryptographic hashes of
        all files in the module output directory. The catalog can later be signed with
        Invoke-PSBuildModuleSigning (or Set-AuthenticodeSignature) to provide tamper detection
        and a trust chain for the entire module.

        The recommended signing order is:
          1. Sign module files (*.psd1, *.psm1, *.ps1) with Invoke-PSBuildModuleSigning.
          2. Create the catalog with New-PSBuildFileCatalog (hashes already-signed files).
          3. Sign the catalog file with Invoke-PSBuildModuleSigning -Include '*.cat'.

        Catalog file creation requires Windows (New-FileCatalog is not available on Linux or macOS).

        Reference: https://p0w3rsh3ll.wordpress.com/2017/09/19/psgallery-and-catalog-files/
    .PARAMETER ModulePath
        The directory whose contents will be hashed and recorded in the catalog.
        Typically the module output directory (PSBPreference.Build.ModuleOutDir).
    .PARAMETER CatalogFilePath
        The full path (directory + filename) of the .cat file to create.
        By convention this is '<ModuleOutDir>\<ModuleName>.cat'.
    .PARAMETER CatalogVersion
        The catalog hash version.
        1 = SHA1, compatible with Windows 7 and Windows Server 2008 R2.
        2 = SHA2 (SHA-256), required for Windows 8 / Server 2012 and newer. Default: 2.
    .OUTPUTS
        System.IO.FileInfo
        Returns the FileInfo object of the created catalog file.
    .EXAMPLE
        PS> New-PSBuildFileCatalog -ModulePath .\Output\MyModule\1.0.0 `
                -CatalogFilePath .\Output\MyModule\1.0.0\MyModule.cat

        Create a version-2 (SHA2) catalog for all files in the module output directory.
    .EXAMPLE
        PS> New-PSBuildFileCatalog -ModulePath .\Output\MyModule\1.0.0 `
                -CatalogFilePath .\Output\MyModule\1.0.0\MyModule.cat -CatalogVersion 1

        Create a SHA1 (version 1) catalog for compatibility with Windows 7 / Server 2008 R2.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [parameter(Mandatory)]
        [ValidateScript({
                if (-not (Test-Path -Path $_ -PathType Container)) {
                    throw ($LocalizedData.PathArgumentMustBeAFolder)
                }
                $true
            })]
        [string]$ModulePath,

        [parameter(Mandatory)]
        [string]$CatalogFilePath,

        [ValidateRange(1, 2)]
        [int]$CatalogVersion = 2
    )

    Write-Verbose ($LocalizedData.CreatingFileCatalog -f $CatalogFilePath, $CatalogVersion)

    $catalogParams = @{
        Path            = $ModulePath
        CatalogFilePath = $CatalogFilePath
        CatalogVersion  = $CatalogVersion
        Verbose         = $VerbosePreference
    }

    Microsoft.PowerShell.Security\New-FileCatalog @catalogParams

    Write-Verbose ($LocalizedData.FileCatalogCreated -f $CatalogFilePath)
}
