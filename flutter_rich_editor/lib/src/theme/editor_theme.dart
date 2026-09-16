import 'package:flutter/material.dart';

/// Immutable design token system controlling every visual attribute of the editor.
@immutable
class EditorTheme {
  const EditorTheme({
    // Canvas & Core Colors
    this.backgroundColor = Colors.white,
    this.textColor = const Color(0xFF1E293B),
    this.cursorColor = const Color(0xFF2563EB),
    this.selectionColor = const Color(0x403B82F6),
    this.placeholderColor = const Color(0xFF94A3B8),
    this.borderColor = const Color(0xFFE2E8F0),
    this.focusBorderColor = const Color(0xFF3B82F6),
    this.contentPadding = const EdgeInsets.all(16.0),
    this.borderRadius = 8.0,

    // Toolbar & Menus
    this.toolbarBackgroundColor = const Color(0xFFF8FAFC),
    this.toolbarBorderColor = const Color(0xFFE2E8F0),
    this.toolbarItemColor = const Color(0xFF475569),
    this.toolbarItemActiveColor = const Color(0xFF2563EB),
    this.toolbarItemActiveBackgroundColor = const Color(0xFFEFF6FF),
    this.toolbarItemHoverColor = const Color(0xFFF1F5F9),
    this.toolbarHeight = 44.0,
    this.toolbarPadding = const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
    this.toolbarBorderRadius = 8.0,
    this.toolbarElevation = 0.0,

    // Typography
    this.heading1Style = const TextStyle(fontSize: 28.0, fontWeight: FontWeight.bold, height: 1.3),
    this.heading2Style = const TextStyle(fontSize: 24.0, fontWeight: FontWeight.bold, height: 1.3),
    this.heading3Style = const TextStyle(fontSize: 20.0, fontWeight: FontWeight.w600, height: 1.3),
    this.heading4Style = const TextStyle(fontSize: 18.0, fontWeight: FontWeight.w600, height: 1.3),
    this.heading5Style = const TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600, height: 1.3),
    this.heading6Style = const TextStyle(fontSize: 14.0, fontWeight: FontWeight.w600, height: 1.3),
    this.bodyStyle = const TextStyle(fontSize: 15.0, height: 1.6, color: Color(0xFF1E293B)),
    this.captionStyle = const TextStyle(fontSize: 12.0, fontStyle: FontStyle.italic, color: Color(0xFF64748B)),

    // Blockquote
    this.blockquoteBorderColor = const Color(0xFFCBD5E1),
    this.blockquoteBackgroundColor = const Color(0xFFF8FAFC),
    this.blockquotePadding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    this.blockquoteTextStyle = const TextStyle(fontSize: 15.0, fontStyle: FontStyle.italic, height: 1.6, color: Color(0xFF334155)),

    // Code Block
    this.codeBlockBackgroundColor = const Color(0xFF0F172A),
    this.codeBlockBorderColor = const Color(0xFF1E293B),
    this.codeBlockTextColor = const Color(0xFFF8FAFC),
    this.codeBlockPadding = const EdgeInsets.all(12.0),
    this.codeBlockBorderRadius = 6.0,
    this.codeBlockTextStyle = const TextStyle(fontFamily: 'monospace', fontSize: 13.0, height: 1.5, color: Color(0xFFF8FAFC)),

    // Tables
    this.tableBorderColor = const Color(0xFFCBD5E1),
    this.tableHeaderBackgroundColor = const Color(0xFFF1F5F9),
    this.tableCellPadding = const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),

    // Divider
    this.hrColor = const Color(0xFFE2E8F0),
    this.hrHeight = 1.0,

    // Links
    this.linkColor = const Color(0xFF2563EB),
    this.linkHoverColor = const Color(0xFF1D4ED8),

    // Media & Video
    this.imageBorderRadius = 8.0,
    this.videoBorderRadius = 8.0,
    this.videoControlsBackgroundColor = const Color(0xCC000000),
    this.uploadProgressColor = const Color(0xFF3B82F6),
    this.uploadErrorColor = const Color(0xFFEF4444),

    // Collaboration & Reviewer
    this.commentHighlightColor = const Color(0x40FCD34D),
    this.commentSidebarBackgroundColor = const Color(0xFFFFFBEB),
    this.trackChangeInsertColor = const Color(0x4022C55E),
    this.trackChangeDeleteColor = const Color(0x40EF4444),

    // Dialogs & Overlays
    this.dialogBackgroundColor = Colors.white,
    this.dialogBorderColor = const Color(0xFFE2E8F0),
    this.dialogTitleStyle = const TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
    this.tooltipBackgroundColor = const Color(0xFF1E293B),
    this.tooltipTextColor = Colors.white,

