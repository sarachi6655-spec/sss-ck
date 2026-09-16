import 'package:flutter_rich_editor/flutter_rich_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Formatting Command Tests', () {
    test('test_formattingCommand_appliesCollapsedSelectionPendingMark', () {
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(id: 'p1', text: 'Hello World'),
        ],
        selection: const EditorSelection.collapsed(5),
      );

      const FormatMarkCommand boldCmd = FormatMarkCommand(mark: 'bold');
      final CommandResult result = boldCmd.execute(doc);

      expect(result.success, true);
      final Map<String, dynamic>? pending = result.document.metadata['pendingMarks'] as Map<String, dynamic>?;
      expect(pending, isNotNull);
      expect(pending!['bold'], true);
    });

    test('test_formattingCommand_removesExpandedSelectionMark', () {
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(
            id: 'p1',
            text: 'Hello World',
            attributes: const <String, dynamic>{'bold': true},
          ),
        ],
        selection: const EditorSelection(baseOffset: 0, extentOffset: 5, nodeIndex: 0),
      );

      // Applying bold to already bold selected text toggles it off
      const FormatMarkCommand boldCmd = FormatMarkCommand(mark: 'bold');
      final CommandResult result = boldCmd.execute(doc);

      expect(result.success, true);
      expect(result.document.nodes[0].attributes['bold'], isNull);
    });
  });
}
