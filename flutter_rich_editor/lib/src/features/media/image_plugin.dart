import '../../core/command_bus/editor_command.dart';
import '../../core/document_model/document_value.dart';
import '../../core/document_model/editor_node.dart';
import '../../core/document_model/editor_selection.dart';
import '../../core/plugin_system/plugin.dart';

/// Command to insert an image node into the document.
class InsertImageCommand extends EditorCommand {
  const InsertImageCommand({
    required this.url,
    this.alt = '',
    this.caption = '',
    this.width,
    this.height,
  });

  final String url;
  final String alt;
  final String caption;
  final double? width;
  final double? height;

  @override
  String get id => 'media.insertImage';

  @override
  CommandResult execute(DocumentValue document) {
    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorSelection sel = document.selection;
    final int insertPos = sel.nodeIndex >= 0 && sel.nodeIndex < updated.length
        ? sel.nodeIndex + 1
        : updated.length;

    final EditorNode imageNode = EditorNode.image(
      id: 'img_${DateTime.now().millisecondsSinceEpoch}',
      url: url,
      alt: alt,
      caption: caption,
      width: width,
      height: height,
    );

    updated.insert(insertPos, imageNode);

    return CommandResult.ok(document.copyWith(
      nodes: updated,
      selection: EditorSelection.collapsed(0, nodeIndex: insertPos),
    ));
  }
}

/// Command to resize an image node.
class ResizeImageCommand extends EditorCommand {
  const ResizeImageCommand({
    required this.nodeId,
    required this.width,
    this.height,
  });

  final String nodeId;
  final double width;
  final double? height;

  @override
  String get id => 'media.resizeImage.$nodeId';

  @override
  CommandResult execute(DocumentValue document) {
    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final int index = updated.indexWhere((EditorNode n) => n.id == nodeId);
    if (index == -1) {
      return CommandResult.failure(
        currentDocument: document,
        code: 'image.not_found',
        message: 'Image node "$nodeId" not found.',
      );
    }

    final EditorNode current = updated[index];
    final Map<String, dynamic> newMeta = Map<String, dynamic>.from(current.metadata);
    newMeta['width'] = width;
    if (height != null) newMeta['height'] = height;

    updated[index] = current.copyWith(metadata: newMeta);
    return CommandResult.ok(document.copyWith(nodes: updated));
  }
}

/// Plugin providing image insertion, resizing, captions, and responsive layout.
class ImagePlugin extends EditorPlugin {
  const ImagePlugin();

  @override
  String get id => 'media.image';

  @override
  String get name => 'Images';

  @override
  List<EditorCommand> get commands => const <EditorCommand>[
        InsertImageCommand(url: ''),
      ];
}
