import 'package:flutter/material.dart';

import 'editor_theme_data.dart';

/// Immutable theme token set for every editor surface.
///
/// Host applications can override any token via [copyWith] or [merge]. No
/// built-in editor widget may use a hard-coded color, text style, spacing, or
/// radius when a token exists.
@immutable
class EditorTheme extends EditorThemeData {
  // Surface
  @override
  final Color backgroundColor;
  @override
  final Color surfaceColor;
  @override
  final Color foregroundColor;
  @override
  final Color disabledColor;
  @override
  final Color selectionColor;
  @override
  final Color cursorColor;

  // Borders / dividers
  final Color borderColor;
  final Color dividerColor;
  final Color focusBorderColor;
  final double borderWidth;
  final double focusedBorderWidth;

  // Placeholder / states
  final Color placeholderColor;
  final Color readOnlyBackgroundColor;
  final Color errorColor;
  final Color warningColor;
  final Color successColor;

  // Toolbar / menu
  @override
  final TextStyle toolbarStyle;
  final Color toolbarBackgroundColor;
  final Color toolbarForegroundColor;
  final Color toolbarHoverColor;
  final Color toolbarSelectedColor;
  final Color toolbarDisabledColor;
  final Color toolbarBorderColor;
  final double toolbarHeight;
  final double toolbarIconSize;
  final double toolbarSpacing;

  // Typography
  final TextStyle titleStyle;
  @override
  final TextStyle paragraphStyle;
  final TextStyle heading1Style;
  final TextStyle heading2Style;
  final TextStyle heading3Style;
  final TextStyle heading4Style;
  final TextStyle heading5Style;
  final TextStyle heading6Style;
  final TextStyle quoteStyle;
  final TextStyle codeStyle;
  final TextStyle captionStyle;

  // Spacing / shape
  @override
  final double spacingUnit;
  final double paragraphSpacing;
  final double blockSpacing;
  @override
  final double borderRadius;
  final double smallRadius;
  final double dialogRadius;

  // Elevations
  final double toolbarElevation;
  final double menuElevation;
  final double dialogElevation;

  // Icons
  final IconThemeData iconTheme;

  // Density
  final EdgeInsets contentPadding;
  final EdgeInsets toolbarPadding;
  final EdgeInsets menuPadding;

  // Feature-specific
  final Color linkColor;
  final Color linkHoverColor;
  final Color codeBlockBackgroundColor;
  final Color codeBlockBorderColor;
  final Color quoteBorderColor;
  final Color quoteBackgroundColor;
  final Color tableBorderColor;
  final Color tableHeaderBackgroundColor;
  final Color tableCellBackgroundColor;
  final Color imagePlaceholderColor;
  final Color videoPosterBackgroundColor;
  final Color uploadProgressColor;
  final Color uploadErrorColor;
  final Color commentBackgroundColor;
  final Color suggestionAddColor;
  final Color suggestionRemoveColor;

  const EditorTheme({
    required this.backgroundColor,
    required this.surfaceColor,
    required this.foregroundColor,
    required this.disabledColor,
    required this.selectionColor,
    required this.cursorColor,
    required this.borderColor,
    required this.dividerColor,
    required this.focusBorderColor,
    required this.borderWidth,
    required this.focusedBorderWidth,
    required this.placeholderColor,
    required this.readOnlyBackgroundColor,
    required this.errorColor,
    required this.warningColor,
    required this.successColor,
    required this.toolbarStyle,
    required this.toolbarBackgroundColor,
    required this.toolbarForegroundColor,
    required this.toolbarHoverColor,
    required this.toolbarSelectedColor,
    required this.toolbarDisabledColor,
    required this.toolbarBorderColor,
    required this.toolbarHeight,
    required this.toolbarIconSize,
    required this.toolbarSpacing,
    required this.titleStyle,
    required this.paragraphStyle,
    required this.heading1Style,
    required this.heading2Style,
    required this.heading3Style,
    required this.heading4Style,
    required this.heading5Style,
    required this.heading6Style,
    required this.quoteStyle,
    required this.codeStyle,
    required this.captionStyle,
    required this.spacingUnit,
    required this.paragraphSpacing,
    required this.blockSpacing,
    required this.borderRadius,
    required this.smallRadius,
    required this.dialogRadius,
    required this.toolbarElevation,
    required this.menuElevation,
    required this.dialogElevation,
    required this.iconTheme,
    required this.contentPadding,
    required this.toolbarPadding,
    required this.menuPadding,
    required this.linkColor,
    required this.linkHoverColor,
    required this.codeBlockBackgroundColor,
    required this.codeBlockBorderColor,
    required this.quoteBorderColor,
    required this.quoteBackgroundColor,
    required this.tableBorderColor,
    required this.tableHeaderBackgroundColor,
    required this.tableCellBackgroundColor,
    required this.imagePlaceholderColor,
    required this.videoPosterBackgroundColor,
    required this.uploadProgressColor,
    required this.uploadErrorColor,
    required this.commentBackgroundColor,
    required this.suggestionAddColor,
    required this.suggestionRemoveColor,
  });

