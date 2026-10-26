import '../../core/command_bus/editor_command.dart';
import '../../core/controller/rich_editor_controller.dart';
import '../../core/document_model/document_value.dart';
import '../../core/document_model/editor_node.dart';
import '../../core/document_model/editor_selection.dart';
import '../../core/plugin_system/plugin.dart';

/// Helper to resolve a table node and index by tableId or tableIndex.
int _resolveTableIndex(DocumentValue document, {String? tableId, int? tableIndex}) {
  if (tableIndex != null && tableIndex >= 0 && tableIndex < document.nodes.length) {
    if (document.nodes[tableIndex].type == 'table') return tableIndex;
  }
  if (tableId != null) {
    return document.nodes.indexWhere((EditorNode n) => n.id == tableId && n.type == 'table');
  }
  return -1;
}

/// Command to insert a new table block into the document.
class InsertTableCommand extends EditorCommand {
  const InsertTableCommand({
    this.rows = 2,
    this.columns = 2,
    this.caption = '',
  });

  final int rows;
  final int columns;
  final String caption;

  @override
  String get id => 'table.insert';

  @override
  CommandResult execute(DocumentValue document) {
    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorSelection sel = document.selection;
    final int insertPos = sel.nodeIndex >= 0 && sel.nodeIndex < updated.length
        ? sel.nodeIndex + 1
        : updated.length;

    final EditorNode tableNode = EditorNode.table(
      id: 'table_${DateTime.now().millisecondsSinceEpoch}',
      rows: rows,
      columns: columns,
      caption: caption,
    );

    updated.insert(insertPos, tableNode);

    return CommandResult.ok(document.copyWith(
      nodes: updated,
      selection: EditorSelection.collapsed(0, nodeIndex: insertPos),
    ));
  }
}

/// Command to insert a row into an existing table.
class InsertTableRowCommand extends EditorCommand {
  const InsertTableRowCommand({
    this.tableId,
    this.tableIndex,
    required this.rowIndex,
    this.isAbove = false,
  });

  final String? tableId;
  final int? tableIndex;
  final int rowIndex;
  final bool isAbove;

  @override
  String get id => 'table.insertRow.${tableId ?? tableIndex}';

  @override
  CommandResult execute(DocumentValue document) {
    final int resolvedIdx = _resolveTableIndex(document, tableId: tableId, tableIndex: tableIndex);
    if (resolvedIdx == -1) {
      return CommandResult.failure(
        currentDocument: document,
        code: 'table.not_found',
        message: 'Table "${tableId ?? tableIndex}" not found.',
      );
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode table = updated[resolvedIdx];
    final List<EditorNode> rows = List<EditorNode>.from(table.children);
    final int colCount = rows.isNotEmpty ? rows.first.children.length : (table.metadata['columns'] as num?)?.toInt() ?? 2;

    final int insertAt = isAbove ? rowIndex.clamp(0, rows.length) : (rowIndex + 1).clamp(0, rows.length);
    final String rowId = 'row_${DateTime.now().microsecondsSinceEpoch}';

    final EditorNode newRow = EditorNode(
      id: rowId,
      type: 'table_row',
      children: List<EditorNode>.generate(colCount, (int c) {
        return EditorNode(
          id: 'cell_${rowId}_$c',
          type: 'table_cell',
          text: '',
          metadata: const <String, dynamic>{'isHeader': false},
        );
      }),
    );

    rows.insert(insertAt, newRow);

    final Map<String, dynamic> newMeta = Map<String, dynamic>.from(table.metadata);
    newMeta['rows'] = rows.length;

    updated[resolvedIdx] = table.copyWith(
      metadata: newMeta,
      children: rows,
    );

    return CommandResult.ok(document.copyWith(nodes: updated));
  }
}

/// Command to insert a column into an existing table.
class InsertTableColumnCommand extends EditorCommand {
  const InsertTableColumnCommand({
    this.tableId,
    this.tableIndex,
    this.columnIndex,
    this.colIndex,
    this.isLeft = false,
  });

  final String? tableId;
  final int? tableIndex;
  final int? columnIndex;
  final int? colIndex;
  final bool isLeft;

  @override
  String get id => 'table.insertColumn.${tableId ?? tableIndex}';

