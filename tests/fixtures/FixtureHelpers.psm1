function Copy-PSBuildTestFixture {
    <#
    .SYNOPSIS
        Copy the PSBuildTestFixture module to a destination directory.
    .DESCRIPTION
        Copies the checked-in PSBuildTestFixture module into the supplied destination (typically
        $TestDrive) and returns the path of the copy. Tests must always operate on a copy so that
        no test run ever mutates the checked-in fixture and every test starts from a pristine
        fixture state.
    .PARAMETER Destination
        Directory to copy the fixture into. The copy is created as a PSBuildTestFixture
        subdirectory of this path.
    .EXAMPLE
        PS> $fixturePath = Copy-PSBuildTestFixture -Destination $TestDrive

        Copies the fixture module into the Pester test drive and returns the path of the copy.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Destination
    )

    $fixtureSourcePath = Join-Path -Path $PSScriptRoot -ChildPath 'PSBuildTestFixture'
    $fixtureCopyPath = Join-Path -Path $Destination -ChildPath 'PSBuildTestFixture'

    # Remove any previous copy and recreate the directory before copying the fixture
    # contents. Copying into an existing directory would otherwise nest a second
    # PSBuildTestFixture directory inside it, and the destination (or its parents)
    # may not exist yet.
    if (Test-Path -Path $fixtureCopyPath) {
        Remove-Item -Path $fixtureCopyPath -Recurse -Force
    }
    New-Item -Path $fixtureCopyPath -ItemType Directory -Force > $null
    Copy-Item -Path (Join-Path -Path $fixtureSourcePath -ChildPath '*') -Destination $fixtureCopyPath -Recurse -Force

    $fixtureCopyPath
}

function New-PSBuildDocsScenario {
    <#
    .SYNOPSIS
        Create an isolated project directory holding a copy of the test fixture, plus the paths
        the help building functions read and write.
    .DESCRIPTION
        Builds the directory layout the docs pipeline expects -- a project root containing a
        same-named module subdirectory, matching the shape Set-BuildEnvironment resolves -- and
        returns the paths derived from it so tests do not recompute them.

        Only the project root and the fixture copy are created. The docs and output directories
        are returned as paths, because the functions under test are responsible for creating
        them and a test that pre-created them could not tell the difference.
    .PARAMETER Path
        Directory to create the scenario under, typically $TestDrive. Passed in rather than read
        from the caller because $TestDrive is a Pester construct and is not visible inside a
        module scope.
    .PARAMETER Name
        Name of the scenario directory. Give each scenario its own name so that scenarios in the
        same test run cannot observe each other's output.
    .PARAMETER Locale
        Help locale the scenario is built for. Defaults to en-US, which is what the fixture's
        comment-based help is written in.
    .EXAMPLE
        PS> $scenario = New-PSBuildDocsScenario -Path $TestDrive -Name 'markdown'

        Creates $TestDrive/markdown/PSBuildTestFixture and returns the scenario paths.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    # Creates a scenario directory but is a test helper, not a user-facing command; a
    # -WhatIf that skipped the copy would leave every caller with nothing to test.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,

        [ValidateNotNullOrEmpty()]
        [string]
        $Locale = 'en-US'
    )

    $projectRoot = Join-Path -Path $Path -ChildPath $Name
    $modulePath = Copy-PSBuildTestFixture -Destination $projectRoot
    $outputPath = Join-Path -Path $projectRoot -ChildPath 'Output'

    [PSCustomObject]@{
        ProjectRoot       = $projectRoot
        ModulePath        = $modulePath
        ModuleName        = 'PSBuildTestFixture'
        Locale            = $Locale
        DocsPath          = Join-Path -Path $projectRoot -ChildPath 'docs'
        LocalePath        = [IO.Path]::Combine($projectRoot, 'docs', $Locale)
        OutputPath        = $outputPath
        MamlPath          = [IO.Path]::Combine($outputPath, $Locale, 'PSBuildTestFixture-help.xml')
        UpdatableHelpPath = Join-Path -Path $outputPath -ChildPath 'UpdatableHelp'
    }
}

