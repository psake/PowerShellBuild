#requires -Version 7.0
<#
.SYNOPSIS
    Publishes the built PowerShellBuild module into a temporary file-share repository and proves,
    in an isolated process, that its declared dependencies resolve at install time.

.DESCRIPTION
    CI builds this module on every push but has never installed it. A build cannot observe an
    install-time break: a RequiredModules entry naming a version that does not exist, or a
    dependency that was removed from the manifest but is still needed. This script closes that
    gap without touching the PowerShell Gallery or the machine's module store. See
    psake/PowerShellBuild#229 for the measurements behind it.

    What it does:

      1. Builds the module (unless -SkipBuild).
      2. Stages a tools module path holding only PowerShellGet and PackageManagement.
      3. Registers a temporary file-share repository under the working root.
      4. Mirrors every RequiredModules entry from the PowerShell Gallery into that repository,
         because Save-Module resolves dependencies only from the repository it saves from.
      5. Publishes the built module into that repository.
      6. Runs Test-InstallTimeDependency.ps1 in a fresh process of the requested edition, whose
         PSModulePath holds only an empty directory and the tools path.
      7. Negative control (unless -SkipNegativeControl): republishes a scratch copy of the module
         whose manifest demands a dependency version that does not exist, and asserts the save
         fails with nothing on disk.
      8. Unregisters the temporary repository however the run ends.

    What this test deliberately does NOT cover. A local repository is a snapshot of three pinned
    packages, so a green run says nothing about:

      - the live dependency graph - the real gallery resolves the newest package satisfying each
        range, not the floor version mirrored here;
      - transitive dependency drift in those packages' own dependencies;
      - PowerShell Gallery ingestion of the published package;
      - real network transport, especially the TLS and proxy behavior of Windows PowerShell 5.1.

    Do not extend this test to prerelease behavior. Against a file-share repository,
    PowerShellGet 2.x gets prerelease gating wrong - Find-Module without -AllowPrerelease returns
    a prerelease package - so any prerelease assertion made here would be testing the harness
    rather than the module. PSResourceGet gates the same folder correctly if that coverage is
    ever wanted.

.PARAMETER ProbeEdition
    Which PowerShell edition runs the isolated probe. This script itself always runs on
    PowerShell 7, because the build and the publish are the same work for both editions; only the
    install is edition-specific.

.PARAMETER WorkingRootPath
    Where the local repository, the tools module path, and the isolated module paths are created.
    Defaults to a directory under the runner temporary path, or the system temporary path when
    running outside CI.

.PARAMETER RepositoryName
    The name to register the temporary file-share repository under.

.PARAMETER ModuleName
    The module under test.

.PARAMETER SkipBuild
    Reuse the existing contents of the Output directory instead of building.

.PARAMETER SkipNegativeControl
    Skip the negative control. The positive result alone is not evidence that the test can fail,
    so only skip this while iterating locally.

.EXAMPLE
    ./tests/InstallTime/Invoke-LocalRepositoryInstallTest.ps1 -ProbeEdition PowerShell7

.EXAMPLE
    ./tests/InstallTime/Invoke-LocalRepositoryInstallTest.ps1 -ProbeEdition WindowsPowerShell -SkipBuild
#>
[CmdletBinding()]
param(
    [ValidateSet('PowerShell7', 'WindowsPowerShell')]
    [string]
    $ProbeEdition = 'PowerShell7',

    [ValidateNotNullOrEmpty()]
    [string]
    $WorkingRootPath,

    [ValidateNotNullOrEmpty()]
    [string]
    $RepositoryName = 'PowerShellBuildInstallTest',

    [ValidateNotNullOrEmpty()]
    [string]
    $ModuleName = 'PowerShellBuild',

    [switch]
    $SkipBuild,

    [switch]
    $SkipNegativeControl
)

$ErrorActionPreference = 'Stop'

# The versions of the two packaging modules staged into the isolated probe's tools path. They are
# taken from the PowerShell Gallery rather than copied off the running machine because the
# PackageManagement that ships inside PowerShell 7 carries coreclr binaries only and will not load
# on Windows PowerShell 5.1, while the gallery package carries both coreclr and fullclr.
$powerShellGetVersion = '2.2.5'
$packageManagementVersion = '1.4.8.1'

