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
    [cmdletbinding(DefaultParameterSetName = 'ApiKey')]
    param(
        [parameter(Mandatory)]
        [ValidateScript({
            if (-not (Test-Path -Path $_ )) {
                throw 'Folder does not exist'
            }
            if (-not (Test-Path -Path $_ -PathType Container)) {
                throw 'The Path argument must be a folder. File paths are not allowed.'
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

        [pscredential]$Credential
    )

    Write-Verbose "Publishing version [$Version] to repository [$Repository]..."

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
