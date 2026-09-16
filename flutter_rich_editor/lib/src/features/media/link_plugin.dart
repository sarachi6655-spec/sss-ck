import '../../core/command_bus/editor_command.dart';
import '../../core/document_model/document_value.dart';
import '../../core/document_model/editor_node.dart';
import '../../core/document_model/editor_selection.dart';
import '../../core/plugin_system/plugin.dart';

/// Command to set or update a link attribute on the current node or selection.
class SetLinkCommand extends EditorCommand {
  const SetLinkCommand({
    required this.url,
    this.text,
  });

  final String url;
  final String? text;

  @override
  String get id => 'media.link.set';

  @override
  CommandResult execute(DocumentValue document) {
    final EditorSelection sel = document.selection;
    final int target = sel.nodeIndex;
    if (target < 0 || target >= document.nodes.length) {
      return CommandResult.ok(document);
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode current = updated[target];
    final Map<String, dynamic> newAttrs = Map<String, dynamic>.from(current.attributes);

    if (url.isEmpty) {
      newAttrs.remove('link');
    } else {
      newAttrs['link'] = url;
    }

    updated[target] = current.copyWith(
      text: text ?? current.text,
      attributes: newAttrs,
    );

    return CommandResult.ok(document.copyWith(nodes: updated));
  }
}

/// Command to remove a link from the current selection.
class RemoveLinkCommand extends EditorCommand {
  const RemoveLinkCommand();

  @override
  String get id => 'media.link.remove';

  @override
  CommandResult execute(DocumentValue document) {
    return const SetLinkCommand(url: '').execute(document);
  }
}

/// Plugin providing hyperlinking support.
class LinkPlugin extends EditorPlugin {
  const LinkPlugin();

  @override
  String get id => 'media.link';

  @override
  String get name => 'Links';

  @override
  List<EditorCommand> get commands => const <EditorCommand>[
        SetLinkCommand(url: ''),
        RemoveLinkCommand(),
      ];
}