  @override
  CommandResult execute(DocumentValue document) {
    final int resolvedIdx = _resolveTableIndex(document, tableId: tableId, tableIndex: tableIndex);
    if (resolvedIdx == -1) {
      return CommandResult.failure(
        currentDocument: document,
        code: 'table.not_found',
        message: 'Table "${tableId ?? tableIndex}" not found.',
      );
    }

    final int targetCol = columnIndex ?? colIndex ?? 0;
    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode table = updated[resolvedIdx];
    final List<EditorNode> rows = List<EditorNode>.from(table.children);

    final int insertCol = isLeft ? targetCol : (columnIndex != null ? targetCol : targetCol + 1);

    for (int r = 0; r < rows.length; r++) {
      final EditorNode row = rows[r];
      final List<EditorNode> cells = List<EditorNode>.from(row.children);
      final int safeCol = insertCol.clamp(0, cells.length);
      final bool isHeader = r == 0 && (cells.isNotEmpty && cells.first.metadata['isHeader'] == true);

      final String cellId = 'cell_${DateTime.now().microsecondsSinceEpoch}_${r}_$safeCol';
      cells.insert(
        safeCol,
        EditorNode(
          id: cellId,
          type: 'table_cell',
          text: '',
          metadata: <String, dynamic>{'isHeader': isHeader},
        ),
      );
      rows[r] = row.copyWith(children: cells);
    }

    final Map<String, dynamic> newMeta = Map<String, dynamic>.from(table.metadata);
    newMeta['columns'] = rows.isNotEmpty ? rows.first.children.length : 0;

    updated[resolvedIdx] = table.copyWith(
      metadata: newMeta,
      children: rows,
    );

    return CommandResult.ok(document.copyWith(nodes: updated));
  }
}

/// Command to delete a table row.
class DeleteTableRowCommand extends EditorCommand {
  const DeleteTableRowCommand({
    this.tableId,
    this.tableIndex,
    required this.rowIndex,
  });

  final String? tableId;
  final int? tableIndex;
  final int rowIndex;

  @override
  String get id => 'table.deleteRow.${tableId ?? tableIndex}';

  @override
  CommandResult execute(DocumentValue document) {
    final int resolvedIdx = _resolveTableIndex(document, tableId: tableId, tableIndex: tableIndex);
    if (resolvedIdx == -1) return CommandResult.ok(document);

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode table = updated[resolvedIdx];
    final List<EditorNode> rows = List<EditorNode>.from(table.children);
    if (rowIndex < 0 || rowIndex >= rows.length) return CommandResult.ok(document);

    rows.removeAt(rowIndex);

    if (rows.isEmpty) {
      updated[resolvedIdx] = EditorNode.paragraph(
        id: 'p_${DateTime.now().microsecondsSinceEpoch}',
        text: '',
      );
    } else {
      final Map<String, dynamic> meta = Map<String, dynamic>.from(table.metadata);
      meta['rows'] = rows.length;
      updated[resolvedIdx] = table.copyWith(children: rows, metadata: meta);
    }

    return CommandResult.ok(document.copyWith(nodes: updated));
  }
}

/// Command to delete a table column.
class DeleteTableColumnCommand extends EditorCommand {
  const DeleteTableColumnCommand({
    this.tableId,
    this.tableIndex,
    this.columnIndex,
    this.colIndex,
  });

  final String? tableId;
  final int? tableIndex;
  final int? columnIndex;
  final int? colIndex;

  @override
  String get id => 'table.deleteColumn.${tableId ?? tableIndex}';

  @override
  CommandResult execute(DocumentValue document) {
    final int resolvedIdx = _resolveTableIndex(document, tableId: tableId, tableIndex: tableIndex);
    if (resolvedIdx == -1) return CommandResult.ok(document);

    final int targetCol = columnIndex ?? colIndex ?? 0;
    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode table = updated[resolvedIdx];
    final List<EditorNode> rows = List<EditorNode>.from(table.children);

    for (int r = 0; r < rows.length; r++) {
      final EditorNode row = rows[r];
      final List<EditorNode> cells = List<EditorNode>.from(row.children);
      if (targetCol >= 0 && targetCol < cells.length) {
        cells.removeAt(targetCol);
        rows[r] = row.copyWith(children: cells);
      }
    }

    if (rows.isEmpty || (rows.isNotEmpty && rows.first.children.isEmpty)) {
      updated[resolvedIdx] = EditorNode.paragraph(
        id: 'p_${DateTime.now().microsecondsSinceEpoch}',
        text: '',
      );
    } else {
      final Map<String, dynamic> meta = Map<String, dynamic>.from(table.metadata);
      meta['columns'] = rows.first.children.length;
      updated[resolvedIdx] = table.copyWith(children: rows, metadata: meta);
    }

    return CommandResult.ok(document.copyWith(nodes: updated));
  }
}

/// Command to delete an entire table.
class DeleteTableCommand extends EditorCommand {
  const DeleteTableCommand({
    this.tableId,
    this.tableIndex,
  });

  final String? tableId;
  final int? tableIndex;

  @override
  String get id => 'table.deleteTable.${tableId ?? tableIndex}';