  factory EditorTheme.light({TextTheme? textTheme}) {
    final TextTheme base = textTheme ?? Typography.material2021().black;
    const Color primary = Color(0xFF1976D2);
    const Color onSurface = Color(0xFF1F1F1F);
    const Color surface = Color(0xFFFFFFFF);
    const Color background = Color(0xFFF5F5F5);
    const TextStyle baseStyle = TextStyle(fontSize: 16, color: onSurface);
    return EditorTheme(
      backgroundColor: background,
      surfaceColor: surface,
      foregroundColor: onSurface,
      disabledColor: const Color(0xFFBDBDBD),
      selectionColor: primary.withOpacity(0.3),
      cursorColor: primary,
      borderColor: const Color(0xFFE0E0E0),
      dividerColor: const Color(0xFFE0E0E0),
      focusBorderColor: primary,
      borderWidth: 1,
      focusedBorderWidth: 2,
      placeholderColor: const Color(0xFF9E9E9E),
      readOnlyBackgroundColor: const Color(0xFFEEEEEE),
      errorColor: const Color(0xFFD32F2F),
      warningColor: const Color(0xFFF57C00),
      successColor: const Color(0xFF388E3C),
      toolbarStyle: base.labelMedium ?? baseStyle,
      toolbarBackgroundColor: surface,
      toolbarForegroundColor: onSurface,
      toolbarHoverColor: const Color(0xFFEEEEEE),
      toolbarSelectedColor: primary.withOpacity(0.15),
      toolbarDisabledColor: const Color(0xFFBDBDBD),
      toolbarBorderColor: const Color(0xFFE0E0E0),
      toolbarHeight: 48,
      toolbarIconSize: 20,
      toolbarSpacing: 4,
      titleStyle: base.titleLarge ?? baseStyle,
      paragraphStyle: base.bodyLarge ?? baseStyle,
      heading1Style: (base.displaySmall ?? baseStyle).copyWith(fontSize: 32),
      heading2Style: (base.headlineMedium ?? baseStyle).copyWith(fontSize: 28),
      heading3Style: (base.headlineSmall ?? baseStyle).copyWith(fontSize: 24),
      heading4Style: (base.titleLarge ?? baseStyle).copyWith(fontSize: 20),
      heading5Style: (base.titleMedium ?? baseStyle).copyWith(fontSize: 18),
      heading6Style: (base.titleSmall ?? baseStyle).copyWith(fontSize: 16),
      quoteStyle: (base.bodyLarge ?? baseStyle)
          .copyWith(fontStyle: FontStyle.italic, color: Color(0xFF616161)),
      codeStyle: base.bodyMedium?.copyWith(fontFamily: 'monospace') ??
          baseStyle.copyWith(fontFamily: 'monospace'),
      captionStyle: (base.bodySmall ?? baseStyle).copyWith(color: Color(0xFF757575)),
      spacingUnit: 8,
      paragraphSpacing: 12,
      blockSpacing: 16,
      borderRadius: 8,
      smallRadius: 4,
      dialogRadius: 12,
      toolbarElevation: 2,
      menuElevation: 4,
      dialogElevation: 8,
      iconTheme: const IconThemeData(color: onSurface, size: 20),
      contentPadding: const EdgeInsets.all(16),
      toolbarPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      menuPadding: const EdgeInsets.symmetric(vertical: 8),
      linkColor: primary,
      linkHoverColor: const Color(0xFF0D47A1),
      codeBlockBackgroundColor: const Color(0xFFF5F5F5),
      codeBlockBorderColor: const Color(0xFFE0E0E0),
      quoteBorderColor: const Color(0xFFE0E0E0),
      quoteBackgroundColor: const Color(0xFFF5F5F5),
      tableBorderColor: const Color(0xFFBDBDBD),
      tableHeaderBackgroundColor: const Color(0xFFEEEEEE),
      tableCellBackgroundColor: surface,
      imagePlaceholderColor: const Color(0xFFE0E0E0),
      videoPosterBackgroundColor: const Color(0xFF212121),
      uploadProgressColor: primary,
      uploadErrorColor: const Color(0xFFD32F2F),
      commentBackgroundColor: const Color(0xFFFFF9C4),
      suggestionAddColor: const Color(0xFFC8E6C9),
      suggestionRemoveColor: const Color(0xFFFFCDD2),
    );
  }

