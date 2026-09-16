import 'package:flutter/material.dart';
import 'editor_theme.dart';

/// Top-level configuration theme data wrapper for the editor.
@immutable
class EditorThemeData {
  const EditorThemeData({
    required this.theme,
  });

  final EditorTheme theme;

  factory EditorThemeData.light() => EditorThemeData(theme: EditorTheme.light());
  factory EditorThemeData.dark() => EditorThemeData(theme: EditorTheme.dark());
  factory EditorThemeData.fromThemeData(ThemeData theme) =>
      EditorThemeData(theme: EditorTheme.fromThemeData(theme));

  EditorThemeData copyWith({EditorTheme? theme}) {
    return EditorThemeData(theme: theme ?? this.theme);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorThemeData &&
          runtimeType == other.runtimeType &&
          theme == other.theme;

  @override
  int get hashCode => theme.hashCode;
}
