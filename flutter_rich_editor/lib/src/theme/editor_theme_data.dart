import 'package:flutter/material.dart';

/// Base theme data contract used by the plugin system and document model.
///
/// The full [EditorTheme] implementation lives in `editor_theme.dart` in this
/// folder and adds every token required by the editor surfaces. This base
/// class keeps the core layer free of theme details while allowing plugins to
/// depend on a stable contract.
abstract class EditorThemeData {
  Color get backgroundColor;
  Color get surfaceColor;
  Color get foregroundColor;
  Color get disabledColor;
  Color get selectionColor;
  Color get cursorColor;
  TextStyle get paragraphStyle;
  TextStyle get toolbarStyle;
  double get spacingUnit;
  double get borderRadius;
}
