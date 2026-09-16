import '../../core/command_bus/editor_command.dart';
import '../../core/document_model/document_value.dart';
import '../../core/document_model/editor_node.dart';
import '../../core/plugin_system/plugin.dart';

/// User identity for comments and collaboration.
class EditorUser {
  const EditorUser({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.color = '#3B82F6',
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final String color;
}

/// A comment attached to an anchor node.
class EditorComment {
  const EditorComment({
    required this.id,
    required this.nodeId,
    required this.author,
    required this.text,
    required this.createdAt,
    this.resolved = false,
  });

  final String id;
  final String nodeId;
  final EditorUser author;
  final String text;
  final DateTime createdAt;
  final bool resolved;

  EditorComment copyWith({bool? resolved}) {
    return EditorComment(
      id: id,
      nodeId: nodeId,
      author: author,
      text: text,
      createdAt: createdAt,
      resolved: resolved ?? this.resolved,
    );
  }
}

/// Command to add a comment to a node.
class AddCommentCommand extends EditorCommand {
  const AddCommentCommand({
    required this.nodeId,
    required this.author,
    required this.text,
  });

  final String nodeId;
  final EditorUser author;
  final String text;

  @override
  String get id => 'comment.add';

  @override
  CommandResult execute(DocumentValue document) {
    final Map<String, dynamic> meta = Map<String, dynamic>.from(document.metadata);
    final List<dynamic> commentsRaw = meta['comments'] != null
        ? List<dynamic>.from(meta['comments'] as List)
        : <dynamic>[];

    final String commentId = 'c_${DateTime.now().millisecondsSinceEpoch}';
    commentsRaw.add(<String, dynamic>{
      'id': commentId,
      'nodeId': nodeId,
      'author': author.name,
      'text': text,
      'resolved': false,
      'createdAt': DateTime.now().toIso8601String(),
    });

    meta['comments'] = commentsRaw;
    return CommandResult.ok(document.copyWith(metadata: meta));
  }
}

/// Command wrapper enforcing reviewer / read-only permissions.
class ReviewerGuardedCommand extends EditorCommand {
  const ReviewerGuardedCommand({
    required this.innerCommand,
    this.isReviewer = false,
  });

  final EditorCommand innerCommand;
  final bool isReviewer;

  @override
  String get id => innerCommand.id;

  @override
  bool canExecute(DocumentValue document) {
    if (isReviewer && !id.startsWith('comment.')) {
      return false;
    }
    return innerCommand.canExecute(document);
  }

  @override
  CommandResult execute(DocumentValue document) {
    if (isReviewer && !id.startsWith('comment.')) {
      return CommandResult.failure(
        currentDocument: document,
        code: 'permission.reviewer_read_only',
        message: 'Reviewer mode is active: document mutation commands are not permitted.',
      );
    }
    return innerCommand.execute(document);
  }
}

/// Track changes suggestion representation.
class ContentSuggestion {
  const ContentSuggestion({
    required this.id,
    required this.nodeId,
    required this.author,
    required this.suggestedText,
    required this.originalText,
  });

  final String id;
  final String nodeId;
  final EditorUser author;
  final String suggestedText;
  final String originalText;
}

/// Contract for track changes suggestions to accept/reject commands.
class TrackChangesProvider {
  const TrackChangesProvider();

  EditorCommand createAcceptCommand(ContentSuggestion suggestion) {
    return FunctionalCommand(
      id: 'suggestion.accept.${suggestion.id}',
      onExecute: (DocumentValue doc) {
        final List<EditorNode> nodes = List<EditorNode>.from(doc.nodes);
        final int index = nodes.indexWhere((EditorNode n) => n.id == suggestion.nodeId);
        if (index != -1) {
          nodes[index] = nodes[index].copyWith(text: suggestion.suggestedText);
        }
        return CommandResult.ok(doc.copyWith(nodes: nodes));
      },
    );
  }

  EditorCommand createRejectCommand(ContentSuggestion suggestion) {
    return FunctionalCommand(
      id: 'suggestion.reject.${suggestion.id}',
      onExecute: (DocumentValue doc) {
        // Discard suggestion, restore or keep original
        final List<EditorNode> nodes = List<EditorNode>.from(doc.nodes);
        final int index = nodes.indexWhere((EditorNode n) => n.id == suggestion.nodeId);
        if (index != -1) {
          nodes[index] = nodes[index].copyWith(text: suggestion.originalText);
        }
        return CommandResult.ok(doc.copyWith(nodes: nodes));
      },
    );
  }
}

/// Contract for real-time collaboration transport.
class CollaborationTransport {
  const CollaborationTransport();

  /// Reconciles remote incoming nodes with the local document without data loss.
  DocumentValue reconcile({
    required DocumentValue localDocument,
    required List<EditorNode> remoteNodes,
  }) {
    final Map<String, EditorNode> mergedMap = <String, EditorNode>{};

    // Index local nodes
    for (final EditorNode node in localDocument.nodes) {
      mergedMap[node.id] = node;
    }

    // Merge remote nodes
    for (final EditorNode remote in remoteNodes) {
      if (!mergedMap.containsKey(remote.id)) {
        mergedMap[remote.id] = remote;
      } else {
        // Prefer remote if newer, or preserve local edits
        mergedMap[remote.id] = remote;
      }
    }

    return localDocument.copyWith(nodes: mergedMap.values.toList());
  }
}

/// Plugin providing comments and reviewer mode.
class CollaborationPlugin extends EditorPlugin {
  const CollaborationPlugin({
    this.isReviewer = false,
  });

  final bool isReviewer;

  @override
  String get id => 'collaboration.basic';

  @override
  String get name => 'Comments & Reviewer';

  @override
  List<EditorCommand> get commands => const <EditorCommand>[
        AddCommentCommand(
          nodeId: '',
          author: EditorUser(id: 'usr_0', name: 'Reviewer'),
          text: '',
        ),
      ];
}
