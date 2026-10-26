import 'dart:typed_data';

import '../../core/command_bus/command_bus.dart';
import '../../core/controller/rich_editor_controller.dart';
import '../../core/document_model/document_value.dart';
import '../../core/document_model/editor_node.dart';
import '../../core/document_model/editor_selection.dart';
import '../../serialization/html_codec.dart';
import 'voice_insert_mode.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Command: InsertHtmlAtCursorCommand
// ─────────────────────────────────────────────────────────────────────────────

/// Inserts a decoded HTML snippet into the document at the current cursor's
/// node position, preserving all content before and after the insertion point.
///
/// This command is undo-safe — it is dispatched through the [CommandBus] so
/// the user can Ctrl+Z the voice insertion just like any other edit.
class InsertHtmlAtCursorCommand extends EditorCommand {
  InsertHtmlAtCursorCommand({
    required this.htmlSnippet,
    required this.cursorNodeIndex,
  });

  /// The raw HTML string returned by the voice API.
  final String htmlSnippet;

  /// The node index where the cursor was when the user triggered voice input.
  /// New nodes are inserted *after* this index.
  final int cursorNodeIndex;

  static const HtmlDocumentCodec _codec = HtmlDocumentCodec();

  @override
  String get id => 'voice.insertHtmlAtCursor';

