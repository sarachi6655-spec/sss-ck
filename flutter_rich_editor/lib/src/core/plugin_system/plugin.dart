import '../command_bus/command_bus.dart';

/// Context provided to an [EditorPlugin] when it is registered.
class PluginContext {
  PluginContext({
    required this.commandBus,
  });

  final CommandBus commandBus;
}

/// Abstract base class for every rich editor feature plugin.
abstract class EditorPlugin {
  const EditorPlugin();

  /// Unique identifier for this plugin (e.g. 'formatting.bold').
  String get id;

  /// Display name of the plugin.
  String get name => id;

  /// Commands contributed by this plugin.
  List<EditorCommand> get commands => const <EditorCommand>[];

  /// Lifecycle callback when the plugin is registered with the editor.
  void initialize(PluginContext context) {
    for (final EditorCommand cmd in commands) {
      context.commandBus.registerCommand(cmd);
    }
  }

  /// Lifecycle callback when the plugin is disposed or unregistered.
  void dispose() {}
}
