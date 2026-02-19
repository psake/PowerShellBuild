# CLAUDE.md — AI Assistant Guide for PowerShellBuild

## Project Overview

**PowerShellBuild** is a PowerShell module that provides a standardized set of build, test, and publish tasks for PowerShell module projects. It supports two popular PowerShell task-runner frameworks:

- **psake** (4.9.0+) — task-based build system
- **Invoke-Build** (5.8.1+) — alternative task runner

The module version is **0.7.3** and targets PowerShell 3.0+. It is cross-platform and tested on Windows, Linux, and macOS.

---

## Repository Layout

```
PowerShellBuild/
├── .devcontainer/              # Dev container (Docker) configuration
│   ├── Dockerfile
│   └── devcontainer.json
├── .github/
│   └── workflows/
│       ├── test.yml            # CI: runs tests on push/PR across 3 OSes
│       └── publish.yaml        # CI: publishes to PSGallery on release
├── .vscode/                    # VS Code editor settings and tasks
├── Build/
│   └── Convert-PSAke.ps1       # Utility: converts psake tasks to Invoke-Build
├── PowerShellBuild/            # THE MODULE SOURCE (System Under Test)
│   ├── Public/                 # Exported (public) functions — 9 functions
│   ├── Private/                # Internal functions — 1 function
│   ├── en-US/
│   │   └── Messages.psd1       # Localized string resources
│   ├── PowerShellBuild.psd1    # Module manifest (version, deps, exports)
│   ├── PowerShellBuild.psm1    # Module entry point (dot-sources all functions)
│   ├── ScriptAnalyzerSettings.psd1  # PSScriptAnalyzer rule config
│   ├── build.properties.ps1    # $PSBPreference config hashtable (canonical config)
│   └── psakeFile.ps1           # psake/Invoke-Build task definitions for consumers
├── tests/                      # Pester test suite
│   ├── build.tests.ps1
│   ├── Help.tests.ps1
│   ├── IBTasks.tests.ps1
│   ├── Manifest.tests.ps1
│   ├── Meta.tests.ps1
│   ├── MetaFixers.psm1
│   ├── ScriptAnalyzerSettings.psd1
│   └── TestModule/             # A complete example module used in tests
├── build.ps1                   # Main build entry point (run this to build/test)
├── build.settings.ps1          # Build settings for the repo's own psake build
├── psakeFile.ps1               # psake tasks for building THIS repo
├── requirements.psd1           # PSDepend dependencies manifest
├── cspell.json                 # Spell checker config
├── .markdownlint.json          # Markdown lint config
├── README.md
└── CHANGELOG.md
```

---

## Key Concepts

### $PSBPreference — The Central Configuration Object

All build behavior is controlled through a single ordered hashtable `$PSBPreference`, defined in `PowerShellBuild/build.properties.ps1`. This is set as a **read-only script-scoped variable** when `psakeFile.ps1` is loaded.

The hashtable is organized into sections:

| Section | Purpose |
|---------|---------|
| `General` | ProjectRoot, SrcRootDir, ModuleName, ModuleVersion, ModuleManifestPath |
| `Build` | OutDir, ModuleOutDir, CompileModule, CompileDirectories, CopyDirectories, Exclude |
| `Test` | Enabled, RootDir, OutputFile, OutputFormat, ScriptAnalysis, CodeCoverage, ImportModule, SkipRemainingOnFailure, OutputVerbosity |
| `Help` | UpdatableHelpOutDir, DefaultLocale, ConvertReadMeToAboutHelp |
| `Docs` | RootDir, Overwrite, AlphabeticParamsOrder, ExcludeDontShow, UseFullTypeName |
| `Publish` | PSRepository, PSRepositoryApiKey, PSRepositoryCredential |

Consumers override settings by modifying `$PSBPreference` in their own `build.ps1` **before** importing the tasks file.

### Module Compilation Modes

The `Build.CompileModule` setting controls how the module is staged to the output directory:

- `$false` (default): Files are copied as-is, preserving the `Public/`/`Private/` directory structure.
- `$true`: All `.ps1` files from `CompileDirectories` (default: `Enum`, `Classes`, `Private`, `Public`) are concatenated into a single `.psm1` file. Optional `CompileHeader`, `CompileFooter`, `CompileScriptHeader`, and `CompileScriptFooter` strings can be injected.

