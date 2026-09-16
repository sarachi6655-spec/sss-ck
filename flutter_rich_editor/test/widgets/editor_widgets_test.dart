import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rich_editor/flutter_rich_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Editor Widgets Tests', () {
    testWidgets('test_editorConfig_rendersReadOnlyAndPlaceholderStates', (WidgetTester tester) async {
      // 1. Placeholder state
      final RichEditorController emptyController = RichEditorController(
        initialDocument: DocumentValue.empty(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichEditor(
              controller: emptyController,
              config: const EditorConfig(
                placeholder: 'Custom placeholder message...',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Custom placeholder message...'), findsOneWidget);

      // 2. Read-only state
      final RichEditorController readOnlyController = RichEditorController(
        initialDocument: DocumentValue(
          nodes: <EditorNode>[
            EditorNode.paragraph(id: 'p1', text: 'Immutable static content'),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichEditor(
              controller: readOnlyController,
              config: const EditorConfig(
                readOnly: true,
              ),
            ),
          ),
        ),
      );

      // In read-only mode, no editable TextField should be rendered, only static Text
      expect(find.text('Immutable static content'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      // And toolbar is hidden
      expect(find.byType(EditorToolbar), findsNothing);
    });

    testWidgets('test_watchdog_preservesLastValidDocumentWhenPluginFails', (WidgetTester tester) async {
      final DocumentValue validDoc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(id: 'p1', text: 'Precious Valid Content'),
        ],
      );

      final RichEditorController controller = RichEditorController(
        initialDocument: validDoc,
      );

      // Force watchdog boundary to catch an error
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WatchdogBoundary(
              controller: controller,
              child: Builder(
                builder: (BuildContext context) {
                  // Simulate normal child rendering initially
                  return const Text('Normal Child Canvas');
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('Normal Child Canvas'), findsOneWidget);
      expect(controller.lastValidDocument.plainText, 'Precious Valid Content');

      // Now verify watchdog boundary renders fallback and recovers
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WatchdogBoundary(
              controller: controller,
              fallbackBuilder: (context, error, lastDoc) {
                return Column(
                  children: <Widget>[
                    const Text('Watchdog Error Fallback'),
                    Text('Preserved: ${lastDoc.plainText}'),
                  ],
                );
              },
              builder: (BuildContext context) {
                throw Exception('Simulated renderer failure');
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Watchdog Error Fallback'), findsOneWidget);
      expect(find.text('Preserved: Precious Valid Content'), findsOneWidget);
      expect(controller.lastValidDocument.plainText, 'Precious Valid Content');
    });

    testWidgets('test_editor_allowsWritingEditingAndSplittingBlocksOnEnter', (WidgetTester tester) async {
      final RichEditorController controller = RichEditorController(
        initialDocument: DocumentValue(
          nodes: <EditorNode>[
            EditorNode.heading(id: 'h1', text: 'Initial Title', level: 1),
            EditorNode.paragraph(id: 'p1', text: 'Initial Paragraph'),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichEditor(
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the second TextField (the paragraph)
      final Finder textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));

      // 1. Enter text
      await tester.enterText(textFields.last, 'Updated live text content');
      expect(controller.document.nodes[1].text, 'Updated live text content');

      // 2. Press Enter to split block
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(controller.document.nodes.length, 3);
      expect(find.byType(TextField), findsNWidgets(3));
    });
  });
}
