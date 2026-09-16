# Flutter Rich Editor (`flutter_rich_editor`)

A production-ready, highly configurable WYSIWYG rich text editor for Flutter with complete **CKEditor 5** feature parity on Web, native fallback for mobile/desktop, dynamic color theming, and an extensible architecture.

---

## Key Features

- **⚡ 100% Automatic Table Formulas**:
  - Live calculations on keystroke: `=SUM(A1:A2)`, `=AVG(A1:A5)`, `=MIN(...)`, `=MAX(...)`, `=COUNT(...)`, `=A1*B1`, `=SUM(ABOVE)`.
  - Automatic chained formula recalculation across dependent cells.
  - Interactive formula documentation modal with formula helper syntax.
- **🎨 Advanced Table Styling & Colorizer**:
  - Color target selection: Individual Cell, Entire Column, Entire Row, Header Row, Zebra Stripes, or Entire Table.
  - Soft pastels & corporate color presets + custom HEX background & text color picker.
  - Table manipulation: insert/delete rows/columns, resize columns, merge/split cells.
- **🎬 Media Embed & Video Resizing**:
  - Direct video attachments: YouTube, Vimeo, MP4 URLs, and uploads.
  - On-click floating video toolbar: 25%, 50%, 75%, 100% width presets + smooth slider + alignment controls (Left, Center, Right).
- **🔤 Comprehensive Typography & Fonts**:
  - Extended font family dropdown: Calibri, Aptos, Segoe UI, Arial, Georgia, Roboto, Times New Roman, Courier New, etc.
  - Custom font sizes (9px – 36px), text colors, background highlights, and line spacing.
- **🧹 Paste Normalization ("Harmonize")**:
  - Seamlessly cleanses pasted content from Word, Excel, and Google Docs.
  - One-click "Harmonize" normalizes mismatched font families, font sizes, and external table borders to match your document's primary style.
- **📱 Responsive & Mobile-Friendly**:
  - Overflow-protected action bar with horizontal touch-scrolling.
  - Mobile & tablet optimized dropdowns and modals.
- **📄 Document Exporting & Utilities**:
  - One-click PDF export, Word (.docx) export, and Print preview.
  - Fullscreen editor mode and HTML source code viewer.
- **Dynamic Theming**:
  - 50+ theme tokens controlling every visual surface, background, and toolbar state.

---

## Installation

### Method 1: Git Dependency (Recommended)
Add to your project's `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_rich_editor:
    git:
      url: https://github.com/sarachi6655-spec/sss-ck.git
      path: flutter_rich_editor
      ref: main
```

### Method 2: Local Path Dependency (Fastest for local development)
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_rich_editor:
    path: ../sss-ck/flutter_rich_editor # Adjust relative or absolute path
```

Then run:
```bash
flutter pub get
```

---

## Quick Start (3 Minutes)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_rich_editor/flutter_rich_editor.dart';

class MyEditorScreen extends StatefulWidget {
  const MyEditorScreen({super.key});

  @override
  State<MyEditorScreen> createState() => _MyEditorScreenState();
}

class _MyEditorScreenState extends State<MyEditorScreen> {
  late final RichEditorController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RichEditorController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _saveDocument() {
    final String htmlContent = _controller.toHtml();
    final String markdownContent = _controller.toMarkdown();
    print('HTML Output: $htmlContent');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Rich Document'),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _saveDocument),
        ],
      ),
      body: SafeArea(
        child: RichEditor(
          controller: _controller,
          config: const EditorConfig(
            placeholder: 'Start typing here...',
          ),
        ),
      ),
    );
  }
}
```

---

## Controller API Reference

### Exporting Content
```dart
// Semantic HTML (CKEditor 5 compliant)
final String html = _controller.toHtml();

// GitHub Flavored Markdown
final String markdown = _controller.toMarkdown();

// Lossless canonical JSON tree
final String jsonTree = _controller.toJson();
```

### Importing / Setting Content
```dart
// Load from HTML
_controller.loadHtml('<h2>Title</h2><p>Hello <strong>World</strong>!</p>');

// Load from Markdown
_controller.loadMarkdown('# Title\n\nSample content with **bold** text.');

// Clear content
_controller.clear();
```

### Listening to Changes
```dart
_controller.addListener(() {
  // Triggered whenever the user edits text, modifies a table, or changes styling
  print('Document updated');
});
```

---

## Dynamic Theming

You can customize all editor visual tokens:

```dart
RichEditor(
  controller: _controller,
  theme: EditorTheme(
    backgroundColor: const Color(0xFFF8FAFC),
    textColor: const Color(0xFF0F172A),
    toolbarBackgroundColor: const Color(0xFFFFFFFF),
    toolbarBorderColor: const Color(0xFFE2E8F0),
    toolbarItemColor: const Color(0xFF334155),
    toolbarItemActiveColor: const Color(0xFF2563EB),
    cursorColor: const Color(0xFF2563EB),
  ),
);
```

---

## Platform Support

| Platform | Engine | Capabilities |
|---|---|---|
| **Web** | CKEditor 5 | Complete feature parity (table formulas, video resize, table colorizer, Calibri fonts, export) |
| **Android / iOS** | Native Flutter Canvas | Core formatting, headers, lists, code blocks |
| **macOS / Windows / Linux** | Native Flutter Canvas | Core formatting, headers, lists, code blocks |
