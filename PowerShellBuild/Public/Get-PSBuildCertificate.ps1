function Get-PSBuildCertificate {
    <#
    .SYNOPSIS
        Resolves a code-signing X509Certificate2 from one of several common sources.
    .DESCRIPTION
        Resolves a code-signing certificate suitable for use with Set-AuthenticodeSignature.
        Supports five certificate sources to accommodate local development, CI/CD pipelines,
        and custom signing infrastructure:

          Auto      - Checks the CertificateEnvVar environment variable first. If it is
                      populated, uses EnvVar mode; otherwise falls back to Store mode.
                      This is the recommended default for projects that run both locally
                      and in automated pipelines.

          Store     - Selects the first valid, unexpired code-signing certificate that has
                      a private key from the Windows certificate store at CertStoreLocation.
                      Suitable for developer workstations where a certificate is installed.

          Thumbprint - Like Store, but matches a specific certificate by its thumbprint.
                      Recommended when multiple code-signing certificates are installed and
                      you need a deterministic selection.

          EnvVar    - Decodes a Base64-encoded PFX from an environment variable and
                      optionally decrypts it with a password from a second variable.
                      The most common approach for GitHub Actions, Azure DevOps Pipelines,
                      and GitLab CI where secrets are stored as masked variables.

          PfxFile   - Loads a PFX/P12 file from disk with an optional SecureString password.
                      Useful for local scripts, containers, and environments where a
                      certificate file is mounted or distributed via a secrets manager.

        Note: Authenticode signing is a Windows-only capability. This function will fail
        on non-Windows platforms when using Store or Thumbprint sources.
    .PARAMETER CertificateSource
        The source from which to resolve the code-signing certificate.
        Valid values: Auto, Store, Thumbprint, EnvVar, PfxFile. Default: Auto.
    .PARAMETER CertStoreLocation
        Windows certificate store path to search when CertificateSource is Store or Thumbprint.
        Default: Cert:\CurrentUser\My.
    .PARAMETER Thumbprint
        The exact certificate thumbprint to look up. Required when CertificateSource is Thumbprint.
    .PARAMETER CertificateEnvVar
        Name of the environment variable holding the Base64-encoded PFX certificate.
        Used by the EnvVar source and by Auto as the presence-detection key.
        Default: SIGNCERTIFICATE.
    .PARAMETER CertificatePasswordEnvVar
        Name of the environment variable holding the PFX password. Used by EnvVar source.
        Default: CERTIFICATEPASSWORD.
    .PARAMETER PfxFilePath
        File system path to a PFX/P12 certificate file. Required when CertificateSource is PfxFile.
    .PARAMETER PfxFilePassword
        Password for the PFX file as a SecureString. Used by PfxFile source.
    .OUTPUTS
        System.Security.Cryptography.X509Certificates.X509Certificate2
        Returns the resolved certificate, or $null if none was found (Store/Thumbprint sources).
    .EXAMPLE
        PS> $cert = Get-PSBuildCertificate

        Resolve automatically: use the SIGNCERTIFICATE env var when present, otherwise search
        the current user's certificate store.
    .EXAMPLE
        PS> $cert = Get-PSBuildCertificate -CertificateSource Store

        Explicitly load the first valid code-signing certificate from the current user's store.
    .EXAMPLE
        PS> $cert = Get-PSBuildCertificate -CertificateSource Thumbprint -Thumbprint 'AB12CD34EF56...'

        Load a specific certificate from the certificate store by its thumbprint.
    .EXAMPLE
        PS> $cert = Get-PSBuildCertificate -CertificateSource EnvVar `
                        -CertificateEnvVar 'MY_PFX' -CertificatePasswordEnvVar 'MY_PFX_PASS'

        Decode a PFX certificate stored in a CI/CD secret environment variable.
    .EXAMPLE
        PS> $pass = Read-Host -Prompt 'Certificate password' -AsSecureString
        PS> $cert = Get-PSBuildCertificate -CertificateSource PfxFile -PfxFilePath './codesign.pfx' -PfxFilePassword $pass

        Load a code-signing certificate from a PFX file on disk.
    #>
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param(
        [ValidateSet('Auto', 'Store', 'Thumbprint', 'EnvVar', 'PfxFile')]
        [string]$CertificateSource = 'Auto',

        [string]$CertStoreLocation = 'Cert:\CurrentUser\My',

        [string]$Thumbprint,

        [string]$CertificateEnvVar = 'SIGNCERTIFICATE',

        [string]$CertificatePasswordEnvVar = 'CERTIFICATEPASSWORD',

        [string]$PfxFilePath,

        [securestring]$PfxFilePassword
    )

    # Resolve 'Auto' to the actual source based on environment variable presence
    $resolvedSource = $CertificateSource
    if ($resolvedSource -eq 'Auto') {
        $resolvedSource = if (-not [string]::IsNullOrEmpty([System.Environment]::GetEnvironmentVariable($CertificateEnvVar))) {
            'EnvVar'
        } else {
            'Store'
        }
        Write-Verbose "CertificateSource is 'Auto'. Resolved to '$resolvedSource'."
    }

    $cert = $null

    switch ($resolvedSource) {
        'Store' {
            $cert = Get-ChildItem -Path $CertStoreLocation -CodeSigningCert |
                Where-Object { $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) } |
                Select-Object -First 1
            if ($cert) {
                Write-Verbose ($LocalizedData.CertificateResolvedFromStore -f $CertStoreLocation, $cert.Subject)
            }
        }
        'Thumbprint' {
            $cert = Get-ChildItem -Path $CertStoreLocation |
                Where-Object { $_.Thumbprint -eq $Thumbprint -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) } |
                Select-Object -First 1
            if ($cert) {
                Write-Verbose ($LocalizedData.CertificateResolvedFromThumbprint -f $Thumbprint, $cert.Subject)
            }
        }
        'EnvVar' {
            $b64Value = [System.Environment]::GetEnvironmentVariable($CertificateEnvVar)
            $buffer   = [System.Convert]::FromBase64String($b64Value)
            $password = [System.Environment]::GetEnvironmentVariable($CertificatePasswordEnvVar)
            $cert     = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($buffer, $password)
            Write-Verbose ($LocalizedData.CertificateResolvedFromEnvVar -f $CertificateEnvVar)
        }
        'PfxFile' {
            $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($PfxFilePath, $PfxFilePassword)
            Write-Verbose ($LocalizedData.CertificateResolvedFromPfxFile -f $PfxFilePath)
        }
    }

    $cert
}
