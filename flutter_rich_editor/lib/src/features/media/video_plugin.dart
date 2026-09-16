import '../../core/command_bus/editor_command.dart';
import '../../core/document_model/document_value.dart';
import '../../core/document_model/editor_node.dart';
import '../../core/document_model/editor_selection.dart';
import '../../core/plugin_system/plugin.dart';

/// Command to insert a video node into the document.
class InsertVideoCommand extends EditorCommand {
  const InsertVideoCommand({
    required this.url,
    this.poster = '',
    this.width,
    this.height,
    this.uploadState = 'ready',
    this.progress = 1.0,
  });

  final String url;
  final String poster;
  final double? width;
  final double? height;
  final String uploadState; // 'ready', 'uploading', 'buffering', 'error'
  final double progress;

  @override
  String get id => 'media.insertVideo';

  @override
  CommandResult execute(DocumentValue document) {
    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorSelection sel = document.selection;
    final int insertPos = sel.nodeIndex >= 0 && sel.nodeIndex < updated.length
        ? sel.nodeIndex + 1
        : updated.length;

    final EditorNode videoNode = EditorNode.video(
      id: 'video_${DateTime.now().millisecondsSinceEpoch}',
      url: url,
      poster: poster,
      width: width,
      height: height,
      uploadState: uploadState,
      progress: progress,
    );

    updated.insert(insertPos, videoNode);

    return CommandResult.ok(document.copyWith(
      nodes: updated,
      selection: EditorSelection.collapsed(0, nodeIndex: insertPos),
    ));
  }
}

/// Command to update the playback or upload state of a video node.
class UpdateVideoStateCommand extends EditorCommand {
  const UpdateVideoStateCommand({
    required this.nodeId,
    this.uploadState,
    this.poster,
    this.progress,
  });

  final String nodeId;
  final String? uploadState;
  final String? poster;
  final double? progress;

  @override
  String get id => 'media.updateVideoState.$nodeId';

  @override
  CommandResult execute(DocumentValue document) {
    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final int index = updated.indexWhere((EditorNode n) => n.id == nodeId);
    if (index == -1) {
      return CommandResult.failure(
        currentDocument: document,
        code: 'video.not_found',
        message: 'Video node "$nodeId" not found.',
      );
    }

    final EditorNode current = updated[index];
    final Map<String, dynamic> newMeta = Map<String, dynamic>.from(current.metadata);

    if (uploadState != null) newMeta['uploadState'] = uploadState;
    if (poster != null) newMeta['poster'] = poster;
    if (progress != null) newMeta['progress'] = progress;

    updated[index] = current.copyWith(metadata: newMeta);
    return CommandResult.ok(document.copyWith(nodes: updated));
  }
}

/// Plugin providing native video playback and upload handling.
class VideoPlugin extends EditorPlugin {
  const VideoPlugin();

  @override
  String get id => 'media.video';

  @override
  String get name => 'Native Video';

  @override
  List<EditorCommand> get commands => const <EditorCommand>[
        InsertVideoCommand(url: ''),
      ];
}
