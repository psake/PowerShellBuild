# PowerShellBuild.Common

Common [psake](https://github.com/psake/psake) tasks for building, testing, and publishing PowerShell modules.

![logo](./media/psaketaskmodule-256x256.png)

## Status - Work in progress

## Tasks

The following tasks are currently available:

| Name       | Dependencies    | Description |
| ---------- | --------------- | ----------- |
| Init       | _none_          | Initialize psake and task variables
| Clean      | init            | Clean output directory
| StageFiles | Clean           | Build module in output directory
| Build      | Init, Clean     | Clean and build module in output directory
| Analyze    | Build           | Run PSScriptAnalyzer tests
| Pester     | Build           | Run Pester tests
| Test       | Analyze, Pester | Run combined tests
