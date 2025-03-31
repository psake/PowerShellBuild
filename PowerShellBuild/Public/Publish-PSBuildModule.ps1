function Publish-PSBuildModule {
    <#
    .SYNOPSIS
        Publishes a module to the defined PowerShell repository.
    .DESCRIPTION
        Publishes a module to the defined PowerShell repository.
    .PARAMETER Path
        The path to the module to publish.
    .PARAMETER Version
        The version of the module to publish.
    .PARAMETER Repository
        The PowerShell repository name to publish to.
    .PARAMETER NuGetApiKey
        The API key to use to authenticate to the PowerShell repository with.
    .PARAMETER Credential
        The credential to use to authenticate to the PowerShell repository with.
    .EXAMPLE
        PS> Publish-PSBuildModule -Path .\Output\0.1.0\MyModule -Version 0.1.0 -Repository PSGallery -NuGetApiKey 12345

        Publish version 0.1.0 of the module at path .\Output\0.1.0\MyModule to the PSGallery repository using an API key.
    .EXAMPLE
        PS> Publish-PSBuildModule -Path .\Output\0.1.0\MyModule -Version 0.1.0 -Repository PSGallery -Credential $myCred

        Publish version 0.1.0 of the module at path .\Output\0.1.0\MyModule to the PSGallery repository using a PowerShell credential.
    .EXAMPLE
        PS> Publish-PSBuildModule -Path .\Output\0.1.0\MyModule -Version 0.1.0 -Repository PSGallery -NuGetApiKey 12345 -Credential $myCred

        Publish version 0.1.0 of the module at path .\Output\0.1.0\MyModule to the PSGallery repository using an API key and a PowerShell credential.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter',
        '',
        Justification = 'Both Credential and NuGetApiKey are used just not via explicit variable call.'
    )]
    [CmdletBinding(DefaultParameterSetName = 'ApiKey')]
    [CmdletBinding(DefaultParameterSetName = 'ApiKey')]
    param(
        [parameter(Mandatory)]
        [ValidateScript({
                if (-not (Test-Path -Path $_ )) {
                    throw ($LocalizedData.PathDoesNotExist -f $_)
                }
                if (-not (Test-Path -Path $_ -PathType Container)) {
                    throw $LocalizedData.PathArgumentMustBeAFolder
                }
                $true
            })]
        [System.IO.FileInfo]$Path,

        [parameter(Mandatory)]
        [string]$Version,

        [parameter(Mandatory)]
        [string]$Repository,

        [Alias('ApiKey')]
        [string]$NuGetApiKey,

        [PSCredential]$Credential
    )

    Write-Verbose ($LocalizedData.PublishingVersionToRepository -f $Version, $Repository)

    $publishParams = @{
        Path       = $Path
        Repository = $Repository
        Verbose    = $VerbosePreference
    }

    'NuGetApiKey', 'Credential' | ForEach-Object {
        if ($PSBoundParameters.ContainsKey($_)) {
            $publishParams.$_ = $PSBoundParameters.$_
        }
    }

    Publish-Module @publishParams
}
