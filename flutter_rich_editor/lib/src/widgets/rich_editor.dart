import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/controller/rich_editor_controller.dart';
import '../core/document_model/document_value.dart';
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
  });

  final RichEditorController controller;
  final EditorTheme theme;
  final EditorConfig config;
  final ToolbarConfig toolbarConfig;
  final ValueChanged<DocumentValue>? onChanged;

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

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return CKEditorWebView(
        key: const ValueKey<String>('ckeditor_web_view'),
        initialHtml: widget.controller.toHtml(),
        isDark: widget.theme.isDark,
        placeholder: widget.config.placeholder,
        onContentChanged: _onWebContentChanged,
        onEditorReady: (void Function(String html) setHtml) {
          _setWebHtml = setHtml;
        },
      );
    }

    return RichEditorNative(
      controller: widget.controller,
      theme: widget.theme,
      config: widget.config,
      toolbarConfig: widget.toolbarConfig,
      onChanged: widget.onChanged,
    );
  }
}
