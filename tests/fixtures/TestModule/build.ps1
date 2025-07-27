[cmdletbinding(DefaultParameterSetName = 'Task')]
param(
    # Build task(s) to execute
    [parameter(ParameterSetName = 'task', position = 0)]
    [string[]]$Task = 'default',

    # Bootstrap dependencies
    [switch]$Bootstrap,

    # List available build tasks
    [parameter(ParameterSetName = 'Help')]
    [switch]$Help,

    [ValidateSet('InvokeBuild', 'psake')]
    [string]$BuildTool = 'psake',

    # Optional properties to pass to psake
    [hashtable]$Properties
)

$ErrorActionPreference = 'Stop'

# Bootstrap dependencies
if ($Bootstrap.IsPresent) {
    Get-PackageProvider -Name Nuget -ForceBootstrap | Out-Null
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    if ((Test-Path -Path ./requirements.psd1)) {
        if (-not (Get-Module -Name PSDepend -ListAvailable)) {
            Install-Module -Name PSDepend -Repository PSGallery -Scope CurrentUser -Force
        }
        Import-Module -Name PSDepend -Verbose:$false
        Invoke-PSDepend -Path './requirements.psd1' -Install -Import -Force -WarningAction SilentlyContinue
    } else {
        Write-Warning "No [requirements.psd1] found. Skipping build dependency installation."
    }
}

if ($BuildTool -eq 'psake') {
    if (Get-Module InvokeBuild) {Remove-Module InvokeBuild -Force}
    # Execute psake task(s)
    $psakeFile = './psakeFile.ps1'
    if ($PSCmdlet.ParameterSetName -eq 'Help') {
        Get-PSakeScriptTasks -buildFile $psakeFile |
            Format-Table -Property Name, Description, Alias, DependsOn
    } else {
        Set-BuildEnvironment -Force
        Invoke-psake -buildFile $psakeFile -taskList $Task -nologo -properties $Properties
        exit ([int](-not $psake.build_success))
    }
} else {
    if ($PSCmdlet.ParameterSetName -eq 'Help') {
        Invoke-Build -File ./.build.ps1 ?
    } else {
        # Execute IB task(s)
        Import-Module InvokeBuild
        if ($Task -eq 'Default') {$Task = '.'}
        Invoke-Build -File ./.build.ps1 -Task $Task
    }
}
