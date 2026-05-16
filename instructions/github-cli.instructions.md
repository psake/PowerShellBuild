---
applyTo: '**/*'
description: 'GitHub CLI usage guidelines and best practices (operational instructions for running gh commands, not file-specific)'
---

# GitHub CLI Guidelines

Instructions for using GitHub CLI (`gh`) for repository operations.

## Authentication

Verify authentication before performing operations:

```bash
# Check current authentication status
gh auth status

# If not authenticated
gh auth login
```

## Repository Operations

### Repository Discovery

```bash
# List repositories in an organization
gh repo list <org> --limit 100

# Get repository default branch (don't assume main)
gh api repos/<owner>/<repo> --jq '.default_branch'

# View repository details
gh repo view <owner>/<repo>
```

### Cloning and Forking

```bash
# Clone a repository
gh repo clone <owner>/<repo>

# Fork a repository
gh repo fork <owner>/<repo> --clone
```

## Issue Management

### Creating Issues

```bash
# Create a new issue
gh issue create --title "Issue Title" --body "Issue description"

# Create with labels and assignee
gh issue create --title "Bug: Login fails" --body "Description" --label "bug" --assignee "@me"

# Create interactively
gh issue create
```

### Viewing and Searching Issues

```bash
# List open issues
gh issue list

# View specific issue
gh issue view <number>

# Search issues
gh issue list --search "bug in:title"
```

### Issue Labels

Common labels to use:

- `bug` - Something isn't working
- `enhancement` - New feature or request
- `documentation` - Documentation improvements
- `question` - Further information requested
- `good first issue` - Good for newcomers

## Pull Request Workflows

### Creating Pull Requests

```bash
# Create PR from current branch
gh pr create --title "PR Title" --body "Description"

# Create draft PR
gh pr create --title "WIP: Feature" --body "Work in progress" --draft

# Create PR with specific base branch
gh pr create --base develop --title "Feature" --body "Description"
```

### PR Review

```bash
# List PRs awaiting review
gh pr list --search "review-requested:@me"

# View PR details
gh pr view <number>

# Checkout PR locally
gh pr checkout <number>

# Approve PR
gh pr review <number> --approve

# Request changes
gh pr review <number> --request-changes --body "Please fix..."
```

### Merging PRs

```bash
# Merge PR
gh pr merge <number>

# Merge with squash
gh pr merge <number> --squash

# Merge with rebase
gh pr merge <number> --rebase

# Delete branch after merge
gh pr merge <number> --delete-branch
```

## GitHub Actions

### Workflow Management

```bash
# List workflow runs
gh run list

# View specific run
gh run view <run-id>

# Watch a running workflow
gh run watch <run-id>

# Re-run failed jobs
gh run rerun <run-id> --failed
```

### Viewing Logs

```bash
# View run logs
gh run view <run-id> --log

# View failed step logs
gh run view <run-id> --log-failed
```

## Releases

### Creating Releases

```bash
# Create release from tag
gh release create v1.0.0 --title "Version 1.0.0" --notes "Release notes"

# Create release with auto-generated notes
gh release create v1.0.0 --generate-notes

# Create draft release
gh release create v1.0.0 --draft --title "Version 1.0.0"

# Upload assets
gh release create v1.0.0 ./dist/*.zip --title "Version 1.0.0"
```

### Viewing Releases

```bash
# List releases
gh release list

# View latest release
gh release view --latest
```

## API Access

### Direct API Calls

```bash
# GET request
gh api repos/<owner>/<repo>

# POST request
gh api repos/<owner>/<repo>/issues --method POST -f title="Title" -f body="Body"

# Use jq for filtering
gh api repos/<owner>/<repo>/pulls --jq '.[].title'
```

## Best Practices

### Pre-Operation Validation

```bash
# Verify you're in a git repository
gh repo view --json nameWithOwner --jq '.nameWithOwner'

# Verify authentication
gh auth status
```

### Issue-to-Branch Workflow

```bash
# Create issue and capture the issue number
ISSUE_NUM=$(gh issue create --title "Feature: New functionality" --body "Description" --json number --jq '.number')

# Create feature branch using the captured issue number
git checkout -b "feature/issue-${ISSUE_NUM}-new-functionality"

# Push and create PR
git push -u origin "feature/issue-${ISSUE_NUM}-new-functionality"
gh pr create --title "Feature: New functionality" --body "Closes #${ISSUE_NUM}"
```

### Common Flags

- `--json` - Output as JSON
- `--jq` - Filter JSON output
- `--web` - Open in browser
- `--help` - Show help for any command

## Environment Variables

Useful environment variables:

- `GH_TOKEN` - Authentication token
- `GH_HOST` - GitHub hostname (for enterprise)
- `GH_REPO` - Default repository
- `GH_EDITOR` - Editor for composing text