# The dependency version demanded by the negative control. Nothing resolvable may ever exist at
# this version.
$unsatisfiableDependencyVersion = '99.0.0'

# The module version the negative control publishes under, so that it can never be confused with
# the real package in the same repository.
$negativeControlModuleVersion = '999.0.0'

function Reset-Directory {
    <#
    .SYNOPSIS
    Removes a directory if it exists and recreates it empty.

    .PARAMETER Path
    The directory to recreate.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path
    )

    if ($PSCmdlet.ShouldProcess($Path, 'Recreate directory')) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Get-ProbeExecutablePath {
    <#
    .SYNOPSIS
    Resolves the executable that runs the isolated probe for a PowerShell edition.

    .PARAMETER Edition
    Either PowerShell7 or WindowsPowerShell.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('PowerShell7', 'WindowsPowerShell')]
        [string]
        $Edition
    )

    if ($Edition -eq 'WindowsPowerShell') {
        $windowsPowerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path $windowsPowerShellPath)) {
            throw "Windows PowerShell was not found at $windowsPowerShellPath. The WindowsPowerShell probe edition requires a Windows runner."
        }
        return $windowsPowerShellPath
    }

    $powerShell7Command = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $powerShell7Command) {
        throw 'pwsh was not found on PATH.'
    }
    return $powerShell7Command.Source
}

function Publish-MirroredDependency {
    <#
    .SYNOPSIS
    Copies one dependency from the PowerShell Gallery into the temporary local repository.

    .DESCRIPTION
    Save-Module and Install-Module resolve a package's dependencies only from the repository the
    package itself came from, so every RequiredModules entry has to exist in the local repository
    before the module under test can be saved from it.

    .PARAMETER Name
    The dependency module name.

    .PARAMETER Version
    The exact dependency version to mirror.

    .PARAMETER StagingPath
    A directory the gallery copy is saved into before being published.

    .PARAMETER RepositoryName
    The local repository to publish the mirrored copy into.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Version,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $StagingPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $RepositoryName
    )

    Save-Module -Name $Name -RequiredVersion $Version -Repository 'PSGallery' -Path $StagingPath -Force
    $savedVersionPath = Join-Path -Path $StagingPath -ChildPath "$Name\$Version"
    if (-not (Test-Path $savedVersionPath)) {
        throw "Saving $Name $Version from the PowerShell Gallery did not produce $savedVersionPath."
    }
    Publish-Module -Path $savedVersionPath -Repository $RepositoryName -NuGetApiKey 'local-repository-not-a-real-key' -Force
    Write-Host "  mirrored $Name $Version"
}

function Invoke-IsolatedProbe {
    <#
    .SYNOPSIS
    Runs the isolated install probe in a fresh process, streaming its output.

.DESCRIPTION
    The probe's own output is written straight through, so the caller reads the result from
    $LASTEXITCODE after this function returns rather than from a return value.

    .PARAMETER ExecutablePath
    The PowerShell executable to run the probe with.

    .PARAMETER ProbeScriptPath
    The path to Test-InstallTimeDependency.ps1.

    .PARAMETER IsolatedModulePath
    An empty directory used as the Save-Module target.

    .PARAMETER ToolsModulePath
    The directory holding only PowerShellGet and PackageManagement.

    .PARAMETER RepositoryName
    The local repository to save from.

    .PARAMETER ModuleName
    The module under test.

    .PARAMETER RequiredVersion
    The exact version of the module under test to save.

    .PARAMETER ExpectSaveToFail
    Run the probe in negative-control mode.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ExecutablePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ProbeScriptPath,

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

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ModuleName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $RequiredVersion,

        [switch]
        $ExpectSaveToFail
    )

    Reset-Directory -Path $IsolatedModulePath

    $probeArguments = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', $ProbeScriptPath
        '-IsolatedModulePath', $IsolatedModulePath
        '-ToolsModulePath', $ToolsModulePath
        '-RepositoryName', $RepositoryName
        '-ModuleName', $ModuleName
        '-RequiredVersion', $RequiredVersion
    )
    if ($ExpectSaveToFail) {
        $probeArguments += '-ExpectSaveToFail'
    }

    & $ExecutablePath @probeArguments
}

$repositoryRootPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
$probeScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'Test-InstallTimeDependency.ps1'

if (-not $WorkingRootPath) {
    $temporaryRootPath = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
    $WorkingRootPath = Join-Path -Path $temporaryRootPath -ChildPath 'PowerShellBuildInstallTest'
}

$paths = @{
    LocalRepository        = Join-Path -Path $WorkingRootPath -ChildPath 'localRepository'
    DependencyStaging      = Join-Path -Path $WorkingRootPath -ChildPath 'dependencyStaging'
    Tools                  = Join-Path -Path $WorkingRootPath -ChildPath 'toolsModulePath'
    Isolated               = Join-Path -Path $WorkingRootPath -ChildPath 'isolatedModulePath'
    NegativeIsolated       = Join-Path -Path $WorkingRootPath -ChildPath 'negativeIsolatedModulePath'
    NegativeModule         = Join-Path -Path $WorkingRootPath -ChildPath 'negativeModule'
    NegativeStubDependency = Join-Path -Path $WorkingRootPath -ChildPath 'negativeStubDependency'
}

Write-Host '=== Local repository install test ==='
Write-Host "Repository root: $repositoryRootPath"
Write-Host "Working root:    $WorkingRootPath"
Write-Host "Probe edition:   $ProbeEdition"

$probeExecutablePath = Get-ProbeExecutablePath -Edition $ProbeEdition
Write-Host "Probe executable: $probeExecutablePath"