  @override
  CommandResult execute(DocumentValue document) {
    // Decode the API HTML into a list of EditorNodes
    final DocumentValue apiDoc = _codec.decode(htmlSnippet);
    if (apiDoc.nodes.isEmpty) {
      return CommandResult.failure(
        currentDocument: document,
        code: 'voice.empty_response',
        message: 'The voice API returned no content.',
      );
    }

    final List<EditorNode> existing = List<EditorNode>.from(document.nodes);
    if (existing.isEmpty) {
      return CommandResult.ok(
        document.copyWith(
          nodes: apiDoc.nodes,
          selection: const EditorSelection.collapsed(0, nodeIndex: 0),
        ),
      );
    }

    // Clamp the insert index so we never go out of bounds
    final int insertAfter = cursorNodeIndex.clamp(0, existing.length - 1);

    // Split existing nodes around the cursor position
    final List<EditorNode> before = existing.sublist(0, insertAfter + 1);
    final List<EditorNode> after =
        insertAfter + 1 < existing.length ? existing.sublist(insertAfter + 1) : <EditorNode>[];

    // Merge: [before nodes] + [api nodes] + [after nodes]
    final List<EditorNode> merged = <EditorNode>[
      ...before,
      ...apiDoc.nodes,
      ...after,
    ];

    // Move cursor to the first node of the inserted content
    final int newCursorIndex = insertAfter + 1;

    return CommandResult.ok(
      document.copyWith(
        nodes: merged,
        selection: EditorSelection.collapsed(0, nodeIndex: newCursorIndex),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Command: AppendHtmlCommand
// ─────────────────────────────────────────────────────────────────────────────

/// Appends a decoded HTML snippet to the end of the existing document,
/// preserving all existing content.
///
/// Also dispatched through the [CommandBus] so it is fully undo-able.
class AppendHtmlCommand extends EditorCommand {
  AppendHtmlCommand({required this.htmlSnippet});

  /// The raw HTML string returned by the voice API.
  final String htmlSnippet;

  static const HtmlDocumentCodec _codec = HtmlDocumentCodec();

  @override
  String get id => 'voice.appendHtml';

  @override
  CommandResult execute(DocumentValue document) {
    final DocumentValue apiDoc = _codec.decode(htmlSnippet);
    if (apiDoc.nodes.isEmpty) {
      return CommandResult.failure(
        currentDocument: document,
        code: 'voice.empty_response',
        message: 'The voice API returned no content.',
      );
    }

    final List<EditorNode> merged = <EditorNode>[
      ...document.nodes,
      ...apiDoc.nodes,
    ];

    // Move cursor to the first appended node
    final int newCursorIndex = document.nodes.length;

    return CommandResult.ok(
      document.copyWith(
        nodes: merged,
        selection: EditorSelection.collapsed(0, nodeIndex: newCursorIndex),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VoiceInputHandler  (the logic the plugin exposes — no UI here)
// ─────────────────────────────────────────────────────────────────────────────

/// Encapsulates the voice-input workflow logic independently of any widget.
///
/// The consuming app provides:
/// - [onRecord]      → records audio and returns raw bytes
/// - [onTranscribe]  → sends bytes to the voice API and returns HTML
/// - [onError]       → receives any error message string
///
/// The handler then injects the returned HTML into the [RichEditorController]
/// using the specified [insertMode].
///
/// Usage in the consuming app:
/// ```dart
/// final handler = VoiceInputHandler(
///   controller: _editorController,
///   insertMode: VoiceInsertMode.insertAtCursor,
///   onRecord: () async {
///     await _audioRecorder.start(...);
///     // user taps stop →
///     final path = await _audioRecorder.stop();
///     return File(path).readAsBytes();
///   },
///   onTranscribe: (Uint8List bytes) async {
///     final res = await http.post(Uri.parse('https://api.example.com/voice'),
///       body: bytes);
///     return (jsonDecode(res.body) as Map)['html'] as String;
///   },
///   onError: (msg) => ScaffoldMessenger.of(context)
///       .showSnackBar(SnackBar(content: Text(msg))),
/// );
///
/// // Trigger from a button or mic icon:
/// await handler.startRecording();
/// await handler.stopAndProcess();
/// ```
class VoiceInputHandler {
  VoiceInputHandler({
    required this.controller,
    required this.onRecord,
    required this.onTranscribe,
    this.onError,
    this.insertMode = VoiceInsertMode.insertAtCursor,
  });

  // ── Dependencies injected by the consuming app ────────────────────────────

  /// The editor controller this handler will mutate.
  final RichEditorController controller;

  /// Called by the handler to start and stop audio recording.
  ///
  /// The app owns the microphone — this handler just invokes the callback.
  /// **The callback must:**
  ///   1. Start recording when called.
  ///   2. Return the raw audio [Uint8List] when the user stops.
  ///
  /// The handler calls this once when [startRecording] is triggered, and awaits
  /// the future (which resolves when recording ends) inside [stopAndProcess].
  final Future<Uint8List> Function() onRecord;

  /// Called with the raw audio bytes captured by [onRecord].
  ///
  /// The app owns the API — this handler just calls the callback and expects
  /// a valid HTML [String] back.
  final Future<String> Function(Uint8List audioBytes) onTranscribe;

  /// Optional callback for error reporting. Receives a human-readable message.
  final void Function(String error)? onError;

  /// Controls where the returned HTML is placed inside the editor.
  final VoiceInsertMode insertMode;

  // ── Internal state ────────────────────────────────────────────────────────

  bool _isRecording = false;
  Future<Uint8List>? _recordingFuture;

  /// Whether recording is currently active.
  bool get isRecording => _isRecording;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Starts listening to the microphone via [onRecord].
  ///
  /// The cursor position is captured at this moment so that
  /// [VoiceInsertMode.insertAtCursor] inserts at the right spot even if
  /// the user taps elsewhere while speaking.
  void startRecording() {
    if (_isRecording) return;
    _isRecording = true;
    _recordingFuture = onRecord();
  }

  /// Stops recording, calls [onTranscribe] with the captured bytes,
  /// and injects the returned HTML into the editor using [insertMode].
  ///
  /// Returns `true` on success, `false` on any failure.
  Future<bool> stopAndProcess() async {
    if (!_isRecording || _recordingFuture == null) return false;
    _isRecording = false;

    // Snapshot cursor position NOW (before any async gap)
    final int cursorNodeIndex = controller.selection.nodeIndex;

    try {
      final Uint8List audioBytes = await _recordingFuture!;
      _recordingFuture = null;

      if (audioBytes.isEmpty) {
        onError?.call('No audio was captured. Please try again.');
        return false;
      }

      final String html = await onTranscribe(audioBytes);

      if (html.trim().isEmpty) {
        onError?.call('The voice API returned an empty response.');
        return false;
      }

      _injectHtml(html, cursorNodeIndex);
      return true;
    } catch (e) {
      _recordingFuture = null;
      onError?.call('Voice input failed: $e');
      return false;
    }
  }

  /// Cancels an in-progress recording without processing.
  void cancel() {
    _isRecording = false;
    _recordingFuture = null;
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _injectHtml(String html, int cursorNodeIndex) {
    switch (insertMode) {
      case VoiceInsertMode.replace:
        // Replaces entire document — uses existing loadHtml on the controller
        controller.loadHtml(html);

      case VoiceInsertMode.append:
        // Undo-safe: dispatched through CommandBus
        controller.execute(AppendHtmlCommand(htmlSnippet: html));

      case VoiceInsertMode.insertAtCursor:
        // Undo-safe: dispatched through CommandBus, inserts at captured cursor
        controller.execute(
          InsertHtmlAtCursorCommand(
            htmlSnippet: html,
            cursorNodeIndex: cursorNodeIndex,
          ),
        );
    }
  }
}
