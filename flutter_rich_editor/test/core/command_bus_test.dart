import 'package:flutter_rich_editor/flutter_rich_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandBus Tests', () {
    test('test_commandBus_executesUndoableCommandAndRestoresPreviousDocument', () {
      final CommandBus bus = CommandBus();
      final DocumentValue initialDoc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(id: 'p1', text: 'Original Content'),
        ],
      );

      final EditorCommand editCommand = FunctionalCommand(
        id: 'cmd.edit',
        onExecute: (DocumentValue doc) {
          return CommandResult.ok(DocumentValue(
            nodes: <EditorNode>[
              EditorNode.paragraph(id: 'p1', text: 'Mutated Content'),
            ],
          ));
        },
      );

      bus.registerCommand(editCommand);

      final CommandResult result = bus.execute(editCommand, initialDoc);
      expect(result.success, true);
      expect(result.document.plainText, 'Mutated Content');
      expect(bus.canUndo, true);

      final CommandResult? undoResult = bus.undo(result.document);
      expect(undoResult, isNotNull);
      expect(undoResult!.success, true);
      expect(undoResult.document.plainText, 'Original Content');
    });
  });
}
