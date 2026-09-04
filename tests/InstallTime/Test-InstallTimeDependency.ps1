#requires -Version 5.1
<#
.SYNOPSIS
    Saves PowerShellBuild from a local repository inside an isolated process and asserts that
    its declared dependencies resolved, loaded, and that the module exports its public surface.

.DESCRIPTION
    This script is the isolated half of the local-repository install test. It is never run in
    the same process as Invoke-LocalRepositoryInstallTest.ps1 - that script starts it in a fresh
    PowerShell 7 or Windows PowerShell 5.1 process so that the PSModulePath below is the only
    module path the process has ever seen.

    The isolated PSModulePath contains:

      1. IsolatedModulePath - empty when the process starts; the Save-Module target.
      2. ToolsModulePath    - PowerShellGet and PackageManagement only.
      3. On PowerShell 7 only, the engine's own module directory. See Set-IsolatedModulePath for
         why it is there on one edition and not the other.

    Nothing installed on the machine can satisfy a dependency from that path, which is the whole
    point: on a developer machine and on a CI runner that has just run `./build.ps1 -Bootstrap`,
    every dependency is already installed, and without this isolation the test would pass no
    matter what the manifest declared. The visibility assertions below hold that line rather than
    trusting the list above.

    Both modules in the tools path are imported by explicit manifest path rather than by name.
    Importing PowerShellGet by name on Windows PowerShell 5.1 asks the module auto-loader to
    resolve helper modules from a PSModulePath that does not contain the engine's own module
    directory, and that fails.

.PARAMETER IsolatedModulePath
    An existing empty directory. It becomes the first PSModulePath entry and the Save-Module
    target.

.PARAMETER ToolsModulePath
    A directory holding only PowerShellGet and PackageManagement.

.PARAMETER RepositoryName
    The name of the registered local file-share repository to save from.

.PARAMETER ModuleName
    The module under test.

.PARAMETER RequiredVersion
    The exact version of the module under test to save. Passing it explicitly keeps this run
    independent of any other package that happens to sit in the local repository.

.PARAMETER ExpectSaveToFail
    Negative-control mode. Asserts that Save-Module fails and that nothing at all landed in the
    isolated path. Used to prove this test is capable of failing.

.PARAMETER ExpectedAlias
    The alias the module under test is expected to export.

.EXAMPLE
    ./Test-InstallTimeDependency.ps1 -IsolatedModulePath C:\scratch\empty -ToolsModulePath C:\scratch\tools -RepositoryName LocalTest -RequiredVersion 0.8.2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $IsolatedModulePath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $ToolsModulePath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $RepositoryName,

    [ValidateNotNullOrEmpty()]
    [string]
    $ModuleName = 'PowerShellBuild',

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $RequiredVersion,

    [switch]
    $ExpectSaveToFail,

    [ValidateNotNullOrEmpty()]
    [string]
    $ExpectedAlias = 'PowerShellBuild.IB.Tasks'
)

$ErrorActionPreference = 'Stop'

function Confirm-Condition {
    <#
    .SYNOPSIS
    Throws when a test condition is not met, and reports it when it is.

    .PARAMETER Condition
    The result of the check being asserted.

    .PARAMETER Description
    A description of what the check proves, used in both the pass and the failure message.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [bool]
        $Condition,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Description
    )

    if (-not $Condition) {
        throw "ASSERTION FAILED: $Description"
    }
    Write-Host "  PASS: $Description"
}

function Set-IsolatedModulePath {
    <#
    .SYNOPSIS
    Points PSModulePath at the isolated save target, the tools directory, and on PowerShell 7 the
    engine's own module directory - and nothing else.

    .DESCRIPTION
    On PowerShell 7 the engine's module directory has to stay reachable. It ships with the engine,
    holds no dependency of the module under test, and dropping it takes CimCmdlets with it: Pester
    6.0.0 falls back to looking for a `uname` application when Get-CimInstance cannot be resolved,
    and on a GitHub Windows runner it finds `uname.exe` from Git for Windows and then throws
    "SafeCommands entry for uname does not hold a reference to the proper command." That is an
    artifact of the isolation, not a defect in this module, and no consumer would ever hit it.

    Windows PowerShell 5.1 does not need it - Get-WmiObject resolves without it, so Pester never
    reaches that fallback - and must not have it: adding the engine directory there makes the
    engine restore the machine's other default module paths as well, which puts the Pester copy
    installed under Program Files back in view and destroys the isolation.

    Whichever way it goes, the isolation is guaranteed by the explicit visibility assertions
    below, not by this list.

    .PARAMETER IsolatedModulePath
    The empty directory that is the Save-Module target.

    .PARAMETER ToolsModulePath
    The directory holding only PowerShellGet and PackageManagement.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $IsolatedModulePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ToolsModulePath
    )

    $modulePaths = @($IsolatedModulePath, $ToolsModulePath)
    if ($PSVersionTable.PSEdition -eq 'Core') {
        $modulePaths += (Join-Path $PSHOME 'Modules')
    }

    if ($PSCmdlet.ShouldProcess('PSModulePath', 'Restrict to the isolated module paths')) {
        $env:PSModulePath = $modulePaths -join [System.IO.Path]::PathSeparator
    }
}

