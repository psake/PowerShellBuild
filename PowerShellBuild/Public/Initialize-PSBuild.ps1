function Initialize-PSBuild {
    <#
    .SYNOPSIS
        Initializes BuildHelpers to populate build environment variables.
    .DESCRIPTION
        Initializes BuildHelpers to populate build environment variables.
    .PARAMETER UseBuildHelpers
        Use BuildHelpers module to popular common environment variables based on current build system context.
    .EXAMPLE
        PS> Initialize-PSBuild -UseBuildHelpers

        Populate build system environment variables.
    #>
    [cmdletbinding()]
    param(
        [switch]$UseBuildHelpers
    )

    Set-BuildEnvironment -Force

    Write-Host 'Build System Details:' -ForegroundColor Yellow
    $psVersion          = $PSVersionTable.PSVersion.ToString()
    $buildModuleName    = $MyInvocation.MyCommand.Module.Name
    $buildModuleVersion = $MyInvocation.MyCommand.Module.Version
    "Build Module:       $buildModuleName`:$buildModuleVersion"
    "PowerShell Version: $psVersion"

    if ($UseBuildHelpers.IsPresent) {
        $nl = [System.Environment]::NewLine
        "$nl`Environment variables:"
        (Get-Item ENV:BH*).Foreach({
            '{0,-20}{1}' -f $_.name, $_.value
        })
    }
}
