# Taken with love from @juneb_get_help (https://raw.githubusercontent.com/juneb/PesterTDD/master/Module.Help.Tests.ps1)

BeforeDiscovery {
    function global:FilterOutCommonParams {
        param ($Params)
        $commonParams = [System.Management.Automation.PSCmdlet]::OptionalCommonParameters +
            [System.Management.Automation.PSCmdlet]::CommonParameters
        $params | Where-Object { $_.Name -notin $commonParams } | Sort-Object -Property Name -Unique
    }

    # This file needs two things the psake build produces: BuildHelpers' BH* variables, and the
    # built module under Output/. When Pester is invoked directly neither exists, so build once
    # rather than failing -- psake/psake's own Help.tests.ps1 takes the same approach, and
    # Manifest.tests.ps1 does the environment half of it here. Inside a build this is a no-op,
    # because build.ps1 has already called Set-BuildEnvironment.
    #
    # The check stays conditional deliberately. Calling Set-BuildEnvironment unconditionally lets
    # an escaping 'break' from BuildHelpers' Get-BuildVariable switch blocks unwind out of this
    # block, which psake 4.9.x absorbs and psake 5.x does not -- Pester then fails the whole
    # container. Manifest.tests.ps1 carries the same guard for the same reason.
    if (-not $env:BHProjectName) {
        $repositoryRoot = Split-Path -Path $PSScriptRoot -Parent
        Push-Location -LiteralPath $repositoryRoot
        try {
            # Resolved from $PSScriptRoot rather than the current directory, so this works
            # wherever Pester was invoked from.
            & ([IO.Path]::Combine($repositoryRoot, 'build.ps1')) -Task Build
        } finally {
            Pop-Location
        }
    }

    $manifest             = Import-PowerShellDataFile -Path $env:BHPSModuleManifest
    $outputDir            = Join-Path -Path $env:BHProjectPath -ChildPath 'Output'
    $outputModDir         = Join-Path -Path $outputDir -ChildPath $env:BHProjectName
    $outputModVerDir      = Join-Path -Path $outputModDir -ChildPath $manifest.ModuleVersion
    $outputModVerManifest = Join-Path -Path $outputModVerDir -ChildPath "$($env:BHProjectName).psd1"

    # Get module commands
    # Remove all versions of the module from the session. Pester can't handle multiple versions.
    Get-Module $env:BHProjectName | Remove-Module -Force -ErrorAction Ignore
    Import-Module -Name $outputModVerManifest -Verbose:$false -ErrorAction Stop

    # Resolve the module explicitly. An unresolved module must never reach Get-Command, where a
    # $null -Module means "no filter" rather than "no commands".
    $module = Get-Module -Name $env:BHProjectName
    if (-not $module) {
        throw (
            "Module '$($env:BHProjectName)' is not loaded after importing '$outputModVerManifest'. " +
            "Build the module first with './build.ps1 -Task Build'."
        )
    }

    $getCommandParameters = @{
        Module      = $module
        CommandType = [System.Management.Automation.CommandTypes[]]'Cmdlet, Function' # Not alias
    }
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $getCommandParameters.CommandType[0] += 'Workflow'
    }
    $commands = Get-Command @getCommandParameters

    # Sanity check the discovered command set against the manifest so this file can never again
    # pass while testing commands that do not belong to the module.
    $expectedCommandName   = @($manifest.FunctionsToExport) | Sort-Object
    $discoveredCommandName = @($commands.Name) | Sort-Object
    if (($discoveredCommandName -join ', ') -ne ($expectedCommandName -join ', ')) {
        # Summarize rather than list every name: a widened set can hold thousands of them.
        $maximumNameToList = 15
        $discoveredSummary = if ($discoveredCommandName.Count -gt $maximumNameToList) {
            $listedName = $discoveredCommandName | Select-Object -First $maximumNameToList
            "$($listedName -join ', '), ... (+$($discoveredCommandName.Count - $maximumNameToList) more)"
        } else {
            $discoveredCommandName -join ', '
        }
        throw (
            "Discovered $($discoveredCommandName.Count) command(s) for module " +
            "'$($env:BHProjectName)' but its manifest exports $($expectedCommandName.Count). " +
            "Expected [$($expectedCommandName -join ', ')]. Discovered [$discoveredSummary]."
        )
    }

    ## When testing help, remember that help is cached at the beginning of each session.
    ## To test, restart session.
}