try {
    Set-IsolatedModulePath -IsolatedModulePath $IsolatedModulePath -ToolsModulePath $ToolsModulePath

    Write-Host "=== Isolated probe: $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion) ==="
    Write-Host 'PSModulePath:'
    $env:PSModulePath -split [System.IO.Path]::PathSeparator | ForEach-Object { Write-Host "  $_" }

    $packageManagementManifestPath = Get-ChildItem -Path (Join-Path $ToolsModulePath 'PackageManagement') -Recurse -Filter 'PackageManagement.psd1' |
        Select-Object -First 1
    $powerShellGetManifestPath = Get-ChildItem -Path (Join-Path $ToolsModulePath 'PowerShellGet') -Recurse -Filter 'PowerShellGet.psd1' |
        Select-Object -First 1
    Import-Module -Name $packageManagementManifestPath.FullName -Force
    Import-Module -Name $powerShellGetManifestPath.FullName -Force
    Write-Host "PackageManagement in use: $((Get-Module -Name PackageManagement).Version)"
    Write-Host "PowerShellGet in use:     $((Get-Module -Name PowerShellGet).Version)"

    # Read the dependency contract from the package that is about to be saved rather than from a
    # hardcoded list, so this test keeps testing the manifest instead of a stale copy of it.
    $declaredDependencies = (Find-Module -Name $ModuleName -RequiredVersion $RequiredVersion -Repository $RepositoryName).Dependencies
    $dependencyNames = @($declaredDependencies | ForEach-Object { $_.Name })
    Write-Host "Declared dependencies of $ModuleName $RequiredVersion : $($dependencyNames -join ', ')"

    # PowerShellGet restores the machine's default PSModulePath entries when a command such as
    # Find-Module or Save-Module returns. Every check below depends on the isolated path, so it is
    # re-asserted after each PowerShellGet call rather than trusted to survive one.
    Set-IsolatedModulePath -IsolatedModulePath $IsolatedModulePath -ToolsModulePath $ToolsModulePath

    Write-Host ''
    Write-Host '--- Isolation: nothing under test may be visible before the save ---'
    foreach ($name in @($ModuleName) + $dependencyNames) {
        $visibleModules = Get-Module -Name $name -ListAvailable -ErrorAction SilentlyContinue
        Confirm-Condition -Condition ($null -eq $visibleModules) -Description "$name is not visible on the isolated PSModulePath"
    }

    Write-Host ''
    Write-Host "--- Save-Module $ModuleName $RequiredVersion -Repository $RepositoryName ---"
    $saveFailed = $false
    try {
        Save-Module -Name $ModuleName -RequiredVersion $RequiredVersion -Repository $RepositoryName -Path $IsolatedModulePath -Force -ErrorAction Stop
        Write-Host 'Save-Module succeeded.'
    } catch {
        $saveFailed = $true
        Write-Host 'Save-Module failed.'
        Write-Host "  FullyQualifiedErrorId: $($_.FullyQualifiedErrorId)"
        Write-Host "  Message: $($_.Exception.Message)"
    }

    $savedModuleDirectories = @(Get-ChildItem -Path $IsolatedModulePath -Directory -ErrorAction SilentlyContinue)
    Write-Host 'What landed in the isolated path:'
    if ($savedModuleDirectories.Count -eq 0) {
        Write-Host '  (nothing)'
    }
    foreach ($savedModuleDirectory in $savedModuleDirectories) {
        $savedVersions = @(Get-ChildItem -Path $savedModuleDirectory.FullName -Directory -ErrorAction SilentlyContinue).Name -join ', '
        Write-Host ("  {0,-16} {1}" -f $savedModuleDirectory.Name, $savedVersions)
    }

    Write-Host ''
    if ($ExpectSaveToFail) {
        Write-Host '--- Negative control assertions ---'
        Confirm-Condition -Condition $saveFailed -Description 'Save-Module refused a package whose dependency version does not exist'
        Confirm-Condition -Condition ($savedModuleDirectories.Count -eq 0) -Description 'Nothing was left in the isolated path by the failed save'
        Write-Host ''
        Write-Host 'RESULT: negative control passed - this test can fail.'
        exit 0
    }

    Write-Host '--- Positive assertions ---'
    Confirm-Condition -Condition (-not $saveFailed) -Description "Save-Module resolved $ModuleName $RequiredVersion from the local repository"

    # Save-Module restored the machine's default PSModulePath entries on the way out. Left alone,
    # the import below would silently fall through to an installed copy of the module or of one of
    # its dependencies, and the test would prove nothing.
    Set-IsolatedModulePath -IsolatedModulePath $IsolatedModulePath -ToolsModulePath $ToolsModulePath

    foreach ($declaredDependency in $declaredDependencies) {
        $dependencyName = $declaredDependency.Name
        # PowerShellGet reports the floor of the dependency range as MinimumVersion, and the local
        # repository holds exactly that version, so an exact match is the right assertion here.
        $expectedVersion = $declaredDependency.MinimumVersion
        $savedDependency = Get-Module -Name $dependencyName -ListAvailable -ErrorAction SilentlyContinue |
            Where-Object { $_.ModuleBase -like "$IsolatedModulePath*" }
        Confirm-Condition -Condition ($null -ne $savedDependency) -Description "$dependencyName was saved into the isolated path"
        Confirm-Condition -Condition ([bool]($savedDependency.Version -contains [version]$expectedVersion)) -Description "$dependencyName resolved at the declared version $expectedVersion"
    }

    Write-Host ''
    Write-Host "--- Import $ModuleName by explicit manifest path ---"
    $savedManifestPath = Get-ChildItem -Path (Join-Path $IsolatedModulePath $ModuleName) -Recurse -Filter "$ModuleName.psd1" |
        Select-Object -First 1
    Import-Module -Name $savedManifestPath.FullName -Force -ErrorAction Stop
    $importedModule = Get-Module -Name $ModuleName
    Write-Host "Imported $($importedModule.Name) $($importedModule.Version) from $($importedModule.ModuleBase)"
    Confirm-Condition -Condition ($importedModule.ModuleBase -like "$IsolatedModulePath*") -Description "$ModuleName was imported from the isolated path"

    Write-Host ''
    Write-Host '--- Required modules loaded into the session ---'
    foreach ($dependencyName in $dependencyNames) {
        $loadedDependency = Get-Module -Name $dependencyName
        Confirm-Condition -Condition ($null -ne $loadedDependency) -Description "$dependencyName was loaded by the import"
        Confirm-Condition -Condition ($loadedDependency.ModuleBase -like "$IsolatedModulePath*") -Description "$dependencyName was loaded from the isolated path, not from an installed copy"
        Write-Host "    $dependencyName $($loadedDependency.Version) from $($loadedDependency.ModuleBase)"
    }

    Write-Host ''
    Write-Host '--- Exported command surface ---'
    $declaredFunctions = @((Import-PowerShellDataFile -Path $savedManifestPath.FullName).FunctionsToExport)
    $exportedFunctions = @($importedModule.ExportedFunctions.Keys)
    Write-Host "  Declared functions ($($declaredFunctions.Count)): $($declaredFunctions -join ', ')"
    Write-Host "  Exported functions ($($exportedFunctions.Count)): $($exportedFunctions -join ', ')"
    $missingFunctions = @($declaredFunctions | Where-Object { $exportedFunctions -notcontains $_ })
    Confirm-Condition -Condition ($missingFunctions.Count -eq 0) -Description "Every function the manifest declares is exported (missing: $($missingFunctions -join ', '))"
    Confirm-Condition -Condition ($exportedFunctions.Count -eq $declaredFunctions.Count) -Description "The module exports exactly the $($declaredFunctions.Count) functions the manifest declares"

    $exportedAliases = @($importedModule.ExportedAliases.Keys)
    Write-Host "  Exported aliases ($($exportedAliases.Count)): $($exportedAliases -join ', ')"
    Confirm-Condition -Condition ($exportedAliases -contains $ExpectedAlias) -Description "The module exports the $ExpectedAlias alias"

    Write-Host ''
    Write-Host 'RESULT: install-time dependency resolution passed.'
    exit 0
} catch {
    Write-Host ''
    Write-Host "RESULT: the isolated probe failed - $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    exit 1
}
