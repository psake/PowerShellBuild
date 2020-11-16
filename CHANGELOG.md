# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.5.0] (beta1) - 2020-11-15

### Added

- When "compiling" a monolithic PSM1, add support for both inserting headers/footers for the entire PSM1, and for each script file. Control these via the following new build parameters (via [@pauby](https://github.com/pauby))
  - `$PSBPreference.Build.CompileHeader`
  - `$PSBPreference.Build.CompileFooter`
  - `$PSBPreference.Build.CompileScriptHeader`
  - `$PSBPreference.Build.CompileScriptFooter`

- Add ability to import project module from output directory prior to executing Pester tests. Toggle this with `$PSBPreference.Test.ImportModule`. Defaults to `$false`. (via [@joeypiccola](https://github.com/joeypiccola))

- Use `$PSBPreference.Build.CompileDirectories` to control directories who's contents will be concatenated into the PSM1 when `$PSBPreference.Build.CompileModule` is `$true`. Defaults to `@('Enum', 'Classes', 'Private', 'Public')`.
- Use `$PSBPreference.Build.CopyDirectories` to control directories that will be copied "as is" into the built module. Default is an empty array.

### Changed

- `$PSBPreference.Build.Exclude` now should be a list of regex expressions when `$PSBPreference.Build.CompileModule` is `$false` (default).

- Use Pester v5

### Fixed

- Overriding `$PSBPreference.Build.OutDir` now correctly determines the final module output directory. `$PSBPreference.Build.ModuleOutDir` is now computed internally and **SHOULD NOT BE SET DIRECTLY**. ` $PSBPreference.Build.OutDir` will accept both relative and fully-qualified paths.

- Before, when `$PSBPreference.Build.CompileModule` was set to `$true`, any files listed in `$PSBPreference.Build.Exclude` weren't being excluded like they should have been. Now, when it is `$true`, files matching regex expressions in `$PSBPreference.Build.Exclude` will be properly excluded (via [@pauby](https://github.com/pauby))

- `$PSBPreference.Help.DefaultLocale` now defaults to `en-US` on Linux since it is not correctly determined with `Get-UICulture`.

## [0.4.0] - 2019-08-31

### Changed

- Allow using both `Credential` and `ApiKey` when publishing a module (via [@pauby](https://github.com/pauby))

### Fixed

- Don't overwrite Pester parameters when specifying `OutputPath` or `OutputFormat` (via [@ChrisLGardner](https://github.com/ChrisLGardner))

## [0.3.1] - 2019-06-09

### Fixed

- Don't create module page MD file.

## [0.3.0] - 2019-04-23

### Fixed

- [**#24**](https://github.com/psake/PowerShellBuild/pull/24) Fix case of 'Public' folder when dot sourcing functions in PSM1 (via [@pauby](https://github.com/pauby))

### Changed

- [**#19**](https://github.com/psake/PowerShellBuild/pull/19) Allow the `BHBuildOutput` environment variable defined by `BuildHelpers` to be set via the `$PSBPreference.Build.ModuleOutDir` property of the build tasks (via [@pauby](https://github.com/pauby))

### Breaking changes

- Refactor build properties into a single hashtable `$PSBPreference`

### Changed

- [**#11**](https://github.com/psake/PowerShellBuild/pull/11) The Invoke-Build tasks are now auto-generated from the psake tasks via a converter script (via [@JustinGrote](https://github.com/JustinGrote))

## [0.2.0] - 2018-11-15

### Added

- Add `Publish` task to publish the module to the defined PowerShell Repository (PSGallery by default).

## [0.1.1] - 2018-11-09

### Fixed

- [**#4**](https://github.com/psake/PowerShellBuild/pull/4) Fix syntax for `Analyze` task in `IB.tasks.ps1` (via [@nightroman](https://github.com/nightroman))

## [0.1.0] - 2018-11-07

### Added

- Initial commit
