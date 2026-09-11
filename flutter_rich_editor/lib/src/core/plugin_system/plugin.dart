import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/editor_theme_data.dart';
import '../document_model/document_model.dart';
import 'plugin_registry.dart';

/// Lifecycle and registration hooks for every editor feature.
///
/// Each feature (bold, lists, tables, images, etc.) is implemented as a plugin
/// that registers its node types, attributes, commands, toolbar items,
/// serializers, and lifecycle handlers with the editor.
abstract class EditorPlugin {
  /// Unique plugin identifier. Used for logging, dependency ordering, and
  /// conflict detection.
  String get id;

  /// Human-readable name, exposed in diagnostics and the showcase app.
  String get name;

  /// Optional list of plugin ids that must be registered before this plugin.
  List<String> get dependencies => const <String>[];

  /// Register this plugin with the [registry].
  ///
  /// Called once when the editor is initialized. Plugins must only mutate the
  /// editor through the registry; they must not hold mutable widget state.
  void register(PluginRegistry registry);

  /// Called when the editor controller is disposed.
  ///
  /// Release any resources acquired during registration or command execution.
  void dispose(PluginRegistry registry) {}
}

/// Metadata returned when a plugin registers a document node type.
@immutable
class NodeTypeRegistration {
  final String nodeType;
  final NodeFromJson fromJson;
  final NodeToJson toJson;
  final NodeRenderer renderer;

  const NodeTypeRegistration({
    required this.nodeType,
    required this.fromJson,
    required this.toJson,
    required this.renderer,
  });
}

/// Factory that rebuilds a node from its canonical JSON representation.
typedef NodeFromJson = EditorNode Function(Map<String, dynamic> json);

/// Serializer from an [EditorNode] to its canonical JSON representation.
typedef NodeToJson = Map<String, dynamic> Function(EditorNode node);

/// Widget builder for a node inside the editor document.
typedef NodeRenderer = Widget Function(
  BuildContext context,
  EditorNode node,
  NodeRenderContext renderContext,
);

/// Context passed to every node renderer.
@immutable
class NodeRenderContext {
  final bool readOnly;
  final bool isSelected;
  final EditorThemeData theme;
  final TextDirection direction;
  final VoidCallback? onTap;
  final ValueChanged<EditorNode>? onUpdate;

  const NodeRenderContext({
    required this.readOnly,
    required this.isSelected,
    required this.theme,
    required this.direction,
    this.onTap,
    this.onUpdate,
  });

  NodeRenderContext copyWith({
    bool? readOnly,
    bool? isSelected,
    EditorThemeData? theme,
    TextDirection? direction,
    VoidCallback? onTap,
    ValueChanged<EditorNode>? onUpdate,
  }) =>
      NodeRenderContext(
        readOnly: readOnly ?? this.readOnly,
        isSelected: isSelected ?? this.isSelected,
        theme: theme ?? this.theme,
        direction: direction ?? this.direction,
        onTap: onTap ?? this.onTap,
        onUpdate: onUpdate ?? this.onUpdate,
      );
}

/// Descriptor for a toolbar/menu item contributed by a plugin.
@immutable
class ToolbarItem {
  final String commandId;
  final String label;
  final IconData? icon;
  final String? tooltip;
  final String group;
  final int order;
  final bool Function(EditorCommandContext context)? isEnabled;
  final bool Function(EditorCommandContext context)? isVisible;

  const ToolbarItem({
    required this.commandId,
    required this.label,
    this.icon,
    this.tooltip,
    required this.group,
    this.order = 0,
    this.isEnabled,
    this.isVisible,
  });
}

/// Descriptor for a keyboard shortcut contributed by a plugin.
@immutable
class ShortcutRegistration {
  final SingleActivator activator;
  final String commandId;
  final Map<String, dynamic>? arguments;

  const ShortcutRegistration({
    required this.activator,
    required this.commandId,
    this.arguments,
  });
}

/// Context used by toolbar item predicates and command factories.
@immutable
class EditorCommandContext {
  final DocumentValue document;
  final EditorSelection selection;
  final bool readOnly;

  const EditorCommandContext({
    required this.document,
    required this.selection,
    required this.readOnly,
  });
}