function New-PSBuildMarkdownParameter {
    <#
    .SYNOPSIS
        Build the Build-PSBuildMarkdown parameter set for a docs scenario.
    .DESCRIPTION
        Build-PSBuildMarkdown takes four mandatory [bool] parameters that most tests do not care
        about but cannot omit. This supplies them at their build.properties.ps1 defaults so a
        test only has to name the ones it is actually exercising.
    .PARAMETER Scenario
        Scenario object from New-PSBuildDocsScenario.
    .PARAMETER Overwrite
        Whether comment-based help overwrites existing markdown. Defaults to $false, matching
        $PSBPreference.Docs.Overwrite.
    .PARAMETER AlphabeticParamsOrder
        Whether parameters are ordered alphabetically. Defaults to $false, matching
        $PSBPreference.Docs.AlphabeticParamsOrder.
    .PARAMETER ExcludeDontShow
        Whether parameters marked DontShow are excluded. Defaults to $false, matching
        $PSBPreference.Docs.ExcludeDontShow.
    .PARAMETER UseFullTypeName
        Whether full type names are used. Defaults to $false, matching
        $PSBPreference.Docs.UseFullTypeName.
    .EXAMPLE
        PS> $parameter = New-PSBuildMarkdownParameter -Scenario $scenario

        Returns the default parameter set for the scenario.
    .OUTPUTS
        System.Collections.Hashtable
    #>
    # Builds and returns a hashtable; it changes nothing. The rule fires on the New- verb
    # alone, and New- is the accurate verb for what this does.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $Scenario,

        [bool]
        $Overwrite = $false,

        [bool]
        $AlphabeticParamsOrder = $false,

        [bool]
        $ExcludeDontShow = $false,

        [bool]
        $UseFullTypeName = $false
    )

    @{
        ModulePath            = $Scenario.ModulePath
        ModuleName            = $Scenario.ModuleName
        DocsPath              = $Scenario.DocsPath
        Locale                = $Scenario.Locale
        Overwrite             = $Overwrite
        AlphabeticParamsOrder = $AlphabeticParamsOrder
        ExcludeDontShow       = $ExcludeDontShow
        UseFullTypeName       = $UseFullTypeName
    }
}

function Invoke-PSBuildCommandInJob {
    <#
    .SYNOPSIS
        Run one PowerShellBuild command in a background job and report what happened.
    .DESCRIPTION
        Imports the built PowerShellBuild module inside a background job, invokes the named
        command there, and returns a result object rather than throwing. Reporting instead of
        throwing keeps a failure legible: the test asserts on ErrorMessage instead of an opaque
        job error.

        A job is used because some commands cannot be exercised in the caller's session. The
        docs pipeline is the current example: platyPS 0.14.2 and Microsoft.PowerShell.PlatyPS
        1.x each load their own YamlDotNet.dll through NestedModules with different assembly
        identities, so whichever imports second fails with "Assembly with same name is already
        loaded". A separate runspace does not escape that; only a separate process does. Pester
        recommends the same technique for session isolation, see
        https://pester.dev/docs/usage/mocking.
    .PARAMETER ModulePath
        Path to the built PowerShellBuild module to import inside the job.
    .PARAMETER CommandName
        Name of the command to invoke.
    .PARAMETER Parameter
        Parameters to splat onto the command.
    .PARAMETER TimeoutSecond
        How long to wait before giving up. A hung job would otherwise stall CI with no output
        and no error, so the timeout is reported as a failure like any other. Defaults to 300.
    .EXAMPLE
        PS> $result = Invoke-PSBuildCommandInJob -ModulePath $builtModulePath -CommandName 'Build-PSBuildMarkdown' -Parameter $parameter

        Runs Build-PSBuildMarkdown in a job and returns Threw, ErrorMessage, and Output.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    #>
    # The job scriptblock declares its own param() block and receives values through
    # -ArgumentList, which is the documented alternative to $using:. The analyzer does not
    # model that pairing and reports every parameter as an undeclared variable.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseUsingScopeModifierInNewRunspaces', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ModulePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $CommandName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]
        $Parameter,

        [ValidateRange(1, 3600)]
        [int]
        $TimeoutSecond = 300
    )

    $job = Start-Job -ScriptBlock {
        param($modulePath, $commandName, $parameter)

        Import-Module -Name $modulePath -Force -ErrorAction Stop

        $threw = $false
        $errorMessage = $null
        # Capture the command's own output rather than letting it fall through to the job's
        # output stream, where it would be interleaved with the result object below.
        $commandOutput = @()
        try {
            $commandOutput = @(& $commandName @parameter -ErrorAction Stop)
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        [PSCustomObject]@{
            Threw        = $threw
            ErrorMessage = $errorMessage
            Output       = $commandOutput
        }
    } -ArgumentList $ModulePath, $CommandName, $Parameter

    $completedJob = Wait-Job -Job $job -Timeout $TimeoutSecond
    if (-not $completedJob) {
        Stop-Job -Job $job
        Remove-Job -Job $job -Force
        return [PSCustomObject]@{
            Threw        = $true
            ErrorMessage = "$CommandName did not complete within $TimeoutSecond seconds."
            Output       = @()
        }
    }

    $jobResult = Receive-Job -Job $job
    Remove-Job -Job $job -Force
    $jobResult
}

Export-ModuleMember -Function @(
    'Copy-PSBuildTestFixture'
    'Invoke-PSBuildCommandInJob'
    'New-PSBuildDocsScenario'
    'New-PSBuildMarkdownParameter'
)
