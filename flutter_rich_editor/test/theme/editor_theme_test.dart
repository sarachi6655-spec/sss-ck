import 'package:flutter/material.dart';
import 'package:flutter_rich_editor/flutter_rich_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Theme and Toolbar Config Tests', () {
    test('test_themeOverride_appliesToEveryEditorSurface', () {
      const Color customBg = Color(0xFF1E1E2E);
      const Color customText = Color(0xFFCDD6F4);
      const Color customToolbarBg = Color(0xFF313244);
      const Color customActive = Color(0xFF89B4FA);

      const EditorTheme theme = EditorTheme(
        backgroundColor: customBg,
        textColor: customText,
        toolbarBackgroundColor: customToolbarBg,
        toolbarItemActiveColor: customActive,
      );

      expect(theme.backgroundColor, customBg);
      expect(theme.textColor, customText);
      expect(theme.toolbarBackgroundColor, customToolbarBg);
      expect(theme.toolbarItemActiveColor, customActive);

      // Verify copyWith override
      const Color newCursor = Color(0xFFF5C2E7);
      final EditorTheme updated = theme.copyWith(cursorColor: newCursor);
      expect(updated.cursorColor, newCursor);
      expect(updated.backgroundColor, customBg);

      // Verify merge
      final EditorTheme merged = theme.merge(const EditorTheme(
        borderColor: Colors.red,
      ));
      expect(merged.borderColor, Colors.red);
      expect(merged.backgroundColor, customBg);
    });

    test('test_toolbarConfig_hidesAndReordersCommandsWithoutChangingCommandBehavior', () {
      final RichEditorController controller = RichEditorController();
      controller.pluginRegistry.registerPlugin(const FormattingPlugin());

      final List<ToolbarItem> baseItems = <ToolbarItem>[
        ToolbarItem(id: 'bold', icon: Icons.format_bold, label: 'Bold', onTap: (c) => c.execute(const FormatMarkCommand(mark: 'bold'))),
        ToolbarItem(id: 'italic', icon: Icons.format_italic, label: 'Italic', onTap: (c) => c.execute(const FormatMarkCommand(mark: 'italic'))),
        ToolbarItem(id: 'underline', icon: Icons.format_underlined, label: 'Underline', onTap: (c) => c.execute(const FormatMarkCommand(mark: 'underline'))),
      ];

      // Config: hide 'italic', reorder underline before bold
      const ToolbarConfig config = ToolbarConfig(
        hiddenItemIds: <String>{'italic'},
        orderedItemIds: <String>['underline', 'bold'],
      );

      final List<ToolbarItem> applied = config.apply(baseItems);

      expect(applied.length, 2);
      expect(applied[0].id, 'underline');
      expect(applied[1].id, 'bold');
      expect(applied.any((ToolbarItem i) => i.id == 'italic'), false);

      // Verify underlying command behavior is intact
      final CommandResult result = controller.execute(const FormatMarkCommand(mark: 'italic'));
      expect(result.success, true);
    });
  });
}
