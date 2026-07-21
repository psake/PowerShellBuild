# Migrating from PowerShellBuild v0.8 to v1.0

> 🚧 **Pre-release.** v1.0.0 has not shipped yet. This guide is being
> prepared alongside the v1.0.0 work; entries are added by each
> breaking-change PR as it lands. Track progress in
> [#120 — PowerShellBuild v1.0.0 roadmap](https://github.com/psake/PowerShellBuild/issues/120).
> If you are on 0.8.x today, no action is needed until you upgrade to a
> 1.0.0 prerelease or release.

This guide helps you upgrade a consumer `build.ps1` (or equivalent) from
PowerShellBuild **0.8.x** to **1.0.0**.

It only covers **breaking changes**. For new features and bug fixes that
do not require user action, see [`CHANGELOG.md`](../CHANGELOG.md).

## Quick Start

One line per break; follow the link for details and migration steps.

- [Minimum supported PowerShell version is now 5.1](#minimum-supported-powershell-version-is-now-51)
  — the manifest requires PowerShell 5.1+; supported and CI-tested
  platforms are Windows PowerShell 5.1 and PowerShell 7.4+.

> More entries will follow as the Phase 2 migrations to
> Microsoft.PowerShell.PlatyPS 1.x and psake 5.x land.

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
`'3.0'`) and `CompatiblePSEditions = @('Desktop', 'Core')`. The supported
and CI-tested platforms for 1.0.0 are **Windows PowerShell 5.1** and
**PowerShell 7.4+**. PowerShell 3.0–5.0 can no longer import the module;
PowerShell 6.0–7.3 is not blocked by the manifest but is untested and
unsupported (the test toolchain, Pester 6, supports only 5.1 and 7.4+).

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
