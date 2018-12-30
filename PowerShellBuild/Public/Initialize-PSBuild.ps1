function Initialize-PSBuild {
    <#
    .SYNOPSIS
        Initializes BuildHelpers to populate build environment variables.
    .DESCRIPTION
        Initializes BuildHelpers to populate build environment variables.
    .PARAMETER BuildEnvironment
        Contains the PowerShellBuild settings (known as $PSBPreference).
    .PARAMETER UseBuildHelpers
        Use BuildHelpers module to popular common environment variables based on current build system context.
    .EXAMPLE
        PS> Initialize-PSBuild -UseBuildHelpers

        Populate build system environment variables.
    #>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory)]
        [Hashtable]
        $BuildEnvironment,

        [switch]$UseBuildHelpers
    )

    $params = @{
        BuildOutput = $BuildEnvironment.Build.ModuleOutDir
    }
    Set-BuildEnvironment @params -Force

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