  @override
  CommandResult execute(DocumentValue document) {
    final int resolvedIdx = _resolveTableIndex(document, tableId: tableId, tableIndex: tableIndex);
    if (resolvedIdx == -1) return CommandResult.ok(document);

    final List<EditorNode> docNodes = List<EditorNode>.from(document.nodes);
    docNodes.removeAt(resolvedIdx);
    if (docNodes.isEmpty) {
      docNodes.add(EditorNode.paragraph(
        id: 'p_${DateTime.now().microsecondsSinceEpoch}',
        text: '',
      ));
    }
    return CommandResult.ok(document.copyWith(
      nodes: docNodes,
      selection: EditorSelection.collapsed(0, nodeIndex: (resolvedIdx - 1).clamp(0, docNodes.length - 1)),
    ));
  }
}

/// Command to toggle whether the first row of a table is a header row.
class ToggleTableHeaderRowCommand extends EditorCommand {
  const ToggleTableHeaderRowCommand({
    this.tableId,
    this.tableIndex,
  });

  final String? tableId;
  final int? tableIndex;

  @override
  String get id => 'table.toggleHeaderRow.${tableId ?? tableIndex}';

  @override
  CommandResult execute(DocumentValue document) {
    final int resolvedIdx = _resolveTableIndex(document, tableId: tableId, tableIndex: tableIndex);
    if (resolvedIdx == -1) return CommandResult.ok(document);

    final List<EditorNode> docNodes = List<EditorNode>.from(document.nodes);
    final EditorNode table = docNodes[resolvedIdx];
    if (table.children.isEmpty) return CommandResult.ok(document);

    final List<EditorNode> rows = List<EditorNode>.from(table.children);
    final EditorNode firstRow = rows.first;
    final bool currentIsHeader = firstRow.children.isNotEmpty && firstRow.children.first.metadata['isHeader'] == true;
    final bool newIsHeader = !currentIsHeader;

    final List<EditorNode> updatedCells = firstRow.children.map((EditorNode cell) {
      final Map<String, dynamic> cellMeta = Map<String, dynamic>.from(cell.metadata);
      cellMeta['isHeader'] = newIsHeader;
      return cell.copyWith(metadata: cellMeta);
    }).toList();

    rows[0] = firstRow.copyWith(children: updatedCells);
    docNodes[resolvedIdx] = table.copyWith(children: rows);

    return CommandResult.ok(document.copyWith(nodes: docNodes));
  }
}

/// Command to merge cells across a rectangular range in a table.
class MergeTableCellsCommand extends EditorCommand {
  const MergeTableCellsCommand({
    required this.tableId,
    required this.startRow,
    required this.startCol,
    required this.endRow,
    required this.endCol,
  });

  final String tableId;
  final int startRow;
  final int startCol;
  final int endRow;
  final int endCol;

  @override
  String get id => 'table.mergeCells.$tableId';

  @override
  CommandResult execute(DocumentValue document) {
    final int tableIdx = _resolveTableIndex(document, tableId: tableId);
    if (tableIdx == -1) {
      return CommandResult.failure(
        currentDocument: document,
        code: 'table.not_found',
        message: 'Table "$tableId" not found.',
      );
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode table = updated[tableIdx];
    final List<EditorNode> rows = List<EditorNode>.from(table.children);

    final int r1 = startRow <= endRow ? startRow : endRow;
    final int r2 = startRow <= endRow ? endRow : startRow;
    final int c1 = startCol <= endCol ? startCol : endCol;
    final int c2 = startCol <= endCol ? endCol : startCol;

    final StringBuffer mergedText = StringBuffer();

    for (int r = r1; r <= r2 && r < rows.length; r++) {
      final List<EditorNode> cells = List<EditorNode>.from(rows[r].children);
      for (int c = c1; c <= c2 && c < cells.length; c++) {
        if (cells[c].text.isNotEmpty) {
          if (mergedText.isNotEmpty) mergedText.write(' ');
          mergedText.write(cells[c].text);
        }
        if (r == r1 && c == c1) {
          final Map<String, dynamic> meta = Map<String, dynamic>.from(cells[c].metadata);
          meta['rowSpan'] = (r2 - r1 + 1);
          meta['colSpan'] = (c2 - c1 + 1);
          cells[c] = cells[c].copyWith(metadata: meta);
        } else {
          final Map<String, dynamic> meta = Map<String, dynamic>.from(cells[c].metadata);
          meta['mergedInto'] = '${r1}_$c1';
          cells[c] = cells[c].copyWith(text: '', metadata: meta);
        }
      }
      rows[r] = rows[r].copyWith(children: cells);
    }

    if (r1 < rows.length && c1 < rows[r1].children.length) {
      final List<EditorNode> firstRowCells = List<EditorNode>.from(rows[r1].children);
      firstRowCells[c1] = firstRowCells[c1].copyWith(text: mergedText.toString());
      rows[r1] = rows[r1].copyWith(children: firstRowCells);
    }

    updated[tableIdx] = table.copyWith(children: rows);
    return CommandResult.ok(document.copyWith(nodes: updated));
  }
}

/// Command to resize a table column.
class ResizeTableColumnCommand extends EditorCommand {
  const ResizeTableColumnCommand({
    required this.tableId,
    required this.columnIndex,
    required this.width,
  });

