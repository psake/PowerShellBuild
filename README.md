# PowerShellBuild

| AppVeyor | PS Gallery | License
|----------|--------|--------------------|
[![AppVeyor Build Status][appveyor-badge]][appveyor-build] | [![PowerShell Gallery][psgallery-badge]][psgallery] | [![License][license-badge]][license]

This project aims to provide common [psake](https://github.com/psake/psake) and [Invoke-Build](https://github.com/nightroman/Invoke-Build) tasks for building, testing, and publishing PowerShell modules.

Using these shared tasks reduces the boilerplate scaffolding needed in most PowerShell module projects and help enforce a consistent module structure.
This consistency ultimately helps the community in building high-quality PowerShell modules.

> If using [psake](https://github.com/psake/psake) as your task runner, version `4.8.0` or greater is required to make use of shared tasks distributed in separate modules.
> To install psake `4.8.0` you can run:

```powershell
Install-Module -Name psake -RequiredVersion 4.8.0 -Repository PSGallery
```

> For [Invoke-Build](https://github.com/nightroman/Invoke-Build), see the [how to dot source tasks using PowerShell aliases](https://github.com/nightroman/Invoke-Build/blob/master/Tasks/Import/README.md#example-2-import-from-a-module-with-tasks) example.

<p align="center">
    <img src="media/psaketaskmodule-256x256.png" alt="Logo">
</p>

## Status - Work in progress

> This project is a **work in progress** and may change significantly before reaching stability based on feedback from the community.
> **Please do not base critical processes on this project** until it has been further refined.

## Tasks

**PowerShellBuild** is a PowerShell module that provides helper functions to handle the common build, test, and release steps typically found in PowerShell module projects.
These steps are exposed as a set of [psake](https://github.com/psake/psake) tasks found in [psakeFile.ps1](./PowerShellBuild/psakeFile.ps1) in the root of the module, and as PowerShell aliases which you can dot source if using [Invoke-Build](https://github.com/nightroman/Invoke-Build).
In psake `v4.8.0`, a feature was added to reference shared psake tasks distributed within PowerShell modules.
This allows a set of tasks to be versioned, distributed, and called by other projects.

### Primary Tasks

These primary tasks are the main tasks you'll typically call as part of PowerShell module development.

| Name                  | Dependencies          | Description |
| --------------------- | --------------------- | ----------- |
| Init                  | _none_                | Initialize psake and task variables
| Clean                 | init                  | Clean output directory
| Build                 | StageFiles, BuildHelp | Clean and build module in output directory
| Analyze               | Build                 | Run PSScriptAnalyzer tests
| Pester                | Build                 | Run Pester tests
| Test                  | Analyze, Pester       | Run combined tests
| Publish               | Test                  | Publish module to defined PowerShell repository

### Secondary Tasks

These secondary tasks are called as dependencies from the primary tasks but may also be called directly.

| Name                  | Dependencies                   | Description |
| --------------------- | -------------------------------| ----------- |
| BuildHelp             | GenerateMarkdown, GenerateMAML | Build all help files
| StageFiles            | Clean                          | Build module in output directory
| GenerateMarkdown      | StageFiles                     | Build markdown-based help
| GenerateMAML          | GenerateMarkdown               | Build MAML help
| GenerateUpdatableHelp | BuildHelp                      | Build updatable help cab

## Task customization

The psake and Invoke-Build tasks can be customized by overriding the values contained in the `$PSBPreference` hashtable. defined in the psake file.
These settings govern if certain tasks are executed or set default paths used to build and test the module.
You can override these in either psake or Invoke-Build to match your environment.

| Setting | Default value | Description |
|---------|---------------|-------------|
| $PSBPreference.General.ProjectRoot | $env:BHProjectPath | Root directory for the project
| $PSBPreference.General.SrcRootDir | $env:BHPSModulePath | Root directory for the module
| $PSBPreference.General.ModuleName | $env:BHProjectName | The name of the module. This should match the basename of the PSD1 file
| $PSBPreference.General.ModuleVersion | \<computed> | The version of the module
| $PSBPreference.General.ModuleManifestPath | $env:BHPSModuleManifest | Path to the module manifest (PSD1)
| $PSBPreference.Build.OutDir | $projectRoot/Output | Output directory when building the module
| $PSBPreference.Build.Dependencies | 'StageFiles, 'BuildHelp' | Default task dependencies for the `Build` task
| $PSBPreference.Build.ModuleOutDir | $outDir/$moduleName/$moduleVersion | `For internal use only. Do not overwrite. Use '$PSBPreference.Build.OutDir' to set output directory`
| $PSBPreference.Build.CompileModule | $false | Controls whether to "compile" module into single PSM1 or not
| $PSBPreference.Build.CompileHeader | <empty> | String that appears at the top of your compiled PSM1 file
| $PSBPreference.Build.CompileFooter | <empty> | String that appears at the bottom of your compiled PSM1 file
| $PSBPreference.Build.CompileScriptHeader | <empty> | String that appears in your compiled PSM1 file before each added script
| $PSBPreference.Build.CompileScriptFooter | <empty> | String that appears in your compiled PSM1 file after each added script
| $PSBPreference.Build.Exclude | <empty> | Array of files to exclude when building module
| $PSBPreference.Test.Enabled | $true | Enable/disable Pester tests
| $PSBPreference.Test.RootDir | $projectRoot/tests | Directory containing Pester tests
| $PSBPreference.Test.OutputFile | $null | Output file path Pester will save test results to
| $PSBPreference.Test.OutputFormat | NUnitXml | Test output format to use when saving Pester test results
| $PSBPreference.Test.ScriptAnalysis.Enabled | $true | Enable/disable use of PSScriptAnalyzer to perform script analysis
| $PSBPreference.Test.ScriptAnalysis.FailBuildOnSeverityLevel | Error | PSScriptAnalyzer threshold to fail the build on
| $PSBPreference.Test.ScriptAnalysis.SettingsPath | ./ScriptAnalyzerSettings.psd1 | Path to the PSScriptAnalyzer settings file
| $PSBPreference.Test.CodeCoverage.Enabled | $false | Enable/disable Pester code coverage reporting
| $PSBPreference.Test.CodeCoverage.Threshold | .75 | Fail Pester code coverage test if below this threshold
| $PSBPreference.Test.CodeCoverage.Files | *.ps1, *.psm1 | Files to perform code coverage analysis on
| $PSBPreference.Help.UpdatableHelpOutDir | $OutDir/UpdatableHelp | Output directory to store update module help (CAB)
| $PSBPreference.Help.DefaultLocale | (Get-UICulture).Name | Default locale used for help generation
| $PSBPreference.Help.ConvertReadMeToAboutHelp | $false | Convert project readme into the module about file
| $PSBPreference.Docs.RootDir | $projectRoot/docs | Directory PlatyPS markdown documentation will be saved to
| $PSBPreference.Publish.PSRepository | PSGallery | PowerShell repository name to publish
| $PSBPreference.Publish.PSRepositoryApiKey | $env:PSGALLERY_API_KEY | API key to authenticate to PowerShell repository with
| $PSBPreference.Publish.PSRepositoryCredential | $null | Credential to authenticate to PowerShell repository with. Overrides `$psRepositoryApiKey` if defined

## Examples

### psake

The example below is a psake file you might use in your PowerShell module.
When psake executes this file, it will recognize that tasks are being referenced from a separate module and automatically load them.
You can run these tasks just as if they were included directly in your task file.

Notice that the task file contained in `MyModule` only references the `Build` task supplied from `PowerShellBuild`.
When executed, the dependent tasks `Init`, `Clear`, and `StageFiles` also contained in `PowerShellBuild` are executed as well.

###### psakeBuild.ps1

```powershell
properties {
    # These settings overwrite values supplied from the PowerShellBuild
    # module and govern how those tasks are executed
    $PSBPreference.Test.ScriptAnalysisEnabled = $false
    $PSBPreference.Test.CodeCoverage.Enabled  = $true
}

task default -depends Build

task Build -FromModule PowerShellBuild -Version '0.1.0'
```

![Example](./media/psake_example.png)

### Invoke-Build

The example below is an [Invoke-Build](https://github.com/nightroman/Invoke-Build) task file that imports the `PowerShellBuild` module which contains the shared tasks and then dot sources the Invoke-Build task files that are referenced by the PowerShell alias `PowerShellBuild.IB.Tasks`.
Additionally, certain settings that control how the build tasks operate are overwritten after the tasks have been imported.

###### .build.ps1

```powershell
Import-Module PowerShellBuild
. PowerShellBuild.IB.Tasks

# Overwrite build settings contained in PowerShellBuild
$PSBPreference.Test.ScriptAnalysisEnabled = $true
$PSBPreference.Test.CodeCoverage.Enabled  = $false
```

![Example](./media/ib_example.png)

[appveyor-badge]: https://ci.appveyor.com/api/projects/status/3iq5efmgmepcl8dx?svg=true
[appveyor-build]: https://ci.appveyor.com/project/devblackops/powershellbuild
[psgallery-badge]: https://img.shields.io/powershellgallery/dt/powershellbuild.svg
[psgallery]: https://www.powershellgallery.com/packages/PowerShellBuild
[license-badge]: https://img.shields.io/github/license/psake/PowerShellBuild.svg
[license]: https://raw.githubusercontent.com/psake/PowerShellBuild/master/LICENSE