Write-Host ''
Write-Host '=== 1. Build the module ==='
if ($SkipBuild) {
    Write-Host 'Skipped; reusing the existing Output directory.'
} else {
    # Built in a child process so that psake, BuildHelpers, and the rest of the build's own
    # dependencies never enter this session.
    Push-Location -Path $repositoryRootPath
    try {
        & (Get-ProbeExecutablePath -Edition 'PowerShell7') -NoProfile -File (Join-Path -Path $repositoryRootPath -ChildPath 'build.ps1') -Task Build -Bootstrap
        if ($LASTEXITCODE -ne 0) {
            throw "The build failed with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
}

$builtModulePath = Get-ChildItem -Path (Join-Path -Path $repositoryRootPath -ChildPath "Output\$ModuleName") -Directory |
    Sort-Object -Property { [version]$_.Name } -Descending |
    Select-Object -First 1
if (-not $builtModulePath) {
    throw "No built module was found under $repositoryRootPath\Output\$ModuleName."
}
$builtModuleVersion = $builtModulePath.Name
$builtManifestPath = Join-Path -Path $builtModulePath.FullName -ChildPath "$ModuleName.psd1"
Write-Host "Built $ModuleName $builtModuleVersion at $($builtModulePath.FullName)"

$builtManifest = Import-PowerShellDataFile -Path $builtManifestPath
$requiredModules = @($builtManifest.RequiredModules)
Write-Host 'RequiredModules declared by the built manifest:'
foreach ($requiredModule in $requiredModules) {
    Write-Host "  $($requiredModule.ModuleName) $($requiredModule.ModuleVersion)"
}
if ($requiredModules.Count -eq 0) {
    throw 'The built manifest declares no RequiredModules; there is nothing for this test to prove.'
}

Write-Host ''
Write-Host '=== 2. Stage the tools module path ==='
Reset-Directory -Path $paths.Tools
PackageManagement\Get-PackageProvider -Name 'NuGet' -ForceBootstrap | Out-Null
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
Save-Module -Name 'PowerShellGet' -RequiredVersion $powerShellGetVersion -Repository 'PSGallery' -Path $paths.Tools -Force
Save-Module -Name 'PackageManagement' -RequiredVersion $packageManagementVersion -Repository 'PSGallery' -Path $paths.Tools -Force
# Saving PowerShellGet brings its own PackageManagement dependency along, which may be a different
# version. Keep only the pinned one so the probe has exactly one candidate to import.
Get-ChildItem -Path (Join-Path -Path $paths.Tools -ChildPath 'PackageManagement') -Directory |
    Where-Object { $_.Name -ne $packageManagementVersion } |
    Remove-Item -Recurse -Force
Get-ChildItem -Path $paths.Tools -Directory | ForEach-Object {
    Write-Host "  staged $($_.Name) $((Get-ChildItem -Path $_.FullName -Directory).Name -join ', ')"
}

try {
    Write-Host ''
    Write-Host '=== 3. Register the temporary file-share repository ==='
    Reset-Directory -Path $paths.LocalRepository
    if (Get-PSRepository -Name $RepositoryName -ErrorAction SilentlyContinue) {
        Unregister-PSRepository -Name $RepositoryName
    }
    Register-PSRepository -Name $RepositoryName -SourceLocation $paths.LocalRepository -PublishLocation $paths.LocalRepository -InstallationPolicy Trusted
    Write-Host "Registered $RepositoryName at $($paths.LocalRepository)"

    Write-Host ''
    Write-Host '=== 4. Mirror the required modules into the local repository ==='
    Reset-Directory -Path $paths.DependencyStaging
    foreach ($requiredModule in $requiredModules) {
        Publish-MirroredDependency -Name $requiredModule.ModuleName -Version $requiredModule.ModuleVersion -StagingPath $paths.DependencyStaging -RepositoryName $RepositoryName
    }

    Write-Host ''
    Write-Host "=== 5. Publish $ModuleName $builtModuleVersion into the local repository ==="
    # Publish-Module validates every RequiredModules entry against the destination repository and
    # refuses to publish when one cannot be resolved. The same gate runs against the PowerShell
    # Gallery, so an unsatisfiable dependency fails the release rather than reaching consumers.
    Publish-Module -Path $builtModulePath.FullName -Repository $RepositoryName -NuGetApiKey 'local-repository-not-a-real-key' -Force
    Get-ChildItem -Path $paths.LocalRepository | ForEach-Object { Write-Host "  $($_.Name)" }

    Write-Host ''
    Write-Host "=== 6. Positive probe on $ProbeEdition ==="
    Invoke-IsolatedProbe -ExecutablePath $probeExecutablePath -ProbeScriptPath $probeScriptPath `
        -IsolatedModulePath $paths.Isolated -ToolsModulePath $paths.Tools -RepositoryName $RepositoryName `
        -ModuleName $ModuleName -RequiredVersion $builtModuleVersion
    $positiveExitCode = $LASTEXITCODE
    if ($positiveExitCode -ne 0) {
        throw "The install probe failed on $ProbeEdition with exit code $positiveExitCode."
    }

    if ($SkipNegativeControl) {
        Write-Host ''
        Write-Host '=== 7. Negative control skipped ==='
    } else {
        Write-Host ''
        Write-Host '=== 7. Negative control: an unsatisfiable dependency must fail the save ==='

        # Break a scratch copy of the built module rather than the build output itself.
        Reset-Directory -Path $paths.NegativeModule
        $negativeModulePath = Join-Path -Path $paths.NegativeModule -ChildPath $ModuleName
        Copy-Item -Path $builtModulePath.FullName -Destination $negativeModulePath -Recurse -Force
        $negativeManifestPath = Join-Path -Path $negativeModulePath -ChildPath "$ModuleName.psd1"

        $brokenDependencyName = $requiredModules[0].ModuleName
        $brokenDependencyVersion = $requiredModules[0].ModuleVersion
        $originalManifestContent = Get-Content -Path $negativeManifestPath -Raw
        $negativeManifestContent = $originalManifestContent `
            -replace "(?m)^(?<indent>\s*)ModuleVersion(?<spacing>\s*)=\s*'[^']+'", "`${indent}ModuleVersion`${spacing}= '$negativeControlModuleVersion'" `
            -replace "(ModuleName\s*=\s*'$([regex]::Escape($brokenDependencyName))'\s*;\s*ModuleVersion\s*=\s*)'$([regex]::Escape($brokenDependencyVersion))'", "`${1}'$unsatisfiableDependencyVersion'"
        Set-Content -Path $negativeManifestPath -Value $negativeManifestContent -NoNewline -Encoding utf8BOM

        # A silent regex miss here would turn the negative control into a second positive run, so
        # confirm both edits actually landed before relying on them.
        $negativeManifest = Import-PowerShellDataFile -Path $negativeManifestPath
        if ($negativeManifest.ModuleVersion -ne $negativeControlModuleVersion) {
            throw "The negative control could not rewrite ModuleVersion to $negativeControlModuleVersion."
        }
        $brokenRequirement = @($negativeManifest.RequiredModules) | Where-Object { $_.ModuleName -eq $brokenDependencyName }
        if ($brokenRequirement.ModuleVersion -ne $unsatisfiableDependencyVersion) {
            throw "The negative control could not rewrite the $brokenDependencyName requirement to $unsatisfiableDependencyVersion."
        }
        Write-Host "Broken manifest: $ModuleName $negativeControlModuleVersion requiring $brokenDependencyName $unsatisfiableDependencyVersion"

        Write-Host ''
        Write-Host '--- 7a. Publish-Module must refuse the broken package ---'
        $publishRefused = $false
        try {
            Publish-Module -Path $negativeModulePath -Repository $RepositoryName -NuGetApiKey 'local-repository-not-a-real-key' -Force
        } catch {
            $publishRefused = $true
            Write-Host "Publish-Module refused it: $($_.FullyQualifiedErrorId)"
        }
        if (-not $publishRefused) {
            throw "Publish-Module accepted a package requiring $brokenDependencyName $unsatisfiableDependencyVersion; the negative control cannot be staged."
        }

        Write-Host ''
        Write-Host '--- 7b. Stage the broken package behind a throwaway stub ---'
        # Publish-Module will not stage the broken package while the dependency is missing, so
        # publish a stub at the unsatisfiable version, publish the broken package, then delete the
        # stub package again. What is left is a package whose dependency cannot be resolved -
        # exactly the shape of a manifest that names a version that was never released.
        $stubVersionPath = Join-Path -Path $paths.NegativeStubDependency -ChildPath "$brokenDependencyName\$unsatisfiableDependencyVersion"
        Reset-Directory -Path $stubVersionPath
        Set-Content -Path (Join-Path -Path $stubVersionPath -ChildPath "$brokenDependencyName.psm1") -Value 'function Invoke-InstallTestStub { }' -Encoding utf8BOM
        New-ModuleManifest -Path (Join-Path -Path $stubVersionPath -ChildPath "$brokenDependencyName.psd1") `
            -RootModule "$brokenDependencyName.psm1" -ModuleVersion $unsatisfiableDependencyVersion `
            -Author 'PowerShellBuild install test' -CompanyName 'PowerShellBuild install test' `
            -Description 'Throwaway stub used only to stage the negative control package.' `
            -FunctionsToExport 'Invoke-InstallTestStub'
        Publish-Module -Path $stubVersionPath -Repository $RepositoryName -NuGetApiKey 'local-repository-not-a-real-key' -Force
        Publish-Module -Path $negativeModulePath -Repository $RepositoryName -NuGetApiKey 'local-repository-not-a-real-key' -Force
        $stubPackagePath = Join-Path -Path $paths.LocalRepository -ChildPath "$brokenDependencyName.$unsatisfiableDependencyVersion.nupkg"
        Remove-Item -Path $stubPackagePath -Force
        Write-Host "Removed the stub package $brokenDependencyName $unsatisfiableDependencyVersion from the local repository."

        Write-Host ''
        Write-Host "--- 7c. Save-Module must now fail on $ProbeEdition ---"
        Invoke-IsolatedProbe -ExecutablePath $probeExecutablePath -ProbeScriptPath $probeScriptPath `
            -IsolatedModulePath $paths.NegativeIsolated -ToolsModulePath $paths.Tools -RepositoryName $RepositoryName `
            -ModuleName $ModuleName -RequiredVersion $negativeControlModuleVersion
        $negativeExitCode = $LASTEXITCODE
        if ($negativeExitCode -ne 0) {
            throw "The negative control failed on $ProbeEdition with exit code $negativeExitCode; this test cannot be trusted to fail when the manifest is broken."
        }

        Remove-Item -Path (Join-Path -Path $paths.LocalRepository -ChildPath "$ModuleName.$negativeControlModuleVersion.nupkg") -Force -ErrorAction SilentlyContinue
    }

    Write-Host ''
    Write-Host "=== Local repository install test passed on $ProbeEdition ==="
} finally {
    if (Get-PSRepository -Name $RepositoryName -ErrorAction SilentlyContinue) {
        Unregister-PSRepository -Name $RepositoryName
        Write-Host "Unregistered $RepositoryName."
    }
}
