import 'package:flutter/foundation.dart';
import '../../serialization/html_codec.dart';
import '../../serialization/json_codec.dart';
import '../../serialization/markdown_codec.dart';
import '../command_bus/command_bus.dart';
import '../document_model/document_value.dart';
import '../document_model/editor_node.dart';
import '../document_model/editor_selection.dart';
import '../plugin_system/plugin.dart';
import '../plugin_system/plugin_preset.dart';
import '../plugin_system/plugin_registry.dart';

/// Command used to replace the current document with a newly loaded document state.
class LoadDocumentCommand extends EditorCommand {
  const LoadDocumentCommand({
    required this.newDocument,
  });

  final DocumentValue newDocument;

  @override
  String get id => 'core.loadDocument';

  @override
  CommandResult execute(DocumentValue document) {
    return CommandResult.ok(newDocument);
  }

  @override
  CommandResult undo(DocumentValue document, DocumentValue previousSnapshot) {
    return CommandResult.ok(previousSnapshot);
  }
}

/// Primary controller managing document state, selection, commands, and codec imports/exports.
class RichEditorController extends ChangeNotifier {
  RichEditorController({
    DocumentValue? initialDocument,
    PluginPreset preset = const PluginPreset.full(),
    List<EditorPlugin> plugins = const <EditorPlugin>[],
    CommandBus? commandBus,
  })  : _document = initialDocument ?? DocumentValue.empty(),
        _commandBus = commandBus ?? CommandBus() {
    _lastValidDocument = _document;
    _pluginRegistry = PluginRegistry(commandBus: _commandBus);

    // Register preset or custom plugins
    final List<EditorPlugin> activePlugins = <EditorPlugin>[
      ...preset.customPlugins,
      ...plugins,
    ];
    if (activePlugins.isNotEmpty) {
      _pluginRegistry.registerPlugins(activePlugins);
    }
  }

  DocumentValue _document;
  DocumentValue _lastValidDocument = DocumentValue.empty();
  String? _rawHtml;
  bool _isDisposed = false;

  final CommandBus _commandBus;
  late final PluginRegistry _pluginRegistry;

  final JsonDocumentCodec _jsonCodec = const JsonDocumentCodec();
  final HtmlDocumentCodec _htmlCodec = const HtmlDocumentCodec();
  final MarkdownDocumentCodec _markdownCodec = const MarkdownDocumentCodec();

  /// Current document snapshot.
  DocumentValue get document {
    _checkNotDisposed();
    return _document;
  }

  /// The last successfully committed document (used by watchdog recovery).
  DocumentValue get lastValidDocument => _lastValidDocument;

  /// Current active selection.
  EditorSelection get selection {
    _checkNotDisposed();
    return _document.selection;
  }

  /// The underlying command bus.
  CommandBus get commandBus {
    _checkNotDisposed();
    return _commandBus;
  }

  /// The active plugin registry.
  PluginRegistry get pluginRegistry {
    _checkNotDisposed();
    return _pluginRegistry;
  }

  /// Whether the controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether an undo operation is available.
  bool get canUndo {
    _checkNotDisposed();
    return _commandBus.canUndo;
  }