  final String tableId;
  final int columnIndex;
  final double width;

  @override
  String get id => 'table.resizeColumn.$tableId.$columnIndex';

  @override
  CommandResult execute(DocumentValue document) {
    final int tableIdx = _resolveTableIndex(document, tableId: tableId);
    if (tableIdx == -1) {
      return CommandResult.failure(
        currentDocument: document,
        code: 'table.not_found',
        message: 'Table "$tableId" not found.',
      );
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode table = updated[tableIdx];
    final Map<String, dynamic> newMeta = Map<String, dynamic>.from(table.metadata);
    final Map<String, dynamic> columnWidths = newMeta['columnWidths'] != null
        ? Map<String, dynamic>.from(newMeta['columnWidths'] as Map)
        : <String, dynamic>{};

    columnWidths[columnIndex.toString()] = width;
    newMeta['columnWidths'] = columnWidths;

    updated[tableIdx] = table.copyWith(metadata: newMeta);
    return CommandResult.ok(document.copyWith(nodes: updated));
  }
}

/// Command to insert a dynamic table cell reference into the document text.
class InsertTableCellReferenceCommand extends EditorCommand {
  const InsertTableCellReferenceCommand({
    required this.coord,
    this.tableIndex = 0,
    this.tableId,
  });

  final String coord;
  final int tableIndex;
  final String? tableId;

  @override
  String get id => 'table.insertReference.$coord';

  @override
  CommandResult execute(DocumentValue document) {
    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorSelection sel = document.selection;
    final int target = sel.nodeIndex >= 0 && sel.nodeIndex < updated.length ? sel.nodeIndex : 0;
    if (updated.isEmpty) {
      updated.add(EditorNode.paragraph(id: 'p_${DateTime.now().microsecondsSinceEpoch}', text: ''));
    }

    final EditorNode targetNode = updated[target];
    if (targetNode.type == 'table') {
      return CommandResult.ok(document);
    }

    // Resolve value from table
    final int resolvedTIdx = _resolveTableIndex(document, tableId: tableId, tableIndex: tableIndex);
    String cellVal = '\$$coord';
    if (resolvedTIdx >= 0 && resolvedTIdx < updated.length) {
      final EditorNode tableNode = updated[resolvedTIdx];
      final ({int col, int row})? parsed = RichEditorController.parseCellCoord(coord);
      if (parsed != null && parsed.row >= 0 && parsed.row < tableNode.children.length) {
        final EditorNode rowNode = tableNode.children[parsed.row];
        if (parsed.col >= 0 && parsed.col < rowNode.children.length) {
          final String raw = rowNode.children[parsed.col].text.trim();
          if (raw.isNotEmpty) cellVal = raw;
        }
      }
    }

    final String refHtml = '<span class="mention table-cell-ref" data-mention="\$$coord" data-cell-coord="$coord" title="Table cell $coord: $cellVal (Live Link)">$cellVal</span> ';
    final String currentText = targetNode.text;
    final int offset = sel.baseOffset.clamp(0, currentText.length);
    final String newText = '${currentText.substring(0, offset)}$refHtml${currentText.substring(offset)}';

    updated[target] = targetNode.copyWith(text: newText);
    return CommandResult.ok(document.copyWith(
      nodes: updated,
      selection: EditorSelection.collapsed(offset + refHtml.length, nodeIndex: target),
    ));
  }
}

/// Plugin providing rich tabular data editing (insert, add rows/cols, merge, resize, cell references).
class TablePlugin extends EditorPlugin {
  const TablePlugin();

  @override
  String get id => 'media.table';

  @override
  String get name => 'Tables';

  @override
  List<EditorCommand> get commands => const <EditorCommand>[
        InsertTableCommand(),
        InsertTableRowCommand(rowIndex: 0),
        InsertTableColumnCommand(),
        DeleteTableRowCommand(rowIndex: 0),
        DeleteTableColumnCommand(),
        DeleteTableCommand(),
        ToggleTableHeaderRowCommand(),
        InsertTableCellReferenceCommand(coord: 'A1'),
      ];
}