### Task Dependency Variables

Task dependencies in `PowerShellBuild/psakeFile.ps1` are defined via variables checked with `if ($null -eq ...)`. This allows consumers to **override dependencies before importing the tasks file**:

```powershell
# Example: add a custom task before Pester runs
$PSBPesterDependency = @('Build', 'MyCustomTask')
```

Available dependency variables:

| Variable | Default |
|----------|---------|
| `$PSBCleanDependency` | `@('Init')` |
| `$PSBStageFilesDependency` | `@('Clean')` |
| `$PSBBuildDependency` | `@('StageFiles', 'BuildHelp')` |
| `$PSBAnalyzeDependency` | `@('Build')` |
| `$PSBPesterDependency` | `@('Build')` |
| `$PSBTestDependency` | `@('Pester', 'Analyze')` |
| `$PSBBuildHelpDependency` | `@('GenerateMarkdown', 'GenerateMAML')` |
| `$PSBGenerateMarkdownDependency` | `@('StageFiles')` |
| `$PSBGenerateMAMLDependency` | `@('GenerateMarkdown')` |
| `$PSBGenerateUpdatableHelpDependency` | `@('BuildHelp')` |
| `$PSBPublishDependency` | `@('Test')` |

---

## Public API (Exported Functions)

All functions reside in `PowerShellBuild/Public/`.

| Function | Description |
|----------|-------------|
| `Initialize-PSBuild` | Sets up BuildHelpers environment variables, displays build info |
| `Build-PSBuildModule` | Copies/compiles module source to output directory |
| `Clear-PSBuildOutputFolder` | Safely removes the build output directory |
| `Build-PSBuildMarkdown` | Generates PlatyPS Markdown docs from module help |
| `Build-PSBuildMAMLHelp` | Converts PlatyPS Markdown to MAML XML help files |
| `Build-PSBuildUpdatableHelp` | Creates a `.cab` file for updatable help |
| `Test-PSBuildPester` | Runs Pester tests with configurable output and coverage |
| `Test-PSBuildScriptAnalysis` | Runs PSScriptAnalyzer with configurable severity threshold |
| `Publish-PSBuildModule` | Publishes the built module to a PowerShell repository |

Private helper: `Remove-ExcludedItem` — filters file system items by regex patterns during builds.

### Invoke-Build Alias

The module exports an alias `PowerShellBuild.IB.Tasks` that points to `IB.tasks.ps1`, enabling the Invoke-Build dot-source pattern:

```powershell
# In your .build.ps1 for Invoke-Build
. ([IO.Path]::Combine((Split-Path (Get-Module PowerShellBuild).Path), 'PowerShellBuild.IB.Tasks'))
```

---

## Build Workflows

### Building This Repository (the module itself)

The repo uses its own psake build system. The main entry point is `build.ps1`.

**Run with PowerShell 7+** (`pwsh`).

```powershell
# Install dependencies and run the default task (Test)
./build.ps1 -Bootstrap

# Run a specific task
./build.ps1 -Task Build
./build.ps1 -Task Test
./build.ps1 -Task Analyze
./build.ps1 -Task Pester

# List available tasks
./build.ps1 -Help

# Publish to PSGallery (requires API key credential)
./build.ps1 -Task Publish -PSGalleryApiKey $cred
```

### Available psake Tasks (repo-level `psakeFile.ps1`)

| Task | Depends On | Description |
|------|-----------|-------------|
| `default` | Test | Default task |
| `Init` | — | Initialize build environment (shows BH* env vars) |
| `Clean` | Init | Remove output directory |
| `Build` | Init, Clean | Copy module source to output directory |
| `Analyze` | Build | Run PSScriptAnalyzer |
| `Pester` | Build | Run Pester tests |
| `Test` | Init, Analyze, Pester | Run all tests |
| `Publish` | Test | Publish to PSGallery |

### Module-Level Tasks (`PowerShellBuild/psakeFile.ps1`)

These are the tasks that consumer modules get when they reference PowerShellBuild:

