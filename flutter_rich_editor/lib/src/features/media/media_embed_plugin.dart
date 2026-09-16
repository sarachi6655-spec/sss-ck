import '../../core/command_bus/editor_command.dart';
import '../../core/document_model/document_value.dart';
import '../../core/document_model/editor_node.dart';
import '../../core/document_model/editor_selection.dart';
import '../../core/plugin_system/plugin.dart';

/// Policy governing which external URLs are permitted for embedding.
class MediaEmbedPolicy {
  const MediaEmbedPolicy({
    this.allowedHosts = const <String>[
      'youtube.com',
      'www.youtube.com',
      'youtu.be',
      'vimeo.com',
      'player.vimeo.com',
      'spotify.com',
      'open.spotify.com',
      'ted.com',
    ],
  });

  final List<String> allowedHosts;

  /// Returns true if [url] is allowed by this policy.
  bool isAllowed(String url) {
    try {
      final Uri uri = Uri.parse(url);
      if (!uri.hasScheme || (!uri.isScheme('http') && !uri.isScheme('https'))) {
        return false;
      }
      final String host = uri.host.toLowerCase();
      return allowedHosts.any((String allowed) =>
          host == allowed.toLowerCase() || host.endsWith('.${allowed.toLowerCase()}'));
    } catch (_) {
      return false;
    }
  }
}

/// Command to insert an external media embed with URL policy validation.
class InsertEmbedCommand extends EditorCommand {
  const InsertEmbedCommand({
    required this.url,
    this.policy = const MediaEmbedPolicy(),
  });

  final String url;
  final MediaEmbedPolicy policy;

  @override
  String get id => 'media.insertEmbed';

  @override
  bool canExecute(DocumentValue document) => true;

  @override
  CommandResult execute(DocumentValue document) {
    if (!policy.isAllowed(url)) {
      return CommandResult.failure(
        currentDocument: document,
        code: 'media.disallowed_url',
        message: 'The URL "$url" is not permitted by the embed security policy.',
      );
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorSelection sel = document.selection;
    final int insertPos = sel.nodeIndex >= 0 && sel.nodeIndex < updated.length
        ? sel.nodeIndex + 1
        : updated.length;

    final EditorNode embedNode = EditorNode(
      id: 'embed_${DateTime.now().millisecondsSinceEpoch}',
      type: 'embed',
      metadata: <String, dynamic>{
        'url': url,
      },
    );

    updated.insert(insertPos, embedNode);

    return CommandResult.ok(document.copyWith(
      nodes: updated,
      selection: EditorSelection.collapsed(0, nodeIndex: insertPos),
    ));
  }
}

/// Plugin providing secure external media embeds (YouTube, Vimeo, etc.).
class MediaEmbedPlugin extends EditorPlugin {
  const MediaEmbedPlugin({
    this.policy = const MediaEmbedPolicy(),
  });

  final MediaEmbedPolicy policy;

  @override
  String get id => 'media.embed';

  @override
  String get name => 'Media Embed';

  @override
  List<EditorCommand> get commands => <EditorCommand>[
        InsertEmbedCommand(url: '', policy: policy),
      ];
}
