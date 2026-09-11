import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../document_model/document_model.dart';
import '../command_bus/editor_command.dart';
import 'plugin.dart';

/// Registry that owns the plugin-registered node types, commands, toolbar
/// items, shortcuts, and serializers.
///
/// The registry enforces deterministic registration order, rejects duplicate
/// command/node keys, and exposes disposal in reverse order.
class PluginRegistry {
  final Map<String, EditorPlugin> _plugins = <String, EditorPlugin>{};
  final List<EditorPlugin> _order = <EditorPlugin>[];

  final Map<String, NodeTypeRegistration> _nodeTypes =
      <String, NodeTypeRegistration>{};
  final Map<String, EditorCommandFactory> _commands =
      <String, EditorCommandFactory>{};
  final List<ToolbarItem> _toolbarItems = <ToolbarItem>[];
  final List<ShortcutRegistration> _shortcuts = <ShortcutRegistration>[];

  /// All registered plugins in registration order.
  Iterable<EditorPlugin> get plugins => List<EditorPlugin>.unmodifiable(_order);

  /// All registered node type keys.
  Iterable<String> get nodeTypes => _nodeTypes.keys;

  /// All registered command ids.
  Iterable<String> get commandIds => _commands.keys;

  /// All registered toolbar items, ordered by [ToolbarItem.order].
  List<ToolbarItem> get toolbarItems => List<ToolbarItem>.unmodifiable(_toolbarItems);

  /// All registered keyboard shortcuts.
  List<ShortcutRegistration> get shortcuts =>
      List<ShortcutRegistration>.unmodifiable(_shortcuts);

  /// Register a plugin. Throws if dependencies are missing or if the plugin
  /// has already been registered.
  void register(EditorPlugin plugin) {
    if (_plugins.containsKey(plugin.id)) {
      throw PluginRegistryException(
          'Plugin ${plugin.id} is already registered.');
    }
    for (final String dep in plugin.dependencies) {
      if (!_plugins.containsKey(dep)) {
        throw PluginRegistryException(
            'Plugin ${plugin.id} depends on missing plugin $dep.');
      }
    }
    _plugins[plugin.id] = plugin;
    _order.add(plugin);
    plugin.register(this);
  }

  /// Register a document node type. Throws on duplicate [nodeType].
  void registerNodeType(NodeTypeRegistration registration) {
    if (_nodeTypes.containsKey(registration.nodeType)) {
      throw PluginRegistryException(
          'Node type ${registration.nodeType} is already registered.');
    }
    _nodeTypes[registration.nodeType] = registration;
  }

  /// Resolve a node from JSON using the registered factory.
  EditorNode nodeFromJson(Map<String, dynamic> json) {
    final String type = json['type'] as String? ?? 'unknown';
    final NodeTypeRegistration? registration = _nodeTypes[type];
    if (registration == null) {
      return UnsupportedNode(
        id: json['id'] as String? ?? _generateId(),
        originalType: type,
        json: json,
      );
    }
    return registration.fromJson(json);
  }

  /// Serialize a node to JSON.
  Map<String, dynamic> nodeToJson(EditorNode node) {
    final NodeTypeRegistration? registration = _nodeTypes[node.type];
    if (registration == null) {
      if (node is UnsupportedNode) {
        return node.json;
      }
      return <String, dynamic>{'type': node.type, 'id': node.id};
    }
    return registration.toJson(node);
  }

  /// Register a command factory. Throws on duplicate [commandId].
  void registerCommand(String commandId, EditorCommandFactory factory) {
    if (_commands.containsKey(commandId)) {
      throw PluginRegistryException(
          'Command $commandId is already registered.');
    }
    _commands[commandId] = factory;
  }

  /// Create a command instance by id.
  EditorCommand createCommand(
    String commandId, {
    Map<String, dynamic> arguments = const <String, dynamic>{},
  }) {
    final EditorCommandFactory? factory = _commands[commandId];
    if (factory == null) {
      throw PluginRegistryException('Command $commandId is not registered.');
    }
    return factory(arguments);
  }

  /// Register a toolbar item.
  void registerToolbarItem(ToolbarItem item) {
    _toolbarItems.add(item);
    _toolbarItems.sort((ToolbarItem a, ToolbarItem b) => a.order - b.order);
  }

  /// Register a keyboard shortcut.
  void registerShortcut(ShortcutRegistration shortcut) {
    _shortcuts.add(shortcut);
  }

  /// Dispose all registered plugins in reverse registration order.
  void dispose() {
    for (final EditorPlugin plugin in _order.reversed) {
      try {
        plugin.dispose(this);
      } on Object catch (e, stack) {
        debugPrint('Error disposing plugin ${plugin.id}: $e\n$stack');
      }
    }
    _plugins.clear();
    _order.clear();
    _nodeTypes.clear();
    _commands.clear();
    _toolbarItems.clear();
    _shortcuts.clear();
  }

  static String _generateId() {
    return 'node_${DateTime.now().millisecondsSinceEpoch}_${_counter++}';
  }

  static int _counter = 0;
}

/// Node used to preserve unknown/unsupported content during round-trips.
class UnsupportedNode extends EditorNode {
  @override
  final String id;
  final String originalType;
  final Map<String, dynamic> json;

  const UnsupportedNode({
    required this.id,
    required this.originalType,
    required this.json,
  });

  @override
  String get type => 'unsupported';

  @override
  Map<String, dynamic> get attributes => const <String, dynamic>{};

  @override
  String get plainText => '';

  @override
  Map<String, dynamic> toJson() => json;

  @override
  EditorNode copyWith({String? id, Map<String, dynamic>? attributes}) =>
      UnsupportedNode(
        id: id ?? this.id,
        originalType: originalType,
        json: json,
      );
}

class PluginRegistryException implements Exception {
  final String message;
  PluginRegistryException(this.message);
  @override
  String toString() => 'PluginRegistryException: $message';
}
