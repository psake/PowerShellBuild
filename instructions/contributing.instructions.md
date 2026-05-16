---
applyTo: '**/*'
description: 'Guidelines for contributing improvements back to the upstream AIM repository'
---

# Contributing Instructions for AI Agents

When users want to improve, fix, or extend the AI agent instructions, this guide helps agents
facilitate contributions back to the upstream AIM repository.

## When to Contribute Upstream vs. Modify Locally

### Contribute Upstream (Submit a PR)

- Fixing errors or typos in instruction files
- Clarifying confusing or ambiguous instructions
- Adding missing best practices that benefit all users
- Creating new instruction modules for languages, frameworks, or tools
- Improving examples or adding helpful code snippets

### Modify Locally Only

- Organization-specific conventions or standards
- Project-specific customizations
- Internal tooling or proprietary workflows
- Content that references internal systems or URLs

**Local changes belong in `repository-specific.instructions.md`** - this file is never synced from upstream.

## Agent-Assisted Contribution Workflow

When a user wants to contribute to upstream, guide them through these steps:

### 1. Fork the Repository

```bash
gh repo fork tablackburn/ai-agent-instruction-modules --clone
cd ai-agent-instruction-modules
```

### 2. Create a Feature Branch

```bash
git checkout -b feature/descriptive-branch-name
```

Use descriptive branch names:

- `feature/add-python-module` - New module
- `fix/powershell-typo` - Bug fix
- `docs/clarify-update-procedure` - Documentation improvement

### 3. Make Changes

Follow existing patterns in the repository:

**For new instruction files:**

- Place in `instructions/` folder
- Use `.instructions.md` extension
- Include required YAML frontmatter

**For existing files:**

- Preserve the file's structure and style
- Make minimal, focused changes
- Don't introduce unrelated modifications

### 4. Validate Changes

```powershell
Invoke-Pester -Path .\tests\
```

Ensure all tests pass before committing.

### 5. Commit with Conventional Commits

```bash
git commit -m "feat: Add Python type hints module"
```

Prefixes:

- `feat:` - New feature or module
- `fix:` - Bug fix or correction
- `docs:` - Documentation only
- `refactor:` - Code restructuring without behavior change

### 6. Push and Create Pull Request

```bash
git push origin feature/descriptive-branch-name
gh pr create --title "feat: Add Python type hints module" --body "Description of changes"
```

## Module Requirements

All instruction files must include YAML frontmatter:

```yaml
---
applyTo: '**/*.py'
description: 'Brief description of what this module covers'
---
```

**Frontmatter fields:**

- `applyTo` - Glob pattern for applicable files (e.g., `'**/*'`, `'**/*.py'`, `'**/README.md'`)
- `description` - One-line description of the module's purpose

**Content guidelines:**

- Keep instructions generic and universally applicable
- Use placeholder examples (`<owner>`, `<repo>`, `example.com`)
- Avoid organization-specific references
- Include practical code examples where helpful
- Follow markdown conventions from `markdown.instructions.md`

## Pull Request Guidelines

**Title:** Use conventional commit format (e.g., `feat: Add Python module`)

**Description should include:**

- Summary of changes (1-3 bullet points)
- Motivation or problem being solved
- Any breaking changes or migration notes

**Example PR body:**

```markdown
## Summary

- Add Python type hints and docstring guidelines
- Include examples for common patterns
- Reference PEP 484 and PEP 257 standards

## Motivation

Python developers need consistent guidance on type annotations and documentation strings.
```

## After Submission

- Respond to review feedback promptly
- Make requested changes in additional commits
- Once merged, downstream repositories can sync using `update.instructions.md`

## Questions or Discussion

For questions about contributing, open an issue on the upstream repository:

```bash
gh issue create --repo tablackburn/ai-agent-instruction-modules --title "Question: Your topic" --body "Your question here"
```
