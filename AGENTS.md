# AI Agent Instructions

AI agents working in this repository must follow these instructions.

Template Version: 0.12.1

Last sync: 2026-08-24 (Update this date when syncing from the centralized repository)

## Instructions for AI Agents

AI agents **must**:

1. **When deploying or updating this template, follow `instructions/update.instructions.md` and
   update the Last sync date above.**

2. **Read `instructions/agent-workflow.instructions.md` FIRST to determine which other instruction
   files apply to your task.** Follow all applicable instructions before proceeding with work.

3. **Check `aim.config.json`** for module configuration, external source, and skill dependency settings.

## Instruction Applicability Matrix

Use this matrix to determine which instruction files to read based on your task:

| Task Type                    | Required Instructions                  |
| ---------------------------- | -------------------------------------- |
| Any task                     | `agent-workflow.instructions.md`       |
| Any code or documentation    | `shorthand.instructions.md`            |
| Git operations               | `git-workflow.instructions.md`         |
| Writing tests                | `testing.instructions.md`              |
| PowerShell code              | `powershell.instructions.md`           |
| Documentation                | `markdown.instructions.md`             |
| README files                 | `readme.instructions.md`               |
| GitHub CLI usage             | `github-cli.instructions.md`           |
| Creating releases            | `releases.instructions.md`             |
| Repository-specific work     | `repository-specific.instructions.md`  |
| Updating instructions        | `update.instructions.md`               |
| Contributing to upstream     | `contributing.instructions.md`         |

## Available Instruction Files

- `agent-workflow.instructions.md` - Pre-flight protocol and task workflow
- `shorthand.instructions.md` - Avoid shorthand and abbreviations
- `git-workflow.instructions.md` - Git branching, commits, and PR conventions
- `testing.instructions.md` - Test writing best practices
- `powershell.instructions.md` - PowerShell coding standards
- `markdown.instructions.md` - Markdown formatting standards
- `readme.instructions.md` - README maintenance guidelines
- `github-cli.instructions.md` - GitHub CLI usage guidelines
- `releases.instructions.md` - Release management guidelines
- `repository-specific.instructions.md` - Repository-specific customizations
- `update.instructions.md` - Procedures for updating instructions
- `contributing.instructions.md` - Contributing improvements to upstream

## Quick Reference

### Before Starting Any Task

1. Identify the task type from the matrix above
2. Read all applicable instruction files
3. Follow the guidelines when implementing

### Best Practices

- Follow existing patterns in the codebase
- Keep solutions simple and focused
- Only make changes that are directly requested
- Follow language-specific guidelines

## Repository-Specific Instructions

See `instructions/repository-specific.instructions.md` for customizations specific to this repository.

## Skill Dependencies

A repository can vendor Agent Skills (the open [Agent Skills](https://agentskills.io) `SKILL.md`
standard) it depends on, declared in `aim.config.json` under `skills`. Unlike a per-developer
install, the skills are checked in under `skills.vendorPath` (default `.agents/skills/`) - the
cross-client convention - so they travel with the repository and any agent can use them. When a
skill is vendored, a row is added to the Instruction Applicability Matrix above mapping its task
type to `<vendorPath>/<name>/SKILL.md`, routing it alongside the instruction files; agents that
natively scan `.agents/skills/` also pick it up directly. Because Claude Code reads `CLAUDE.md`
rather than `AGENTS.md`, a `CLAUDE.md` that imports
this file (`@AGENTS.md`) carries the routing into Claude Code. When a skill covers a task (for
example build and test tooling), prefer its guidance over ad-hoc commands. See
`instructions/update.instructions.md` for how skills are vendored and routed during sync.
