---
applyTo: '**/*'
description: 'Procedures for updating AI agent instructions from the centralized repository'
---

# Update Instructions for AI Agents

These instructions are self-contained for update procedures but assume familiarity with Git.
For general workflow guidance, see agent-workflow.instructions.md.

## Configuration Schema

Repositories control AIM behavior through `aim.config.json` in the repository root:

```json
{
  "version": "latest",
  "modules": {
    "include": ["agent-workflow", "powershell", "markdown"],
    "exclude": []
  },
  "externalSources": {
    "enabled": true,
    "repositories": [
      {
        "name": "awesome-copilot",
        "url": "https://github.com/github/awesome-copilot",
        "path": "instructions",
        "description": "Community-contributed instructions from GitHub"
      }
    ]
  },
  "skills": {
    "enabled": true,
    "vendorPath": ".agents/skills",
    "dependencies": [
      {
        "name": "psake",
        "source": "psake/psake-llm-tools",
        "path": "plugins/psake/skills/psake",
        "version": "v2.2.0",
        "format": "skill-md",
        "description": "psake build authoring (Agent Skill, agentskills.io)"
      }
    ]
  }
}
```

**Configuration fields:**

- `version` - Target AIM version: `"latest"` or specific version (e.g., `"0.8.0"`)
- `modules.include` - List of modules to include (without `.instructions.md` extension)
- `modules.exclude` - List of modules to exclude (takes precedence over include)
- `externalSources.enabled` - Enable fetching from external repositories
- `externalSources.repositories` - List of external instruction sources
- `skills.enabled` - Enable vendoring declared Agent Skill (SKILL.md) dependencies into the repo
- `skills.vendorPath` - Directory skills are vendored into (default `.agents/skills`, the
  cross-client Agent Skills convention)
- `skills.dependencies` - List of skills to vendor, each with `name`, `source` (repo), `path`
  (skill folder within the source), `version` (tag to pin, or `latest`), `format` (`skill-md`),
  and `description`. Unlike instruction modules, skills are copied to `vendorPath` (not
  `instructions/`) and routed via `AGENTS.md` - see step 7

## Update Procedure

When updating AI agent instructions in a repository that uses AIM, AI agents should:

### 1. Read Configuration

- Check if `aim.config.json` exists in the repository root
- If it exists, read all configuration fields
- If it doesn't exist, use defaults: version=latest, all modules, externalSources disabled

### 2. Clone the Centralized Repository

- Clone: `git clone https://github.com/tablackburn/ai-agent-instruction-modules.git`
- If targeting a specific version (not "latest"), checkout that tag: `git checkout v0.8.0`
- Use `AGENTS.template.md` from the cloned repository, NOT `AGENTS.md`
- The file `AGENTS.md` in the centralized repository is that repository's own implementation
- The file `AGENTS.template.md` is the template for downstream repositories

### 3. Summarize Changes

- Read the current version from the downstream repository's `AGENTS.md` header
  (e.g., "Template Version: 0.7.0")
- Read `CHANGELOG.md` from the cloned upstream repository
- Extract all version sections between the current version and the target version
- Provide the user with a brief summary of what has changed, noting any breaking changes
- If the current version equals the target version, inform the user they are already up to date

### 4. Determine Modules to Sync

Based on `aim.config.json`:

- If `modules.include` is specified, only sync those modules
- If `modules.exclude` is specified, exclude those from the sync
- Core modules (`agent-workflow`, `update`) should always be included unless explicitly excluded
- `repository-specific.instructions.md` is NEVER copied from upstream

### 5. Sync Instruction Files

For each instruction file in the upstream `instruction-templates/` folder:

1. Check if the module should be synced based on configuration
2. Check if the file already exists in the downstream `instructions/` folder
3. **If the file exists, ask the user:**
   - "File X already exists. Overwrite with upstream version? (yes/no/diff)"
   - If "diff", show the differences between local and upstream versions
   - Only overwrite if the user confirms
4. **If the file is new**, copy it without prompting

### 6. Handle External Sources

If `externalSources.enabled` is true and a needed language/framework instruction is not found in
AIM:

1. Check each configured external repository in order
2. For awesome-copilot, look in the `instructions/` path for matching `.instructions.md` files
3. Download the instruction file and copy to the downstream `instructions/` folder
4. Inform the user which files were fetched from external sources

**Example external fetch:**

```text
Fetching python.instructions.md from github/awesome-copilot...
Fetching react.instructions.md from github/awesome-copilot...
```

### 7. Handle Skill Dependencies

