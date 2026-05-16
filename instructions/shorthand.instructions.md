---
applyTo: '**/*'
description: 'Guidelines for avoiding shorthand and abbreviations in all code and documentation.'
---

# Shorthand Guidelines

## Avoid Shorthand and Abbreviations

To maximize clarity, maintainability, and consistency across all code and documentation, always
use full, descriptive words instead of shorthand or abbreviations.

- **Do not use**: `Params`, `Props`, `Config`, `Info`, `Temp`, `Env`, `Obj`, `Val`, `Ref`,
  `Err`, `Msg`, etc.
- **Do use**: `Parameters`, `Properties`, `Configuration`, `Information`, `Temporary`,
  `Environment`, `Object`, `Value`, `Reference`, `Error`, `Message`, etc.

### Rationale

- Shorthand and abbreviations can be ambiguous and reduce code readability.
- Full words make intent clear for all contributors and AI agents.
- Consistent naming improves searchability and onboarding for new team members.

### Examples

| Avoid  | Prefer                       |
| ------ | ---------------------------- |
| Params | Parameters                   |
| Props  | Properties                   |
| Config | Configuration                |
| Info   | Information                  |
| Temp   | Temporary                    |
| Env    | Environment                  |
| Obj    | Object                       |
| Val    | Value                        |
| Ref    | Reference                    |
| Err    | Error                        |
| Msg    | Message                      |
| Conn   | Connection / Connections     |
| Cmd    | Command                      |
| Svc    | Service                      |
| Cfg    | Configuration                |
| Tmp    | Temporary                    |
| Usr    | User                         |
| Grp    | Group                        |
| Ctx    | Context                      |
| Auth   | Authentication / Authorize   |
| Util   | Utility / Utilities          |
| Init   | Initialize / Initialization  |
| Req    | Request / Requirement        |
| Resp   | Response                     |
| ObjRef | Object Reference             |
| Num    | Number                       |

### Additional Guidance

- Never use abbreviations in parameter, property, or variable names unless they are
  industry-standard and unambiguous (e.g., `ID`, `URL`).
- Use the singular or plural form of a word as appropriate for the context (e.g., use
  `Connection` for a single item, `Connections` for collections or lists).
- If a project already uses a specific abbreviation as a standard, document it clearly in the
  relevant instruction file.
- If new abbreviations are introduced in the future, document them here and avoid their use
  unless absolutely necessary and unambiguous.
- This rule applies to all code, documentation, commit messages, and user-facing text.
