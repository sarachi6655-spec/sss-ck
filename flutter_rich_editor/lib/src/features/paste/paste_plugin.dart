import '../../core/command_bus/editor_command.dart';
import '../../core/plugin_system/plugin.dart';
import 'paste_handler.dart';

/// Plugin providing secure clipboard paste with sanitization and undoability.
class PastePlugin extends EditorPlugin {
  const PastePlugin();

  @override
  String get id => 'paste';

  @override
  String get name => 'Paste & Clipboard';

  @override
  List<EditorCommand> get commands => const <EditorCommand>[
        PasteContentCommand(rawContent: ''),
      ];
}