  factory EditorTheme.dark({TextTheme? textTheme}) {
    final TextTheme base = textTheme ?? Typography.material2021().white;
    const Color primary = Color(0xFF90CAF9);
    const Color onSurface = Color(0xFFE0E0E0);
    const Color surface = Color(0xFF1E1E1E);
    const Color background = Color(0xFF121212);
    const TextStyle baseStyle = TextStyle(fontSize: 16, color: onSurface);
    return EditorTheme(
      backgroundColor: background,
      surfaceColor: surface,
      foregroundColor: onSurface,
      disabledColor: const Color(0xFF616161),
      selectionColor: primary.withOpacity(0.3),
      cursorColor: primary,
      borderColor: const Color(0xFF424242),
      dividerColor: const Color(0xFF424242),
      focusBorderColor: primary,
      borderWidth: 1,
      focusedBorderWidth: 2,
      placeholderColor: const Color(0xFF757575),
      readOnlyBackgroundColor: const Color(0xFF1E1E1E),
      errorColor: const Color(0xFFEF5350),
      warningColor: const Color(0xFFFFA726),
      successColor: const Color(0xFF66BB6A),
      toolbarStyle: base.labelMedium ?? baseStyle,
      toolbarBackgroundColor: surface,
      toolbarForegroundColor: onSurface,
      toolbarHoverColor: const Color(0xFF2C2C2C),
      toolbarSelectedColor: primary.withOpacity(0.15),
      toolbarDisabledColor: const Color(0xFF616161),
      toolbarBorderColor: const Color(0xFF424242),
      toolbarHeight: 48,
      toolbarIconSize: 20,
      toolbarSpacing: 4,
      titleStyle: base.titleLarge ?? baseStyle,
      paragraphStyle: base.bodyLarge ?? baseStyle,
      heading1Style: (base.displaySmall ?? baseStyle).copyWith(fontSize: 32),
      heading2Style: (base.headlineMedium ?? baseStyle).copyWith(fontSize: 28),
      heading3Style: (base.headlineSmall ?? baseStyle).copyWith(fontSize: 24),
      heading4Style: (base.titleLarge ?? baseStyle).copyWith(fontSize: 20),
      heading5Style: (base.titleMedium ?? baseStyle).copyWith(fontSize: 18),
      heading6Style: (base.titleSmall ?? baseStyle).copyWith(fontSize: 16),
      quoteStyle: (base.bodyLarge ?? baseStyle)
          .copyWith(fontStyle: FontStyle.italic, color: Color(0xFFBDBDBD)),
      codeStyle: base.bodyMedium?.copyWith(fontFamily: 'monospace') ??
          baseStyle.copyWith(fontFamily: 'monospace'),
      captionStyle: (base.bodySmall ?? baseStyle).copyWith(color: Color(0xFF9E9E9E)),
      spacingUnit: 8,
      paragraphSpacing: 12,
      blockSpacing: 16,
      borderRadius: 8,
      smallRadius: 4,
      dialogRadius: 12,
      toolbarElevation: 2,
      menuElevation: 4,
      dialogElevation: 8,
      iconTheme: const IconThemeData(color: onSurface, size: 20),
      contentPadding: const EdgeInsets.all(16),
      toolbarPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      menuPadding: const EdgeInsets.symmetric(vertical: 8),
      linkColor: primary,
      linkHoverColor: const Color(0xFFBBDEFB),
      codeBlockBackgroundColor: const Color(0xFF2C2C2C),
      codeBlockBorderColor: const Color(0xFF424242),
      quoteBorderColor: const Color(0xFF424242),
      quoteBackgroundColor: const Color(0xFF1E1E1E),
      tableBorderColor: const Color(0xFF616161),
      tableHeaderBackgroundColor: const Color(0xFF2C2C2C),
      tableCellBackgroundColor: surface,
      imagePlaceholderColor: const Color(0xFF424242),
      videoPosterBackgroundColor: const Color(0xFF000000),
      uploadProgressColor: primary,
      uploadErrorColor: const Color(0xFFEF5350),
      commentBackgroundColor: const Color(0xFF3E3B26),
      suggestionAddColor: const Color(0xFF2E4C33),
      suggestionRemoveColor: const Color(0xFF4C2E2E),
    );
  }

