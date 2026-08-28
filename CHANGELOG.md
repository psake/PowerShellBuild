# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## Unreleased

### Changed

- [**#172**](https://github.com/psake/PowerShellBuild/issues/172)
  **Breaking:** the consumer Pester floor in `RequiredModules` is raised from
  `5.6.1` to `6.0.0`, and `Test-PSBuildPester` refuses to run under anything
  older. Pester 5.x is no longer supported. As with the psake floor, the lower
  minimum asserted support nothing verified — CI runs Pester 6 and nothing
  exercised a 5.x consumer. Pester 6 keeps the v5 `Should -Be` assertions
  (`Should.DisableV5` defaults to `$false`), so most suites need no changes; the
  one behavioral change to watch is `Run.FailOnNullOrEmptyForEach`, which now
  defaults to `$true`. Also fixes a guard that could never work:
  `Test-PSBuildPester` declared a `5.0.0` minimum while calling
  `New-PesterConfiguration` and `Run.SkipRemainingOnFailure`, neither of which
  exists in 5.0.0. See the
  [v0.8 → v1.0 migration guide](docs/migration-v0.8-to-v1.0.md).

- [**#166**](https://github.com/psake/PowerShellBuild/issues/166)
  **Breaking:** the consumer psake floor in `RequiredModules` is raised from
  `4.9.0` to `5.0.4`. psake 4.x is no longer supported. `RequiredModules` is
  enforced at import, so a consumer with only psake 4.x installed cannot import
  the module at all. The lower floor was untested — CI has exercised only 5.0.4
  since the toolchain moved there in #162 — so it asserted support nothing
  verified. Invoke-Build users are unaffected. See the
  [v0.8 → v1.0 migration guide](docs/migration-v0.8-to-v1.0.md); most v4 build
  scripts work under v5 unchanged.

- [**#105**](https://github.com/psake/PowerShellBuild/issues/105)
  **Breaking:** help generation moved from `platyPS` 0.14.x to
  [`Microsoft.PowerShell.PlatyPS`](https://www.powershellgallery.com/packages/Microsoft.PowerShell.PlatyPS)
  1.x. PlatyPS is also no longer a `RequiredModules` entry, so
  `Install-Module PowerShellBuild` no longer installs it — the two PlatyPS
  modules cannot be loaded into one process, so forcing the new one into every
  session would break any consumer still holding the old one. Install it
  yourself if you build help. `$PSBPreference.Docs.AlphabeticParamsOrder` is
  removed, because PlatyPS 1.x always sorts parameters alphabetically and
  offers no way back. Generated markdown carries the 1.x schema, though its
  on-disk layout is unchanged, and now includes a module landing page that
  0.14.x never produced. Updatable help is covered separately under **Fixed**.
  See the [v0.8 → v1.0 migration guide](docs/migration-v0.8-to-v1.0.md).

- [**#144**](https://github.com/psake/PowerShellBuild/issues/144)
  **Breaking:** `Test-PSBuildScriptAnalysis` now counts PSScriptAnalyzer
  `ParseError` records alongside `Error`. A file that does not parse at all
  previously satisfied no threshold — not even the strictest validated value,
  `Information` — so it was reported and the build passed anyway. It now fails
  every threshold except `None`. See the
  [v0.8 → v1.0 migration guide](docs/migration-v0.8-to-v1.0.md) — a build that
  passed before may now correctly fail.

- [**#120**](https://github.com/psake/PowerShellBuild/issues/120)
  **Breaking:** the module manifest now requires PowerShell 5.1 or newer
  (`PowerShellVersion = '5.1'`, previously `'3.0'`) and declares
  `CompatiblePSEditions = @('Desktop', 'Core')`. The support floor is
  Windows PowerShell 5.1 or PowerShell 7.4+ (CI runs Windows PowerShell
  5.1 and the runners' current PowerShell 7 release). See the
  [v0.8 → v1.0 migration guide](docs/migration-v0.8-to-v1.0.md) for
  details.

### Added

- [**#144**](https://github.com/psake/PowerShellBuild/issues/144)
  `Test-PSBuildScriptAnalysis` accepts `Any` as a `SeverityThreshold`, failing
  the build on any diagnostic record regardless of severity. `Any` was already
  documented in `build.properties.ps1` but was missing from the parameter's
  `ValidateSet`, so setting
  `$PSBPreference.Test.ScriptAnalysis.FailBuildOnSeverityLevel = 'Any'` failed
  parameter binding instead of working as documented.

### Fixed

- [**#193**](https://github.com/psake/PowerShellBuild/issues/193)
  `$PSBPreference.Sign.SkipCertificateValidation` now does something. It was
  read only by `psakeFile.ps1`, and even there `Get-PSBuildCertificate` consulted
  it only for the `EnvVar` and `PfxFile` sources — the `Store` and `Thumbprint`
  sources checked expiry and private key presence inside the filter that selects
  the certificate, where the switch could not reach them. So the documented
  escape hatch did nothing on two of the four sources for psake consumers, and
  nothing at all for Invoke-Build consumers, because `IB.tasks.ps1` never passed
  the setting to `Get-PSBuildCertificate` in either of its signing tasks. A
  build with an expired store certificate failed with `NoCertificateFound`,
  which points at a missing certificate rather than at the expiry that actually
  caused it. `IB.tasks.ps1` now passes the setting, and for `Store` and
  `Thumbprint` the relaxation is a fallback rather than a blanket bypass: an
  unexpired certificate is still preferred whenever one exists, an expired one
  is selected only when no unexpired one was found, and a warning is emitted
  when that happens. `Thumbprint` still matches the requested thumbprint, and
  both store-backed sources still require a private key, because that is part of
  how they select a certificate rather than a check layered on afterwards. Note
  that `EnvVar` and `PfxFile` are different: the setting skips every check for
  them, the private key check included, so a certificate exported without its
  key is accepted here and fails later in `Set-AuthenticodeSignature` instead.

- [**#191**](https://github.com/psake/PowerShellBuild/issues/191)
  The README's psake and Invoke-Build examples assigned
  `$PSBPreference.Test.ScriptAnalysisEnabled`, which is not a setting. The real
  one is nested, `$PSBPreference.Test.ScriptAnalysis.Enabled`, as the README's
  own settings table has always said. `$PSBPreference` is a plain hashtable, so
  the unrecognized name added a key nothing reads and neither errored nor
  warned. **Check your own build file if you copied the psake example**: it
  assigned `$false`, so script analysis has been running on every build even
  though you asked for it off. The Invoke-Build example assigned `$true`, which
  is already the default, so that one did nothing either way. Correcting the
  name is the whole fix; no module behavior changed.

- [**#185**](https://github.com/psake/PowerShellBuild/issues/185)
  Consumers on a non-English Windows PowerShell 5.1 host get the module's
  real messages. `PowerShellBuild.psm1` carried a hand-maintained second copy
  of every string, bound whenever `Import-LocalizedData` resolved nothing, and
  it had drifted sixteen strings behind `en-US/Messages.psd1` — every
  certificate and signing message was absent, and the Pester floor was still
  reported as `5.0.0`. That lookup resolves by UI culture and the module ships
  `en-US` only: PowerShell 7 falls back to `en-US` and never saw the drift,
  but Windows PowerShell 5.1 does not fall back at all, so a French or
  Japanese install bound the stale copy. A missing string does not throw, so
  the symptom was a blank `WARNING:` line, or a bare `ScriptHalted` where the
  signing tasks meant to say no certificate was found. The copy is gone,
  `en-US` is now requested by name when the culture lookup misses, and an
  import that cannot find the strings at all fails outright rather than
  blanking every message.

  The same sweep found one string the module read and never shipped:
  `Publish-PSBuildModule` validated `-Path` against `PathDoesNotExist`, which
  `en-US/Messages.psd1` did not define, so passing a path that does not exist
  failed with a blank message on **every** host and culture while the very
  next check in the same validation block reported itself properly. The string
  is now defined, and a test asserts that every string the module reads is one
  it ships.

- [**#124**](https://github.com/psake/PowerShellBuild/issues/124)
  The docs tree can hold documentation that is not generated help. A `README.md`
  at its root, a `CONTRIBUTING.md` beside the generated markdown, an `images/` or
  `guides/` directory alongside the locale — none of it interferes with the help
  tasks any more. Markdown without PlatyPS metadata used to fail the build
  outright; the move to PlatyPS 1.x ended that, because the markdown and MAML
  steps now select documents by type rather than taking every `*.md` in the
  directory. What remained was `Build-PSBuildUpdatableHelp` treating every
  subdirectory of the docs tree as a help locale and warning, once per
  directory, about a module landing page that was never going to be there. It
  now considers only directories that are actually locales.

- [**#178**](https://github.com/psake/PowerShellBuild/issues/178)
  Invoke-Build consumers get the code coverage output format they configured.
  `IB.tasks.ps1` read `$PSBPreference.Test.CodeCoverage.OutputFormat`, but the
  setting is `OutputFileFormat`, so the expression evaluated to `$null` and bound
  to the `[string]` parameter as an empty string rather than falling back to its
  `JaCoCo` default. Pester accepted the empty format silently, leaving the
  documented setting inert and the coverage threshold gate unable to find or parse
  a report. The psake task was unaffected.

- [**#169**](https://github.com/psake/PowerShellBuild/issues/169)
  `Build-PSBuildUpdatableHelp` produces a help cabinet. It never could before:
  it needed a module landing page that `Build-PSBuildMarkdown` did not
  generate, passed an undefined variable as the cabinet source folder, and was
  never given the module name — so any build that reached the
  `GenerateUpdatableHelp` task failed with a parameter-binding error.
  `Build-PSBuildMarkdown` now writes the landing page, and the task passes the
  module name and output path it always should have. Using the task requires a
  `HelpInfoUri` in your module manifest; without one it warns and produces
  nothing, rather than writing a cabinet with no `HelpInfo.xml` to find it by.
  See the [v0.8 → v1.0 migration guide](docs/migration-v0.8-to-v1.0.md).

- [**#147**](https://github.com/psake/PowerShellBuild/issues/147)
  `Test-PSBuildScriptAnalysis` retries the analysis when a PSScriptAnalyzer rule
  crashes on an internal race
  ([PSScriptAnalyzer#1538](https://github.com/PowerShell/PSScriptAnalyzer/issues/1538)),
  which is unrelated to the code being analyzed and succeeds on a re-run.
  Consumers who set `$ErrorActionPreference = 'Stop'` — common in a build script —
  previously got a randomly red build. A crash that survives every attempt is
  still surfaced, so a persistent failure behaves as it did before.

- [**#96**](https://github.com/psake/PowerShellBuild/issues/96)
  `Test-PSBuildScriptAnalysis` now fails the build when PSScriptAnalyzer
  reports findings at or above the configured severity threshold. The
  severity counts were computed from `$_Severity` — an undefined variable —
  instead of `$_.Severity`, so all three counts were always zero and the
  `Error`, `Warning`, and `Information` thresholds could never fail a build.
  Script analysis reported its findings and the build passed regardless.
  Because the default `FailBuildOnSeverityLevel` is `Error`, any consumer
  running the `Analyze` task had a gate that only ever looked like it was
  working. See the
  [v0.8 → v1.0 migration guide](docs/migration-v0.8-to-v1.0.md) — a build
  that passed before may now correctly fail.
- [**#96**](https://github.com/psake/PowerShellBuild/issues/96)
  `Test-PSBuildScriptAnalysis` no longer fails with a path-resolution error
  when `SettingsPath` is not supplied. An unsupplied path was forwarded to
  PSScriptAnalyzer as `-Settings ''`, which resolved against the current
  directory and threw before any analysis ran, so the function's own
  documented example could not run as written.
- [**#102**](https://github.com/psake/PowerShellBuild/issues/102)
  `Test-PSBuildPester` no longer raises a parameter-binding error from its
  cleanup logic when the optional `ModuleName` parameter is not supplied.
- [**#102**](https://github.com/psake/PowerShellBuild/issues/102)
  `Test-PSBuildPester` now respects a Pester module that is already loaded in
  the session instead of unconditionally importing the newest installed
  version on top of it, which crashed with a Pester.dll version conflict when
  two Pester versions were installed side by side. When no Pester is loaded,
  the newest installed version (5.0.0 minimum) is imported as before, and a
  loaded Pester older than 5.0.0 now produces a clear error.
- [**#138**](https://github.com/psake/PowerShellBuild/issues/138)
  `Test-PSBuildPester` now reports real code coverage percentages and compares
  them against `CodeCoverageThreshold` correctly. Each percentage was passed
  through `[Math]::Truncate`, which collapses any fraction to zero, so the
  coverage report always printed `0.00%` (or `100.00%`) and every threshold
  above zero failed the build unless coverage was exactly 100%. Consumers who
  set `$PSBPreference.Test.CodeCoverage.Threshold` could not use coverage
  gating at all. The comparison is now strictly more permissive than before,
  so a build that passed with a coverage threshold set still passes.

## [0.8.2] 2026-07-08

### Fixed

- [**#133**](https://github.com/psake/PowerShellBuild/pull/133)
  `Test-PSBuildPester` now fails the build when a Pester run fails for any
  reason, not only when individual tests fail. Previously the function gated
  only on `FailedCount`, so a `BeforeAll`/`AfterAll` that threw or a test file
  that errored during discovery left the count at zero and the build passed
  despite tests never running. The gate now checks the run's aggregate
  `Result` property, which Pester derives from all failure categories.
  Companion to [#128](https://github.com/psake/PowerShellBuild/pull/128),
  which fixes the same gap in this repository's own build file.

## [0.8.1] 2026-06-03

### Fixed

- Restore Windows PowerShell 5.1 (Desktop edition) compatibility, which regressed
  in 0.8.0. `Get-PSBuildCertificate` used the PowerShell 7+-only ternary operator,
  causing the file to fail to parse and the whole module to fail to import under
  Windows PowerShell 5.1 — even though the manifest still declares support for it.
  The ternary is replaced with an `if`/`else` expression, and the `$IsWindows`
  platform guard now treats the absent automatic variable on Desktop edition as
  Windows (matching the existing pattern in `Build-PSBuildUpdatableHelp`). Behavior
  on PowerShell 7+ is unchanged.

## [0.8.0] 2026-02-20

### Added

- [**#92**](https://github.com/psake/PowerShellBuild/pull/92) Add Authenticode
  code-signing support for PowerShell modules with three new public functions:
  - `Get-PSBuildCertificate` - Resolves code-signing X509Certificate2 objects
    from certificate store, PFX files, Base64-encoded environment variables,
    or pre-resolved certificate objects
  - `Invoke-PSBuildModuleSigning` - Signs PowerShell module files (*.psd1,
    *.psm1, *.ps1) with Authenticode signatures supporting configurable
    timestamp servers and hash algorithms
  - `New-PSBuildFileCatalog` - Creates Windows catalog (.cat) files for
    tamper detection
- New build tasks for module signing pipeline: `SignModule`, `BuildCatalog`,
  `SignCatalog`, `Sign` (meta-task)
- Extended `$PSBPreference.Sign` configuration section with certificate
  source selection, timestamp server configuration, hash algorithm options,
  and catalog generation settings

### Fixed

- Remove extra backticks during localization text migration.

## [0.7.3] 2025-08-01

### Added

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
