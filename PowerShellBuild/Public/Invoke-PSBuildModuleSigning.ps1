function Invoke-PSBuildModuleSigning {
    <#
    .SYNOPSIS
        Signs PowerShell module files with an Authenticode signature.
    .DESCRIPTION
        Signs all files matching the Include patterns found under Path using
        Set-AuthenticodeSignature. Typically called after the module is staged to the output
        directory and before the catalog file is created, so that all signed source files are
        captured in the catalog hash.

        Authenticode signing is Windows-only. This function will fail on Linux or macOS.

        Use Get-PSBuildCertificate to resolve the certificate from any of the supported sources
        (certificate store, PFX file, Base64 environment variable, thumbprint, etc.) before
        calling this function.
    .PARAMETER Path
        The directory to search recursively for files to sign. Typically the module output
        directory (PSBPreference.Build.ModuleOutDir).
    .PARAMETER Certificate
        The X509Certificate2 code-signing certificate to sign files with. Must have a private
        key and an Extended Key Usage (EKU) of Code Signing (1.3.6.1.5.5.7.3.3).
    .PARAMETER TimestampServer
        RFC 3161 timestamp server URI to embed in the Authenticode signature, allowing the
        signature to remain valid after the certificate expires. Default: http://timestamp.digicert.com.

        Other common timestamp servers:
          http://timestamp.sectigo.com
          http://timestamp.comodoca.com
          http://tsa.starfieldtech.com
          http://timestamp.globalsign.com/scripts/timstamp.dll
    .PARAMETER HashAlgorithm
        Hash algorithm for the Authenticode signature.
        Valid values: SHA256 (default), SHA384, SHA512, SHA1.
        SHA1 is deprecated; prefer SHA256 or higher.
    .PARAMETER Include
        Glob patterns of file names to sign. Searched recursively under Path.
        Default: *.psd1, *.psm1, *.ps1.
    .OUTPUTS
        System.Management.Automation.Signature
        Returns the Signature objects from Set-AuthenticodeSignature for each signed file.
    .EXAMPLE
        PS> $cert = Get-PSBuildCertificate
        PS> Invoke-PSBuildModuleSigning -Path .\Output\MyModule\1.0.0 -Certificate $cert

        Sign all .psd1, .psm1, and .ps1 files in the module output directory using a
        certificate resolved automatically from the environment or certificate store.
    .EXAMPLE
        PS> $cert = Get-PSBuildCertificate -CertificateSource Thumbprint -Thumbprint 'AB12CD...'
        PS> Invoke-PSBuildModuleSigning -Path .\Output\MyModule\1.0.0 -Certificate $cert `
                -TimestampServer 'http://timestamp.sectigo.com' -Include '*.psd1','*.psm1'

        Sign only the manifest and root module using a specific certificate and a custom
        timestamp server.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Signature])]
    param(
        [parameter(Mandatory)]
        [ValidateScript({
                if (-not (Test-Path -Path $_ -PathType Container)) {
                    throw ($LocalizedData.PathArgumentMustBeAFolder)
                }
                $true
            })]
        [string]$Path,

        [parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [string]$TimestampServer = 'http://timestamp.digicert.com',

        [ValidateSet('SHA256', 'SHA384', 'SHA512', 'SHA1')]
        [string]$HashAlgorithm = 'SHA256',

        [string[]]$Include = @('*.psd1', '*.psm1', '*.ps1')
    )

    $files = Get-ChildItem -Path $Path -Recurse -Include $Include
    Write-Verbose ($LocalizedData.SigningModuleFiles -f $files.Count, ($Include -join ', '), $Path)

    $sigParams = @{
        Certificate     = $Certificate
        TimestampServer = $TimestampServer
        HashAlgorithm   = $HashAlgorithm
    }

    $files | Set-AuthenticodeSignature @sigParams
}
