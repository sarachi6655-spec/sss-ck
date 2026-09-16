import 'package:flutter_rich_editor/flutter_rich_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Collaboration & Reviewer Tests', () {
    test('test_reviewerMode_allowsCommentsAndRejectsDocumentMutation', () {
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(id: 'p1', text: 'Document Body'),
        ],
      );

      // Mutating command wrapped with reviewer permissions
      const ReviewerGuardedCommand editCmd = ReviewerGuardedCommand(
        innerCommand: FormatMarkCommand(mark: 'bold'),
        isReviewer: true,
      );

      final CommandResult editResult = editCmd.execute(doc);
      expect(editResult.success, false);
      expect(editResult.errorCode, 'permission.reviewer_read_only');

      // Comment command is permitted in reviewer mode
      const AddCommentCommand commentCmd = AddCommentCommand(
        nodeId: 'p1',
        author: EditorUser(id: 'u1', name: 'Reviewer Alex'),
        text: 'Needs revision',
      );

      final CommandResult commentResult = commentCmd.execute(doc);
      expect(commentResult.success, true);
      expect(commentResult.document.metadata['comments'], isNotNull);
    });

    test('test_trackChangesProvider_mapsSuggestionToAcceptRejectCommands', () {
      const TrackChangesProvider provider = TrackChangesProvider();
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(id: 'node_1', text: 'Original line'),
        ],
      );

      const ContentSuggestion suggestion = ContentSuggestion(
        id: 'sug_1',
        nodeId: 'node_1',
        author: EditorUser(id: 'u1', name: 'Reviewer'),
        originalText: 'Original line',
        suggestedText: 'Refined proposal text',
      );

      // Test accept command
      final EditorCommand acceptCmd = provider.createAcceptCommand(suggestion);
      final CommandResult acceptResult = acceptCmd.execute(doc);
      expect(acceptResult.success, true);
      expect(acceptResult.document.nodes[0].text, 'Refined proposal text');

      // Test reject command
      final EditorCommand rejectCmd = provider.createRejectCommand(suggestion);
      final CommandResult rejectResult = rejectCmd.execute(acceptResult.document);
      expect(rejectResult.success, true);
      expect(rejectResult.document.nodes[0].text, 'Original line');
    });

    test('test_collaborationTransport_reconcilesProviderOperationsWithoutLocalDataLoss', () {
      const CollaborationTransport transport = CollaborationTransport();

      final DocumentValue localDoc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(id: 'n1', text: 'Local edited content'),
          EditorNode.paragraph(id: 'n2', text: 'Local paragraph 2'),
        ],
      );

      final List<EditorNode> remoteIncoming = <EditorNode>[
        EditorNode.paragraph(id: 'n2', text: 'Remote updated paragraph 2'),
        EditorNode.paragraph(id: 'n3', text: 'New remote paragraph 3'),
      ];

      final DocumentValue reconciled = transport.reconcile(
        localDocument: localDoc,
        remoteNodes: remoteIncoming,
      );

      expect(reconciled.nodes.length, 3);
      expect(reconciled.nodes.any((EditorNode n) => n.id == 'n1'), true);
      expect(reconciled.nodes.any((EditorNode n) => n.id == 'n2'), true);
      expect(reconciled.nodes.any((EditorNode n) => n.id == 'n3'), true);
    });
  });
}