AfterAll {
    Remove-Item Function:/FilterOutCommonParams
}

# Reports in the test results what the discovery-time guard above enforces: the commands whose
# help is tested are exactly the ones the module manifest exports.
Describe 'Command discovery' -ForEach @{
    ExpectedCommandName   = $expectedCommandName
    DiscoveredCommandName = $discoveredCommandName
} {
    It 'Finds exactly the commands the module manifest exports' {
        ($DiscoveredCommandName -join ', ') | Should -Be ($ExpectedCommandName -join ', ')
    }
}

Describe "Test help for <_.Name>" -ForEach $commands {

    BeforeDiscovery {
        # Get command help, parameters, and links
        $command               = $_
        $commandHelp           = Get-Help $command.Name -ErrorAction SilentlyContinue
        $commandParameters     = global:FilterOutCommonParams -Params $command.ParameterSets.Parameters
        $commandParameterNames = $commandParameters.Name
        $helpLinks             = $commandHelp.relatedLinks.navigationLink.uri
        $helpParameters        = global:FilterOutCommonParams -Params $commandHelp.Parameters.Parameter
        $helpParameterNames    = $helpParameters.Name
    }

    BeforeAll {
        # These vars are needed in both discovery and test phases so we need to duplicate them here
        $command                = $_
        $commandName            = $_.Name
        $commandHelp            = Get-Help $command.Name -ErrorAction SilentlyContinue
        $commandParameters      = global:FilterOutCommonParams -Params $command.ParameterSets.Parameters
        $commandParameterNames  = $commandParameters.Name
        $helpParameters         = global:FilterOutCommonParams -Params $commandHelp.Parameters.Parameter
        $helpParameterNames     = $helpParameters.Name
    }

    # If help is not found, synopsis in auto-generated help is the syntax diagram
    It 'Help is not auto-generated' {
        $commandHelp.Synopsis | Should -Not -BeLike '*`[`<CommonParameters`>`]*'
    }

    # Should be a description for every function
    It "Has description" {
        $commandHelp.Description | Should -Not -BeNullOrEmpty
    }

    # Should be at least one example
    It "Has example code" {
        ($commandHelp.Examples.Example | Select-Object -First 1).Code | Should -Not -BeNullOrEmpty
    }

    # Should be at least one example description
    It "Has example help" {
        ($commandHelp.Examples.Example.Remarks | Select-Object -First 1).Text | Should -Not -BeNullOrEmpty
    }

    # The if guards around the data-driven blocks below skip generation when the
    # collection is empty. Pester 5 skipped empty -ForEach silently; Pester 6 fails
    # discovery instead, and these guards keep the v5 behavior on both versions.
    if ($helpLinks) {
        It "Help link <_> is valid" -ForEach $helpLinks {
            (Invoke-WebRequest -Uri $_ -UseBasicParsing).StatusCode | Should -Be '200'
        }
    }

    if ($commandParameters) {
        Context "Parameter <_.Name>" -Foreach $commandParameters {

            BeforeAll {
                $parameter         = $_
                $parameterName     = $parameter.Name
                $parameterHelp     = $commandHelp.parameters.parameter | Where-Object Name -eq $parameterName
                $parameterHelpType = if ($parameterHelp.ParameterValue) { $parameterHelp.ParameterValue.Trim() }
            }

            # Should be a description for every parameter
            It "Has description" {
                $parameterHelp.Description.Text | Should -Not -BeNullOrEmpty
            }

            # Required value in Help should match IsMandatory property of parameter
            It "Has correct [mandatory] value" {
                $codeMandatory = $_.IsMandatory.toString()
                $parameterHelp.Required | Should -Be $codeMandatory
            }

            # Parameter type in help should match code
            It "Has correct parameter type" {
                $parameterHelpType | Should -Be $parameter.ParameterType.Name
            }
        }
    }

    if ($helpParameterNames) {
        Context "Test <_> help parameter help for <commandName>" -Foreach $helpParameterNames {

            # Shouldn't find extra parameters in help.
            It "finds help parameter in code: <_>" {
                $_ -in $commandParameterNames | Should -Be $true
            }
        }
    }
}