  /// Merge another [EditorTheme] on top of this one, overriding only non-null
  /// fields.
  EditorTheme merge(EditorTheme? other) {
    if (other == null) return this;
    return copyWith(
      backgroundColor: other.backgroundColor,
      surfaceColor: other.surfaceColor,
      foregroundColor: other.foregroundColor,
      disabledColor: other.disabledColor,
      selectionColor: other.selectionColor,
      cursorColor: other.cursorColor,
      borderColor: other.borderColor,
      dividerColor: other.dividerColor,
      focusBorderColor: other.focusBorderColor,
      borderWidth: other.borderWidth,
      focusedBorderWidth: other.focusedBorderWidth,
      placeholderColor: other.placeholderColor,
      readOnlyBackgroundColor: other.readOnlyBackgroundColor,
      errorColor: other.errorColor,
      warningColor: other.warningColor,
      successColor: other.successColor,
      toolbarStyle: other.toolbarStyle,
      toolbarBackgroundColor: other.toolbarBackgroundColor,
      toolbarForegroundColor: other.toolbarForegroundColor,
      toolbarHoverColor: other.toolbarHoverColor,
      toolbarSelectedColor: other.toolbarSelectedColor,
      toolbarDisabledColor: other.toolbarDisabledColor,
      toolbarBorderColor: other.toolbarBorderColor,
      toolbarHeight: other.toolbarHeight,
      toolbarIconSize: other.toolbarIconSize,
      toolbarSpacing: other.toolbarSpacing,
      titleStyle: other.titleStyle,
      paragraphStyle: other.paragraphStyle,
      heading1Style: other.heading1Style,
      heading2Style: other.heading2Style,
      heading3Style: other.heading3Style,
      heading4Style: other.heading4Style,
      heading5Style: other.heading5Style,
      heading6Style: other.heading6Style,
      quoteStyle: other.quoteStyle,
      codeStyle: other.codeStyle,
      captionStyle: other.captionStyle,
      spacingUnit: other.spacingUnit,
      paragraphSpacing: other.paragraphSpacing,
      blockSpacing: other.blockSpacing,
      borderRadius: other.borderRadius,
      smallRadius: other.smallRadius,
      dialogRadius: other.dialogRadius,
      toolbarElevation: other.toolbarElevation,
      menuElevation: other.menuElevation,
      dialogElevation: other.dialogElevation,
      iconTheme: other.iconTheme,
      contentPadding: other.contentPadding,
      toolbarPadding: other.toolbarPadding,
      menuPadding: other.menuPadding,
      linkColor: other.linkColor,
      linkHoverColor: other.linkHoverColor,
      codeBlockBackgroundColor: other.codeBlockBackgroundColor,
      codeBlockBorderColor: other.codeBlockBorderColor,
      quoteBorderColor: other.quoteBorderColor,
      quoteBackgroundColor: other.quoteBackgroundColor,
      tableBorderColor: other.tableBorderColor,
      tableHeaderBackgroundColor: other.tableHeaderBackgroundColor,
      tableCellBackgroundColor: other.tableCellBackgroundColor,
      imagePlaceholderColor: other.imagePlaceholderColor,
      videoPosterBackgroundColor: other.videoPosterBackgroundColor,
      uploadProgressColor: other.uploadProgressColor,
      uploadErrorColor: other.uploadErrorColor,
      commentBackgroundColor: other.commentBackgroundColor,
      suggestionAddColor: other.suggestionAddColor,
      suggestionRemoveColor: other.suggestionRemoveColor,
    );
  }

