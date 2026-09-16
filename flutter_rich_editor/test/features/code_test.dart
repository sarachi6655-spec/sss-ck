import 'package:flutter/material.dart';
import 'package:flutter_rich_editor/flutter_rich_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Code Block and Mermaid Tests', () {
    test('test_codeBlock_highlightsConfiguredLanguageAndFallsBackToEditableText', () {
      const DefaultSyntaxHighlighter highlighter = DefaultSyntaxHighlighter();

      // Supported language (Dart) returns styled TextSpan
      final TextSpan? dartSpan = highlighter.highlight('void main() {}', 'dart');
      expect(dartSpan, isNotNull);
      expect(dartSpan!.text, isNull); // root contains children
      expect(dartSpan.children, isNotEmpty);

      // Unsupported language falls back to null (plain editable text)
      final TextSpan? unsupportedSpan = highlighter.highlight('xyz content', 'unknown_lang_xyz');
      expect(unsupportedSpan, isNull);
    });

    test('test_mermaidRenderer_rejectsUnsafeInput', () {
      const MermaidSanitizer sanitizer = MermaidSanitizer();

      const String safeMermaid = 'graph TD;\nA-->B;\nA-->C;\nB-->D;\nC-->D;';
      expect(sanitizer.isSafe(safeMermaid), true);

      const String unsafeScript = 'graph TD;\nA-->B;\n<script>alert("hack")</script>';
      expect(sanitizer.isSafe(unsafeScript), false);

      const InsertMermaidCommand unsafeCmd = InsertMermaidCommand(
        diagramSource: unsafeScript,
        sanitizer: sanitizer,
      );
      final CommandResult result = unsafeCmd.execute(DocumentValue.empty());
      expect(result.success, false);
      expect(result.errorCode, 'mermaid.unsafe_input');
    });
  });
}
