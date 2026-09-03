function Import-PSBuildX509Certificate {
    <#
    .SYNOPSIS
        Construct an X509Certificate2 from raw PFX bytes or from a PFX file on disk.
    .DESCRIPTION
        Get-PSBuildCertificate loads a certificate from two places that are not the Windows
        certificate store: a Base64 payload held in an environment variable, and a PFX file on
        disk. Both go through the X509Certificate2 constructor, and a constructor is a .NET call
        rather than a command, so nothing downstream of it could be tested without a certificate
        that the running machine happened to have.

        Naming the load as a command gives it a seam. With the load replaced, the validation
        Get-PSBuildCertificate applies afterwards -- private key, expiry, and the Code Signing
        extended key usage -- can be driven against a certificate of the caller's choosing on any
        platform. That validation had never executed before psake/PowerShellBuild#216.

        No validation happens here, and nothing is written to a certificate store. Whatever the
        constructor throws is left to propagate: its message about malformed input is more
        specific than anything this function could add.
    .PARAMETER RawData
        The decoded PFX bytes to construct the certificate from.
    .PARAMETER Password
        Password protecting the PFX bytes. An empty string means no password: the loader treats
        a null and an empty password identically, measured on Windows PowerShell 5.1 and
        PowerShell 7 against a password-less PFX, a password-protected one, and one exported with
        an explicitly empty password. Nothing here needs to tell the two apart, which is just as
        well, because a PowerShell [string] parameter cannot carry a null to begin with.
    .PARAMETER FilePath
        Path to the PFX or P12 file to construct the certificate from.
    .PARAMETER FilePassword
        Password protecting the PFX file, as a SecureString. Omit it when the file carries no
        password.
    .EXAMPLE
        PS> Import-PSBuildX509Certificate -RawData $decodedBytes -Password $password

        Construct a certificate from the bytes of a Base64-encoded PFX held in a CI secret.
    .EXAMPLE
        PS> Import-PSBuildX509Certificate -FilePath ./signing-certificate.pfx -FilePassword $securePassword

        Construct a certificate from a PFX file on disk.
    .OUTPUTS
        System.Security.Cryptography.X509Certificates.X509Certificate2
    #>
    [CmdletBinding(DefaultParameterSetName = 'RawData')]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingPlainTextForPassword',
        'Password',
        Justification = 'The X509Certificate2 overload that takes raw bytes takes the password as a string, and the caller reads it from an environment variable that is already a string.'
    )]
    param(
        [Parameter(Mandatory, ParameterSetName = 'RawData')]
        [byte[]]$RawData,

        [Parameter(ParameterSetName = 'RawData')]
        [AllowEmptyString()]
        [string]$Password,

        [Parameter(Mandatory, ParameterSetName = 'FilePath')]
        [string]$FilePath,

        [Parameter(ParameterSetName = 'FilePath')]
        [securestring]$FilePassword
    )

    if ($PSCmdlet.ParameterSetName -eq 'RawData') {
        [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($RawData, $Password)
    } else {
        [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($FilePath, $FilePassword)
    }
}
