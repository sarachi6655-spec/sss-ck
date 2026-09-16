import 'package:flutter/material.dart';
import '../core/controller/rich_editor_controller.dart';
import '../features/media/table_plugin.dart';
import '../theme/editor_theme.dart';

class ContextualTableToolbar extends StatelessWidget {
  const ContextualTableToolbar({
    super.key,
    required this.controller,
    required this.tableIndex,
    required this.currentRow,
    required this.currentCol,
    required this.theme,
  });

  final RichEditorController controller;
  final int tableIndex;
  final int currentRow;
  final int currentCol;
  final EditorTheme theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3.0,
      color: theme.toolbarBackgroundColor,
      borderRadius: BorderRadius.circular(6.0),
      child: Container(
        height: 36.0,
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        decoration: BoxDecoration(
          color: theme.toolbarBackgroundColor,
          border: Border.all(color: theme.toolbarBorderColor),
          borderRadius: BorderRadius.circular(6.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _btn(
              icon: Icons.table_rows_rounded,
              tooltip: 'Insert Row Above',
              onPressed: () => controller.execute(InsertTableRowCommand(
                tableIndex: tableIndex,
                rowIndex: currentRow,
                isAbove: true,
              )),
            ),
            _btn(
              icon: Icons.add_circle_outline,
              tooltip: 'Insert Row Below',
              onPressed: () => controller.execute(InsertTableRowCommand(
                tableIndex: tableIndex,
                rowIndex: currentRow,
                isAbove: false,
              )),
            ),
            const VerticalDivider(width: 8.0, indent: 6.0, endIndent: 6.0),
            _btn(
              icon: Icons.view_column_outlined,
              tooltip: 'Insert Column Left',
              onPressed: () => controller.execute(InsertTableColumnCommand(
                tableIndex: tableIndex,
                colIndex: currentCol,
                isLeft: true,
              )),
            ),
            _btn(
              icon: Icons.add_circle_outline,
              tooltip: 'Insert Column Right',
              onPressed: () => controller.execute(InsertTableColumnCommand(
                tableIndex: tableIndex,
                colIndex: currentCol,
                isLeft: false,
              )),
            ),
            const VerticalDivider(width: 8.0, indent: 6.0, endIndent: 6.0),
            _btn(
              icon: Icons.remove_circle_outline,
              tooltip: 'Delete Row',
              color: Colors.red.shade400,
              onPressed: () => controller.execute(DeleteTableRowCommand(
                tableIndex: tableIndex,
                rowIndex: currentRow,
              )),
            ),
            _btn(
              icon: Icons.delete_sweep_outlined,
              tooltip: 'Delete Column',
              color: Colors.red.shade400,
              onPressed: () => controller.execute(DeleteTableColumnCommand(
                tableIndex: tableIndex,
                colIndex: currentCol,
              )),
            ),
            const VerticalDivider(width: 8.0, indent: 6.0, endIndent: 6.0),
            _btn(
              icon: Icons.splitscreen_outlined,
              tooltip: 'Toggle Header Row',
              onPressed: () => controller.execute(ToggleTableHeaderRowCommand(
                tableIndex: tableIndex,
              )),
            ),
            _btn(
              icon: Icons.delete_forever,
              tooltip: 'Delete Table',
              color: Colors.red.shade600,
              onPressed: () => controller.execute(DeleteTableCommand(
                tableIndex: tableIndex,
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return Focus(
      canRequestFocus: false,
      child: IconButton(
        icon: Icon(icon, size: 18, color: color ?? theme.toolbarItemColor),
        tooltip: tooltip,
        padding: const EdgeInsets.all(4.0),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        onPressed: onPressed,
      ),
    );
  }
}
