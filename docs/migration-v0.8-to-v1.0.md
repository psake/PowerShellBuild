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

> More entries will follow as the remaining Phase 2 work lands.

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
