function Initialize-PSBuild {
    <#
    .SYNOPSIS
        Initializes BuildHelpers to populate build environment variables.
    .DESCRIPTION
        Initializes BuildHelpers to populate build environment variables.
    .PARAMETER BuildEnvironment
        Contains the PowerShellBuild settings (known as $PSBPreference).
    .PARAMETER UseBuildHelpers
        Use BuildHelpers module to populate common environment variables based on current build system context.
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

    if ($BuildEnvironment.Build.OutDir.StartsWith($env:BHProjectPath, [StringComparison]::OrdinalIgnoreCase)) {
        $BuildEnvironment.Build.ModuleOutDir = [IO.Path]::Combine($BuildEnvironment.Build.OutDir, $env:BHProjectName, $BuildEnvironment.General.ModuleVersion)
    } else {
        $BuildEnvironment.Build.ModuleOutDir = [IO.Path]::Combine($env:BHProjectPath, $BuildEnvironment.Build.OutDir, $env:BHProjectName, $BuildEnvironment.General.ModuleVersion)
    }

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

        Write-Host "$nl`Environment variables:" -ForegroundColor Yellow
        (Get-Item ENV:BH*).Foreach({
            '{0,-20}{1}' -f $_.name, $_.value
        })
    }
}