  EditorTheme copyWith({
    Color? backgroundColor,
    Color? surfaceColor,
    Color? foregroundColor,
    Color? disabledColor,
    Color? selectionColor,
    Color? cursorColor,
    Color? borderColor,
    Color? dividerColor,
    Color? focusBorderColor,
    double? borderWidth,
    double? focusedBorderWidth,
    Color? placeholderColor,
    Color? readOnlyBackgroundColor,
    Color? errorColor,
    Color? warningColor,
    Color? successColor,
    TextStyle? toolbarStyle,
    Color? toolbarBackgroundColor,
    Color? toolbarForegroundColor,
    Color? toolbarHoverColor,
    Color? toolbarSelectedColor,
    Color? toolbarDisabledColor,
    Color? toolbarBorderColor,
    double? toolbarHeight,
    double? toolbarIconSize,
    double? toolbarSpacing,
    TextStyle? titleStyle,
    TextStyle? paragraphStyle,
    TextStyle? heading1Style,
    TextStyle? heading2Style,
    TextStyle? heading3Style,
    TextStyle? heading4Style,
    TextStyle? heading5Style,
    TextStyle? heading6Style,
    TextStyle? quoteStyle,
    TextStyle? codeStyle,
    TextStyle? captionStyle,
    double? spacingUnit,
    double? paragraphSpacing,
    double? blockSpacing,
    double? borderRadius,
    double? smallRadius,
    double? dialogRadius,
    double? toolbarElevation,
    double? menuElevation,
    double? dialogElevation,
    IconThemeData? iconTheme,
    EdgeInsets? contentPadding,
    EdgeInsets? toolbarPadding,
    EdgeInsets? menuPadding,
    Color? linkColor,
    Color? linkHoverColor,
    Color? codeBlockBackgroundColor,
    Color? codeBlockBorderColor,
    Color? quoteBorderColor,
    Color? quoteBackgroundColor,
    Color? tableBorderColor,
    Color? tableHeaderBackgroundColor,
    Color? tableCellBackgroundColor,
    Color? imagePlaceholderColor,
    Color? videoPosterBackgroundColor,
    Color? uploadProgressColor,
    Color? uploadErrorColor,
    Color? commentBackgroundColor,
    Color? suggestionAddColor,
    Color? suggestionRemoveColor,
  }) =>
      EditorTheme(
        backgroundColor: backgroundColor ?? this.backgroundColor,
        surfaceColor: surfaceColor ?? this.surfaceColor,
        foregroundColor: foregroundColor ?? this.foregroundColor,
        disabledColor: disabledColor ?? this.disabledColor,
        selectionColor: selectionColor ?? this.selectionColor,
        cursorColor: cursorColor ?? this.cursorColor,
        borderColor: borderColor ?? this.borderColor,
        dividerColor: dividerColor ?? this.dividerColor,
        focusBorderColor: focusBorderColor ?? this.focusBorderColor,
        borderWidth: borderWidth ?? this.borderWidth,
        focusedBorderWidth: focusedBorderWidth ?? this.focusedBorderWidth,
        placeholderColor: placeholderColor ?? this.placeholderColor,
        readOnlyBackgroundColor:
            readOnlyBackgroundColor ?? this.readOnlyBackgroundColor,
        errorColor: errorColor ?? this.errorColor,
        warningColor: warningColor ?? this.warningColor,
        successColor: successColor ?? this.successColor,
        toolbarStyle: toolbarStyle ?? this.toolbarStyle,
        toolbarBackgroundColor:
            toolbarBackgroundColor ?? this.toolbarBackgroundColor,
        toolbarForegroundColor:
            toolbarForegroundColor ?? this.toolbarForegroundColor,
        toolbarHoverColor: toolbarHoverColor ?? this.toolbarHoverColor,
        toolbarSelectedColor:
            toolbarSelectedColor ?? this.toolbarSelectedColor,
        toolbarDisabledColor: toolbarDisabledColor ?? this.toolbarDisabledColor,
        toolbarBorderColor: toolbarBorderColor ?? this.toolbarBorderColor,
        toolbarHeight: toolbarHeight ?? this.toolbarHeight,
        toolbarIconSize: toolbarIconSize ?? this.toolbarIconSize,
        toolbarSpacing: toolbarSpacing ?? this.toolbarSpacing,
        titleStyle: titleStyle ?? this.titleStyle,
        paragraphStyle: paragraphStyle ?? this.paragraphStyle,
        heading1Style: heading1Style ?? this.heading1Style,
        heading2Style: heading2Style ?? this.heading2Style,
        heading3Style: heading3Style ?? this.heading3Style,
        heading4Style: heading4Style ?? this.heading4Style,
        heading5Style: heading5Style ?? this.heading5Style,
        heading6Style: heading6Style ?? this.heading6Style,
        quoteStyle: quoteStyle ?? this.quoteStyle,
        codeStyle: codeStyle ?? this.codeStyle,
        captionStyle: captionStyle ?? this.captionStyle,
        spacingUnit: spacingUnit ?? this.spacingUnit,
        paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
        blockSpacing: blockSpacing ?? this.blockSpacing,
        borderRadius: borderRadius ?? this.borderRadius,
        smallRadius: smallRadius ?? this.smallRadius,
        dialogRadius: dialogRadius ?? this.dialogRadius,
        toolbarElevation: toolbarElevation ?? this.toolbarElevation,
        menuElevation: menuElevation ?? this.menuElevation,
        dialogElevation: dialogElevation ?? this.dialogElevation,
        iconTheme: iconTheme ?? this.iconTheme,
        contentPadding: contentPadding ?? this.contentPadding,
        toolbarPadding: toolbarPadding ?? this.toolbarPadding,
        menuPadding: menuPadding ?? this.menuPadding,
        linkColor: linkColor ?? this.linkColor,
        linkHoverColor: linkHoverColor ?? this.linkHoverColor,
        codeBlockBackgroundColor:
            codeBlockBackgroundColor ?? this.codeBlockBackgroundColor,
        codeBlockBorderColor: codeBlockBorderColor ?? this.codeBlockBorderColor,
        quoteBorderColor: quoteBorderColor ?? this.quoteBorderColor,
        quoteBackgroundColor: quoteBackgroundColor ?? this.quoteBackgroundColor,
        tableBorderColor: tableBorderColor ?? this.tableBorderColor,
        tableHeaderBackgroundColor:
            tableHeaderBackgroundColor ?? this.tableHeaderBackgroundColor,
        tableCellBackgroundColor:
            tableCellBackgroundColor ?? this.tableCellBackgroundColor,
        imagePlaceholderColor:
            imagePlaceholderColor ?? this.imagePlaceholderColor,
        videoPosterBackgroundColor:
            videoPosterBackgroundColor ?? this.videoPosterBackgroundColor,
        uploadProgressColor: uploadProgressColor ?? this.uploadProgressColor,
        uploadErrorColor: uploadErrorColor ?? this.uploadErrorColor,
        commentBackgroundColor:
            commentBackgroundColor ?? this.commentBackgroundColor,
        suggestionAddColor: suggestionAddColor ?? this.suggestionAddColor,
        suggestionRemoveColor:
            suggestionRemoveColor ?? this.suggestionRemoveColor,
      );

  /// Build an [EditorTheme] from the host [ThemeData].
  factory EditorTheme.fromThemeData(ThemeData theme) {
    return (theme.brightness == Brightness.dark
            ? EditorTheme.dark(textTheme: theme.textTheme)
            : EditorTheme.light(textTheme: theme.textTheme))
        .copyWith(
      backgroundColor: theme.colorScheme.surface,
      surfaceColor: theme.colorScheme.surfaceContainerHighest,
      foregroundColor: theme.colorScheme.onSurface,
      cursorColor: theme.colorScheme.primary,
      selectionColor: theme.colorScheme.primary.withOpacity(0.3),
      linkColor: theme.colorScheme.primary,
    );
  }
}
