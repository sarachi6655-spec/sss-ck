import 'package:flutter/material.dart';

/// Position of the toolbar relative to the editor canvas.
enum ToolbarPosition {
  top,
  bottom,
  none,
}

/// Operational configuration for [RichEditor].
@immutable
class EditorConfig {
  const EditorConfig({
    this.readOnly = false,
    this.placeholder = 'Write something wonderful...',
    this.autoFocus = false,
    this.showToolbar = true,
    this.toolbarPosition = ToolbarPosition.top,
    this.enableWatchdog = true,
    this.showStatusBar = true,
  });

  final bool readOnly;
  final String placeholder;
  final bool autoFocus;
  final bool showToolbar;
  final ToolbarPosition toolbarPosition;
  final bool enableWatchdog;
  final bool showStatusBar;

  EditorConfig copyWith({
    bool? readOnly,
    String? placeholder,
    bool? autoFocus,
    bool? showToolbar,
    ToolbarPosition? toolbarPosition,
    bool? enableWatchdog,
    bool? showStatusBar,
  }) {
    return EditorConfig(
      readOnly: readOnly ?? this.readOnly,
      placeholder: placeholder ?? this.placeholder,
      autoFocus: autoFocus ?? this.autoFocus,
      showToolbar: showToolbar ?? this.showToolbar,
      toolbarPosition: toolbarPosition ?? this.toolbarPosition,
      enableWatchdog: enableWatchdog ?? this.enableWatchdog,
      showStatusBar: showStatusBar ?? this.showStatusBar,
    );
  }
}
