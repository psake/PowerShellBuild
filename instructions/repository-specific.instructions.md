---
applyTo: '**/*'
description: 'Repository-specific instructions for the PowerShellBuild module'
---

# Repository-Specific Instructions

These instructions cover the parts of PowerShellBuild that an agent cannot infer from the
standard AIM modules (`powershell`, `git-workflow`, `testing`, etc.). Read those first; this
file only adds repo-specific concepts.

## Repository Context

**PowerShellBuild** is a PowerShell module that provides standardized build, test, and publish
tasks for other PowerShell module projects. It supports two task-runner frameworks:

- **psake** (4.9.0+)
- **Invoke-Build** (5.8.1+)

- Current version: **0.8.1** (see `PowerShellBuild/PowerShellBuild.psd1`)
- `PowerShellVersion` in the manifest is currently `'3.0'` — almost certainly wrong; under
  review in the v1.0.0 roadmap (psake/PowerShellBuild#120)
- Cross-platform: Windows, Linux, macOS (CI matrix in `.github/workflows/test.yml`)
- The module is **psake/PowerShellBuild** on PSGallery and GitHub; maintained by the psake org

## Repository Layout

```text
PowerShellBuild/
├── Build/Convert-PSAke.ps1     # Dev utility: converts psake tasks to Invoke-Build (not shipped)
├── PowerShellBuild/            # THE MODULE SOURCE (system under test)
│   ├── Public/                 # 12 exported functions
│   ├── Private/                # Internal helpers
│   ├── en-US/Messages.psd1     # Localized strings (Import-LocalizedData)
│   ├── PowerShellBuild.psd1    # Manifest
│   ├── PowerShellBuild.psm1    # Dot-sources Public/ and Private/
│   ├── ScriptAnalyzerSettings.psd1
│   ├── build.properties.ps1    # $PSBPreference (canonical config hashtable)
│   ├── psakeFile.ps1           # Tasks consumers import
│   └── IB.tasks.ps1            # Invoke-Build entry (aliased as PowerShellBuild.IB.Tasks)
├── tests/                      # Pester 5+ tests
│   └── TestModule/             # Sample module exercised by the test suite
├── build.ps1                   # Main build entry point for THIS repo
├── build.settings.ps1          # Build settings for THIS repo's own psake build
├── psakeFile.ps1               # psake tasks for building THIS repo (simpler than the inner one)
└── requirements.psd1           # PSDepend manifest
```

**The two `psakeFile.ps1` files serve different purposes:**

- Root `psakeFile.ps1` → builds *this* repo
- `PowerShellBuild/psakeFile.ps1` → what consumers import to build *their* repo

## Key Concepts

### `$PSBPreference` — the central configuration object

All build behavior is controlled through a single ordered hashtable named `$PSBPreference`,
defined in `PowerShellBuild/build.properties.ps1`. The variable name is fixed — never rename
it or recreate it under a different name.

It is set as a **read-only script-scoped variable** when `psakeFile.ps1` is loaded. To modify
it, set values *before* loading the task file, or use `Set-Variable -Force`.

Sections:

| Section        | Purpose                                                                                                            |
| -------------- | ------------------------------------------------------------------------------------------------------------------ |
| `General`      | ProjectRoot, SrcRootDir, ModuleName, ModuleVersion, ModuleManifestPath                                             |
| `Build`        | OutDir, ModuleOutDir, CompileModule, CompileDirectories, CopyDirectories, Exclude                                  |
| `Test`         | Enabled, RootDir, OutputFile/Format, ScriptAnalysis, CodeCoverage, ImportModule, etc.                              |
| `Help`         | UpdatableHelpOutDir, DefaultLocale, ConvertReadMeToAboutHelp                                                       |
| `Docs`         | RootDir, Overwrite, AlphabeticParamsOrder, ExcludeDontShow, UseFullTypeName                                        |
| `Publish`      | PSRepository, PSRepositoryApiKey, PSRepositoryCredential                                                           |
| `Sign`         | Enabled, CertificateSource, CertStoreLocation, Thumbprint, EnvVar/PfxFile sources, TimestampServer, HashAlgorithm, FilesToSign, Catalog |
| `Sign.Catalog` | Enabled, Version, FileName                                                                                         |

### Module compilation modes

`$PSBPreference.Build.CompileModule` controls how the module is staged to the output directory:

- `$false` (default) — files copied as-is, preserving the `Public/`/`Private/` structure
- `$true` — all `.ps1` files from `CompileDirectories` (default: `Enum`, `Classes`, `Private`,
  `Public`) are concatenated into a single `.psm1`. Optional `CompileHeader`, `CompileFooter`,
  `CompileScriptHeader`, and `CompileScriptFooter` strings can be injected.

### Task dependency variables

Task dependencies in `PowerShellBuild/psakeFile.ps1` are defined via variables checked with
`if ($null -eq ...)`. This lets consumers override dependencies *before* importing the tasks
file:

```powershell
# Example: insert a custom task before Pester runs
$PSBPesterDependency = @('Build', 'MyCustomTask')
```

Variables (pattern: `$PSB{TaskName}Dependency`):

| Variable                              | Default                          |
| ------------------------------------- | -------------------------------- |
| `$PSBCleanDependency`                 | `@('Init')`                      |
| `$PSBStageFilesDependency`            | `@('Clean')`                     |
| `$PSBBuildDependency`                 | `@('StageFiles', 'BuildHelp')`   |
| `$PSBAnalyzeDependency`               | `@('Build')`                     |
| `$PSBPesterDependency`                | `@('Build')`                     |
| `$PSBTestDependency`                  | `@('Pester', 'Analyze')`         |
| `$PSBBuildHelpDependency`             | `@('GenerateMarkdown', 'GenerateMAML')` |
| `$PSBGenerateMarkdownDependency`      | `@('StageFiles')`                |
| `$PSBGenerateMAMLDependency`          | `@('GenerateMarkdown')`          |
| `$PSBGenerateUpdatableHelpDependency` | `@('BuildHelp')`                 |
| `$PSBPublishDependency`               | `@('Test')`                      |
| `$PSBSignModuleDependency`            | `@('Build')`                     |
| `$PSBBuildCatalogDependency`          | `@('SignModule')`                |
| `$PSBSignCatalogDependency`           | `@('BuildCatalog')`              |
| `$PSBSignDependency`                  | `@('SignCatalog')`               |

## Public API (Exported Functions)

12 exported functions in `PowerShellBuild/Public/` (all follow the `Verb-PSBuildNoun` naming
pattern — keep new public functions consistent with this):

| Function                       | Description                                                            |
| ------------------------------ | ---------------------------------------------------------------------- |
| `Initialize-PSBuild`           | Sets up BuildHelpers env vars, displays build info                     |
| `Build-PSBuildModule`          | Copies/compiles module source to output directory                      |
| `Clear-PSBuildOutputFolder`    | Safely removes the build output directory                              |
| `Build-PSBuildMarkdown`        | Generates PlatyPS Markdown docs from module help                       |
| `Build-PSBuildMAMLHelp`        | Converts PlatyPS Markdown to MAML XML help files                       |
| `Build-PSBuildUpdatableHelp`   | Creates a `.cab` file for updatable help                               |
| `Test-PSBuildPester`           | Runs Pester tests with configurable output and coverage                |
| `Test-PSBuildScriptAnalysis`   | Runs PSScriptAnalyzer with a configurable severity threshold           |
| `Publish-PSBuildModule`        | Publishes the built module to a PowerShell repository                  |
| `Get-PSBuildCertificate`       | Resolves an Authenticode signing certificate                           |
| `Invoke-PSBuildModuleSigning`  | Signs module files with an Authenticode certificate                    |
| `New-PSBuildFileCatalog`       | Generates a `.cat` file catalog for the module                         |

Private helper: `Remove-ExcludedItem` — filters file system items by regex patterns during builds.

### Invoke-Build alias

The module exports an alias `PowerShellBuild.IB.Tasks` that points to `IB.tasks.ps1`, enabling
the Invoke-Build dot-source pattern:

```powershell
# In a consumer's .build.ps1 for Invoke-Build
Import-Module PowerShellBuild
. PowerShellBuild.IB.Tasks
```

## Build Workflows

### Building this repo

The repo uses its own psake build. Main entry point is `./build.ps1`. **Run with PowerShell 7+
(`pwsh`).**

```powershell
# First time in a fresh env — installs deps via PSDepend
./build.ps1 -Bootstrap

# Specific tasks
./build.ps1 -Task Build
./build.ps1 -Task Test
./build.ps1 -Task Analyze
./build.ps1 -Task Pester

# List available tasks
./build.ps1 -Help

# Publish to PSGallery (requires API-key credential)
./build.ps1 -Task Publish -PSGalleryApiKey $cred
```

### Repo-level tasks (root `psakeFile.ps1`)

| Task      | Depends On             | Description                                |
| --------- | ---------------------- | ------------------------------------------ |
| `default` | Test                   | Default task                               |
| `Init`    | —                      | Initialize build env (shows `BH*` env vars)|
| `Clean`   | Init                   | Remove output directory                    |
| `Build`   | Init, Clean            | Copy module source to output               |
| `Analyze` | Build                  | Run PSScriptAnalyzer                       |
| `Pester`  | Build                  | Run Pester tests                           |
| `Test`    | Init, Analyze, Pester  | Run all tests                              |
| `Publish` | Test                   | Publish to PSGallery                       |

### Module-level tasks (consumer-facing `PowerShellBuild/psakeFile.ps1`)

These are the tasks consumer modules get when they import PowerShellBuild:

| Task                    | Description                                  |
| ----------------------- | -------------------------------------------- |
| `Init`                  | Initialize build env variables               |
| `Clean`                 | Clear module output directory                |
| `StageFiles`            | Copy/compile source to output                |
| `Build`                 | StageFiles + BuildHelp                       |
| `Analyze`               | PSScriptAnalyzer                             |
| `Pester`                | Pester tests                                 |
| `Test`                  | Pester + Analyze                             |
| `GenerateMarkdown`      | PlatyPS Markdown from help                   |
| `GenerateMAML`          | MAML XML from Markdown                       |
| `BuildHelp`             | GenerateMarkdown + GenerateMAML              |
| `GenerateUpdatableHelp` | CAB file for updatable help                  |
| `Publish`               | Publish to repository                        |
| `SignModule`            | Authenticode-sign module files (`*.psd1`, `*.psm1`, `*.ps1`) |
| `BuildCatalog`          | Create Windows catalog (`.cat`) for the built module |
| `SignCatalog`           | Authenticode-sign the module catalog file    |
| `Sign`                  | Meta task — runs the full signing chain      |

Tasks with prerequisite modules (`Analyze`, `Pester`, `GenerateMarkdown`, `GenerateMAML`,
`GenerateUpdatableHelp`) check that required modules are installed; they skip gracefully
with a warning if the module is missing.

The signing tasks (`SignModule`, `BuildCatalog`, `SignCatalog`) have similar preconditions:
they skip when `$PSBPreference.Sign.Enabled` is `$false` (catalog tasks also require
`$PSBPreference.Sign.Catalog.Enabled = $true`) or when the required Windows-only cmdlets
(`Set-AuthenticodeSignature`, `New-FileCatalog`) are not available — so signing safely
no-ops on non-Windows.

## Dependencies

Defined in `requirements.psd1`, installed via **PSDepend** when `./build.ps1 -Bootstrap` runs:

| Module           | Version  |
| ---------------- | -------- |
| BuildHelpers     | 2.0.16   |
| Pester           | ≥ 5.6.1  |
| psake            | 4.9.0    |
| PSScriptAnalyzer | 1.24.0   |
| InvokeBuild      | 5.8.1    |
| platyPS          | 0.14.2   |

## Testing

Tests live in `tests/` and use **Pester 5+** syntax.

- Always build the module before running Pester directly — running against source can produce
  incorrect results. Prefer `./build.ps1 -Task Test` over a raw `Invoke-Pester` call.
- `tests/TestModule/` is a complete example module used to exercise PowerShellBuild's tasks.
  It has its own `build.ps1`, `psakeFile.ps1`, `.build.ps1` (Invoke-Build), and Pester tests.

| Test file              | Tests                                                                   |
| ---------------------- | ----------------------------------------------------------------------- |
| `build.tests.ps1`      | Module compilation, file staging, exclusion, header/footer injection    |
| `Help.tests.ps1`       | Help documentation completeness                                         |
| `IBTasks.tests.ps1`    | Invoke-Build task definitions                                           |
| `Manifest.tests.ps1`   | Module manifest validity                                                |
| `Meta.tests.ps1`       | Script analysis, best practices across module source                    |

## CI / CD (GitHub Actions)

### Test workflow (`.github/workflows/test.yml`)

- Triggers: push to default branch, pull requests, manual dispatch
- Matrix: `ubuntu-latest`, `windows-latest`, `macOS-latest`
- Command: `./build.ps1 -Task Test -Bootstrap`
- Supports a `DEBUG` runner flag for verbose output

### Publish workflow (`.github/workflows/publish.yaml`)

- Triggers: manual dispatch, GitHub release published
- Runs on: `ubuntu-latest`
- Reads `PSGALLERY_API_KEY` secret, converts to `PSCredential`, runs
  `./build.ps1 -Task Publish -PSGalleryApiKey $cred -Bootstrap`

## Repo-Specific Conventions

These supplement `powershell.instructions.md` and `git-workflow.instructions.md` — they
don't replace them.

- **Function naming**: public functions follow `Verb-PSBuildNoun` (e.g., `Build-PSBuildModule`,
  `Test-PSBuildPester`). Always use an approved verb.
- **Config variable**: always `$PSBPreference`. Never rename or recreate it.
- **Task dependency vars**: `$PSB{TaskName}Dependency` (e.g., `$PSBPesterDependency`).
- **Localization**: user-facing strings live in `PowerShellBuild/en-US/Messages.psd1` and load
  via `Import-LocalizedData`. Add new strings there rather than hardcoding messages in
  function bodies. Use UTF-8 with BOM (standard for PowerShell data files).
- **Script analysis**: PSScriptAnalyzer config is `PowerShellBuild/ScriptAnalyzerSettings.psd1`.
  Default severity threshold for build failure is `Error`. Warnings are reported but don't
  fail the build.
- **Spell-checker ignores**: inline comments — `# spell-checker:ignore MAML PSGALLERY`.

## How Consumers Use This Module

### With psake

```powershell
# In consumer's psakeFile.ps1
properties {
    # These settings overwrite values supplied from the PowerShellBuild
    # module and govern how those tasks are executed
    $PSBPreference.Test.ScriptAnalysisEnabled = $false
    $PSBPreference.Test.CodeCoverage.Enabled  = $true
}

task default -depends Build

task Build -FromModule PowerShellBuild -Version '0.1.0'
```

### With Invoke-Build

```powershell
# In consumer's .build.ps1
Import-Module PowerShellBuild
. PowerShellBuild.IB.Tasks

# Override configuration after dot-sourcing
$PSBPreference.Build.CompileModule = $false
```

## Common Development Tasks

### Adding a new public function

1. Create the file under `PowerShellBuild/Public/NewFunction.ps1`
2. Use the `Verb-PSBuildNoun` naming pattern
3. Add any user-facing strings to `PowerShellBuild/en-US/Messages.psd1`
4. Add the function name to `FunctionsToExport` in `PowerShellBuild.psd1`
5. No edit to `PowerShellBuild.psm1` needed — it dot-sources all files in `Public/` automatically

### Adding a new build task

1. Add the task to `PowerShellBuild/psakeFile.ps1`
2. Define a corresponding `$PSB{TaskName}Dependency` variable with an `if ($null -eq ...)` guard
3. If the task requires a new module, update `PowerShellBuild.psd1` and `requirements.psd1`

### Updating module version

1. Edit `ModuleVersion` in `PowerShellBuild/PowerShellBuild.psd1`
2. Add a `CHANGELOG.md` entry (see `releases.instructions.md` for format)

## Environment Variables (set by BuildHelpers)

`Initialize-PSBuild` calls `BuildHelpers\Set-BuildEnvironment`, which populates:

| Variable                  | Value                                                |
| ------------------------- | ---------------------------------------------------- |
| `$env:BHProjectPath`      | Repository root directory                            |
| `$env:BHProjectName`      | Module name (from directory structure)               |
| `$env:BHPSModulePath`     | Path to module source directory                      |
| `$env:BHPSModuleManifest` | Path to `.psd1` manifest                             |
| `$env:BHModulePath`       | Same as `BHPSModulePath`                             |
| `$env:BHBuildSystem`      | Detected CI system (e.g., `GitHubActions`, `Unknown`)|
| `$env:BHBranchName`       | Current git branch                                   |
| `$env:BHCommitMessage`    | Latest git commit message                            |

## Output Directory Structure

After a successful build:

```text
Output/
└── PowerShellBuild/
    └── 0.8.0/
        ├── Public/                   # (when CompileModule = $false)
        ├── Private/
        ├── en-US/
        ├── PowerShellBuild.psd1
        ├── PowerShellBuild.psm1
        └── ScriptAnalyzerSettings.psd1
```

When `CompileModule = $true`, all `.ps1` files are merged into the single `.psm1` and the
`Public/`/`Private/` directories are not copied to output.

`Output/` is in `.gitignore` and excluded from VS Code search (`.vscode/settings.json`).

## v1.0.0 Roadmap

The v1.0.0 release is actively being planned in **psake/PowerShellBuild#120**. Locked-in
decisions include: PRs directly to `main`, `1.0.0-preview.N` prereleases after each phase,
hard cut + migration guide (no deprecation cycle), psake 5.x in scope. Phase-by-phase
breakdown lives in the tracking issue.

Migration guide path (created in Phase 1): `docs/migration/v0.8-to-v1.0.md`.

## Notes for AI Agents

- **First-time setup**: always run `./build.ps1 -Bootstrap` in a fresh environment to install
  dependencies via PSDepend.
- **`$PSBPreference` is read-only at script scope** once `psakeFile.ps1` is loaded. To modify
  it, set values before loading the task file, or use `Set-Variable -Force`.
- **Tests need the module built first** — running Pester directly against source can produce
  incorrect results. Use `./build.ps1 -Task Test` rather than raw `Invoke-Pester` unless the
  module is already built and imported.
- `Build/Convert-PSAke.ps1` is a developer convenience tool, not part of the published module.
