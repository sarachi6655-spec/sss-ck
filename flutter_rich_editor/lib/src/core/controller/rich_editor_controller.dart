import 'package:flutter/foundation.dart';
import '../../serialization/html_codec.dart';
import '../../serialization/json_codec.dart';
import '../../serialization/markdown_codec.dart';
import '../command_bus/command_bus.dart';
import '../document_model/document_value.dart';
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
    import(DocumentValue.empty());
  }

  /// Updates document state directly during active typing without flooding undo history.
  void updateDocumentDirect(DocumentValue newDoc, {bool notify = true}) {
    _checkNotDisposed();
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
  }

  /// Exports the current document as semantic HTML.
  String toHtml() {
    _checkNotDisposed();
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
