---
applyTo: '**/*'
description: 'Mandatory pre-flight protocol for AI agents'
---

# Agent Workflow Instructions

## Purpose

This file defines the recommended workflow that AI agents should follow when working in
repositories using AIM. It ensures agents understand the context and guidelines before
starting work.

## Pre-Flight Protocol

**Before starting any task, AI agents should:**

### 1. Identify Task Type

Analyze the user's request and identify all areas it touches. Common patterns:

- Code development (specific languages or frameworks)
- Documentation (Markdown files, README files)
- Git operations (commits, branches, PRs)
- Testing and quality assurance
- Security considerations
- Repository-specific customizations

### 2. Consider Applicable Instructions

Review the instruction files listed in the repository's `AGENTS.md` to understand:

- Language-specific coding standards
- Framework conventions
- Documentation requirements
- Git workflow expectations
- Security best practices

### 3. Implement with Compliance

Execute your task following the guidelines from the applicable instruction sections.

## Best Practices

### Read Before Writing

- Always read existing code before modifying it
- Understand the project's patterns and conventions
- Check for existing implementations before creating new ones

### Confirm Understanding

When starting complex tasks, briefly confirm your understanding:

> "Based on the instructions, I'll follow [specific guidelines]. Here's my approach..."

This builds trust and catches misunderstandings early.

### Avoid Over-Engineering

- Only make changes that are directly requested
- Keep solutions simple and focused
- Don't add features, refactoring, or improvements beyond what was asked

### Security First

- Never introduce security vulnerabilities
- Be careful with user input validation
- Avoid hardcoding secrets or credentials
- Follow the security guidelines in this document

## When in Doubt

1. **Ask for clarification** - Better to ask than implement incorrectly
2. **Check existing code** - Follow established patterns in the codebase
3. **Keep it simple** - The simplest solution that works is usually best

## Post-Task Protocol

### Before Committing

1. **Run tests** - Ensure all tests pass before committing
2. **Check repository-specific requirements** - Review `repository-specific.instructions.md` for
   any post-task requirements such as:
   - Release processes (version bumps, changelogs, tags)
   - Commit message conventions beyond standard guidelines
   - Required reviewers or approval workflows
   - Documentation updates

Following repository-specific requirements ensures consistency with the project's established
workflows and prevents incomplete changes from being committed.

## Custom Instructions

If this repository has a custom instructions section, those guidelines take precedence for
repository-specific conventions and may override or supplement the general instructions above.