| Task | Description |
|------|-------------|
| `Init` | Initialize build environment variables |
| `Clean` | Clear module output directory |
| `StageFiles` | Copy/compile source to output |
| `Build` | StageFiles + BuildHelp |
| `Analyze` | PSScriptAnalyzer |
| `Pester` | Pester tests |
| `Test` | Pester + Analyze |
| `GenerateMarkdown` | PlatyPS Markdown from help |
| `GenerateMAML` | MAML XML from Markdown |
| `BuildHelp` | GenerateMarkdown + GenerateMAML |
| `GenerateUpdatableHelp` | CAB file for updatable help |
| `Publish` | Publish to repository |

Tasks with prerequisites (`Analyze`, `Pester`, `GenerateMarkdown`, `GenerateMAML`, `GenerateUpdatableHelp`) check that required modules are installed before running; they skip gracefully with a warning if the module is missing.

---

## Dependencies

Defined in `requirements.psd1`, installed via **PSDepend**:

| Module | Version |
|--------|---------|
| BuildHelpers | 2.0.16 |
| Pester | ≥ 5.6.1 |
| psake | 4.9.0 |
| PSScriptAnalyzer | 1.24.0 |
| InvokeBuild | 5.8.1 |
| platyPS | 0.14.2 |

---

## Testing

Tests are in the `tests/` directory and use **Pester 5+** syntax.

```powershell
# Run tests via build script (recommended)
./build.ps1 -Task Test -Bootstrap

# Run Pester directly (after building)
Invoke-Pester ./tests
```

### Test Files

| File | Tests |
|------|-------|
| `build.tests.ps1` | Module compilation, file staging, exclusion, header/footer injection |
| `Help.tests.ps1` | Help documentation completeness |
| `IBTasks.tests.ps1` | Invoke-Build task definitions |
| `Manifest.tests.ps1` | Module manifest validity |
| `Meta.tests.ps1` | Script analysis, best practices across module source |

### TestModule

`tests/TestModule/` is a complete example module used to exercise PowerShellBuild's tasks. It has its own `build.ps1`, `psakeFile.ps1`, `.build.ps1` (Invoke-Build), and Pester tests.

---

## CI/CD (GitHub Actions)

### Test Workflow (`.github/workflows/test.yml`)

- **Triggers**: Push to default branch, pull requests, manual dispatch
- **Matrix**: `ubuntu-latest`, `windows-latest`, `macOS-latest`
- **Command**: `./build.ps1 -Task Test -Bootstrap`
- Supports `DEBUG` runner flag for verbose output

### Publish Workflow (`.github/workflows/publish.yaml`)

- **Triggers**: Manual dispatch, GitHub release published
- **Runs on**: `ubuntu-latest`
- Reads `PSGALLERY_API_KEY` secret, converts to `PSCredential`, then runs:
  `./build.ps1 -Task Publish -PSGalleryApiKey $cred -Bootstrap`

---

## Code Style & Conventions

### PowerShell Formatting (from `.vscode/settings.json`)

- **Indentation**: Spaces (not tabs)
- **Formatting preset**: OTBS (One True Brace Style)
- **Whitespace**: Spaces around pipe operators (`|`)
- **Casing**: Correct/consistent casing enforced
- **Property alignment**: Values aligned in hashtables

### Naming Conventions

- **Functions**: `Verb-PSBuildNoun` pattern for all public functions (e.g., `Build-PSBuildModule`, `Test-PSBuildPester`)
- **Config variable**: Always `$PSBPreference` — never rename or recreate
- **Task dependency vars**: `$PSB{TaskName}Dependency` pattern (e.g., `$PSBPesterDependency`)

### Script Analysis

PSScriptAnalyzer is configured via `PowerShellBuild/ScriptAnalyzerSettings.psd1`. The default severity threshold for build failure is `Error`. Warnings are reported but do not fail the build.

Inline suppressions use the standard attribute:
```powershell
[System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseDeclaredVarsMoreThanAssigments', '')]
```

Spell-checker ignores use inline comments:
```powershell
# spell-checker:ignore MAML PSGALLERY
```

### Localization

User-facing strings are stored in `PowerShellBuild/en-US/Messages.psd1` and loaded via `Import-LocalizedData`. Add new strings there rather than hardcoding messages in function bodies.

---

## How Consumers Use This Module

### With psake

