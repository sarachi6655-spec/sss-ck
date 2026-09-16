import 'package:flutter_rich_editor/flutter_rich_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Paste Handler Tests', () {
    test('test_pasteHandler_sanitizesUnsafeHtmlAndCreatesUndoableInsertion', () {
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(id: 'p0', text: 'Original line'),
        ],
      );

      const String dirtyHtml = '<p onclick="steal()">Clean Text <script>alert(1)</script><iframe src="evil.com"></iframe></p>';

      const PasteContentCommand pasteCmd = PasteContentCommand(
        rawContent: dirtyHtml,
        isHtml: true,
      );

      final CommandResult result = pasteCmd.execute(doc);
      expect(result.success, true);

      // Verify dangerous tags/attributes are sanitized
      final String serializedHtml = const HtmlDocumentCodec().encode(result.document);
      expect(serializedHtml.contains('steal()'), false);
      expect(serializedHtml.contains('<script>'), false);
      expect(serializedHtml.contains('<iframe'), false);
      expect(serializedHtml.contains('Clean Text'), true);

      // Verify undoable insertion
      final CommandResult undoRes = pasteCmd.undo(result.document, doc);
      expect(undoRes.success, true);
      expect(undoRes.document.plainText, 'Original line');
    });
  });
}
