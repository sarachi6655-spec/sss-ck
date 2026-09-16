import 'package:flutter/material.dart';
import '../core/controller/rich_editor_controller.dart';
import '../core/document_model/document_value.dart';
import '../theme/editor_theme.dart';

/// An individual interactive button or action on the editor toolbar.
class ToolbarItem {
  const ToolbarItem({
    required this.id,
    required this.icon,
    required this.label,
    this.tooltip,
    this.commandId,
    this.isActive,
    this.isEnabled,
    this.onTap,
    this.customWidget,
  });

  final String id;
  final IconData icon;
  final String label;
  final String? tooltip;
  final String? commandId;
  final bool Function(DocumentValue)? isActive;
  final bool Function(DocumentValue)? isEnabled;
  final void Function(RichEditorController)? onTap;
  final Widget Function(BuildContext context, RichEditorController controller, EditorTheme theme)?
      customWidget;

  ToolbarItem copyWith({
    String? id,
    IconData? icon,
    String? label,
    String? tooltip,
    String? commandId,
    bool Function(DocumentValue)? isActive,
    bool Function(DocumentValue)? isEnabled,
    void Function(RichEditorController)? onTap,
    Widget Function(BuildContext context, RichEditorController controller, EditorTheme theme)?
        customWidget,
  }) {
    return ToolbarItem(
      id: id ?? this.id,
      icon: icon ?? this.icon,
      label: label ?? this.label,
      tooltip: tooltip ?? this.tooltip,
      commandId: commandId ?? this.commandId,
      isActive: isActive ?? this.isActive,
      isEnabled: isEnabled ?? this.isEnabled,
      onTap: onTap ?? this.onTap,
      customWidget: customWidget ?? this.customWidget,
    );
  }
}