    // Disabled / Read-Only
    this.readOnlyBackgroundColor = const Color(0xFFFAFAFA),
    this.disabledOpacity = 0.5,
  });

  // Canvas
  final Color backgroundColor;
  final Color textColor;
  final Color cursorColor;
  final Color selectionColor;
  final Color placeholderColor;
  final Color borderColor;
  final Color focusBorderColor;
  final EdgeInsets contentPadding;
  final double borderRadius;

  // Toolbar
  final Color toolbarBackgroundColor;
  final Color toolbarBorderColor;
  final Color toolbarItemColor;
  final Color toolbarItemActiveColor;
  final Color toolbarItemActiveBackgroundColor;
  final Color toolbarItemHoverColor;
  final double toolbarHeight;
  final EdgeInsets toolbarPadding;
  final double toolbarBorderRadius;
  final double toolbarElevation;

  // Typography
  final TextStyle heading1Style;
  final TextStyle heading2Style;
  final TextStyle heading3Style;
  final TextStyle heading4Style;
  final TextStyle heading5Style;
  final TextStyle heading6Style;
  final TextStyle bodyStyle;
  final TextStyle captionStyle;

  // Blockquote
  final Color blockquoteBorderColor;
  final Color blockquoteBackgroundColor;
  final EdgeInsets blockquotePadding;
  final TextStyle blockquoteTextStyle;

  // Code Block
  final Color codeBlockBackgroundColor;
  final Color codeBlockBorderColor;
  final Color codeBlockTextColor;
  final EdgeInsets codeBlockPadding;
  final double codeBlockBorderRadius;
  final TextStyle codeBlockTextStyle;

  // Tables
  final Color tableBorderColor;
  final Color tableHeaderBackgroundColor;
  final EdgeInsets tableCellPadding;

  // Divider
  final Color hrColor;
  final double hrHeight;

  // Links
  final Color linkColor;
  final Color linkHoverColor;

  // Media
  final double imageBorderRadius;
  final double videoBorderRadius;
  final Color videoControlsBackgroundColor;
  final Color uploadProgressColor;
  final Color uploadErrorColor;

  // Collaboration
  final Color commentHighlightColor;
  final Color commentSidebarBackgroundColor;
  final Color trackChangeInsertColor;
  final Color trackChangeDeleteColor;

  // Dialogs
  final Color dialogBackgroundColor;
  final Color dialogBorderColor;
  final TextStyle dialogTitleStyle;
  final Color tooltipBackgroundColor;
  final Color tooltipTextColor;

  // Read-only
  final Color readOnlyBackgroundColor;
  final double disabledOpacity;

  /// Default clean light theme.
  factory EditorTheme.light() => const EditorTheme();

  /// Sleek dark theme.
  factory EditorTheme.dark() {
    return const EditorTheme(
      backgroundColor: Color(0xFF0F172A),
      textColor: Color(0xFFF8FAFC),
      cursorColor: Color(0xFF60A5FA),
      selectionColor: Color(0x4060A5FA),
      placeholderColor: Color(0xFF64748B),
      borderColor: Color(0xFF334155),
      focusBorderColor: Color(0xFF60A5FA),
      toolbarBackgroundColor: Color(0xFF1E293B),
      toolbarBorderColor: Color(0xFF334155),
      toolbarItemColor: Color(0xFF94A3B8),
      toolbarItemActiveColor: Color(0xFF60A5FA),
      toolbarItemActiveBackgroundColor: Color(0xFF1E3A8A),
      toolbarItemHoverColor: Color(0xFF334155),
      bodyStyle: TextStyle(fontSize: 15.0, height: 1.6, color: Color(0xFFF8FAFC)),
      captionStyle: TextStyle(fontSize: 12.0, fontStyle: FontStyle.italic, color: Color(0xFF94A3B8)),
      blockquoteBorderColor: Color(0xFF475569),
      blockquoteBackgroundColor: Color(0xFF1E293B),
      blockquoteTextStyle: TextStyle(fontSize: 15.0, fontStyle: FontStyle.italic, height: 1.6, color: Color(0xFFCBD5E1)),
      codeBlockBackgroundColor: Color(0xFF020617),
      codeBlockBorderColor: Color(0xFF1E293B),
      tableBorderColor: Color(0xFF334155),
      tableHeaderBackgroundColor: Color(0xFF1E293B),
      hrColor: Color(0xFF334155),
      linkColor: Color(0xFF60A5FA),
      linkHoverColor: Color(0xFF93C5FD),
      readOnlyBackgroundColor: Color(0xFF090D16),
      dialogBackgroundColor: Color(0xFF1E293B),
      dialogBorderColor: Color(0xFF334155),
      dialogTitleStyle: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: Colors.white),
    );
  }

  /// Whether this theme represents a dark theme.
  bool get isDark => backgroundColor.computeLuminance() < 0.5;

  /// Derives an [EditorTheme] matching the host app's [ThemeData].
  factory EditorTheme.fromThemeData(ThemeData theme) {
    final bool isDark = theme.brightness == Brightness.dark;
    final Color primary = theme.colorScheme.primary;

    return EditorTheme(
      backgroundColor: theme.colorScheme.surface,
      textColor: theme.colorScheme.onSurface,
      cursorColor: primary,
      selectionColor: primary.withValues(alpha: 0.3),
      borderColor: theme.dividerColor,
      focusBorderColor: primary,
      toolbarBackgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
      toolbarBorderColor: theme.dividerColor,
      toolbarItemColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
      toolbarItemActiveColor: primary,
      toolbarItemActiveBackgroundColor: primary.withValues(alpha: 0.15),
      bodyStyle: TextStyle(fontSize: 15.0, height: 1.6, color: theme.colorScheme.onSurface),
      dialogBackgroundColor: theme.dialogTheme.backgroundColor ?? theme.colorScheme.surface,
    );
  }

  /// Copies this theme with token overrides.
  EditorTheme copyWith({
    Color? backgroundColor,
    Color? textColor,
    Color? cursorColor,
    Color? selectionColor,
    Color? placeholderColor,
    Color? borderColor,
    Color? focusBorderColor,
    EdgeInsets? contentPadding,
    double? borderRadius,
    Color? toolbarBackgroundColor,
    Color? toolbarBorderColor,
    Color? toolbarItemColor,
    Color? toolbarItemActiveColor,
    Color? toolbarItemActiveBackgroundColor,
    Color? toolbarItemHoverColor,
    double? toolbarHeight,
    EdgeInsets? toolbarPadding,
    double? toolbarBorderRadius,
    double? toolbarElevation,
    TextStyle? heading1Style,
    TextStyle? heading2Style,
    TextStyle? heading3Style,
    TextStyle? heading4Style,
    TextStyle? heading5Style,
    TextStyle? heading6Style,
    TextStyle? bodyStyle,
    TextStyle? captionStyle,
    Color? blockquoteBorderColor,
    Color? blockquoteBackgroundColor,
    EdgeInsets? blockquotePadding,
    TextStyle? blockquoteTextStyle,
    Color? codeBlockBackgroundColor,
    Color? codeBlockBorderColor,
    Color? codeBlockTextColor,
    EdgeInsets? codeBlockPadding,
    double? codeBlockBorderRadius,
    TextStyle? codeBlockTextStyle,
    Color? tableBorderColor,
    Color? tableHeaderBackgroundColor,
    EdgeInsets? tableCellPadding,
    Color? hrColor,
    double? hrHeight,
    Color? linkColor,
    Color? linkHoverColor,
    double? imageBorderRadius,
    double? videoBorderRadius,
    Color? videoControlsBackgroundColor,
    Color? uploadProgressColor,
    Color? uploadErrorColor,
    Color? commentHighlightColor,
    Color? commentSidebarBackgroundColor,
    Color? trackChangeInsertColor,
    Color? trackChangeDeleteColor,
    Color? dialogBackgroundColor,
    Color? dialogBorderColor,
    TextStyle? dialogTitleStyle,
    Color? tooltipBackgroundColor,
    Color? tooltipTextColor,
    Color? readOnlyBackgroundColor,
    double? disabledOpacity,
  }) {
    return EditorTheme(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      cursorColor: cursorColor ?? this.cursorColor,
      selectionColor: selectionColor ?? this.selectionColor,
      placeholderColor: placeholderColor ?? this.placeholderColor,
      borderColor: borderColor ?? this.borderColor,
      focusBorderColor: focusBorderColor ?? this.focusBorderColor,
      contentPadding: contentPadding ?? this.contentPadding,
      borderRadius: borderRadius ?? this.borderRadius,
      toolbarBackgroundColor: toolbarBackgroundColor ?? this.toolbarBackgroundColor,
      toolbarBorderColor: toolbarBorderColor ?? this.toolbarBorderColor,
      toolbarItemColor: toolbarItemColor ?? this.toolbarItemColor,
      toolbarItemActiveColor: toolbarItemActiveColor ?? this.toolbarItemActiveColor,
      toolbarItemActiveBackgroundColor:
          toolbarItemActiveBackgroundColor ?? this.toolbarItemActiveBackgroundColor,
      toolbarItemHoverColor: toolbarItemHoverColor ?? this.toolbarItemHoverColor,
      toolbarHeight: toolbarHeight ?? this.toolbarHeight,
      toolbarPadding: toolbarPadding ?? this.toolbarPadding,
      toolbarBorderRadius: toolbarBorderRadius ?? this.toolbarBorderRadius,
      toolbarElevation: toolbarElevation ?? this.toolbarElevation,
      heading1Style: heading1Style ?? this.heading1Style,
      heading2Style: heading2Style ?? this.heading2Style,
      heading3Style: heading3Style ?? this.heading3Style,
      heading4Style: heading4Style ?? this.heading4Style,
      heading5Style: heading5Style ?? this.heading5Style,
      heading6Style: heading6Style ?? this.heading6Style,
      bodyStyle: bodyStyle ?? this.bodyStyle,
      captionStyle: captionStyle ?? this.captionStyle,
      blockquoteBorderColor: blockquoteBorderColor ?? this.blockquoteBorderColor,
      blockquoteBackgroundColor: blockquoteBackgroundColor ?? this.blockquoteBackgroundColor,
      blockquotePadding: blockquotePadding ?? this.blockquotePadding,
      blockquoteTextStyle: blockquoteTextStyle ?? this.blockquoteTextStyle,
      codeBlockBackgroundColor: codeBlockBackgroundColor ?? this.codeBlockBackgroundColor,
      codeBlockBorderColor: codeBlockBorderColor ?? this.codeBlockBorderColor,
      codeBlockTextColor: codeBlockTextColor ?? this.codeBlockTextColor,
      codeBlockPadding: codeBlockPadding ?? this.codeBlockPadding,
      codeBlockBorderRadius: codeBlockBorderRadius ?? this.codeBlockBorderRadius,
      codeBlockTextStyle: codeBlockTextStyle ?? this.codeBlockTextStyle,
      tableBorderColor: tableBorderColor ?? this.tableBorderColor,
      tableHeaderBackgroundColor: tableHeaderBackgroundColor ?? this.tableHeaderBackgroundColor,
      tableCellPadding: tableCellPadding ?? this.tableCellPadding,
      hrColor: hrColor ?? this.hrColor,
      hrHeight: hrHeight ?? this.hrHeight,
      linkColor: linkColor ?? this.linkColor,
      linkHoverColor: linkHoverColor ?? this.linkHoverColor,
      imageBorderRadius: imageBorderRadius ?? this.imageBorderRadius,
      videoBorderRadius: videoBorderRadius ?? this.videoBorderRadius,
      videoControlsBackgroundColor:
          videoControlsBackgroundColor ?? this.videoControlsBackgroundColor,
      uploadProgressColor: uploadProgressColor ?? this.uploadProgressColor,
      uploadErrorColor: uploadErrorColor ?? this.uploadErrorColor,
      commentHighlightColor: commentHighlightColor ?? this.commentHighlightColor,
      commentSidebarBackgroundColor:
          commentSidebarBackgroundColor ?? this.commentSidebarBackgroundColor,
      trackChangeInsertColor: trackChangeInsertColor ?? this.trackChangeInsertColor,
      trackChangeDeleteColor: trackChangeDeleteColor ?? this.trackChangeDeleteColor,
      dialogBackgroundColor: dialogBackgroundColor ?? this.dialogBackgroundColor,
      dialogBorderColor: dialogBorderColor ?? this.dialogBorderColor,
      dialogTitleStyle: dialogTitleStyle ?? this.dialogTitleStyle,
      tooltipBackgroundColor: tooltipBackgroundColor ?? this.tooltipBackgroundColor,
      tooltipTextColor: tooltipTextColor ?? this.tooltipTextColor,
      readOnlyBackgroundColor: readOnlyBackgroundColor ?? this.readOnlyBackgroundColor,
      disabledOpacity: disabledOpacity ?? this.disabledOpacity,
    );
  }

  /// Merges overrides from [other] into this theme.
  EditorTheme merge(EditorTheme? other) {
    if (other == null) return this;
    return copyWith(
      backgroundColor: other.backgroundColor != const Color(0xFFFFFFFF) ? other.backgroundColor : null,
      textColor: other.textColor,
      cursorColor: other.cursorColor,
      selectionColor: other.selectionColor,
      placeholderColor: other.placeholderColor,
      borderColor: other.borderColor,
      focusBorderColor: other.focusBorderColor,
      toolbarBackgroundColor: other.toolbarBackgroundColor,
      toolbarBorderColor: other.toolbarBorderColor,
      toolbarItemColor: other.toolbarItemColor,
      toolbarItemActiveColor: other.toolbarItemActiveColor,
      toolbarItemActiveBackgroundColor: other.toolbarItemActiveBackgroundColor,
      bodyStyle: other.bodyStyle,
      blockquoteBorderColor: other.blockquoteBorderColor,
      blockquoteBackgroundColor: other.blockquoteBackgroundColor,
      codeBlockBackgroundColor: other.codeBlockBackgroundColor,
      tableBorderColor: other.tableBorderColor,
      hrColor: other.hrColor,
      linkColor: other.linkColor,
      dialogBackgroundColor: other.dialogBackgroundColor,
    );
  }
}
