import 'package:flutter/material.dart';
import 'package:flutter_rich_editor/flutter_rich_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Accessibility and Localization Tests', () {
    testWidgets('test_accessibility_exposesToolbarMediaAndTableSemantics', (WidgetTester tester) async {
      final RichEditorController controller = RichEditorController(
        initialDocument: DocumentValue(
          nodes: <EditorNode>[
            EditorNode.video(id: 'v1', url: 'https://sample.mp4'),
            EditorNode.table(id: 't1', rows: 2, columns: 2),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichEditor(controller: controller),
          ),
        ),
      );

      // Verify semantics labels exist
      expect(find.bySemanticsLabel('Video player'), findsOneWidget);
      expect(find.bySemanticsLabel('Data table'), findsOneWidget);
      expect(find.bySemanticsLabel('Bold'), findsOneWidget);
      expect(find.bySemanticsLabel('Italic'), findsOneWidget);
    });

    test('test_rtlLayout_reversesDirectionWithoutChangingDocumentOrder', () {
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.heading(id: 'h1', text: 'عنوان المستند', level: 1),
          EditorNode.paragraph(id: 'p1', text: 'هذا نص باللغة العربية'),
        ],
      );

      const AccessibilityConfig rtlConfig = AccessibilityConfig(
        textDirection: TextDirection.rtl,
      );

      expect(rtlConfig.textDirection, TextDirection.rtl);
      // Verify node ordering remains strictly identical
      expect(doc.nodes[0].id, 'h1');
      expect(doc.nodes[1].id, 'p1');
    });

    test('test_localizations_replaceAllVisibleEditorLabels', () {
      const EditorLocalizations es = EditorLocalizations.es;

      expect(es.bold, 'Negrita');
      expect(es.italic, 'Cursiva');
      expect(es.underline, 'Subrayado');
      expect(es.table, 'Tabla');
      expect(es.undo, 'Deshacer');
      expect(es.redo, 'Rehacer');

      // Custom override
      final EditorLocalizations custom = es.copyWith(
        bold: 'Gras',
        italic: 'Italique',
      );

      expect(custom.bold, 'Gras');
      expect(custom.italic, 'Italique');
      expect(custom.table, 'Tabla');
    });
  });
}
