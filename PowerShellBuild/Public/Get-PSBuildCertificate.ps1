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
    .PARAMETER SkipValidation
        Relax the certificate validity checks. For the EnvVar and PfxFile sources, which load
        exactly one certificate, this skips the private key, expiration, and Code Signing EKU
        checks outright. For the Store and Thumbprint sources, which select one certificate out
        of many, an unexpired certificate is still preferred whenever one exists; an expired
        certificate is returned only when no unexpired one was found, and a warning is emitted
        when that happens. Those two sources always require a private key, because it is part of
        how the certificate is selected rather than a check layered on afterwards; EnvVar and
        PfxFile do not, since this skips their checks entirely. Use with caution; invalid
        certificates will fail during actual signing operations with less descriptive errors.
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingPlainTextForPassword',
        'CertificatePasswordEnvVar',
        Justification = 'This is not a password in plain text. It is the name of an environment variable that contains the password, which is a common pattern for CI/CD pipelines and secrets management.'
    )]
    param(
        [ValidateSet('Auto', 'Store', 'Thumbprint', 'EnvVar', 'PfxFile')]
        [string]$CertificateSource = 'Auto',

        [string]$CertStoreLocation = 'Cert:\CurrentUser\My',

        [string]$Thumbprint,

        [string]$CertificateEnvVar = 'SIGNCERTIFICATE',

        [string]$CertificatePasswordEnvVar = 'CERTIFICATEPASSWORD',

        [string]$PfxFilePath,

        [securestring]$PfxFilePassword,

        [switch]$SkipValidation
    )

    # Resolve 'Auto' to the actual source based on environment variable presence
    $resolvedSource = $CertificateSource
    if ($resolvedSource -eq 'Auto') {
        $resolvedSource = if (-not [string]::IsNullOrEmpty([System.Environment]::GetEnvironmentVariable($CertificateEnvVar))) {
            'EnvVar'
        } else {
            'Store'
        }
        Write-Verbose ($LocalizedData.CertificateSourceAutoResolved -f $resolvedSource)
    }

    $cert = $null

    switch ($resolvedSource) {
        'Store' {
            # Throw if running on a non-Windows platform since the certificate store is not supported.
            # $IsWindows does not exist on Windows PowerShell 5.1 (Desktop edition), where it is $null
            # and the platform is always Windows; only treat the platform as non-Windows when $IsWindows
            # is explicitly $false (PowerShell 7+ on Linux/macOS).
            if ($null -ne $IsWindows -and -not $IsWindows) {
                throw $LocalizedData.CertificateSourceStoreNotSupported
            }
            $candidateCertificate = Get-ChildItem -Path $CertStoreLocation -CodeSigningCert

            # The store holds many certificates, so validity is part of how the right one is
            # selected rather than a gate applied to a single loaded certificate. Prefer a valid
            # certificate first, always.
            $cert = $candidateCertificate |
                Where-Object { $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) } |
                Select-Object -First 1

            # Only when the consumer explicitly opted out of validation does an expired
            # certificate become acceptable, and only as a fallback, so a valid certificate is
            # never passed over in favour of an expired one further down the store.
            # HasPrivateKey stays required: a certificate without one cannot sign anything, so
            # relaxing that check would buy nothing and only defer the failure to
            # Set-AuthenticodeSignature with a less descriptive error.
            if (-not $cert -and $SkipValidation) {
                $cert = $candidateCertificate |
                    Where-Object { $_.HasPrivateKey } |
                    Select-Object -First 1
                if ($cert) {
                    Write-Warning ($LocalizedData.CertificateValidationRelaxed -f $cert.NotAfter, $cert.Subject)
                }
            }

            if ($cert) {
                Write-Verbose ($LocalizedData.CertificateResolvedFromStore -f $CertStoreLocation, $cert.Subject)
            }
        }
        'Thumbprint' {
            if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
                throw "CertificateSource 'Thumbprint' requires a non-empty Thumbprint value."
            }

            # Normalize thumbprint input by removing whitespace for robust matching
            $normalizedThumbprint = ($Thumbprint -replace '\s', '')

            $candidateCertificate = Get-ChildItem -Path $CertStoreLocation -CodeSigningCert

            # As with the Store source, validity is part of the selection. Prefer a valid
            # certificate first, always.
            $cert = $candidateCertificate |
                Where-Object {
                    ($_.Thumbprint -replace '\s', '') -ieq $normalizedThumbprint -and
                    $_.HasPrivateKey -and
                    $_.NotAfter -gt (Get-Date)
                } |
                Select-Object -First 1

            # The fallback relaxes only the expiry check. The thumbprint match is kept, because
            # returning a certificate other than the one the consumer named would sign with a
            # different identity than the build asked for, and HasPrivateKey is kept for the
            # same reason it is kept in the Store source.
            if (-not $cert -and $SkipValidation) {
                $cert = $candidateCertificate |
                    Where-Object {
                        ($_.Thumbprint -replace '\s', '') -ieq $normalizedThumbprint -and
                        $_.HasPrivateKey
                    } |
                    Select-Object -First 1
                if ($cert) {
                    Write-Warning ($LocalizedData.CertificateValidationRelaxed -f $cert.NotAfter, $cert.Subject)
                }
            }

            if ($cert) {
                Write-Verbose ($LocalizedData.CertificateResolvedFromThumbprint -f $Thumbprint, $cert.Subject)
            }
        }
        'EnvVar' {
            $b64Value = [System.Environment]::GetEnvironmentVariable($CertificateEnvVar)
            if ([string]::IsNullOrWhiteSpace($b64Value)) {
                throw "Environment variable '$CertificateEnvVar' is not set or is empty. When using CertificateSource='EnvVar', you must provide a Base64-encoded PFX in this variable."
            }

            try {
                $buffer = [System.Convert]::FromBase64String($b64Value)
            } catch [System.FormatException] {
                throw "Environment variable '$CertificateEnvVar' does not contain a valid Base64-encoded PFX value."
            }
            $password = [System.Environment]::GetEnvironmentVariable($CertificatePasswordEnvVar)
            $cert = Import-PSBuildX509Certificate -RawData $buffer -Password $password
            Write-Verbose ($LocalizedData.CertificateResolvedFromEnvVar -f $CertificateEnvVar)
        }
        'PfxFile' {
            $cert = Import-PSBuildX509Certificate -FilePath $PfxFilePath -FilePassword $PfxFilePassword
            Write-Verbose ($LocalizedData.CertificateResolvedFromPfxFile -f $PfxFilePath)
        }
    }

    # Validate certificates loaded from EnvVar or PfxFile sources unless -SkipValidation is specified
    if ($cert -and -not $SkipValidation -and ($resolvedSource -eq 'EnvVar' -or $resolvedSource -eq 'PfxFile')) {
        # Check for private key
        if (-not $cert.HasPrivateKey) {
            throw ($LocalizedData.CertificateMissingPrivateKey -f $cert.Subject)
        }

        # Check expiration
        if ($cert.NotAfter -le (Get-Date)) {
            throw ($LocalizedData.CertificateExpired -f $cert.NotAfter, $cert.Subject)
        }

        # Check for Code Signing EKU (1.3.6.1.5.5.7.3.3)
        $codeSigningOid = '1.3.6.1.5.5.7.3.3'
        $hasCodeSigningEku = $cert.EnhancedKeyUsageList | Where-Object { $_.ObjectId -eq $codeSigningOid }
        if (-not $hasCodeSigningEku) {
            throw ($LocalizedData.CertificateMissingCodeSigningEku -f $cert.Subject)
        }

        Write-Verbose "Certificate validation passed: HasPrivateKey=$($cert.HasPrivateKey), NotAfter=$($cert.NotAfter), CodeSigningEKU=Present"
    }

    $certSubject = if ($cert) { $cert.Subject } else { 'No certificate found' }
    Write-Verbose ('Certificate resolution complete: ' + $certSubject)
    $cert
}
