# Flutter Rich Editor (`flutter_rich_editor` / `sss_rich_editor`)

A high-performance, fully configurable rich text editor for Flutter with complete CKEditor 5 feature parity, dynamic color theming, and an extensible plugin architecture.

---

## Features

- **CKEditor 5 Feature Parity**:
  - **Formatting**: Bold, italic, underline, strikethrough, inline code, subscript, superscript, colors, background highlights, clear formatting.
  - **Structure**: Headings (H1–H6), blockquotes, horizontal rules, bullet lists, numbered lists, to-do lists with checkbox interaction, list indent & outdent.
  - **Media & Tables**: Resizable images, native video playback and upload progress, external media embeds (with strict host security policy), links, and full tables with rows, columns, merged cells, and column resizing.
  - **Code & Diagrams**: Code blocks with syntax highlighting and editable fallback, plus sanitized Mermaid diagram rendering.
  - **Interoperability & Serialization**: Lossless canonical JSON tree codec, semantic HTML import/export with comment preservation, GitHub Flavored Markdown import/export, and Quill Delta migration support.
  - **Security & Paste**: Sanitized HTML paste with Word/Google Docs cleanup and undoable insertions.
  - **Collaboration & Reviewer Mode**: Comments, reviewer-restricted editing, track changes suggestions (accept/reject), and conflict-free collaboration transport contracts.
  - **Dynamic Theming**: 50+ theme tokens controlling every visual surface, border, background, typography, icon, and state without hardcoded colors.
  - **Enterprise Reliability**: Built-in `WatchdogBoundary` ensuring error recovery without data loss.

---

## Getting Started

Add the private package as a path dependency in your Flutter app's `pubspec.yaml`:

```yaml
dependencies:
  flutter_rich_editor:
    path: flutter_rich_editor
```

### Basic Usage

```dart
import 'package:flutter/material.dart';
import 'package:flutter_rich_editor/flutter_rich_editor.dart';

class MyEditorPage extends StatefulWidget {
  const MyEditorPage({super.key});

  @override
  State<MyEditorPage> createState() => _MyEditorPageState();
}

class _MyEditorPageState extends State<MyEditorPage> {
  late final RichEditorController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RichEditorController(
      initialDocument: DocumentValue(
        nodes: [
          EditorNode.heading(id: 'h1', text: 'Welcome to the Editor', level: 1),
          EditorNode.paragraph(id: 'p1', text: 'Start writing your rich document here...'),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rich Editor')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: RichEditor(
          controller: _controller,
          theme: EditorTheme.light(),
        ),
      ),
    );
  }
}
```

---

## Dynamic Theming

Every color, font, spacing, and radius is completely customizable:

```dart
RichEditor(
  controller: _controller,
  theme: EditorTheme(
    backgroundColor: const Color(0xFF1E1E2E),
    textColor: const Color(0xFFCDD6F4),
    cursorColor: const Color(0xFFF5C2E7),
    selectionColor: const Color(0x4089B4FA),
    toolbarBackgroundColor: const Color(0xFF313244),
    toolbarBorderColor: const Color(0xFF45475A),
    toolbarItemColor: const Color(0xFFBAC2DE),
    toolbarItemActiveColor: const Color(0xFF89B4FA),
    toolbarItemActiveBackgroundColor: const Color(0xFF45475A),
    codeBlockBackgroundColor: const Color(0xFF181825),
    tableBorderColor: const Color(0xFF45475A),
    tableHeaderBackgroundColor: const Color(0xFF313244),
    blockquoteBorderColor: const Color(0xFF6C7086),
    blockquoteBackgroundColor: const Color(0xFF181825),
  ),
);
```

---

## HTML & Markdown Import / Export

```dart
// Export to HTML
final String html = _controller.toHtml();

// Load from HTML
_controller.loadHtml('<h1>Report</h1><p>Sample <strong>bold</strong> text.</p>');

// Export to Markdown
final String markdown = _controller.toMarkdown();

// Load from Markdown
_controller.loadMarkdown('# Title\n\n- [ ] Task 1\n- [x] Task 2');
```

---

## Migration from Flutter Quill

Migrating from `flutter_quill` is straightforward using the built-in `DeltaDocumentCodec`:

```dart
import 'package:flutter_rich_editor/flutter_rich_editor.dart';

final List<dynamic> quillDeltaOps = [
  {'insert': 'Hello '},
  {'insert': 'World', 'attributes': {'bold': true}},
  {'insert': '\n'},
];

// Decode Delta to DocumentValue
final DocumentValue doc = const DeltaDocumentCodec().decode(quillDeltaOps);
_controller.import(doc);
```
