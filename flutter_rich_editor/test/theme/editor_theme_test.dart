import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_rich_editor/src/theme/editor_theme.dart';

void main() {
  group('EditorTheme', () {
    test('light factory produces a non-null fully-specified theme', () {
      final EditorTheme t = EditorTheme.light();
      expect(t.backgroundColor, isA<Color>());
      expect(t.surfaceColor, isA<Color>());
      expect(t.foregroundColor, isA<Color>());
      expect(t.disabledColor, isA<Color>());
      expect(t.selectionColor, isA<Color>());
      expect(t.cursorColor, isA<Color>());
      expect(t.borderColor, isA<Color>());
      expect(t.borderWidth, greaterThan(0));
      expect(t.focusedBorderWidth, greaterThan(0));
      expect(t.toolbarHeight, greaterThan(0));
      expect(t.toolbarIconSize, greaterThan(0));
      expect(t.toolbarSpacing, greaterThanOrEqualTo(0));
      expect(t.spacingUnit, greaterThan(0));
      expect(t.borderRadius, greaterThanOrEqualTo(0));
      expect(t.smallRadius, greaterThanOrEqualTo(0));
      expect(t.dialogRadius, greaterThanOrEqualTo(0));
      expect(t.toolbarElevation, greaterThanOrEqualTo(0));
      expect(t.menuElevation, greaterThanOrEqualTo(0));
      expect(t.dialogElevation, greaterThanOrEqualTo(0));
      expect(t.iconTheme, isA<IconThemeData>());
      expect(t.contentPadding, isA<EdgeInsets>());
      expect(t.toolbarPadding, isA<EdgeInsets>());
      expect(t.menuPadding, isA<EdgeInsets>());
      expect(t.linkColor, isA<Color>());
      expect(t.codeBlockBackgroundColor, isA<Color>());
      expect(t.quoteBackgroundColor, isA<Color>());
      expect(t.tableBorderColor, isA<Color>());
      expect(t.imagePlaceholderColor, isA<Color>());
      expect(t.videoPosterBackgroundColor, isA<Color>());
      expect(t.uploadProgressColor, isA<Color>());
      expect(t.uploadErrorColor, isA<Color>());
      expect(t.commentBackgroundColor, isA<Color>());
      expect(t.suggestionAddColor, isA<Color>());
      expect(t.suggestionRemoveColor, isA<Color>());
    });

    test('dark factory produces a different theme than light', () {
      final EditorTheme light = EditorTheme.light();
      final EditorTheme dark = EditorTheme.dark();
      expect(light.backgroundColor, isNot(equals(dark.backgroundColor)));
      expect(light.foregroundColor, isNot(equals(dark.foregroundColor)));
    });

    test('light factory uses provided TextTheme for paragraph style', () {
      final TextStyle custom = const TextStyle(
        fontSize: 22,
        color: Color(0xFF112233),
      );
      final TextTheme customTheme = Typography.material2021().black.copyWith(
            bodyLarge: custom,
          );
      final EditorTheme t = EditorTheme.light(textTheme: customTheme);
      expect(t.paragraphStyle.fontSize, 22);
      expect(t.paragraphStyle.color, const Color(0xFF112233));
    });

    test('copyWith overrides only specified fields', () {
      final EditorTheme original = EditorTheme.light();
      final Color customBg = const Color(0xFFAABBCC);
      final EditorTheme copy = original.copyWith(backgroundColor: customBg);
      expect(copy.backgroundColor, customBg);
      // Unchanged fields preserved.
      expect(copy.surfaceColor, original.surfaceColor);
      expect(copy.toolbarHeight, original.toolbarHeight);
    });

    test('copyWith with no args returns equivalent theme', () {
      final EditorTheme original = EditorTheme.light();
      final EditorTheme copy = original.copyWith();
      // Same value semantics — every getter matches.
      expect(copy.backgroundColor, original.backgroundColor);
      expect(copy.foregroundColor, original.foregroundColor);
      expect(copy.toolbarHeight, original.toolbarHeight);
    });

    test('merge with null returns same instance', () {
      final EditorTheme original = EditorTheme.light();
      final EditorTheme merged = original.merge(null);
      expect(identical(original, merged), isTrue);
    });

    test('merge overrides fields from another theme', () {
      final EditorTheme original = EditorTheme.light();
      final EditorTheme override = EditorTheme.light().copyWith(
        backgroundColor: const Color(0xFF112233),
        toolbarHeight: 64,
      );
      final EditorTheme merged = original.merge(override);
      expect(merged.backgroundColor, const Color(0xFF112233));
      expect(merged.toolbarHeight, 64);
      // Non-overridden fields remain the same as original.
      expect(merged.surfaceColor, original.surfaceColor);
    });

    test('fromThemeData with light theme produces a usable EditorTheme', () {
      final ThemeData host = ThemeData(brightness: Brightness.light);
      final EditorTheme t = EditorTheme.fromThemeData(host);
      expect(t.backgroundColor, isA<Color>());
      expect(t.foregroundColor, isA<Color>());
    });

    test('fromThemeData with dark theme produces a usable EditorTheme', () {
      final ThemeData host = ThemeData(brightness: Brightness.dark);
      final EditorTheme t = EditorTheme.fromThemeData(host);
      expect(t.backgroundColor, isA<Color>());
      expect(t.foregroundColor, isA<Color>());
    });

    test('all heading styles are present', () {
      final EditorTheme t = EditorTheme.light();
      expect(t.heading1Style, isA<TextStyle>());
      expect(t.heading2Style, isA<TextStyle>());
      expect(t.heading3Style, isA<TextStyle>());
      expect(t.heading4Style, isA<TextStyle>());
      expect(t.heading5Style, isA<TextStyle>());
      expect(t.heading6Style, isA<TextStyle>());
      expect(t.quoteStyle, isA<TextStyle>());
      expect(t.codeStyle, isA<TextStyle>());
      expect(t.captionStyle, isA<TextStyle>());
      expect(t.titleStyle, isA<TextStyle>());
      expect(t.toolbarStyle, isA<TextStyle>());
    });
  });
}