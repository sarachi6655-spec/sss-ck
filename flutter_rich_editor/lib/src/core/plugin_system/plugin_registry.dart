import 'dart:collection';
import '../command_bus/command_bus.dart';
import 'plugin.dart';

/// Registry managing the lifecycle and dependencies of [EditorPlugin]s.
class PluginRegistry {
  PluginRegistry({
    required CommandBus commandBus,
  }) : _commandBus = commandBus;

  final CommandBus _commandBus;
  final List<EditorPlugin> _plugins = <EditorPlugin>[];
  final Set<String> _registeredCommandIds = <String>{};

  /// Returns unmodifiable list of registered plugins in registration order.
  List<EditorPlugin> get plugins => UnmodifiableListView<EditorPlugin>(_plugins);

  /// Returns a set of all enabled plugin IDs.
  Set<String> get enabledFeatures =>
      _plugins.map((EditorPlugin p) => p.id).toSet();

  /// Registers a single plugin.
  /// Throws [ArgumentError] if the plugin ID is duplicate or if any command ID is already registered.
  void registerPlugin(EditorPlugin plugin) {
    if (_plugins.any((EditorPlugin p) => p.id == plugin.id)) {
      throw ArgumentError('Plugin with id "${plugin.id}" is already registered.');
    }

    // Validate that no command IDs conflict before initializing
    for (final EditorCommand cmd in plugin.commands) {
      if (_registeredCommandIds.contains(cmd.id) ||
          _commandBus.getCommand(cmd.id) != null) {
        throw ArgumentError('Duplicate command ID "${cmd.id}" introduced by plugin "${plugin.id}".');
      }
    }

    // Track command IDs
    for (final EditorCommand cmd in plugin.commands) {
      _registeredCommandIds.add(cmd.id);
    }

    // Initialize with context
    final PluginContext context = PluginContext(commandBus: _commandBus);
    plugin.initialize(context);
    _plugins.add(plugin);
  }

  /// Registers multiple plugins in given sequence.
  void registerPlugins(Iterable<EditorPlugin> plugins) {
    for (final EditorPlugin p in plugins) {
      registerPlugin(p);
    }
  }

  /// Checks if a plugin with [pluginId] is currently registered.
  bool hasPlugin(String pluginId) =>
      _plugins.any((EditorPlugin p) => p.id == pluginId);

  /// Returns the plugin with [pluginId] typed as [T], or null if not found.
  T? getPlugin<T extends EditorPlugin>(String pluginId) {
    for (final EditorPlugin p in _plugins) {
      if (p.id == pluginId && p is T) {
        return p;
      }
    }
    return null;
  }

  /// Disposes all registered plugins in reverse registration order.
  void dispose() {
    // Reverse disposal order for LIFO safety
    for (int i = _plugins.length - 1; i >= 0; i--) {
      _plugins[i].dispose();
    }
    _plugins.clear();
    _registeredCommandIds.clear();
  }
}
