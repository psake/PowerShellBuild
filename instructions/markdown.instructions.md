---
applyTo: '**/*.md'
description: 'Markdown formatting standards'
---

# Markdown Style Guidelines

Consistent Markdown formatting for documentation files.

## Blank Lines

- Use single blank lines between sections and elements
- Never use multiple consecutive blank lines
- Headings, lists, and code blocks must have a blank line above and below

## Headings

- Use ATX style (`#`) not setext (underlines)
- Use consistent heading levels (don't skip levels)
- Start with a single H1 (`#`) for the document title
- Use sentence case for headings
- Include a space after `#` characters
- No trailing punctuation (colons, periods, etc.)
- Avoid duplicate heading text within the same document

## Lists

- Use `-` for unordered lists
- Use sequential numbering for ordered lists (`1.`, `2.`, `3.`, etc.)
- Use 2 spaces for nested list indentation

```markdown
Text before list.

- First item
- Second item
  - Nested item
  - Another nested item
- Third item

Text after list.
```

## Code Blocks

- Use backticks (`` ` ``) not tildes (`~`) for code fences
- Always specify language for fenced code blocks
- Ensure closing triple backticks are on their own line
- No trailing whitespace after closing backticks
- Code inside fenced blocks should follow the conventions of the relevant language's instruction
  file (e.g., PowerShell snippets follow `powershell.instructions.md`)

```javascript
// JavaScript code here
```

```python
# Python code here
```

```bash
# Shell code here
```

## Inline Formatting

- Use `**bold**` for strong emphasis
- Use `*italic*` for light emphasis
- Use backticks for `code`, `filenames`, and `commands`
- Use backticks for keyboard shortcuts like `Ctrl+C`
- No spaces inside emphasis markers (`**text**` not `** text **`)
- No spaces inside backticks (`` `code` `` not `` ` code ` ``)
- Don't use bold/emphasis as a substitute for headings

## Links

- Use descriptive link text (not "click here")
- Use reference-style links for long URLs
- Use reference-style links when the same URL appears multiple times
- Links must have valid destinations (no empty hrefs)

```markdown
See the [official documentation][docs] for more details.
The [documentation][docs] covers advanced topics.

[docs]: https://example.com/documentation
```

## Images

- Always include alt text for accessibility
- Use descriptive alt text that conveys the image content

```markdown
![Diagram showing data flow between components](./images/data-flow.png)
```

## Line Length

- Wrap prose at 80-100 characters when practical
- Don't wrap tables - maintain table formatting
- Don't wrap URLs or code blocks

## File Structure

- End all files with exactly one newline character
- No trailing whitespace on any lines
- Use spaces, not hard tabs
- Use UTF-8 encoding
- Avoid inline HTML when markdown alternatives exist

## Tables

- Align columns for readability in source
- Use header row separators
- Keep tables simple when possible

```markdown
| Column 1 | Column 2 | Column 3 |
|----------|----------|----------|
| Value 1  | Value 2  | Value 3  |
| Value 4  | Value 5  | Value 6  |
```
