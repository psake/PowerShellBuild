# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.7.3] 2025-08-01

- Add new dependencies variables to allow end user to modify which tasks are
  run.
- Add localization support.

## [0.7.2] 2025-05-21

### Added

- The `$PSBPreference` variable now supports the following PlatyPS
  `New-MarkdownHelp` and `Update-MarkdownHelp` boolean options:
  - `$PSBPreference.Docs.AlphabeticParamsOrder`
  - `$PSBPreference.Docs.ExcludeDontShow`
  - `$PSBPreference.Docs.UseFullTypeName`
- The `$PSBPreference` variable now supports the following Pester test
  configuration options:
  - `$PSBPreference.Test.SkipRemainingOnFailure` can be set to **None**,
    **Run**, **Container** and **Block**. The default value is **None**.
  - `$PSBPreference.Test.OutputVerbosity` can be set to **None**, **Normal**,
    **Detailed**, and **Diagnostic**. The default value is **Detailed**.

## [0.7.1] 2025-04-01

### Fixes

- Fix a bug in `Build-PSBuildMarkdown` where a hashtable item was added twice.

## [0.7.0] 2025-03-31

### Changed

- [**#71**](https://github.com/psake/PowerShellBuild/pull/71) Compiled modules
  are now explicitly created as UTF-8 files.
- [**#67**](https://github.com/psake/PowerShellBuild/pull/67) You can now
  overwrite existing markdown files using `$PSBPreference.Docs.Overwrite` and
  setting it to `$true`.
- [**#72**](https://github.com/psake/PowerShellBuild/pull/72) Loosen
  dependencies by allowing them to be overwritten with
  `$PSBPreference.TaskDependencies`.

## [0.6.2] 2024-10-06

### Changed

- Bump Pester to latest 5.6.1

### Fixed

- [**#52**](https://github.com/psake/PowerShellBuild/pull/52) Pester object
  wasn't being passed back after running tests, causing the Pester task to never
  fail (via [@webtroter](https://github.com/webtroter))
- [**#55**](https://github.com/psake/PowerShellBuild/pull/55) Add `-Module`
  parameter to `Build-PSBuildUpdatableHelp` (via
  [@IMJLA](https://github.com/IMJLA))
- [**#60**](https://github.com/psake/PowerShellBuild/pull/60) Fix Windows
  PowerShell compatibility in `Initialize-PSBuild` (via
  [@joshooaj](https://github.com/joshooaj))
- [**#62**](https://github.com/psake/PowerShellBuild/pull/62) Fix code coverage
  output fle format not working (via
  [@OpsM0nkey](https://github.com/OpsM0nkey))

## [0.6.1] 2021-03-14

### Fixed

- Fixed bug in IB task `GenerateMarkdown` when dot sourcing precondition

## [0.6.0] 2021-03-14

### Changed

- [**#50**](https://github.com/psake/PowerShellBuild/pull/50) Invoke-Build tasks
  brought inline with psake equivalents (via
  [@JustinGrote](https://github.com/JustinGrote))

## [0.5.0] 2021-02-27

### Added

- New code coverage parameters for setting output path and format:
  - `$PSBPreference.Test.CodeCoverage.OutputFile` - Output file path for code
    coverage results
  - `$PSBPreference.Test.CodeCoverage.OutputFileFormat` - Code coverage output
    format

## [0.5.0] (beta1) - 2020-11-15

### Added

- When "compiling" a monolithic PSM1, add support for both inserting
  headers/footers for the entire PSM1, and for each script file. Control these
  via the following new build parameters (via
  [@pauby](https://github.com/pauby))
  - `$PSBPreference.Build.CompileHeader`
  - `$PSBPreference.Build.CompileFooter`
  - `$PSBPreference.Build.CompileScriptHeader`
  - `$PSBPreference.Build.CompileScriptFooter`

- Add ability to import project module from output directory prior to executing
  Pester tests. Toggle this with `$PSBPreference.Test.ImportModule`. Defaults to
  `$false`. (via [@joeypiccola](https://github.com/joeypiccola))

- Use `$PSBPreference.Build.CompileDirectories` to control directories who's
  contents will be concatenated into the PSM1 when
  `$PSBPreference.Build.CompileModule` is `$true`. Defaults to
  `@('Enum', 'Classes', 'Private', 'Public')`.
- Use `$PSBPreference.Build.CopyDirectories` to control directories that will be
  copied "as is" into the built module. Default is an empty array.

### Changed

- `$PSBPreference.Build.Exclude` now should be a list of regex expressions when
  `$PSBPreference.Build.CompileModule` is `$false` (default).

- Use Pester v5

### Fixed

- Overriding `$PSBPreference.Build.OutDir` now correctly determines the final
  module output directory. `$PSBPreference.Build.ModuleOutDir` is now computed
  internally and **SHOULD NOT BE SET DIRECTLY**. `$PSBPreference.Build.OutDir`
  will accept both relative and fully-qualified paths.

- Before, when `$PSBPreference.Build.CompileModule` was set to `$true`, any
  files listed in `$PSBPreference.Build.Exclude` weren't being excluded like
  they should have been. Now, when it is `$true`, files matching regex
  expressions in `$PSBPreference.Build.Exclude` will be properly excluded (via
  [@pauby](https://github.com/pauby))

- `$PSBPreference.Help.DefaultLocale` now defaults to `en-US` on Linux since it
  is not correctly determined with `Get-UICulture`.

## [0.4.0] - 2019-08-31

### Changed

- Allow using both `Credential` and `ApiKey` when publishing a module (via
  [@pauby](https://github.com/pauby))

### Fixed

- Don't overwrite Pester parameters when specifying `OutputPath` or
  `OutputFormat` (via [@ChrisLGardner](https://github.com/ChrisLGardner))

## [0.3.1] - 2019-06-09

### Fixed

- Don't create module page MD file.

## [0.3.0] - 2019-04-23

### Fixed

- [**#24**](https://github.com/psake/PowerShellBuild/pull/24) Fix case of
  'Public' folder when dot sourcing functions in PSM1 (via
  [@pauby](https://github.com/pauby))

### Breaking changes

- Refactor build properties into a single hashtable `$PSBPreference`

### Changed

- [**#11**](https://github.com/psake/PowerShellBuild/pull/11) The Invoke-Build
  tasks are now auto-generated from the psake tasks via a converter script (via
  [@JustinGrote](https://github.com/JustinGrote))

- [**#19**](https://github.com/psake/PowerShellBuild/pull/19) Allow the
  `BHBuildOutput` environment variable defined by `BuildHelpers` to be set via
  the `$PSBPreference.Build.ModuleOutDir` property of the build tasks (via
  [@pauby](https://github.com/pauby))

## [0.2.0] - 2018-11-15

### Added

- Add `Publish` task to publish the module to the defined PowerShell Repository
  (PSGallery by default).

## [0.1.1] - 2018-11-09

### Fixed

- [**#4**](https://github.com/psake/PowerShellBuild/pull/4) Fix syntax for
  `Analyze` task in `IB.tasks.ps1` (via
  [@nightroman](https://github.com/nightroman))

## [0.1.0] - 2018-11-07

### Added

- Initial commit

<!--spell-checker:ignore IMJLA webtroter joshooaj pauby joeypiccola nightroman -->