```powershell
# In consumer's psakeFile.ps1
properties {
    # Override defaults BEFORE including the tasks
    $PSBPreference.Build.CompileModule = $true
    $PSBPreference.Test.CodeCoverage.Enabled = $true
}

# Include PowerShellBuild tasks
Include "$PSScriptRoot/node_modules/PowerShellBuild/psakeFile.ps1"
```

### With Invoke-Build

```powershell
# In consumer's .build.ps1
. ([IO.Path]::Combine((Split-Path (Get-Module PowerShellBuild -ListAvailable).Path), 'PowerShellBuild.IB.Tasks'))

# Override configuration after dot-sourcing
$PSBPreference.Build.CompileModule = $false
```

---

## Common Development Tasks

### Adding a New Public Function

1. Create the file in `PowerShellBuild/Public/NewFunction.ps1`
2. Follow the `Verb-PSBuildNoun` naming convention
3. Add any user-facing strings to `en-US/Messages.psd1`
4. Export the function by adding it to the `FunctionsToExport` array in `PowerShellBuild.psd1`
5. No need to edit `PowerShellBuild.psm1` — it dot-sources all files in `Public/` automatically

### Adding a New Build Task

1. Add the task to `PowerShellBuild/psakeFile.ps1`
2. Define a corresponding `$PSB{TaskName}Dependency` variable with a `if ($null -eq ...)` guard
3. Expose the dependency variable so consumers can override it
4. Update `PowerShellBuild.psd1` if any new modules are required

### Updating Module Version

1. Edit the `ModuleVersion` field in `PowerShellBuild/PowerShellBuild.psd1`
2. Add a changelog entry in `CHANGELOG.md`

### Running Script Analysis Only

```powershell
./build.ps1 -Task Analyze
```

### Debugging the Build

```powershell
# Enable debug output
$DebugPreference = 'Continue'
./build.ps1 -Task Test -Bootstrap
```

---

## Environment Variables (Set by BuildHelpers)

`Initialize-PSBuild` calls `BuildHelpers\Set-BuildEnvironment`, which populates:

| Variable | Value |
|----------|-------|
| `$env:BHProjectPath` | Repository root directory |
| `$env:BHProjectName` | Module name (from directory structure) |
| `$env:BHPSModulePath` | Path to module source directory |
| `$env:BHPSModuleManifest` | Path to `.psd1` manifest |
| `$env:BHModulePath` | Same as `BHPSModulePath` |
| `$env:BHBuildSystem` | Detected CI system (e.g., `GitHubActions`, `Unknown`) |
| `$env:BHBranchName` | Current git branch |
| `$env:BHCommitMessage` | Latest git commit message |

---

## Output Directory Structure

After a successful build, output is in `Output/PowerShellBuild/<version>/`:

```
Output/
└── PowerShellBuild/
    └── 0.7.3/
        ├── Public/                   # (when CompileModule = $false)
        ├── Private/
        ├── en-US/
        ├── PowerShellBuild.psd1
        ├── PowerShellBuild.psm1
        └── ScriptAnalyzerSettings.psd1
```

When `CompileModule = $true`, all `.ps1` files are merged into the single `.psm1` file and the `Public/`/`Private/` directories are not copied.

---

## Notes for AI Assistants

- **Always run `./build.ps1 -Bootstrap` first** in a fresh environment to install all dependencies via PSDepend.
- The `$PSBPreference` variable is **read-only at the script scope** once `psakeFile.ps1` is loaded. To modify it, set values before loading the task file, or use `-Force` on `Set-Variable`.
- Tests require the module to be **built first** — running Pester directly against source (not output) may produce incorrect results. Use `./build.ps1 -Task Test` rather than calling `Invoke-Pester` directly unless the module is already built and imported.
- The `Output/` directory is **excluded from VS Code search** (per `.vscode/settings.json`) and should not be committed to git (it is in `.gitignore`).
- The `Build/Convert-PSAke.ps1` utility is a developer convenience tool; it is not part of the published module.
- When editing `en-US/Messages.psd1`, ensure it uses UTF-8 encoding with BOM (standard for PowerShell data files).
- The repo's own `psakeFile.ps1` (at the root) is simpler than the one inside the module (`PowerShellBuild/psakeFile.ps1`). The root one is for building the module itself; the inner one is what consumers import.
