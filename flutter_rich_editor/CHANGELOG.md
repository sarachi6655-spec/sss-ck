# Changelog

## 0.1.0 - Initial Release

- Core tree-based document model (`DocumentValue`, `EditorNode`, `EditorSelection`).
- Type-safe `CommandBus` with undo/redo transactions and history management.
- `PluginRegistry` with duplicate detection and deterministic ordered disposal.
- `RichEditorController` supporting canonical JSON, semantic HTML, Markdown, and Delta imports/exports.
- `EditorTheme` with 50+ configurable visual design tokens for dynamic colors and typography.
- Formatting plugin (bold, italic, underline, strikethrough, code, subscript, superscript, clear formatting).
- Structure plugin (headings 1–6, blockquotes, horizontal rule, bullet, numbered, and todo lists with indent/outdent).
- Media module (images, native video player, links, external media embed security policy, tables with rows/cols/merged cells/resize).
- Code blocks with syntax highlighting and editable fallback, plus sanitized Mermaid diagram renderer.
- Paste handler with HTML sanitization, Word/Google Docs cleanup, and undoable insertions.
- Basic collaboration hooks: reviewer/read-only mode, comments, track changes suggestion accept/reject commands.
- Optional provider contracts for AI assistant, real-time collaboration transport, PDF export, and DOCX import.
- Built-in `WatchdogBoundary` ensuring error recovery without data loss.
- Interactive `EditorToolbar` with customizable groups, ordering, and responsive styling.
