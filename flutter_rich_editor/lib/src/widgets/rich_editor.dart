import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/controller/rich_editor_controller.dart';
import '../core/document_model/document_value.dart';
import '../features/voice_input/voice_insert_mode.dart';
import '../theme/editor_theme.dart';
import '../toolbar/toolbar_config.dart';
import 'editor_config.dart';
import 'ckeditor_stub.dart'
    if (dart.library.js_interop) 'ckeditor_web.dart';
import 'rich_editor_native.dart';

/// Primary WYSIWYG rich text editor widget.
///
/// On Web ([kIsWeb]), delegates to [CKEditorWebView] to provide 100% feature
/// parity with CKEditor 5 (full table styling, formulas, media embeds, and native
/// browser multi-element selection/hover).
///
/// On non-web platforms, renders the native Flutter editor canvas.
class RichEditor extends StatefulWidget {
  const RichEditor({
    super.key,
    required this.controller,
    this.theme = const EditorTheme(),
    this.config = const EditorConfig(),
    this.toolbarConfig = const ToolbarConfig(),
    this.onChanged,
    // ── Voice input convenience shortcuts ────────────────────────────────────
    this.onVoiceRecord,
    this.onVoiceTranscribe,
    this.onVoiceInput,
    this.onMicPressed,
    this.onVoiceError,
    this.voiceInsertMode = VoiceInsertMode.insertAtCursor,
  });

  final RichEditorController controller;
  final EditorTheme theme;
  final EditorConfig config;
  final ToolbarConfig toolbarConfig;
  final ValueChanged<DocumentValue>? onChanged;

  // ── Voice input (optional) ────────────────────────────────────────────────

  /// Called when the user confirms their voice input.
  ///
  /// Can be either:
  /// - `Future<String?> Function(String text)`: receives the transcribed text,
  ///   calls your API, and returns the HTML to be inserted.
  /// - `Future<String?> Function()`: legacy/custom recording flow without arguments.
  final dynamic onVoiceInput;

  /// Optional direct callback when the mic button is tapped.
  final VoidCallback? onMicPressed;

  /// Starts the microphone and returns raw audio bytes when recording stops.
  /// When non-null the mic button is automatically shown in the toolbar.
  final Future<Uint8List> Function()? onVoiceRecord;

  /// Receives the audio bytes, calls your voice-to-HTML API, and returns
  /// the HTML string to be inserted into the editor.
  final Future<String> Function(Uint8List bytes)? onVoiceTranscribe;

  /// Optional error handler.  Receives a human-readable message on failure.
  final void Function(String message)? onVoiceError;

  /// Where to insert the returned HTML. Defaults to [VoiceInsertMode.insertAtCursor].
  final VoiceInsertMode voiceInsertMode;

  @override
  State<RichEditor> createState() => _RichEditorState();
}

class _RichEditorState extends State<RichEditor> {
  void Function(String html)? _setWebHtml;
  bool _isSyncingFromWeb = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant RichEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted || _isSyncingFromWeb) return;
    if (kIsWeb) {
      _setWebHtml?.call(widget.controller.toHtml());
    }
    setState(() {});
  }

  void _onWebContentChanged(String html) {
    if (_isSyncingFromWeb) return;
    _isSyncingFromWeb = true;
    try {
      widget.controller.loadHtml(html);
    } catch (_) {}
    _isSyncingFromWeb = false;
    widget.onChanged?.call(widget.controller.document);
  }

  static Future<String?> _invokeVoiceCallback(dynamic callback, [String text = '']) async {
    if (callback == null) return null;
    if (callback is Future<String?> Function(String)) {
      return await callback(text);
    }
    if (callback is Future<String?> Function()) {
      return await callback();
    }
    if (callback is Function) {
      try {
        final dynamic res = await (callback as dynamic)(text);
        return res is String ? res : res?.toString();
      } catch (_) {
        try {
          final dynamic res = await (callback as dynamic)();
          return res is String ? res : res?.toString();
        } catch (_) {}
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Merge voice callbacks into toolbarConfig when provided at the widget level.
    final bool hasWidgetVoice = widget.onVoiceInput != null ||
        widget.onMicPressed != null ||
        widget.onVoiceRecord != null ||
        widget.onVoiceTranscribe != null;

    final ToolbarConfig effectiveToolbarConfig = hasWidgetVoice
        ? ToolbarConfig(
            hiddenItemIds: widget.toolbarConfig.hiddenItemIds,
            orderedItemIds: widget.toolbarConfig.orderedItemIds,
            customItems: widget.toolbarConfig.customItems,
            // On native, ToolbarConfig.onVoiceInput has no text arg — adapt dynamically
            onVoiceInput: widget.onVoiceInput != null
                ? () => _invokeVoiceCallback(widget.onVoiceInput, '')
                : widget.toolbarConfig.onVoiceInput,
            onMicPressed: widget.onMicPressed ?? widget.toolbarConfig.onMicPressed,
            onVoiceRecord: widget.onVoiceRecord ?? widget.toolbarConfig.onVoiceRecord,
            onVoiceTranscribe: widget.onVoiceTranscribe ?? widget.toolbarConfig.onVoiceTranscribe,
            onVoiceError: widget.onVoiceError ?? widget.toolbarConfig.onVoiceError,
            voiceInsertMode: widget.voiceInsertMode,
          )
        : widget.toolbarConfig;

    if (kIsWeb) {
      Future<String?> Function(String)? webVoiceInput;
      if (widget.onVoiceInput != null) {
        webVoiceInput = (String text) => _invokeVoiceCallback(widget.onVoiceInput, text);
      } else if (widget.toolbarConfig.onVoiceInput != null) {
        webVoiceInput = (String _) => widget.toolbarConfig.onVoiceInput!();
      }

      return CKEditorWebView(
        key: widget.key ?? ValueKey<int>(widget.controller.hashCode),
        initialHtml: widget.controller.toHtml(),
        isDark: widget.theme.isDark,
        placeholder: widget.config.placeholder,
        onContentChanged: _onWebContentChanged,
        onEditorReady: (void Function(String html) setHtml) {
          _setWebHtml = setHtml;
        },
        onVoiceInput: webVoiceInput,
      );
    }

    return RichEditorNative(
      controller: widget.controller,
      theme: widget.theme,
      config: widget.config,
      toolbarConfig: effectiveToolbarConfig,
      onChanged: widget.onChanged,
    );
  }
}
