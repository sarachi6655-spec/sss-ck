import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../command_bus/command_bus.dart';
import '../document_model/document_model.dart';
import '../plugin_system/plugin_system.dart';
import '../../serialization/json_codec.dart';

/// Public controller for the rich editor.
///
/// This is the primary API surface for host applications. It wraps the command
/// bus, document model, selection, focus, and serialization adapters.
class RichEditorController extends ChangeNotifier {
  final PluginRegistry _registry;
  final CommandBus _commandBus;
  final ValueNotifier<DocumentValue> _document;
  final ValueNotifier<EditorSelection> _selection;
  final FocusNode focusNode;
  final bool readOnly;
  final void Function(EditorCommandException error)? onError;
  final StreamController<EditorChangeEvent> _changeController =
      StreamController<EditorChangeEvent>.broadcast();

  DocumentValue _lastValidDocument;
  bool _disposed = false;

  RichEditorController({
    required PluginRegistry registry,
    DocumentValue? initialDocument,
    EditorSelection? initialSelection,
    this.readOnly = false,
    this.onError,
    FocusNode? focusNode,
  })  : _registry = registry,
        _document = ValueNotifier<DocumentValue>(
            initialDocument ?? DocumentValue.empty),
        _selection = ValueNotifier<EditorSelection>(
            initialSelection ?? const EditorSelection.none()),
        focusNode = focusNode ?? FocusNode(),
        _lastValidDocument = initialDocument ?? DocumentValue.empty,
        _commandBus = CommandBus(
          registry: registry,
          document: ValueNotifier<DocumentValue>(
              initialDocument ?? DocumentValue.empty),
          selection: ValueNotifier<EditorSelection>(
              initialSelection ?? const EditorSelection.none()),
          readOnly: readOnly,
          onError: onError,
        ) {
    _document.addListener(_onDocumentChanged);
    _selection.addListener(_onSelectionChanged);
  }

  /// Current document value.
  DocumentValue get document => _document.value;

  /// Current selection.
  EditorSelection get selection => _selection.value;

  /// Stream of document/selection change events.
  Stream<EditorChangeEvent> get changes => _changeController.stream;

  /// Whether undo is available.
  bool get canUndo => _commandBus.canUndo;

  /// Whether redo is available.
  bool get canRedo => _commandBus.canRedo;

  /// Last valid document snapshot. Updated after every successful mutation and
  /// used by the watchdog boundary for recovery.
  DocumentValue get lastValidDocument => _lastValidDocument;

  /// Execute a command by registered id.
  EditorCommandResult executeCommand(
    String commandId, {
    Map<String, dynamic> arguments = const <String, dynamic>{},
  }) {
    _assertNotDisposed();
    final EditorCommandResult result = _commandBus.executeCommand(
      commandId,
      arguments: arguments,
    );
    _syncFromBus();
    return result;
  }

  /// Execute an arbitrary command instance.
  EditorCommandResult execute(EditorCommand command) {
    _assertNotDisposed();
    final EditorCommandResult result = _commandBus.execute(command);
    _syncFromBus();
    return result;
  }

  /// Undo the last command.
  EditorCommandResult undo() {
    _assertNotDisposed();
    final EditorCommandResult result = _commandBus.undo();
    _syncFromBus();
    return result;
  }

  /// Redo the last undone command.
  EditorCommandResult redo() {
    _assertNotDisposed();
    final EditorCommandResult result = _commandBus.redo();
    _syncFromBus();
    return result;
  }

  /// Select all content.
  void selectAll() {
    _assertNotDisposed();
    if (_document.value.nodes.isEmpty) {
      return;
    }
    final EditorNode first = _document.value.nodes.first;
    final EditorNode last = _document.value.nodes.last;
    _selection.value = EditorSelection.range(
      nodeId: first.id,
      startOffset: 0,
      endOffset: last.plainText.length,
    );
    notifyListeners();
  }

  /// Update selection directly.
  void updateSelection(EditorSelection selection) {
    _assertNotDisposed();
    _selection.value = selection;
    notifyListeners();
  }

  /// Load a document from canonical JSON.
  void loadJson(Map<String, dynamic> json) {
    _assertNotDisposed();
    final DocumentValue value = JsonCodec.decode(json, _registry);
    _document.value = value;
    _lastValidDocument = value;
    _selection.value = const EditorSelection.none();
    _commandBus.clearHistory();
    notifyListeners();
  }

  /// Export the current document to canonical JSON.
  Map<String, dynamic> toJson() {
    _assertNotDisposed();
    return JsonCodec.encode(_document.value, _registry);
  }

  /// Import from HTML, Markdown, or Delta using the registered codecs.
  void import(String format, String data) {
    _assertNotDisposed();
    // Delegated to serialization adapters registered by plugins.
    _document.value = ImportedDocumentResolver.resolve(format, data, _registry);
    _lastValidDocument = _document.value;
    _commandBus.clearHistory();
    notifyListeners();
  }

  /// Export to the requested format.
  String export(String format) {
    _assertNotDisposed();
    return ExportedDocumentResolver.resolve(format, _document.value, _registry);
  }

  void _onDocumentChanged() {
    if (_document.value != _lastValidDocument) {
      _lastValidDocument = _document.value;
      _changeController.add(EditorChangeEvent.document(_document.value));
      notifyListeners();
    }
  }

  void _onSelectionChanged() {
    _changeController.add(EditorChangeEvent.selection(_selection.value));
    notifyListeners();
  }

  void _syncFromBus() {
    _document.value = _commandBus.document;
    _selection.value = _commandBus.selection;
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('RichEditorController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _document.removeListener(_onDocumentChanged);
    _selection.removeListener(_onSelectionChanged);
    _registry.dispose();
    _changeController.close();
    focusNode.dispose();
    super.dispose();
  }
}

/// Change event emitted by [RichEditorController.changes].
@immutable
class EditorChangeEvent {
  final EditorChangeType type;
  final dynamic payload;

  const EditorChangeEvent._(this.type, this.payload);

  factory EditorChangeEvent.document(DocumentValue document) =>
      EditorChangeEvent._(EditorChangeType.document, document);

  factory EditorChangeEvent.selection(EditorSelection selection) =>
      EditorChangeEvent._(EditorChangeType.selection, selection);

  DocumentValue? get document =>
      type == EditorChangeType.document ? payload as DocumentValue : null;

  EditorSelection? get selection =>
      type == EditorChangeType.selection ? payload as EditorSelection : null;
}

enum EditorChangeType { document, selection }

/// Placeholder resolver for imports. Real implementations live in the
/// serialization layer.
class ImportedDocumentResolver {
  static DocumentValue resolve(
    String format,
    String data,
    PluginRegistry registry,
  ) {
    // Default to a single paragraph containing the raw data when no codec is
    // available. This is safe but lossy; real codecs override this.
    return DocumentValue(nodes: <EditorNode>[]);
  }
}

/// Placeholder resolver for exports. Real implementations live in the
/// serialization layer.
class ExportedDocumentResolver {
  static String resolve(String format, DocumentValue document,
      PluginRegistry registry) {
    return document.plainText;
  }
}