If `skills.enabled` is true, vendor each declared Agent Skill (SKILL.md format) into the
repository so it travels with the code and any agent can use it - materialized like an instruction
module, not installed per-developer. Skills are NOT copied into `instructions/`; they are vendored
under `skills.vendorPath` (default `.agents/skills`), the cross-client
[Agent Skills](https://agentskills.io) convention that conforming agents discover directly.

For each entry in `skills.dependencies`:

1. Resolve `source` at the pinned `version` and locate the skill folder at `path` (the directory
   containing `SKILL.md`). `version` is an exact tag or `latest`; `latest` means the most recent
   release tag of `source` (its newest version tag when the source publishes no GitHub releases),
   never the default branch's moving HEAD, so every agent vendors identical contents.
2. Copy that folder verbatim to `<vendorPath>/<name>/` (the `SKILL.md` plus any `references/`,
   `scripts/`, or `assets/`). Do not edit the vendored copy - re-sync from upstream instead.
3. **If `<vendorPath>/<name>/` already exists, ask the user** before overwriting (same posture as
   instruction files): overwrite / skip / diff.
4. Record or refresh upstream attribution and license in `<vendorPath>/NOTICE.md`.
5. Route the skill in `AGENTS.md`: add a row to the Instruction Applicability Matrix mapping the
   relevant task type to `<vendorPath>/<name>/SKILL.md`, and list it in the "Skill Dependencies"
   section. This is what makes any AGENTS-aware agent consult the skill.
6. Ensure a `CLAUDE.md` exists whose first line imports `AGENTS.md` (`@AGENTS.md`). Claude Code
   reads `CLAUDE.md` - not `AGENTS.md` and not `<vendorPath>/` - so this import is the bridge that
   carries the routing into Claude Code. Preserve any Claude-specific content below the import.

Agents that natively scan `.agents/skills/` (for example Cursor and opencode) pick the skill up
directly; the `AGENTS.md` routing plus the `CLAUDE.md` bridge covers agents that do not.

### 8. Update AGENTS.md

- Replace the HTML comment block at the top (the comment starting with `<!-- THIS IS THE TEMPLATE`)
- Update the sync date to today's date
- Update the template version to match the upstream version
- Preserve any "Repository-Specific" sections from the existing file

### 9. Update Configuration

If new modules were added or configuration changed during the update:

- Update `aim.config.json` to reflect the current module selection
- Ask the user if they want to enable/disable any modules going forward

### 10. Validate and Clean Up

- List all files in the local instructions directory
- Verify file structure matches expected configuration
- Remove the cloned repository folder to prevent nested Git repositories

## Adding New Modules

When the user requests a new instruction module that doesn't exist locally:

### From AIM Repository

1. Check if the module exists in `instruction-templates/`
2. If found, copy to `instructions/` and update `aim.config.json`

### From External Sources

1. If not in AIM and `externalSources.enabled` is true:
2. Search configured external repositories for matching instruction files
3. Download and copy to `instructions/`
4. Add the module name to `aim.config.json` modules.include

### New Language Detection

If the user adds new source files in a language not currently covered:

1. Detect new file extensions (e.g., `*.py` files added)
2. Check if corresponding instruction exists locally
3. If not, suggest fetching from external sources
4. Ask user: "Python files detected but no python.instructions.md found. Fetch from awesome-copilot?"

## Sync Checklist

- [ ] Configuration read from `aim.config.json`
- [ ] Target version determined (latest or pinned)
- [ ] Correct version/tag checked out from upstream
- [ ] Change summary provided to user (from CHANGELOG)
- [ ] Module list determined based on configuration
- [ ] User prompted before overwriting existing files
- [ ] New modules copied without prompting
- [ ] External sources checked for missing modules (if enabled)
- [ ] Skill dependencies vendored (if enabled) and routed via `AGENTS.md` + `CLAUDE.md` bridge
- [ ] AGENTS.md updated with new version and sync date
- [ ] Repository-specific content preserved
- [ ] Configuration updated with any changes
- [ ] Cloned repository folder cleaned up

## Content Preservation Rules

- The file `repository-specific.instructions.md` must NEVER be copied from upstream
- Repository-specific sections in AGENTS.md should be preserved
- Local customizations to instruction files should be flagged before overwriting
- Template sync date should be updated to current date
- Template version should match the centralized repository version

## Handling Breaking Changes

When upstream structural changes occur (e.g., renamed files, moved directories):

- Review the upstream changelog for breaking changes
- Compare file structure between current and target versions
- If `instruction-templates/` replaces `instructions/` as the source folder, adapt accordingly
- Rename local files to match upstream naming
- Update `aim.config.json` if module names changed

## Version Tracking

- **Current version**: Stored in `AGENTS.md` header as "Template Version: X.Y.Z"
- **Target version**: Configured in `aim.config.json` version field (defaults to "latest")
- **Change history**: Available in upstream `CHANGELOG.md`, follows semantic versioning
- Use version pinning for stability in production repositories
- Use "latest" for repositories that want to stay current with upstream changes