  /// Whether a redo operation is available.
  bool get canRedo {
    _checkNotDisposed();
    return _commandBus.canRedo;
  }

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw StateError('Cannot use RichEditorController after it has been disposed.');
    }
  }

  /// Updates the selection without modifying document content.
  void setSelection(EditorSelection newSelection) {
    _checkNotDisposed();
    if (_document.selection != newSelection) {
      _document = _document.copyWith(selection: newSelection);
      notifyListeners();
    }
  }

  /// Dispatches a command through the command bus.
  CommandResult execute(EditorCommand command) {
    _checkNotDisposed();
    final CommandResult result = _commandBus.execute(command, _document);
    if (result.success) {
      _rawHtml = null;
      _document = result.document;
      _lastValidDocument = _document;
      notifyListeners();
    }
    return result;
  }

  /// Undoes the last mutation.
  CommandResult? undo() {
    _checkNotDisposed();
    final CommandResult? result = _commandBus.undo(_document);
    if (result != null && result.success) {
      _rawHtml = null;
      _document = result.document;
      _lastValidDocument = _document;
      notifyListeners();
    }
    return result;
  }

  /// Redoes the last undone mutation.
  CommandResult? redo() {
    _checkNotDisposed();
    final CommandResult? result = _commandBus.redo(_document);
    if (result != null && result.success) {
      _rawHtml = null;
      _document = result.document;
      _lastValidDocument = _document;
      notifyListeners();
    }
    return result;
  }

  /// Selects all text across all nodes.
  void selectAll() {
    _checkNotDisposed();
    if (_document.nodes.isEmpty) return;
    final int lastNodeIndex = _document.nodes.length - 1;
    final int lastNodeLength = _document.nodes[lastNodeIndex].text.length;
    setSelection(EditorSelection(
      baseOffset: 0,
      extentOffset: lastNodeLength,
      nodeIndex: 0,
      endNodeIndex: lastNodeIndex,
    ));
  }

  /// Clears the document content to an empty state.
  void clear() {
    _rawHtml = '';
    import(DocumentValue.empty());
  }

  /// Updates document state directly during active typing without flooding undo history.
  void updateDocumentDirect(DocumentValue newDoc, {bool notify = true}) {
    _checkNotDisposed();
    _rawHtml = null;
    _document = newDoc;
    _lastValidDocument = newDoc;
    if (notify) {
      notifyListeners();
    }
  }

  /// Imports a [DocumentValue] through the command bus to ensure undoability.
  void import(DocumentValue doc) {
    _checkNotDisposed();
    execute(LoadDocumentCommand(newDocument: doc));
  }

  /// Exports the current document snapshot.
  DocumentValue export() {
    _checkNotDisposed();
    return _document;
  }

  /// Loads canonical JSON content.
  void loadJson(Map<String, dynamic> json) {
    _checkNotDisposed();
    final DocumentValue decoded = _jsonCodec.decodeFromMap(json);
    import(decoded);
  }

  /// Exports the current document as canonical JSON.
  Map<String, dynamic> toJson() {
    _checkNotDisposed();
    return _jsonCodec.encodeToMap(_document);
  }

  /// Loads HTML content.
  void loadHtml(String html) {
    _checkNotDisposed();
    final DocumentValue decoded = _htmlCodec.decode(html);
    import(decoded);
    _rawHtml = html;
  }

  /// Inserts an HTML snippet at the current cursor position.
  /// If the document is empty, imports the snippet as the document.
  void insertHtml(String htmlSnippet) {
    _checkNotDisposed();
    final DocumentValue decoded = _htmlCodec.decode(htmlSnippet);
    if (decoded.nodes.isEmpty) return;

    final List<EditorNode> existing = List<EditorNode>.from(_document.nodes);
    if (existing.isEmpty) {
      import(decoded);
      return;
    }

    final int insertAfter = _document.selection.nodeIndex.clamp(0, existing.length - 1);
    final List<EditorNode> before = existing.sublist(0, insertAfter + 1);
    final List<EditorNode> after =
        insertAfter + 1 < existing.length ? existing.sublist(insertAfter + 1) : <EditorNode>[];

    final List<EditorNode> merged = <EditorNode>[
      ...before,
      ...decoded.nodes,
      ...after,
    ];

    final int newCursorIndex = insertAfter + 1;
    final DocumentValue newDoc = _document.copyWith(
      nodes: merged,
      selection: EditorSelection.collapsed(0, nodeIndex: newCursorIndex),
    );
    import(newDoc);
  }

  /// Appends an HTML snippet to the end of the document.
  void appendHtml(String htmlSnippet) {
    _checkNotDisposed();
    final DocumentValue decoded = _htmlCodec.decode(htmlSnippet);
    if (decoded.nodes.isEmpty) return;

    final List<EditorNode> merged = <EditorNode>[
      ..._document.nodes,
      ...decoded.nodes,
    ];

    final int newCursorIndex = _document.nodes.length;
    final DocumentValue newDoc = _document.copyWith(
      nodes: merged,
      selection: EditorSelection.collapsed(0, nodeIndex: newCursorIndex),
    );
    import(newDoc);
  }

  /// Exports the current document as semantic HTML.
  String toHtml() {
    _checkNotDisposed();
    if (_rawHtml != null) {
      return _rawHtml!;
    }
    return _htmlCodec.encode(_document);
  }

  /// Loads Markdown content.
  void loadMarkdown(String markdown) {
    _checkNotDisposed();
    final DocumentValue decoded = _markdownCodec.decode(markdown);
    import(decoded);
  }

  /// Exports the current document as GitHub Flavored Markdown.
  String toMarkdown() {
    _checkNotDisposed();
    return _markdownCodec.encode(_document);
  }

  /// Returns the combined plain text of the current document.
  String toPlainText() {
    _checkNotDisposed();
    return _document.plainText;
  }

  /// Alias for [toPlainText], compatible with QuillController.pastePlainText.
  String get pastePlainText => toPlainText();

  /// Whether the document has no content.
  bool get isEmpty => _document.isEmpty;

  /// Whether the document has content.
  bool get isNotEmpty => _document.isNotEmpty;

  /// Exports the document HTML cleanly formatted for reports/printing, stripping
  /// interactive cell reference badges/spans into clean inline text.
  String toCleanReportHtml() {
    _checkNotDisposed();
    final String html = toHtml();
    return html.replaceAllMapped(
      RegExp(r'<span[^>]*class="[^"]*(?:table-cell-ref|mention cell-ref|inline-formula-pill)[^"]*"[^>]*>(.*?)</span>', caseSensitive: false),
      (Match m) => m.group(1) ?? '',
    );
  }

  /// Parses a cell coordinate like 'A1', 'B2', etc. into column and row indices (0-based).
  static ({int col, int row})? parseCellCoord(String coordStr) {
    final String s = coordStr.trim().toUpperCase();
    final RegExp regex = RegExp(r'^([A-Z]+)(\d+)$');
    final Match? match = regex.firstMatch(s);
    if (match == null) return null;

    final String colLetters = match.group(1)!;
    final int row = int.parse(match.group(2)!) - 1;

    int col = 0;
    for (int i = 0; i < colLetters.length; i++) {
      col = col * 26 + (colLetters.codeUnitAt(i) - 64);
    }
    col -= 1;

    return (col: col, row: row);
  }

  /// Formats column and row indices (0-based) into a standard coordinate like 'A1', 'B2'.
  static String formatCellCoord(int col, int row) {
    String colLetters = '';
    int c = col + 1;
    while (c > 0) {
      final int rem = (c - 1) % 26;
      colLetters = String.fromCharCode(65 + rem) + colLetters;
      c = (c - 1) ~/ 26;
    }
    return '$colLetters${row + 1}';
  }

  /// Returns the value of a table cell by its coordinate (e.g. 'A1', 'B2').
  String? getTableCellValue(String coord, {int tableIndex = 0}) {
    _checkNotDisposed();
    final List<EditorNode> tables = _document.nodes.where((EditorNode n) => n.type == 'table').toList();
    if (tableIndex < 0 || tableIndex >= tables.length) return null;

    final ({int col, int row})? parsed = parseCellCoord(coord);
    if (parsed == null) return null;

    final EditorNode table = tables[tableIndex];
    if (parsed.row >= 0 && parsed.row < table.children.length) {
      final EditorNode row = table.children[parsed.row];
      if (parsed.col >= 0 && parsed.col < row.children.length) {
        return row.children[parsed.col].text.trim();
      }
    }
    return null;
  }

  /// Returns a map of all cell coordinates to their values for the given table.
  Map<String, String> getAllTableCells({int tableIndex = 0}) {
    _checkNotDisposed();
    final Map<String, String> result = <String, String>{};
    final List<EditorNode> tables = _document.nodes.where((EditorNode n) => n.type == 'table').toList();
    if (tableIndex < 0 || tableIndex >= tables.length) return result;

    final EditorNode table = tables[tableIndex];
    for (int r = 0; r < table.children.length; r++) {
      final EditorNode row = table.children[r];
      for (int c = 0; c < row.children.length; c++) {
        final String coord = formatCellCoord(c, r);
        result[coord] = row.children[c].text.trim();
      }
    }
    return result;
  }

  /// Resolves any cell reference tokens (like `$A1`, `$B2`) in a given string
  /// with the live values from the document's table.
  String resolveCellReferences(String text, {int tableIndex = 0}) {
    _checkNotDisposed();
    if (!text.contains(r'$')) return text;
    return text.replaceAllMapped(RegExp(r'\$([A-Za-z]+)(\d+)'), (Match match) {
      final String coord = '${match.group(1)!.toUpperCase()}${match.group(2)!}';
      final String? val = getTableCellValue(coord, tableIndex: tableIndex);
      return val != null && val.isNotEmpty ? val : match.group(0)!;
    });
  }

  @override
  void dispose() {
    if (!_isDisposed) {
      _isDisposed = true;
      _pluginRegistry.dispose();
      _commandBus.dispose();
      super.dispose();
    }
  }
}

