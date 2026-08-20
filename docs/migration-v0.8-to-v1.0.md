# Migrating from PowerShellBuild v0.8 to v1.0

> 🚧 **Pre-release.** v1.0.0 has not shipped yet. This guide is being
> prepared alongside the v1.0.0 work; entries are added by each
> breaking-change PR as it lands. Track progress in
> [#120 — PowerShellBuild v1.0.0 roadmap](https://github.com/psake/PowerShellBuild/issues/120).
> If you are on 0.8.x today, no action is needed until you upgrade to a
> 1.0.0 prerelease or release.

This guide helps you upgrade a consumer `build.ps1` (or equivalent) from
PowerShellBuild **0.8.x** to **1.0.0**.

It covers **breaking changes**, plus any **behavioral change that can
require action when you upgrade** — including bug fixes that make a
previously passing build start failing. For new features and fixes that
need nothing from you, see [`CHANGELOG.md`](../CHANGELOG.md).

## Quick Start

One line per break; follow the link for details and migration steps.

- [Minimum supported PowerShell version is now 5.1](#minimum-supported-powershell-version-is-now-51)
  — the manifest requires PowerShell 5.1+; the support floor is
  Windows PowerShell 5.1 or PowerShell 7.4+.
- [Script analysis now actually fails the build](#script-analysis-now-actually-fails-the-build)
  — the `Analyze` task's severity threshold never fired in 0.8.x; a build
  that passed before may now correctly fail.
- [psake 5.x is now the tested build toolchain](#psake-5x-is-now-the-tested-build-toolchain)
  — `Invoke-psake` returns a result object where it previously returned
  nothing, and Pester tests that call `Set-BuildEnvironment` can start
  failing.

> More entries will follow as the Phase 2 migration to
> Microsoft.PowerShell.PlatyPS 1.x lands.

## AI-assisted migration

If you use an IDE or CLI agent (Claude Code, GitHub Copilot in VS Code,
Copilot CLI, Cursor, Aider, etc.), you can ask it to migrate your build
file for you. From inside the repository you are migrating, paste this
prompt:

```text
You are migrating a PowerShellBuild consumer's build configuration from
0.8.x to 1.0.0.

Inputs:
- This migration guide: docs/migration-v0.8-to-v1.0.md in the
  psake/PowerShellBuild repository on GitHub. Fetch and read it if you
  have web or repo access; otherwise ask me to paste it.
- My build file (default: ./build.ps1 for psake, or ./.build.ps1 for
  Invoke-Build; ask if it lives elsewhere or has a different name).
- Any psake or Invoke-Build files my build file references.

Task:
1. Read the migration guide's "Migration entries" section.
2. For each entry, check whether it applies to my file(s).
3. Apply applicable entries' migration steps. Preserve all customizations
   not directly affected by the migration.
4. If you are uncertain how to apply an entry, leave the original code
   in place and add a `# MIGRATION-REVIEW: <reason>` comment on the
   relevant line.
5. After editing, run my test suite if one is configured. If you don't
   know how, ask.
6. Output: a summary of the changes you applied and any review flags
   you raised.

PowerShellBuild conventions worth knowing:
- The module is imported with `Import-Module PowerShellBuild`.
- Configuration goes through `$PSBPreference`, a hashtable populated in
  build.ps1 before tasks are invoked.
- Invoke-Build users dot-source the alias after import:
  `. PowerShellBuild.IB.Tasks`.
- psake users invoke via `-FromModule PowerShellBuild`.
```

**Notes on the workflow:**

- The agent reads the migration guide and your build file directly. You
  do not need to paste either into the prompt.
- If you are using a web chatbot (Claude.ai, ChatGPT, etc.) without
  file-system access, paste the relevant entries from this guide and
  your build file into the conversation alongside the prompt.
- Always review the agent's output before committing. The
  `# MIGRATION-REVIEW:` markers (if any) flag lines that need a human
  decision.

## Migration entries

### Minimum supported PowerShell version is now 5.1

The module manifest now declares `PowerShellVersion = '5.1'` (previously
`'3.0'`) and `CompatiblePSEditions = @('Desktop', 'Core')`. The support
floor for 1.0.0 is **Windows PowerShell 5.1** or **PowerShell 7.4+**.
PowerShell 3.0–5.0 can no longer import the module; PowerShell 6.0–7.3 is
not blocked by the manifest but is untested and unsupported (the test
toolchain, Pester 6, supports only 5.1 and 7.4+). CI exercises Windows
PowerShell 5.1 and the runners' current PowerShell 7 release on Linux,
Windows, and macOS.

The previous `'3.0'` floor was aspirational — the module's dependencies
(Pester 5+, BuildHelpers, psake) and its own code have required a newer
engine for some time. The manifest now states the contract that is
actually tested.

No build-file code change is needed. If you run your build on an engine
older than 5.1, `Import-Module PowerShellBuild` fails with an error that
the module "requires a minimum PowerShell version of '5.1'" — migrate by
running the build under Windows PowerShell 5.1 or PowerShell 7.4+.

Tracked in PR
[#141](https://github.com/psake/PowerShellBuild/pull/141); decision
record and platform validation details in
[#120 (comment)](https://github.com/psake/PowerShellBuild/issues/120#issuecomment-5028978464).

### Script analysis now actually fails the build

This is a bug fix, but it is listed here because it can turn a build that
passed on 0.8.x red on 1.0.0 without anything else changing.

In 0.8.x, `Test-PSBuildScriptAnalysis` counted findings by severity using
`$_Severity` — an undefined variable — rather than `$_.Severity`. Every
count was therefore zero, and the `Error`, `Warning`, and `Information`
thresholds could never fail a build. The `Analyze` task printed its
findings and then passed. Since `FailBuildOnSeverityLevel` defaults to
`Error`, this affected every consumer who ran the task: the gate reported
problems but never enforced them.

The counts are now correct, so the threshold you have configured is
enforced for the first time.

**No configuration change is required.** If your build starts failing at
the `Analyze` task after upgrading, the analyzer findings it reports were
present before too — they were simply never enforced. You have three
options:

1. Fix the reported findings (recommended — they are real).
2. Exclude specific rules through your PSScriptAnalyzer settings file,
   pointed to by `$PSBPreference.Test.ScriptAnalysis.SettingsPath`.
3. Raise the bar or turn enforcement off:

**Report findings without failing the build:**

    $PSBPreference.Test.ScriptAnalysis.FailBuildOnSeverityLevel = 'None'

**Fail only on errors, ignoring warnings:**

    $PSBPreference.Test.ScriptAnalysis.FailBuildOnSeverityLevel = 'Error'

To see what will be enforced before you upgrade, run PSScriptAnalyzer
against your built module directly:

    Invoke-ScriptAnalyzer -Path ./Output/MyModule/1.0.0 -Recurse |
        Group-Object -Property Severity

A related fix ships alongside it: omitting `-SettingsPath` no longer
fails with a path-resolution error, so
`Test-PSBuildScriptAnalysis -Path ./Output/MyModule/0.1.0 -SeverityThreshold Error`
now runs as documented instead of throwing.

Tracked in issue #96.

### psake 5.x is now the tested build toolchain

PowerShellBuild's own build and test toolchain moved from psake 4.9.0 to
**psake 5.0.4**. The module manifest still requires only `psake` **4.9.0
or newer**, so this does not force you to upgrade: PowerShellBuild's
task definitions are unchanged and run on both majors. Task names,
task dependencies, and the `$PSBPreference` contract are all identical.

Two things can still affect you if *you* move to psake 5.x.

**1. `Invoke-psake` now returns a result object.**

In psake 4.x, `Invoke-psake` wrote nothing to the pipeline. In 5.x it
returns a `PsakeBuildResult` (`Success`, `Duration`, `Tasks`,
`ErrorMessage`, and more). A `build.ps1` that captures or pipes the call
now receives an object where it previously received nothing.

**Before (psake 4.x):**

    # $result is $null; the build's success is read from $psake
    $result = Invoke-psake -buildFile ./psakeFile.ps1 -taskList $Task -nologo
    exit ([int](-not $psake.build_success))

**After (psake 5.x):**

    # $result is a PsakeBuildResult
    $result = Invoke-psake -buildFile ./psakeFile.ps1 -taskList $Task -nologo
    exit ([int](-not $result.Success))

`$psake.build_success` is still set by psake 5.x, so the original form
keeps working — you only need to change anything if an unexpected object
on the pipeline breaks your script (for example, a `build.ps1` whose
output is consumed by another tool).

**Detection:** look for an assignment or pipe on the `Invoke-psake` call
in your build file.

    Select-String -Path ./build.ps1 -Pattern '=\s*Invoke-psake|Invoke-psake.*\|'

**2. Pester tests that call `Set-BuildEnvironment` can start failing.**

If your Pester suite calls BuildHelpers' `Set-BuildEnvironment` inside a
`BeforeAll` block, and that suite runs inside a psake task, the whole
test container can fail on psake 5.x with:

    A 'break' or 'continue' statement with a label that does not match
    any enclosing loop escaped from your code.

`Set-BuildEnvironment` calls `Get-BuildVariable`, which uses `break`
inside `switch` blocks. That `break` can unwind out of the `BeforeAll`.
psake 4.9.x's task invocation absorbs it; psake 5.x's does not, so
Pester fails the container and every test in it
([pester/Pester#2669](https://github.com/pester/Pester/issues/2669)).

The fix is to skip the call when the build variables are already set —
your build script normally sets them before invoking psake, which makes
the call redundant there while keeping standalone `Invoke-Pester` runs
working:

**Before:**

    BeforeAll {
        Set-BuildEnvironment -Force
    }

**After:**

    BeforeAll {
        if (-not $env:BHProjectName) { Set-BuildEnvironment -Force }
    }

Wrapping the call in a dummy loop does **not** help — the `break` escapes
that too.

**Detection:**

    Select-String -Path ./tests -Pattern 'Set-BuildEnvironment' -Recurse

For psake's own list of v4 → v5 breaking changes (`default.ps1`
auto-detection, the `psake.ps1`/`psake.cmd` launchers, .NET Framework
below 4.0, and the `$framework` global), see
[`psake/psake docs/migration-v4-to-v5.md`](https://github.com/psake/psake/blob/main/docs/migration-v4-to-v5.md).
None of them affect PowerShellBuild itself.

Tracked in issue
[#161](https://github.com/psake/PowerShellBuild/issues/161); spike
findings and evidence in
[#155](https://github.com/psake/PowerShellBuild/issues/155).

## Adding an entry (for PR contributors)

Every breaking-change PR that lands in v1.0.0 must add an entry here for
each distinct user-visible break.

Format conventions (loose — match what's useful for the specific break,
modeled on [`psake/psake docs/migration-v4-to-v5.md`](https://github.com/psake/psake/blob/main/docs/migration-v4-to-v5.md)):

- `###` heading describing the change in user terms (not internal
  terms — e.g. "`Build-PSBuildMarkdown` now requires a module page
  path", not "PlatyPS 1.x signature change")
- A short prose paragraph: what changed and why
- A `**Before (0.8.x):**` / `**After (1.0.0):**` PowerShell code-block
  pair, when the migration is a concrete code change
- A sentence on detection when not obvious from the code (the error
  message a user will see, or a `grep` pattern to find affected code)
- A closing reference to the PR and any related issues

Also:

- Add a one-line summary to the **Quick Start** section above, linking
  to your new entry's heading.
- Reference this guide from your PR description (the entry it adds).

Use the existing entries in the **Migration entries** section above as a
model for structure and tone.

## Related

- Tracking issue: [#120 — PowerShellBuild v1.0.0 roadmap](https://github.com/psake/PowerShellBuild/issues/120)
- Changelog (non-breaking changes and complete release history):
  [`CHANGELOG.md`](../CHANGELOG.md)
- Sibling convention reference:
  [`psake/psake docs/migration-v4-to-v5.md`](https://github.com/psake/psake/blob/main/docs/migration-v4-to-v5.md)
