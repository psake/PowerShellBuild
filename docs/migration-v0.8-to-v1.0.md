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
- [Unparsable files now fail the script analysis gate](#unparsable-files-now-fail-the-script-analysis-gate)
  — `ParseError` findings are counted with `Error`, so a file that does not
  parse fails every threshold except `None`.
- [Check your build file for `$PSBPreference.Test.ScriptAnalysisEnabled`](#check-your-build-file-for-psbpreferencetestscriptanalysisenabled)
  — that setting never existed; this project's own examples used the wrong
  name, so a build file copied from them silently does nothing.
- [Code coverage percentages are no longer truncated to zero](#code-coverage-percentages-are-no-longer-truncated-to-zero)
  — coverage gating could not be used at all in 0.8.x; it can now. Cannot
  newly fail your build.
- [Invoke-Build consumers: code coverage reporting now works](#invoke-build-consumers-code-coverage-reporting-now-works)
  — the coverage report was written in a format the gate could not parse;
  a real threshold failure now replaces a file-not-found error.
- [If you pin exact versions, the floors are not the whole answer](#if-you-pin-exact-versions-the-floors-are-not-the-whole-answer)
  — `platyPS` is replaced rather than upgraded, and the new key needs quoting.
- [Your own module's `PowerShellVersion` is not changed for you](#your-own-modules-powershellversion-is-not-changed-for-you)
  — nothing forces it, but a floor below 5.1 is now an untested claim.
- [Help generation now uses Microsoft.PowerShell.PlatyPS 1.x, and installs it yourself](#help-generation-now-uses-microsoftpowershellplatyps-1x-and-installs-it-yourself)
  — the PlatyPS dependency changed module, and is no longer installed for you.
- [`$PSBPreference.Docs.AlphabeticParamsOrder` is removed](#psbpreferencedocsalphabeticparamsorder-is-removed)
  — PlatyPS 1.x always sorts alphabetically, so the setting could no longer do anything.
- [Generated markdown uses the PlatyPS 1.x schema](#generated-markdown-uses-the-platyps-1x-schema)
  — expect a large diff in `docs/` on the first 1.0.0 build.
- [Updatable help works, and now requires a `HelpInfoUri`](#updatable-help-works-and-now-requires-a-helpinfouri)
  — it could never succeed in 0.8.x; using it now needs a `HelpInfoUri` in your manifest.
- [Your `docs/` tree gains a module landing page](#your-docs-tree-gains-a-module-landing-page)
  — a new `<Module>.md` appears alongside the per-command documents.
- [A committed `docs/` tree converts itself on the first build](#a-committed-docs-tree-converts-itself-on-the-first-build)
  — the schema conversion is automatic; review the diff for the prose it
  drops, and convert orphaned documents by hand.
- [psake 4.x is no longer supported; the floor is now 5.0.4](#psake-4x-is-no-longer-supported-the-floor-is-now-504)
  — psake users must upgrade to 5.0.4+; Invoke-Build users are unaffected.
- [Pester 5.x is no longer supported; the floor is now 6.0.0](#pester-5x-is-no-longer-supported-the-floor-is-now-600)
  — Pester 6 keeps the `Should -Be` syntax, so most suites need no changes.
- [`Build-PSBuildModule -CompileDirectories` has a real default](#build-psbuildmodule--compiledirectories-has-a-real-default)
  — only affects direct callers of the function; the tasks always passed it.
- [`$PSBPreference.Sign.SkipCertificateValidation` now has an effect](#psbpreferencesignskipcertificatevalidation-now-has-an-effect)
  — the escape hatch did nothing on 0.8.x; a build that failed on an expired
  certificate may now succeed by signing with it.
- [The `GenerateMarkdown` task no longer unloads your module](#the-generatemarkdown-task-no-longer-unloads-your-module)
  — building help emptied the session it ran in; if you dropped the docs
  tasks to avoid that, you can put them back.
- [The `Pester` task no longer unloads a module it never imported](#the-pester-task-no-longer-unloads-a-module-it-never-imported)
  — the same defect on the default `Test` chain, where nothing was imported
  to justify the removal at all.


## AI-assisted migration

If you use an IDE or CLI agent (Claude Code, GitHub Copilot in VS Code,
Copilot CLI, Cursor, Aider, etc.), you can ask it to migrate your build
file for you. From inside the repository you are migrating, paste this
prompt:

```text
You are migrating a PowerShellBuild consumer's build configuration from
0.8.x to 1.0.0.

Inputs:
- The migration guide, at this exact URL:
  https://raw.githubusercontent.com/psake/PowerShellBuild/main/docs/migration-v0.8-to-v1.0.md
- My build file (default: ./build.ps1 for psake, or ./.build.ps1 for
  Invoke-Build; ask if it lives elsewhere or has a different name).
- Any psake or Invoke-Build files my build file references.
- Any dependency manifest or bootstrap my build file uses to install
  the toolchain -- requirements.psd1 for PSDepend, or an equivalent.
  This is where the psake, Pester, and PlatyPS floors are actionable.

Read the guide before anything else:
- Fetch the RAW file at the URL above. Do not work from a fetch tool
  that summarizes pages -- many do, silently, and a summary of this
  guide drops whole entries while still reading as complete.
- Verify you have the whole document: it ends with a section titled
  "Related". If yours does not, you have a partial or summarized copy.
  Get the raw text another way, or ask me to paste it. Do not proceed
  on a summary.

Task:
1. Read the guide's "Migration entries" section in full.
2. For each entry, decide whether it applies to my files.
3. Apply applicable entries' migration steps. Preserve every
   customization not directly affected by the migration.
4. Before editing anything, check which PowerShellBuild version is
   installed here, and run my test suite once to get a baseline. After
   step 5 the suite may not run at all.
5. Update the PowerShellBuild version itself. This is the upgrade, and
   no individual entry covers it: change the pin in my dependency
   manifest, and for psake consumers the -Version on
   `task <name> -FromModule PowerShellBuild -Version '<version>'`.
   Ask me which version to pin if you are unsure what is current.
   Make this change even if that version is not published or installed
   yet -- a half-migrated pin is worse than one I have to wait on. Add
   a review marker saying so rather than leaving the old version.
6. Where you cannot safely make a change, leave the original code in
   place and add a `# MIGRATION-REVIEW: <reason>` comment on the
   relevant line. Use this when you are unsure how to apply an entry,
   and when a decision is mine rather than yours.
7. Flag configuration that will interact badly with an entry even when
   the entry itself needs no edit. A setting that silently does nothing
   is worth telling me about if an entry changes what happens around it.
8. Output:
   - changes you applied, by file
   - every `# MIGRATION-REVIEW:` marker you left, and why
   - entries that apply but need no code change, as a checklist of what
     to expect on my first 1.0.0 build. MOST entries are this kind --
     for a typical consumer only a handful produce a diff. Do not omit
     them because they produced none, and do not treat a long checklist
     as padding.
   - anything you noticed that is not a migration item but changes what
     I should expect from an entry -- a task that will not run, a
     setting that has never taken effect.

PowerShellBuild conventions worth knowing:
- The module is imported with `Import-Module PowerShellBuild`.
- Configuration goes through `$PSBPreference`, a hashtable populated in
  build.ps1 before tasks are invoked. It is a plain hashtable, so an
  unrecognized setting name is silently ignored rather than rejected.
- Invoke-Build users dot-source the alias after import:
  `. PowerShellBuild.IB.Tasks`.
- psake users invoke via `-FromModule PowerShellBuild`.
```

**Notes on the workflow:**

- The agent reads this guide and your build file directly. You do not
  need to paste either into the prompt.
- **Check that it actually read the whole guide.** Many agent web-fetch
  tools do not return the page — they run a small model over it and hand
  back a summary. This guide is long, and a summary of it silently drops
  whole entries while still reading as complete. We measured three
  entries lost that way in testing. The prompt tells the agent to fetch
  the raw file and to verify the copy ends with the `Related` section; if
  it reports anything else, make it try again or paste the guide yourself.
- If you are using a web chatbot (Claude.ai, ChatGPT, etc.) without
  file-system access, paste this guide and your build file into the
  conversation alongside the prompt.
- Always review the agent's output before committing. The
  `# MIGRATION-REVIEW:` markers flag lines that need a human decision —
  including changes the agent was sure about but could not make.
- Expect a checklist as well as a diff. Roughly half the entries here
  require no code change at all; they describe what your first 1.0.0
  build will do differently. An agent that reports only its edits has
  told you less than half the story.

This prompt has been exercised against sample psake and Invoke-Build
consumers before release. It is not guaranteed to be complete for your
build file, and the review step is not optional.

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

Tracked in [#96](https://github.com/psake/PowerShellBuild/issues/96).

### Unparsable files now fail the script analysis gate

PSScriptAnalyzer's severity enum has four members — `Information`,
`Warning`, `Error`, and `ParseError`. In 0.8.x,
`Test-PSBuildScriptAnalysis` counted only the first three. A
`ParseError` record — a file that does not parse at all — therefore
satisfied no threshold, including the strictest one available
(`Information`): the record was printed in the results table and the
build passed.

`ParseError` is now counted alongside `Error`, so a file the engine
cannot even read fails every threshold except `None`. A file that does
not parse cannot be meaningfully analyzed, so this closes a gap where
the most severe possible finding was the only one that could never fail
a build.

**No configuration change is required.** If your build starts failing at
the `Analyze` task after upgrading and the reported record has severity
`ParseError`, the file genuinely does not parse — fix the syntax error.
It was being reported on 0.8.x too; it just never failed anything.

To check before you upgrade:

    Invoke-ScriptAnalyzer -Path ./Output/MyModule/1.0.0 -Recurse |
        Where-Object Severity -eq 'ParseError'

Any output there is what will start failing your build.

Alongside this, the severity threshold gains an **`Any`** value, which
fails the build on any diagnostic record regardless of severity:

    $PSBPreference.Test.ScriptAnalysis.FailBuildOnSeverityLevel = 'Any'

`Any` was documented in `build.properties.ps1` on 0.8.x but was missing
from the parameter's `ValidateSet`, so setting it failed parameter
binding rather than doing what the documentation promised. It now works.
This is additive — existing values behave as before.

Tracked in issue
[#144](https://github.com/psake/PowerShellBuild/issues/144).

### Check your build file for `$PSBPreference.Test.ScriptAnalysisEnabled`

That setting does not exist and never did. The real one is nested:
`$PSBPreference.Test.ScriptAnalysis.Enabled`.

It is listed here because the flat name appeared in this project's own
README examples through the whole 0.8.x line, so a consumer who started
from those examples has it in their build file today. `$PSBPreference` is
a plain hashtable, so assigning an unrecognized path adds a key nothing
reads — no error, no warning, no hint that the line does nothing.

Combined with the script analysis fix above, this bites twice: the setting
that was meant to turn analysis off never did, and analysis now enforces
its threshold for the first time.

**Search your build file:**

    Select-String -Path ./build.ps1, ./psakeFile.ps1, ./.build.ps1 `
        -Pattern 'ScriptAnalysisEnabled' -ErrorAction SilentlyContinue

**If it is there, correct the name:**

    # Before -- does nothing
    $PSBPreference.Test.ScriptAnalysisEnabled = $false

    # After
    $PSBPreference.Test.ScriptAnalysis.Enabled = $false

**Correcting the name changes behavior — decide before you do it.** With
the wrong name, analysis has been *running* on every build all along; the
line you thought turned it off never did. Fixing the name turns it off for
real, and findings you have been seeing in build output will stop
appearing. If that CI job you meant to run analysis in has quietly gone
away, correcting the name silently removes your only analysis coverage.

Look at what you would be switching off before you decide:

    Invoke-ScriptAnalyzer -Path ./Output/MyModule/1.0.0 -Recurse |
        Group-Object -Property Severity

Then pick deliberately: correct the name to genuinely disable analysis, or
delete the line and let the (now enforced) threshold do its job.

Tracked in [#191](https://github.com/psake/PowerShellBuild/issues/191).

### Code coverage percentages are no longer truncated to zero

`Test-PSBuildPester` passed every coverage percentage through
`[Math]::Truncate`, which collapses any fraction to zero. The report
always printed `0.00%` unless coverage was exactly 100%, and every
threshold above zero failed the build.

So `$PSBPreference.Test.CodeCoverage.Threshold` could not be used at all
on 0.8.x. If you set one and gave up because the build failed regardless
of your real coverage, that is why.

**The comparison is strictly more permissive, so this alone cannot turn a
passing build red.** Read that narrowly, though: if you have a threshold
configured today, your build has never once seen a real coverage number.
1.0.0 is where you find out what your coverage actually is, and it may be
far below the threshold you set years ago. The gate is not newly stricter;
it is newly *working*, and that can feel identical from the outside.

If you turned coverage gating off to work around this, you can turn it
back on:

    $PSBPreference.Test.CodeCoverage.Enabled   = $true
    $PSBPreference.Test.CodeCoverage.Threshold = 0.75

Tracked in [#138](https://github.com/psake/PowerShellBuild/issues/138).

### Invoke-Build consumers: code coverage reporting now works

**Invoke-Build only.** The psake tasks were unaffected.

`IB.tasks.ps1` read `$PSBPreference.Test.CodeCoverage.OutputFormat`, but
the setting is named `OutputFileFormat`. The expression evaluated to
`$null` and bound to a `[string]` parameter as an empty string rather than
falling back to its `JaCoCo` default, so Pester wrote a report the
threshold gate could not find or parse. The gate then failed with
`Code coverage file [...] not found` — a message about a missing file,
when the real problem was a format that was never set.

Coverage now runs end to end under Invoke-Build for the first time. Taken
together with the truncation fix above, a consumer who had
`$PSBPreference.Test.CodeCoverage.Enabled = $true` under Invoke-Build had
it broken in two independent ways and never saw a real coverage number.

**What to expect on upgrade:** if your coverage is genuinely below your
threshold, you will now get a real threshold failure naming the
percentage, where before you got a file-not-found error. Both are red
builds; the new one tells you the truth.

Note that `OutputFormat` was never a valid setting name, so nothing needs
renaming in your build file — if you set `OutputFormat`, it was silently
ignored and you should set `OutputFileFormat` instead:

    $PSBPreference.Test.CodeCoverage.OutputFileFormat = 'JaCoCo'

Tracked in [#178](https://github.com/psake/PowerShellBuild/issues/178).

### If you pin exact versions, the floors are not the whole answer

This guide states dependency changes as **floors** — psake `5.0.4` or
newer, Pester `6.0.0` or newer, `Microsoft.PowerShell.PlatyPS` `1.0.3`.
`RequiredModules` in the PowerShellBuild manifest enforces exactly that.

Most consumers do not pin floors, though. A PSDepend `requirements.psd1`
takes exact versions:

    @{
        Pester          = '5.6.1'
        platyPS         = '0.14.2'
        psake           = '4.9.0'
        PowerShellBuild = '0.8.2'
    }

Pinning the floor exactly is a safe reading of every entry here, and it
is what we would do:

    @{
        Pester                         = '6.0.0'
        'Microsoft.PowerShell.PlatyPS' = '1.0.3'
        psake                          = '5.0.4'
        PowerShellBuild                = '1.0.0'
    }

Two details that are easy to miss:

- **`platyPS` is replaced, not upgraded.** The module name changed, so
  the old key must go rather than have its version raised. Leaving both
  in place is worse than leaving neither: the two modules ship different
  `YamlDotNet` assemblies, and whichever loads second fails with
  `Assembly with same name is already loaded`.
- **The key needs quoting.** `Microsoft.PowerShell.PlatyPS` contains dots,
  so it must be `'Microsoft.PowerShell.PlatyPS' = '1.0.3'` in a PowerShell
  data file.

Installing Pester 6 over a Windows PowerShell 5.1 machine that carries
the Microsoft-signed Pester 3 can require `-SkipPublisherCheck`; see the
Pester entry below. PSDepend passes that through its `Parameters` key, and
if your bootstrap uses `Install-Module` directly, add the switch there.

### Your own module's `PowerShellVersion` is not changed for you

No entry here touches your module manifest, and 1.0.0 does not require
you to change it. But it is worth a look while you are upgrading.

If your manifest declares something below `5.1`:

    PowerShellVersion = '3.0'

that claim is now untested by your own build. PowerShellBuild 1.0.0
requires PowerShell 5.1 to run, and Pester 6 requires it to test, so
nothing in your pipeline can exercise the module on 3.0 or 4.0 any more.
The module may still work there; you simply have no evidence.

Either raise the floor to match what you actually test, or keep it and
know it is an untested claim. The same reasoning is why PowerShellBuild
raised its own — see the first entry in this guide.

### Help generation now uses Microsoft.PowerShell.PlatyPS 1.x, and installs it yourself

`Build-PSBuildMarkdown` and `Build-PSBuildMAMLHelp` are built on
[`Microsoft.PowerShell.PlatyPS`](https://www.powershellgallery.com/packages/Microsoft.PowerShell.PlatyPS)
1.x instead of `platyPS` 0.14.x. The `GenerateMarkdown` and `GenerateMAML`
tasks now check for the new module and skip with a warning if it is
missing, exactly as they did for the old one.

PlatyPS is **no longer listed in `RequiredModules`**, so
`Install-Module PowerShellBuild` no longer installs it for you. This is
deliberate rather than an oversight. The two PlatyPS modules each ship
their own `YamlDotNet.dll` with different assembly identities, and .NET
refuses to load both into one process — whichever imports second fails
with `Assembly with same name is already loaded`. A `RequiredModules`
entry forces that load into **every** session that imports
PowerShellBuild, including builds that never generate documentation, so
any consumer still holding `platyPS` 0.14.x — which is every consumer
part-way through this upgrade — would be unable to import PowerShellBuild
at all. Making the dependency optional matches how the docs tasks have
always behaved: they probe for the module and skip when it is absent.

**Before (0.8.x):**

```powershell
# platyPS arrived with PowerShellBuild via RequiredModules
Install-Module -Name PowerShellBuild
```

**After (1.0.0):**

```powershell
Install-Module -Name PowerShellBuild
# Only if you build help; add it to your own requirements/bootstrap
Install-Module -Name Microsoft.PowerShell.PlatyPS -MinimumVersion 1.0.3
```

**Detection:** the build prints
`Microsoft.PowerShell.PlatyPS module is not installed. Skipping [GenerateMarkdown] task.`
and produces no markdown or MAML.

You can uninstall `platyPS` 0.14.x once nothing else on the machine needs
it. Leaving it installed is safe — it is only a problem if something
loads it into the same session that loads PlatyPS 1.x.

Tracked in PRs [#150](https://github.com/psake/PowerShellBuild/issues/150)
and [#151](https://github.com/psake/PowerShellBuild/issues/151); chain
context in [#105](https://github.com/psake/PowerShellBuild/issues/105).

### `$PSBPreference.Docs.AlphabeticParamsOrder` is removed

PlatyPS 1.x always orders parameters alphabetically and offers no option
to restore declaration order, so the setting could no longer do anything.
Rather than keep a setting that silently lies, it is gone, along with the
`AlphabeticParamsOrder` parameter on `Build-PSBuildMarkdown`.

**Before (0.8.x):**

```powershell
$PSBPreference.Docs.AlphabeticParamsOrder = $true
```

**After (1.0.0):**

```powershell
# Remove the line. Alphabetical ordering is now the only behavior.
```

**Detection:** setting the property no longer fails (it is a plain
hashtable), so this will not error — grep your build file for
`AlphabeticParamsOrder` and delete the assignment. Calling
`Build-PSBuildMarkdown` with `-AlphabeticParamsOrder` **does** fail, with
`A parameter cannot be found that matches parameter name 'AlphabeticParamsOrder'`.

`ExcludeDontShow` and `UseFullTypeName` are unchanged and keep their
existing behavior.

### Generated markdown uses the PlatyPS 1.x schema

Markdown written into `$PSBPreference.Docs.RootDir` now carries
`PlatyPS schema version: 2024-05-01` and a `document type:` key where
0.14.x wrote `schema: 2.0.0`. Command documents also gain an `## ALIASES`
section and per-parameter-set `### __AllParameterSets` headings inside
`SYNTAX`.

The on-disk layout is unchanged: documents stay at
`<Docs.RootDir>/<locale>/<Command>.md`, and MAML still lands at
`<ModuleOutDir>/<locale>/<ModuleName>-help.xml`. PlatyPS 1.x would
otherwise nest both a level deeper under a `<ModuleName>` directory;
PowerShellBuild flattens that back out so existing docs trees, static
site configuration, and `.ExternalHelp` directives keep working.

**Detection:** your first 1.0.0 build produces a large diff in `docs/`.

If you **commit** your `docs/` tree, review that diff for lost prose
before committing it. Existing documents are refreshed in place with
`Update-MarkdownCommandHelp`, which preserves hand-written content, so
this should be schema churn rather than content loss — but verify.
Consumer guidance for converting a committed tree is in
[A committed `docs/` tree converts itself on the first build](#a-committed-docs-tree-converts-itself-on-the-first-build).

### Updatable help works, and now requires a `HelpInfoUri`

`Build-PSBuildUpdatableHelp` and the `GenerateUpdatableHelp` task produce a
help cabinet, its `.zip`, and a `HelpInfo.xml`. In 0.8.x they could not:
the function needed a module landing page that `Build-PSBuildMarkdown`
never generated, passed an undefined variable as the cabinet source
folder, and never received the module name — three separate defects,
recorded in [#169](https://github.com/psake/PowerShellBuild/issues/169).
Any 0.8.x build that reached this task failed with a parameter-binding
error, so nothing that worked before stops working.

**Your module manifest must declare a `HelpInfoUri`.** That URI is where
`Update-Help` looks for the content, so a cabinet built without one cannot
be consumed. If it is missing, the task now writes a warning and produces
nothing:

```text
Updatable help was skipped for [MyModule]. The module manifest does not
declare a HelpInfoUri, ...
```

Refusing is deliberate. `New-HelpCabinetFile` will otherwise write the
cabinet and its `.zip` and then fail before writing the `HelpInfo.xml`
that makes them findable — output that looks complete and is useless.

**Migration:** add the URI where you publish help.

```powershell
# In your module manifest
HelpInfoUri = 'https://example.com/mymodule/help'
```

Nothing is needed if you do not use the `GenerateUpdatableHelp` task; it
is opt-in and not part of the default build.

**Calling the function directly?** Its signature changed. `Module` is now
mandatory rather than defaulting from a caller-scope variable, and
`ModulePath` is new — it is where the MAML written by the `GenerateMAML`
task is read from.

**Before (0.8.x):**

```powershell
Build-PSBuildUpdatableHelp -DocsPath ./docs -OutputPath ./Output/UpdatableHelp
```

**After (1.0.0):**

```powershell
Build-PSBuildUpdatableHelp -DocsPath ./docs -OutputPath ./Output/UpdatableHelp `
    -ModulePath ./Output/MyModule/1.0.0 -Module MyModule
```

### Your `docs/` tree gains a module landing page

`Build-PSBuildMarkdown` now generates `<Docs.RootDir>/<locale>/<Module>.md`
alongside the per-command documents. 0.14.x never produced one.

The page carries the module GUID, locale, and help version into the
updatable-help cabinet, which is why its absence was one of the three
defects above. It is also a different document type from command help, and
is excluded from MAML generation automatically — a module page in a MAML
export batch aborts the entire export
([PowerShell/platyPS#862](https://github.com/PowerShell/platyPS/issues/862)),
so `Build-PSBuildMAMLHelp` filters it out.

**Detection:** a new `<Module>.md` file appears in your docs tree on the
first 1.0.0 build. If you commit `docs/`, commit it too.

### A committed `docs/` tree converts itself on the first build

**This entry assumes `GenerateMarkdown` actually runs.** Everything below
is inert if it does not — and it skips silently when
`Microsoft.PowerShell.PlatyPS` is not installed, when your module exports
no commands, or when the task is not in your build chain. A skipped task
converts nothing: your tree stays on the 0.14.x schema indefinitely and
MAML is generated from an empty set. If your build log carries
`No commands have been exported. Skipping markdown generation.` or a
missing-PlatyPS warning, fix that first; none of the rest of this entry
applies until it runs.

If you commit your `docs/` tree, you do **not** need a manual conversion
step in the ordinary case. The `GenerateMarkdown` task runs
`Update-MarkdownCommandHelp` over every existing command document on every
build, and that cmdlet rewrites a 0.14.x document into the 1.x schema in
place. A tree that went into the first 1.0.0 build as `V1Schema` comes out
of it as `V2Schema`, in the same files, with no staging directory and no
leftovers:

```console
=== docs tree BEFORE the build (genuine 0.14.x) ===
  Get-ScratchWidget.md         CommandHelp, V1Schema
  New-ScratchWidget.md         CommandHelp, V1Schema
  Remove-ScratchWidget.md      CommandHelp, V1Schema
  ScratchModule.md             ModuleFile, V1Schema

=== docs tree AFTER the build ===
  Get-ScratchWidget.md         CommandHelp, V2Schema
  New-ScratchWidget.md         CommandHelp, V2Schema
  Remove-ScratchWidget.md      CommandHelp, V2Schema
  ScratchModule.md             ModuleFile, V2Schema
```

`Measure-PlatyPSMarkdown` is how you check which schema a tree is on:

```powershell
Measure-PlatyPSMarkdown -Path ./docs/en-US/*.md |
    Select-Object FileType, FilePath
```

So the work is not running a conversion. It is **reading the diff the build
produces before you commit it**, and handling the few documents the build
cannot convert.

#### What the conversion keeps and what it drops

Verified by round-tripping a 0.14.x tree whose markdown had been edited by
hand beyond what comment-based help contained:

| Hand-written content                                    | Result                  |
| ------------------------------------------------------- | ----------------------- |
| Extra prose paragraph in `## DESCRIPTION`                | Survives                |
| A whole `### EXAMPLE` block added only to the markdown   | Survives                |
| An edited parameter description                          | Survives, but see below |
| Bodies under `## INPUTS` and `## OUTPUTS`                | Survives                |
| Extra paragraph in `## NOTES`                            | Survives                |
| A heading that is not part of the schema (`## CAVEATS`)  | **Silently dropped**    |

The last row is the one to grep for. PlatyPS parses a command document into
a fixed set of sections; anything outside them has nowhere to go and is
discarded with no warning and no error. If your documents carry custom
sections, move that content into `## NOTES` — or into the module landing
page — before your first 1.0.0 build.

**Edited parameter descriptions are appended to, not replaced.** Where the
description in the markdown differs from the one in the module's
comment-based help, `Update-MarkdownCommandHelp` adds the comment-based help
text underneath the markdown text rather than reconciling them — and it does
so again on every subsequent build. After one build:

```text
### -IncludeHidden

Include widgets that are marked as hidden. HANDWRITTEN-PARAMETER text.
Include widgets that are marked as hidden.
```

After two:

```text
Include widgets that are marked as hidden. HANDWRITTEN-PARAMETER text.
Include widgets that are marked as hidden.
Include widgets that are marked as hidden.
```

Parameter descriptions unchanged from comment-based help are not affected.
The fix is to keep comment-based help as the single source of truth for
parameter descriptions and delete the divergent markdown text; prose in
`DESCRIPTION`, `EXAMPLES`, and `NOTES` does not behave this way.

#### What the front matter becomes

```yaml
# Before (0.14.x)
external help file: ScratchModule-help.xml
Module Name: ScratchModule
online version: https://example.com/scratch-widget
schema: 2.0.0
```

```yaml
# After (1.0.0)
document type: cmdlet
external help file: ScratchModule-help.xml
HelpUri: https://example.com/scratch-widget
Module Name: ScratchModule
ms.date: 08/26/2026
PlatyPS schema version: 2024-05-01
```

`schema:` becomes `PlatyPS schema version:`, `online version:` becomes
`HelpUri:`, `document type:` and `ms.date:` are new, and the keys are
re-sorted. `external help file:` is carried across **byte for byte**, which
is what you want: the value names the MAML file, PowerShellBuild pins it to
the 0.14.x lowercase `<Module>-help.xml` spelling, and an existing
`.ExternalHelp` directive keeps resolving — including on case-sensitive file
systems.

#### The documents the build cannot convert

`Update-MarkdownCommandHelp` looks each document's command up in the current
session. A document for a command your module no longer exports has nothing
to look up, so the cmdlet writes a non-terminating error whose message is
just the command name, and leaves the file on the 0.14.x schema:

```text
Update-MarkdownCommandHelp: Get-ScratchWidget
```

The error identifier is
`FailedToImportMarkdown,Microsoft.PowerShell.PlatyPS.UpdateMarkdownHelpCommand`
and the category reason is `CommandNotFoundException`. **Detection:** after
the build, `Measure-PlatyPSMarkdown` still reports `V1Schema` for those
files. Delete them if the command is gone, or rename them to match the
command that replaced it.

#### Converting by hand, without a build

You need the one-shot below only when you want the conversion as its own
reviewable commit, separate from a build. Import your module first — the
same session lookup applies:

```powershell
Import-Module ./Output/MyModule/1.0.0/MyModule.psd1 -Force

$commandDocument = Measure-PlatyPSMarkdown -Path ./docs/en-US/*.md |
    Where-Object FileType -match 'CommandHelp'
Update-MarkdownCommandHelp -Path $commandDocument.FilePath -NoBackup
```

That converts the command documents only. If your 0.14.x tree has a module
landing page, it stays on the old schema — `Update-MarkdownModuleFile`
cannot refresh one on its own, because it requires the imported
`-CommandHelp` objects the page indexes. Leave it: your next build replaces
the landing page wholesale and stamps the 1.x front matter on it.

Three details in that snippet are load-bearing:

- **Filter to `CommandHelp`.** Your tree contains a module landing page
  (`<Module>.md`), and it is a different document type. Fed to
  `Update-MarkdownCommandHelp` it is at least rejected loudly —
  `'…\MyModule.md' is not a CommandHelp file.` — and left alone while the
  command documents still convert. The other two entry points are not so
  safe. `Import-MarkdownCommandHelp` accepts the landing page without
  complaint, hands back a `CommandHelp` object titled after the module, and
  `Export-MarkdownCommandHelp` then writes it back out as an empty cmdlet
  document whose front matter has the landing page's
  `{{ Update Download Link }}` placeholders embedded as malformed YAML. Feed
  the same object to `Export-MamlCommandHelp` and it aborts the whole export
  and writes **nothing**, not even for the command documents that were fine
  ([PowerShell/platyPS#862](https://github.com/PowerShell/platyPS/issues/862)).
- **Pass `-NoBackup`.** Without it the cmdlet writes a `<Command>.md.bak`
  beside every document, and a second run fails on all of them with
  `IOException: Cannot create a file when that file already exists.`
  ([PowerShell/platyPS#863](https://github.com/PowerShell/platyPS/issues/863)).
  With `-NoBackup` the command is repeatable. Your version control is the
  backup.
- **Update in place; do not export.** The export pipeline that looks like
  the natural one-shot does not do what it appears to:

  ```powershell
  # Does NOT convert ./docs/en-US in place
  Measure-PlatyPSMarkdown -Path ./docs/en-US/*.md |
      Where-Object FileType -match 'CommandHelp' |
      Import-MarkdownCommandHelp -Path { $_.FilePath } |
      Export-MarkdownCommandHelp -OutputFolder ./docs/en-US -Force
  ```

  `Export-MarkdownCommandHelp` always appends the module name to
  `-OutputFolder`, so that writes `./docs/en-US/MyModule/*.md` and leaves
  every original file untouched on the 0.14.x schema. If you use the export
  pipeline anyway, send it to a staging folder and move
  `<staging>/<Module>/*.md` back over your tree. Dropping `-Force` does not
  help either: the export then skips each existing file with only a warning
  — `'Get-ScratchWidget' exists, skipping. Use -Force to overwrite.` —
  writes nothing, and returns success.

#### Recommended sequence

1. Commit or stash everything, so the conversion diff stands alone.
2. Grep your documents for headings outside the PlatyPS schema and relocate
   that content.
3. Run your normal 1.0.0 build.
4. Run `Measure-PlatyPSMarkdown` and confirm every command document reports
   `V2Schema`. Anything still on `V1Schema` is an orphaned document.
5. Read the diff for prose, not just for schema churn — in particular
   doubled parameter descriptions and missing custom sections.
6. Commit the converted tree together with the new `<Module>.md` landing
   page.

Verified against Microsoft.PowerShell.PlatyPS 1.0.3 on PowerShell 7 with a
throwaway module whose 0.14.x markdown was generated by platyPS 0.14.2.
Note that platyPS 0.14.2 and Microsoft.PowerShell.PlatyPS cannot be loaded
into the same session — they ship conflicting `YamlDotNet` assemblies — so
if you compare old and new output yourself, use two separate PowerShell
processes.

Related: [#154](https://github.com/psake/PowerShellBuild/issues/154).

### psake 4.x is no longer supported; the floor is now 5.0.4

`RequiredModules` requires **psake 5.0.4 or newer**, previously 4.9.0. If you
use Invoke-Build rather than psake, nothing here applies to you.

`RequiredModules` is enforced when the module is imported, so this is not a
degraded experience — with only psake 4.x installed,
`Import-Module PowerShellBuild` fails outright.

**Migration:**

```powershell
Install-Module -Name psake -MinimumVersion 5.0.4 -Repository PSGallery
```

If you pin psake in a `requirements.psd1` or equivalent, raise the pin there
too — installing PowerShellBuild will pull a satisfying psake, but a pinned
4.9.x will still be the one your build imports.

**Detection:** `Import-Module PowerShellBuild` fails with a message that the
required module `psake` is not installed, naming version `5.0.4`.

**What upgrading psake costs you.** Per
[psake's own v4-to-v5 migration guide](https://github.com/psake/psake/blob/main/docs/migration-v4-to-v5.md),
most v4 build scripts work unchanged. The `Task ... -Depends` syntax,
`-FromModule`, and `$psake.build_success` are all explicitly retained — this
repository still uses all three. The breaks are:

- `default.ps1` is no longer auto-detected — rename it to `psakefile.ps1`, or
  pass `-BuildFile`. PowerShellBuild's own convention has always been
  `psakeFile.ps1`, so this is unlikely to affect you.
- The standalone `psake.ps1` and `psake.cmd` runners are gone — use
  `Import-Module psake; Invoke-psake`. Again unlikely, since the documented
  PowerShellBuild pattern is a `build.ps1` wrapper.
- `Invoke-psake` now returns a `PsakeBuildResult` where v4 returned nothing.
  This only matters if your wrapper assigns or pipes the result;
  `$psake.build_success` still works.
- The `OutputHandler`, `OutputHandlers`, and `ColoredOutput` configuration
  options are removed. Use `$env:NO_COLOR`, `-OutputFormat`, or `-Quiet`.
- .NET Framework older than 4.0 is unsupported and the default `Framework`
  moved from `4.0` to `4.7.2`, and the `$framework` global is gone. Neither
  affects PowerShell module builds.
- psake 5 requires PowerShell 5.1 (v4 declared 3.0) — already the
  PowerShellBuild floor, so no additional constraint.

**Why the floor moved.** The floors this module declares were not all earned
the same way. Pester's floor is lower than the version we build with, and that
is deliberate: `Test-PSBuildPester` supports both Pester majors and CI proves
it on every run. The psake floor was lower *and untested* — CI has exercised
only 5.0.4 since the toolchain moved there, so 4.9.0 was a claim rather than a
guarantee. Rather than keep asserting support nothing verifies, the floor now
matches what is tested.

**One thing you gain.** psake 5 stops silently swallowing an escaping `break`.
Under 4.9.x, a `break` leaking out of a Pester `BeforeAll` — which
BuildHelpers' `Get-BuildVariable` does — is absorbed, so the test container
fails invisibly and the build still passes. In this repository that was twelve
tests that had not been running. If your Pester tests call
`Set-BuildEnvironment`, upgrading may surface failures that were always there.

Decision and evidence in
[#166](https://github.com/psake/PowerShellBuild/issues/166).

### Pester 5.x is no longer supported; the floor is now 6.0.0

`RequiredModules` requires **Pester 6.0.0 or newer**, previously 5.6.1, and
`Test-PSBuildPester` refuses to run under anything older.

`RequiredModules` is enforced when the module is imported, so with only
Pester 5.x installed, `Import-Module PowerShellBuild` fails outright.

**Migration:**

```powershell
Install-Module -Name Pester -MinimumVersion 6.0.0 -Repository PSGallery -SkipPublisherCheck
```

`-SkipPublisherCheck` is needed on Windows PowerShell, where an older
Microsoft-signed Pester ships in the box.

**Detection:** `Import-Module PowerShellBuild` fails naming `Pester` and
version `6.0.0`. If a Pester 5.x is already loaded in the session when
`Test-PSBuildPester` runs, it throws instead: `Pester version [5.9.1] is
loaded, but Test-PSBuildPester requires Pester 6.0.0 or newer.`

**What upgrading Pester costs you.** Less than a major version bump usually
implies, because Pester 6 kept the v5 assertion syntax:

- **`Should -Be` and the rest of the v5 assertions still work.** Pester 6's
  `Should.DisableV5` configuration option defaults to `$false`, so existing
  tests keep running unchanged. You are not required to adopt the new
  `Should-Be` family.
- **An empty or `$null` `-ForEach` now fails.** `Run.FailOnNullOrEmptyForEach`
  defaults to `$true` in Pester 6, where Pester 5 skipped silently. If a
  data-driven test is fed an empty collection, discovery now errors instead of
  quietly generating no tests. That is usually a bug being surfaced — a test
  that never ran and never said so — but it can turn a green suite red.
  Set `-AllowNullOrEmptyForEach` on the specific `It`/`Context` that can
  legitimately be empty.
- Pester 6 supports Windows PowerShell 5.1 and PowerShell 7.4+, matching
  PowerShellBuild's own support floor, so it adds no engine constraint.

**Why the floor moved.** The same reason as the psake floor: the declared
minimum should be what is actually tested. CI runs Pester 6 and nothing else
verifies a 5.x consumer, so 5.6.1 asserted support nothing proved.

Two related defects are fixed in the same change. `Test-PSBuildPester`
declared a `5.0.0` minimum it could never honor — Pester 5.0.0 does not export
`New-PesterConfiguration` and has no `Run.SkipRemainingOnFailure`, both of
which the function calls — so the guard admitted versions that failed later
with a confusing `CommandNotFoundException`. And the exact pin in
`requirements.psd1` moved to the current release.

Decision and evidence in
[#172](https://github.com/psake/PowerShellBuild/issues/172).

### `Build-PSBuildModule -CompileDirectories` has a real default

**Only affects code that calls `Build-PSBuildModule` directly.** Consumers
going through the psake or Invoke-Build tasks are unaffected, because both
pass the setting explicitly.

The parameter used to default to `@()`. That was never usable: PowerShell
treats an empty `-Path` as *not supplied* and falls back to the current
location, so `-Compile` without `-CompileDirectories` concatenated every
`.ps1` beneath the working directory into the built module — and reported
success. The default is now the same value the tasks pass and the README
has always documented:

    @('Enum', 'Classes', 'Private', 'Public')

**No action is required if your sources live in those directories**, which
is the layout the setting has documented since 0.5.0.

**If they do not**, and you called the function without the parameter while
standing in your module's source root, the old fallback happened to sweep
your sources up anyway. That stops. Name your directories explicitly:

    Build-PSBuildModule -Path ./src -Compile -CompileDirectories @('functions')

A build that compiles nothing now warns rather than producing a module with
no functions, so the change announces itself rather than being discovered in
a published package.

Tracked in [#206](https://github.com/psake/PowerShellBuild/issues/206).
### `$PSBPreference.Sign.SkipCertificateValidation` now has an effect

**Only affects builds with `$PSBPreference.Sign.Enabled = $true`.**

The setting is documented as an escape hatch for CI where a certificate is
mid-rotation. On 0.8.x it did nothing on two of the four certificate
sources for psake consumers, and nothing at all for Invoke-Build
consumers, because `IB.tasks.ps1` never passed it through.

Both are fixed, so a build that previously failed with
`No valid code signing certificate was found` may now succeed **by signing
with an expired certificate** — which is what you asked for, but worth
knowing you are now getting.

The relaxation is a fallback, not a bypass: an unexpired certificate is
preferred whenever one exists, an expired one is used only when no valid
one was found, and a warning names the certificate and its expiry when
that happens. `Thumbprint` still matches the thumbprint you asked for.

**If you do not want expired certificates used, leave the setting at its
default:**

    $PSBPreference.Sign.SkipCertificateValidation = $false

Note the two source families differ, and the difference matters:

- `Store` and `Thumbprint` always require a private key, because that is
  part of how the certificate is selected.
- `EnvVar` and `PfxFile` skip **every** check, the private key included.
  A certificate exported without its private key is accepted here and
  fails later in `Set-AuthenticodeSignature` with a much less helpful
  message.

Tracked in [#193](https://github.com/psake/PowerShellBuild/issues/193).

### The `GenerateMarkdown` task no longer unloads your module

On 0.8.x, `Build-PSBuildMarkdown` ended with
`Remove-Module -Name <ModuleName>` in its `finally` block. `Remove-Module
-Name` removes **every** loaded module with that name — including a copy
you loaded yourself, from a different path, that the function never
imported. Generating documentation emptied the session it ran in.

This was on by default. `Build` depends on `BuildHelp`, which depends on
`GenerateMarkdown`, so every consumer who did not override
`$PSBBuildDependency` ran it on every build.

On 1.0.0 the function records the copies you had loaded, removes only the
instance it imported itself, and re-imports what it displaced — including
on the zero-export path, where it warns
`No commands have been exported. Skipping markdown generation.` and
returns without generating anything.

**Detection.** You were affected if a command that worked before your build
stopped being recognized afterwards, in a session where nothing obviously
removed it:

    The term 'Get-Widget' is not recognized as a name of a cmdlet, function,
    script file, or executable program.

**If you worked around this by dropping the documentation tasks**, you can
put them back. `PowerShellOrg/PSDepend` did exactly that:

**Before (0.8.x):**

```powershell
# Skips BuildHelp (GenerateMarkdown) - Build-PSBuildMarkdown has a Remove-Module scope bug
$PSBBuildDependency = @('StageFiles')
```

**After (1.0.0):**

```powershell
# The default is fine again; delete the override entirely
```

Two smaller notes. The restored module is a fresh import rather than
literally your original instance, so a `PSModuleInfo` reference you were
holding across the call goes stale — a much smaller problem than the
command disappearing, and the only way to keep `-Force` refreshing the
documented command surface. And the import no longer passes `-Global`:
PlatyPS resolves the module through the `PSModuleInfo` object it is handed,
never by name, so the import no longer reaches into your session state at
all. The generated markdown is byte-for-byte unchanged.

Tracked in [#221](https://github.com/psake/PowerShellBuild/issues/221).

### The `Pester` task no longer unloads a module it never imported

The same defect in a worse form. On 0.8.x, `Test-PSBuildPester` imported
the module under test only when `-ImportModule` was passed, but removed it
by name **unconditionally**. `$PSBPreference.Test.ImportModule` defaults to
`$false`, and both task files forward it verbatim, so for every consumer who
had not turned it on, the `Pester` task imported nothing and then removed
whatever you happened to have loaded under that name. `Test` depends on
`Pester`, so `./build.ps1` and `./build.ps1 -Task Test` both did it.

On 1.0.0 the function removes only the instance it imported, and restores
anything it displaced on the way in. When `-ImportModule` is not passed it
now touches your loaded modules not at all.

**Detection** is the same as the entry above: a command that was available
before the build is not available after it. This one reaches more builds,
because a consumer who turned documentation generation off still runs tests.

No build-file change is needed. If you set
`$PSBPreference.Test.ImportModule = $true` purely to make the removal
symmetrical, that is no longer a reason to keep it — but leaving it on is
harmless, and the module under test is still imported from the output
directory, still displacing a stale copy for the duration of the run.

Tracked in [#222](https://github.com/psake/PowerShellBuild/issues/222).

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
