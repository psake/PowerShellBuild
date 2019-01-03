# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.3.0] - Unreleased

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
