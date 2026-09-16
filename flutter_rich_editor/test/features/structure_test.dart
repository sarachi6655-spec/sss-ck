import 'package:flutter_rich_editor/flutter_rich_editor.dart';
import 'package:flutter_rich_editor/src/features/structure/structure_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Structure Command Tests', () {
    test('test_structureCommand_keepsNestedListValidAfterIndentAndOutdent', () {
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.listItem(id: 'li1', text: 'Item 1', indent: 0),
          EditorNode.listItem(id: 'li2', text: 'Nested Item', indent: 0),
        ],
        selection: const EditorSelection.collapsed(0, nodeIndex: 1),
      );

      // Indent item 2
      const IndentListCommand indentCmd = IndentListCommand();
      final CommandResult indentResult = indentCmd.execute(doc);

      expect(indentResult.success, true);
      expect(indentResult.document.nodes[1].metadata['indent'], 1);

      // Indent again
      final CommandResult indentResult2 = indentCmd.execute(indentResult.document);
      expect(indentResult2.document.nodes[1].metadata['indent'], 2);

      // Outdent item 2
      const OutdentListCommand outdentCmd = OutdentListCommand();
      final CommandResult outdentResult = outdentCmd.execute(indentResult2.document);

      expect(outdentResult.success, true);
      expect(outdentResult.document.nodes[1].metadata['indent'], 1);

      // Outdent back to 0
      final CommandResult outdentResult2 = outdentCmd.execute(outdentResult.document);
      expect(outdentResult2.document.nodes[1].metadata['indent'], 0);

      // Further outdent does not drop below 0
      final CommandResult outdentResult3 = outdentCmd.execute(outdentResult2.document);
      expect(outdentResult3.document.nodes[1].metadata['indent'], 0);
    });
  });

  group('MergeBlockForwardCommand Tests', () {
    test('merges next paragraph text into current', () {
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(id: 'p1', text: 'Hello'),
          EditorNode.paragraph(id: 'p2', text: ' World'),
        ],
        selection: const EditorSelection.collapsed(5, nodeIndex: 0),
      );

      const MergeBlockForwardCommand cmd = MergeBlockForwardCommand(nodeIndex: 0);
      final CommandResult result = cmd.execute(doc);

      expect(result.success, true);
      expect(result.document.nodes.length, 1);
      expect(result.document.nodes[0].text, 'Hello World');
      expect(result.document.selection.baseOffset, 5);
    });

    test('removes non-text nodes when merging forward', () {
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(id: 'p1', text: 'Hello'),
          EditorNode(id: 'hr1', type: 'hr'),
          EditorNode.paragraph(id: 'p2', text: 'World'),
        ],
        selection: const EditorSelection.collapsed(5, nodeIndex: 0),
      );

      const MergeBlockForwardCommand cmd = MergeBlockForwardCommand(nodeIndex: 0);
      final CommandResult result = cmd.execute(doc);

      expect(result.success, true);
      expect(result.document.nodes.length, 2);
      expect(result.document.nodes[0].text, 'Hello');
      expect(result.document.nodes[1].text, 'World');
    });

    test('no-op when at last node', () {
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(id: 'p1', text: 'Hello'),
        ],
        selection: const EditorSelection.collapsed(5, nodeIndex: 0),
      );

      const MergeBlockForwardCommand cmd = MergeBlockForwardCommand(nodeIndex: 0);
      final CommandResult result = cmd.execute(doc);

      expect(result.success, true);
      expect(result.document.nodes.length, 1);
      expect(result.document.nodes[0].text, 'Hello');
    });
  });

  group('DeleteSelectedNodesCommand Tests', () {
    test('deletes selected text within a single node', () {
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(id: 'p1', text: 'Hello World'),
        ],
        selection: const EditorSelection(baseOffset: 5, extentOffset: 11, nodeIndex: 0),
      );

      const DeleteSelectedNodesCommand cmd = DeleteSelectedNodesCommand(
        startNodeIndex: 0,
        endNodeIndex: 0,
        startOffset: 5,
        endOffset: 11,
      );
      final CommandResult result = cmd.execute(doc);

      expect(result.success, true);
      expect(result.document.nodes[0].text, 'Hello');
      expect(result.document.selection.baseOffset, 5);
    });

    test('deletes across multiple nodes and merges remaining', () {
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(id: 'p1', text: 'Hello'),
          EditorNode.paragraph(id: 'p2', text: 'Middle'),
          EditorNode.paragraph(id: 'p3', text: 'World'),
        ],
        selection: const EditorSelection(
          baseOffset: 3,
          extentOffset: 2,
          nodeIndex: 0,
          endNodeIndex: 2,
        ),
      );

      const DeleteSelectedNodesCommand cmd = DeleteSelectedNodesCommand(
        startNodeIndex: 0,
        endNodeIndex: 2,
        startOffset: 3,
        endOffset: 2,
      );
      final CommandResult result = cmd.execute(doc);

      expect(result.success, true);
      expect(result.document.nodes.length, 1);
      expect(result.document.nodes[0].text, 'Helrld');
      expect(result.document.selection.baseOffset, 3);
    });

    test('ensures document is never empty after deletion', () {
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(id: 'p1', text: 'Only node'),
        ],
        selection: const EditorSelection(baseOffset: 0, extentOffset: 9, nodeIndex: 0),
      );

      const DeleteSelectedNodesCommand cmd = DeleteSelectedNodesCommand(
        startNodeIndex: 0,
        endNodeIndex: 0,
        startOffset: 0,
        endOffset: 9,
      );
      final CommandResult result = cmd.execute(doc);

      expect(result.success, true);
      expect(result.document.nodes.length, 1);
      expect(result.document.nodes[0].text, '');
    });
  });

  group('ClearDocumentCommand Tests', () {
    test('clears entire document to empty state', () {
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(id: 'p1', text: 'Hello'),
          EditorNode.paragraph(id: 'p2', text: 'World'),
          EditorNode.heading(id: 'h1', text: 'Title', level: 1),
        ],
        selection: const EditorSelection.collapsed(0),
      );

      const ClearDocumentCommand cmd = ClearDocumentCommand();
      final CommandResult result = cmd.execute(doc);

      expect(result.success, true);
      expect(result.document.nodes.length, 1);
      expect(result.document.nodes[0].text, '');
      expect(result.document.nodes[0].type, 'paragraph');
      expect(result.document.selection.baseOffset, 0);
      expect(result.document.selection.nodeIndex, 0);
    });
  });
}
