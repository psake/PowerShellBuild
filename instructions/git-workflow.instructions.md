---
applyTo: '**/*'
description: 'Git workflow conventions including branching, commits, and pull requests'
---

# Git Workflow Instructions

Guidelines for consistent Git usage across repositories.

## Working on Branches

**Agents must always work on branches, never directly on main.**

Before starting any work:

1. Create a branch from `main` using the naming conventions below
2. Make changes in small, logical commits
3. Push the branch and create a pull request
4. Wait for CI checks and address any review feedback
5. Report status and wait for instructions before merging

This ensures all changes go through review and CI validation before reaching the main branch.

## Branch Naming

Use descriptive, lowercase branch names with hyphens.

### Basic Format

```text
<type>/<short-description>
```

### Format with Ticket Numbers

When using project management tools, include the ticket identifier:

```text
<type>/<ticket-id>-<short-description>
```

### Branch Types

| Prefix      | Purpose                              | Example                              |
| ----------- | ------------------------------------ | ------------------------------------ |
| `feature/`  | New functionality                    | `feature/user-authentication`        |
| `bugfix/`   | Bug fixes                            | `bugfix/login-validation-error`      |
| `hotfix/`   | Urgent production patches            | `hotfix/security-vulnerability`      |
| `release/`  | Release preparation                  | `release/v1.2.0`                     |
| `docs/`     | Documentation only                   | `docs/api-documentation`             |
| `refactor/` | Code restructuring                   | `refactor/database-queries`          |
| `test/`     | Adding or updating tests             | `test/payment-integration`           |
| `chore/`    | Maintenance tasks                    | `chore/update-dependencies`          |

### Examples with Ticket Numbers

```text
feature/PROJ-123-add-user-authentication
bugfix/PROJ-456-fix-login-validation
hotfix/PROJ-789-patch-security-issue
```

### Best Practices

- **Be descriptive**: Names should reflect the branch's purpose or task
- **Be concise**: Keep names brief but meaningful
- **Be consistent**: Follow the same conventions across the team
- **Use lowercase**: Avoid mixed case for cross-platform compatibility
- **Use hyphens**: Separate words with hyphens, not underscores or spaces

### Technical Constraints

Avoid the following in branch names:

- Dots at the start of the name
- Trailing slashes
- Reserved Git names (`HEAD`, `FETCH_HEAD`)
- Spaces or special characters (except hyphens and forward slashes)

### Avoid

- Overly long names
- Generic names like `fix`, `update`, `changes`
- Names without context or purpose

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/) format:

```text
<type>: <description>

[optional body]

[optional footer]
```

**Types:**

- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `style:` - Formatting (no code change)
- `refactor:` - Code restructuring
- `test:` - Adding/updating tests
- `chore:` - Maintenance tasks

**Guidelines:**

- Use imperative mood ("Add feature" not "Added feature")
- Keep first line under 72 characters
- Capitalize first letter after type
- No period at end of subject line
- Separate subject from body with blank line

**Good examples:**

```text
feat: Add user authentication flow
fix: Resolve null reference in payment processing
docs: Update API endpoint documentation
refactor: Extract validation logic to separate module
```

**Avoid:**

```text
Fixed stuff
WIP
updates
asdfasdf
```

## Pull Request Guidelines

### Before Creating a PR

1. Ensure your branch is up to date with the base branch
2. Run tests locally and verify they pass
3. Review your own changes first
4. Remove debugging code and console logs

### PR Title

Use the same format as commit messages:

```text
feat: Add user authentication flow
```

### PR Description

Include:

- **Summary** - What changed and why (1-3 bullet points)
- **Test plan** - How to verify the changes work
- **Breaking changes** - Note any breaking changes

**Template:**

```markdown
## Summary

- Added user login and logout functionality
- Integrated with OAuth2 provider
- Added session management

## Test Plan

- [ ] Login with valid credentials succeeds
- [ ] Login with invalid credentials shows error
- [ ] Logout clears session

## Breaking Changes

None
```

### PR Size

- Keep PRs focused and small when possible
- Large changes should be split into logical commits
- If a PR is too large, consider breaking it into smaller PRs

### After Creating a PR

1. **Monitor CI**: Wait for CI checks to complete and verify they pass
2. **Check for comments**: Review the PR for any feedback or requested changes
3. **Address feedback**: Make additional commits to address review comments
4. **Report status**: Report the PR status to the user and wait for instructions before merging

## Branching Strategy

### Default Branch

- Use `main` as the default branch name for new repositories
- `main` is the industry standard and preferred for inclusive terminology
- When working with existing repositories using `master`, follow the repository's convention
- Consider migrating legacy repositories from `master` to `main` when practical

### Main Branch

- `main` is the production-ready branch
- Should always be in a deployable state
- Direct commits to main should be avoided

### Feature Branches

1. Create feature branch from `main`
2. Make changes in small, logical commits
3. Push branch and create PR
4. After review and approval, merge to `main`
5. Delete feature branch after merge

### Keeping Branches Updated

```bash
# Update your feature branch with latest main
git fetch origin
git rebase origin/main
```

Prefer rebase for feature branches to maintain clean history.

## Merge Strategy

### Squash and Merge (Recommended for feature branches)

- Combines all commits into one clean commit
- Keeps main branch history clean
- Use when feature branch has many small/WIP commits

### Merge Commit

- Preserves full commit history
- Use for significant features where history is valuable
- Use for release branches

### Rebase and Merge

- Applies commits linearly without merge commit
- Use when commits are already clean and logical

## Git Safety

### Before Force Pushing

- Never force push to `main` or shared branches
- Only force push to your own feature branches
- Always communicate with team before force pushing shared branches

### Avoiding Common Issues

- Pull before pushing to avoid conflicts
- Don't commit sensitive data (secrets, credentials, API keys)
- Use `.gitignore` for build artifacts and dependencies
- Review staged changes before committing

## Useful Commands

```bash
# View branch status
git status

# View commit history
git log --oneline -10

# Amend last commit (before pushing)
git commit --amend

# Stash changes temporarily
git stash
git stash pop

# Undo last commit (keep changes)
git reset --soft HEAD~1

# View changes before committing
git diff --staged
```
