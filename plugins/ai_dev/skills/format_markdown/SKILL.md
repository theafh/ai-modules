---
name: format_markdown
description: Apply markdown linting compliance and best practices when creating or editing markdown files (.md, .mdc). Covers blank-line rules around block elements, consistent bullet style, fenced code blocks with language identifiers, table alignment syntax, header level progression, list indentation and spacing, and link/image conventions.
version: 2.0.0
author: Andreas F. Hoffmann
license: MIT
---

# format_markdown

## Linting Compliance

- **Blank lines**: One around headings, lists, tables, code blocks
- **Single newline**: File must end with exactly one newline
- **No multiple blanks**: Maximum one consecutive blank line
- **Consistent bullets**: Use `-` for all unordered lists
- **Fenced code**: Always use language identifier
- **Table alignment**: Use `:---:` for center, `:---` for left, `---:` for right
- **Header levels**: Don't skip levels (H1 → H2 → H3, not H1 → H3)
- **List indentation**: 2 spaces for nested items
- **List marker spacing**: Use 1 space after list markers
- **No bare URLs**: Wrap in angle brackets or use reference links
- **No trailing punctuation**: In headers

## Best Practices

- **Descriptive links**: Meaningful text, not "click here"
- **Alt text**: Always for images
- **Consistent emphasis**: `**bold**` and `*italic*` only
- **Table headers**: Always include
