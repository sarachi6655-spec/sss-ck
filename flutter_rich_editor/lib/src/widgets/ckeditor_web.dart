import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Web implementation of the CKEditor 5 rich text editor embedded via [HtmlElementView].
///
/// Provides near-100% parity with CKEditor 5 free features and custom
/// implementations for premium-like features (track changes, export to
/// PDF/Word, revision history, document outline, templates, mentions,
/// AI assistant, etc.).
class CKEditorWebView extends StatefulWidget {
  const CKEditorWebView({
    super.key,
    required this.initialHtml,
    required this.isDark,
    required this.placeholder,
    required this.onContentChanged,
    this.onEditorReady,
    this.onVoiceInput,
  });

  final String initialHtml;
  final bool isDark;
  final String placeholder;
  final void Function(String html) onContentChanged;
  final void Function(void Function(String html) setHtml)? onEditorReady;

  /// Called when the user completes a voice recording in the editor.
  /// Receives the raw transcribed [text], calls your API, and returns the
  /// HTML to be inserted. Return `null` to cancel insertion.
  final Future<String?> Function(String text)? onVoiceInput;

  @override
  State<CKEditorWebView> createState() => _CKEditorWebViewState();
}

class _CKEditorWebViewState extends State<CKEditorWebView> {
  late final String _viewType;
  late final String _editorId;
  web.HTMLIFrameElement? _iframe;
  JSFunction? _messageListener;
  String? _lastReportedHtml;

  @override
  void initState() {
    super.initState();
    final int uniqueId = DateTime.now().microsecondsSinceEpoch;
    _editorId = 'ckeditor_$uniqueId';
    _viewType = 'ckeditor-view-$uniqueId';
    _lastReportedHtml = widget.initialHtml;

    _registerViewFactory();
    _setupMessageListener();

    widget.onEditorReady?.call(setHtml);
  }

  @override
  void didUpdateWidget(covariant CKEditorWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialHtml != widget.initialHtml && widget.initialHtml != _lastReportedHtml) {
      _lastReportedHtml = widget.initialHtml;
      setHtml(widget.initialHtml);
    }
    if (oldWidget.isDark != widget.isDark) {
      _sendThemeUpdate(widget.isDark);
    }
  }

  void _sendThemeUpdate(bool isDark) {
    if (_iframe?.contentWindow == null) return;
    _iframe!.contentWindow!.postMessage(
      jsonEncode(<String, dynamic>{
        'type': 'setTheme',
        'isDark': isDark,
      }).toJS,
      '*'.toJS,
    );
  }

  void _registerViewFactory() {
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int id) {
      final web.HTMLIFrameElement iframe = web.document.createElement('iframe') as web.HTMLIFrameElement;
      iframe.style.border = 'none';
      iframe.style.width = '100%';
      iframe.style.height = '100%';
      iframe.setAttribute('allow', 'clipboard-read; clipboard-write; fullscreen; microphone');
      iframe.setAttribute('allowfullscreen', 'true');
      iframe.srcdoc = _generateHtmlTemplate().toJS;
      _iframe = iframe;
      return iframe;
    });
  }

  void _setupMessageListener() {
    final JSFunction listener = ((web.Event event) {
      if (event is web.MessageEvent) {
        final JSAny? data = event.data;
        if (data != null && data.isA<JSString>()) {
          try {
            final String jsonStr = (data as JSString).toDart;
            final dynamic decoded = jsonDecode(jsonStr);
            if (decoded is Map<String, dynamic>) {
              final String? type = decoded['type'] as String?;
              final String? targetId = decoded['editorId'] as String?;
              if (targetId != _editorId) return;

              if (type == 'ckeditor_ready') {
                setHtml(widget.initialHtml);
                _sendThemeUpdate(widget.isDark);
              } else if (type == 'ckeditor_change') {
                final String html = decoded['html'] as String? ?? '';
                _lastReportedHtml = html;
                widget.onContentChanged(html);
              } else if (type == 'voice_input') {
                final String text = decoded['text'] as String? ?? '';
                _handleVoiceInput(text);
              } else if (type == 'ai_generate_request') {
                final String text = decoded['text'] as String? ?? '';
                _handleAiGenerate(text);
              }
            }
          } catch (_) {}
        }
      }
    }).toJS;
    _messageListener = listener;
    web.window.addEventListener('message', listener);
  }

  /// Handles an AI generation request from the in-editor AI modal.
  /// Calls [widget.onVoiceInput] with the user-reviewed prompt and inserts
  /// the returned HTML upon completion.
  Future<void> _handleAiGenerate(String promptText) async {
    if (promptText.trim().isEmpty) return;
    if (!mounted) return;

    if (widget.onVoiceInput == null) {
      _sendAiError('No AI generation handler is configured on the editor.');
      return;
    }

    try {
      final String? html = await widget.onVoiceInput!(promptText.trim());
      if (html != null && html.isNotEmpty) {
        _insertVoiceHtml(html);
      } else {
        _sendAiError('The AI generation API returned no content.');
      }
    } catch (e) {
      _sendAiError('AI generation failed: $e');
    }
  }

  /// Sends an error message to the iframe so the AI modal can display it.
  void _sendAiError(String error) {
    if (_iframe?.contentWindow == null) return;
    _iframe!.contentWindow!.postMessage(
      jsonEncode(<String, dynamic>{
        'type': 'ai_generate_error',
        'error': error,
      }).toJS,
      '*'.toJS,
    );
  }

  /// Receives the transcribed [text] from JS, shows a correction bottom sheet
  /// so the user can review/edit the transcript, calls [onVoiceInput] with
  /// the user's content, and inserts the returned HTML into CKEditor.
  Future<void> _handleVoiceInput(String text) async {
    if (text.isEmpty) return;
    if (!mounted) return;

    // Show the correction / review dialog and call onVoiceInput when confirmed.
    final String? html = await _showVoiceCorrectionSheet(text, widget.onVoiceInput);
    if (html != null && html.isNotEmpty) {
      _insertVoiceHtml(html);
    }
  }

  /// Shows a bottom sheet where the user can review and correct the auto-transcribed
  /// text before it is sent to the API.
  ///
  /// Calls [onVoiceInput] with the user's content when they tap Insert,
  /// displaying a progress indicator until the HTML response is received.
  Future<String?> _showVoiceCorrectionSheet(
    String initialText,
    Future<String?> Function(String)? onVoiceInput,
  ) async {
    final TextEditingController textCtrl = TextEditingController(text: initialText);
    textCtrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: initialText.length,
    );

    bool isLoading = false;
    String? errorMessage;

    final String? result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF1E293B),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF475569),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Title row
                    Row(
                      children: <Widget>[
                        const Text('\u{2728}', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Generate with AI',
                            style: TextStyle(
                              color: Color(0xFFF1F5F9),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: isLoading ? null : () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Review or edit your prompt before sending to the API.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    // Editable transcript field
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: TextField(
                        controller: textCtrl,
                        maxLines: 5,
                        minLines: 2,
                        autofocus: true,
                        enabled: !isLoading,
                        style: const TextStyle(
                          color: Color(0xFFE2E8F0),
                          fontSize: 14,
                          height: 1.6,
                        ),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.all(12),
                          border: InputBorder.none,
                          hintText: 'Your transcribed text\u2026',
                          hintStyle: TextStyle(color: Color(0xFF475569)),
                        ),
                      ),
                    ),
                    if (errorMessage != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        errorMessage!,
                        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Action buttons
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isLoading ? null : () => Navigator.of(ctx).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF94A3B8),
                              side: const BorderSide(color: Color(0xFF334155)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: (isLoading || textCtrl.text.trim().isEmpty)
                                ? null
                                : () async {
                                    final String promptText = textCtrl.text.trim();
                                    if (onVoiceInput == null) {
                                      Navigator.of(ctx).pop('<p>$promptText</p>');
                                      return;
                                    }
                                    setSheetState(() {
                                      isLoading = true;
                                      errorMessage = null;
                                    });
                                    try {
                                      final String? html = await onVoiceInput(promptText);
                                      if (ctx.mounted) {
                                        if (html != null && html.isNotEmpty) {
                                          Navigator.of(ctx).pop(html);
                                        } else {
                                          setSheetState(() {
                                            isLoading = false;
                                            errorMessage = 'Failed to generate HTML content.';
                                          });
                                        }
                                      }
                                    } catch (e) {
                                      if (ctx.mounted) {
                                        setSheetState(() {
                                          isLoading = false;
                                          errorMessage = 'AI Generation Error: $e';
                                        });
                                      }
                                    }
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: isLoading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded, size: 16),
                            label: Text(
                              isLoading ? 'Generating HTML\u2026' : '\u{2728} Generate with AI',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    textCtrl.dispose();
    return result;
  }

  /// Sends an `insertVoiceHtml` message into the iframe so the JS layer can
  /// insert the HTML at the current cursor position in CKEditor.
  void _insertVoiceHtml(String html) {
    if (_iframe?.contentWindow == null) return;
    _iframe!.contentWindow!.postMessage(
      jsonEncode(<String, dynamic>{
        'type': 'insertVoiceHtml',
        'html': html,
      }).toJS,
      '*'.toJS,
    );
  }

  void setHtml(String html) {
    _lastReportedHtml = html;
    if (_iframe?.contentWindow == null) return;
    _iframe!.contentWindow!.postMessage(
      jsonEncode(<String, dynamic>{
        'type': 'setHtml',
        'html': html,
      }).toJS,
      '*'.toJS,
    );
  }

  @override
  void dispose() {
    if (_messageListener != null) {
      web.window.removeEventListener('message', _messageListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }

  String _generateHtmlTemplate() {
    final String darkClass = widget.isDark ? 'dark' : 'light';
    final String initialJson = jsonEncode(widget.initialHtml).replaceAll('<', r'\u003c');
    final String placeholderJson = jsonEncode(widget.placeholder).replaceAll('<', r'\u003c');
    final String editorIdJson = jsonEncode(_editorId).replaceAll('<', r'\u003c');
    final bool isInitialRtl = widget.initialHtml.contains('dir="rtl"') || widget.initialHtml.contains("dir='rtl'") || widget.initialHtml.contains('direction:rtl') || widget.initialHtml.contains('direction: rtl');
    final String initialDir = isInitialRtl ? 'rtl' : 'ltr';
    final String ltrSelected = !isInitialRtl ? 'selected' : '';
    final String rtlSelected = isInitialRtl ? 'selected' : '';

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="format-detection" content="telephone=no">
  <title>CKEditor 5 — Full Featured</title>
  <!-- Non-blocking KaTeX CSS -->
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css" media="print" onload="this.media='all'">
  <!-- Non-blocking Google Fonts -->
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Fira+Code:ital,wght@0,400;0,500;0,600;1,400;1,500;1,600&family=Inter:ital,wght@0,400;0,500;0,600;0,700;1,400;1,500;1,600;1,700&family=Lato:ital,wght@0,400;0,700;1,400;1,700&family=Montserrat:ital,wght@0,400;0,600;0,700;1,400;1,600;1,700&family=Open+Sans:ital,wght@0,400;0,600;0,700;1,400;1,600;1,700&family=Poppins:ital,wght@0,400;0,500;0,600;0,700;1,400;1,500;1,600;1,700&family=Roboto:ital,wght@0,400;0,500;0,700;1,400;1,500;1,700&display=swap" rel="stylesheet" media="print" onload="this.media='all'">
  <style>
    /* ====== RESET & BASE ====== */
    * { box-sizing: border-box; margin: 0; padding: 0; }
    html, body {
      width: 100%; height: 100%; min-height: 100%; overflow: hidden;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, Cantarell, "Helvetica Neue", sans-serif;
      font-size: 14px;
      background: #ffffff; color: #1e293b;
      touch-action: manipulation;
      -webkit-tap-highlight-color: transparent;
      transition: background 0.2s, color 0.2s;
    }
    @keyframes spin { 100% { transform: rotate(360deg); } }
    @keyframes voicePulse {
      0% { box-shadow: 0 0 0 0 rgba(220, 38, 38, 0.5); }
      70% { box-shadow: 0 0 0 8px rgba(220, 38, 38, 0); }
      100% { box-shadow: 0 0 0 0 rgba(220, 38, 38, 0); }
    }
    #btn-voice-to-text.listening {
      background: #dc2626 !important;
      color: #ffffff !important;
      border-color: #b91c1c !important;
      animation: voicePulse 1.5s infinite;
    }
    /* ====== MAIN LAYOUT ====== */
    #app-container {
      display: flex; flex-direction: column; width: 100%; height: 100%; min-height: 100%;
      position: relative; overflow: hidden;
    }
    #app-container.fullscreen-mode {
      position: fixed !important;
      top: 0 !important;
      left: 0 !important;
      width: 100vw !important;
      height: 100vh !important;
      height: 100dvh !important;
      z-index: 2147483647 !important;
      background: #ffffff !important;
    }
    body.dark #app-container.fullscreen-mode {
      background: #1e1e2e !important;
    }
    /* Custom action bar (above CKEditor toolbar) - Smooth horizontal touch scroll */
    #action-bar {
      display: flex; align-items: center; gap: 6px; padding: 6px 10px;
      background: #f1f5f9; border-bottom: 1px solid #e2e8f0;
      flex-shrink: 0; flex-wrap: nowrap; min-height: 40px;
      overflow-x: auto; white-space: nowrap;
      -webkit-overflow-scrolling: touch;
      touch-action: pan-x;
      scrollbar-width: none;
      overscroll-behavior-x: contain;
    }
    #action-bar::-webkit-scrollbar { display: none; }
    #action-bar button, #action-bar select {
      flex-shrink: 0;
      padding: 5px 10px; border: 1px solid #cbd5e1; border-radius: 6px;
      background: #ffffff; cursor: pointer; font-size: 12px; font-weight: 500; color: #334155;
      transition: all 0.15s ease;
      white-space: nowrap;
      display: inline-flex; align-items: center; gap: 4px;
      user-select: none;
      touch-action: manipulation;
      -webkit-tap-highlight-color: transparent;
    }
    #action-bar button:hover { background: #e2e8f0; border-color: #94a3b8; }
    #action-bar button:active { transform: scale(0.97); }
    #action-bar button.active { background: #3b82f6; color: white; border-color: #3b82f6; box-shadow: 0 2px 4px rgba(59,130,246,0.25); }
    #action-bar .separator { width: 1px; height: 20px; background: #cbd5e1; margin: 0 4px; flex-shrink: 0; }
    /* ====== EDITOR WRAPPER ====== */
    #editor-wrapper {
      display: flex; flex: 1 1 auto; overflow: hidden; position: relative; min-height: 250px;
    }
    #editor-main {
      flex: 1 1 auto; display: flex; flex-direction: column;
      overflow: hidden; min-width: 0; min-height: 250px;
    }
    /* ====== CKEDITOR CUSTOMIZATION ====== */
    .ck.ck-editor { display: flex !important; flex-direction: column !important; height: 100% !important; width: 100% !important; border: none !important; border-radius: 0 !important; }
    .ck.ck-editor__top { flex-shrink: 0 !important; }
    .ck.ck-toolbar { border: none !important; border-bottom: 1px solid #e2e8f0 !important; background: #f8fafc !important; padding: 3px 6px !important; flex-wrap: wrap !important; overflow: visible !important; }
    .ck.ck-toolbar .ck-toolbar__items { flex-wrap: wrap !important; overflow: visible !important; }
    .ck.ck-toolbar .ck-toolbar__separator { background: #e2e8f0 !important; }
    .ck.ck-editor__main { flex: 1 1 auto !important; overflow-y: auto !important; height: 0 !important; }
    .ck-content { min-height: 100% !important; padding: 14px 20px !important; font-size: 15px !important; line-height: 1.7 !important; cursor: text !important; font-synthesis: weight style small-caps !important; -webkit-font-smoothing: antialiased; }
    .ck-content * { font-synthesis: weight style small-caps !important; }
    .ck-content:focus { outline: none !important; }
    .ck-content i, .ck-content em, .ck-content cite, .ck-content dfn,
    .ck-content [style*="font-style: italic"], .ck-content [style*="font-style:italic"], .ck-content span[style*="italic"] {
      font-style: italic !important;
    }
    /* Heading Styles */
    .ck-content h1 { font-size: 2em; font-weight: 700; margin: 0.67em 0; color: #0f172a; }
    .ck-content h2 { font-size: 1.5em; font-weight: 600; margin: 0.83em 0; color: #1e293b; }
    .ck-content h3 { font-size: 1.17em; font-weight: 600; margin: 1em 0; color: #334155; }
    .ck-content h4 { font-size: 1em; font-weight: 600; margin: 1.33em 0; color: #475569; }
    /* Blockquote */
    .ck-content blockquote { border-left: 4px solid #3b82f6; padding: 12px 20px; margin: 16px 0; background: #eff6ff; border-radius: 0 8px 8px 0; font-style: italic; color: #1e40af; }
    /* Code block */
    .ck-content pre { background: #1e293b; color: #e2e8f0; padding: 16px 20px; border-radius: 8px; overflow-x: auto; font-family: 'Fira Code', 'Consolas', monospace; font-size: 13px; line-height: 1.5; margin: 16px 0; }
    .ck-content code { background: #f1f5f9; padding: 2px 6px; border-radius: 4px; font-family: 'Fira Code', 'Consolas', monospace; font-size: 0.9em; color: #e11d48; }
    .ck-content pre code { background: none; padding: 0; color: inherit; }
    /* Table */
    .ck-content figure.table {
      display: block !important;
      width: 100% !important;
      max-width: 100% !important;
      margin: 14px 0 !important;
      overflow-x: auto !important;
      -webkit-overflow-scrolling: touch !important;
      box-sizing: border-box !important;
    }
    .ck-content figure.table table,
    .ck-content table,
    #fallback-content table {
      border-collapse: collapse !important;
      width: 100% !important;
      min-width: 100% !important;
      margin: 0 !important;
      display: table !important;
      box-sizing: border-box !important;
      /* Columns keep their set widths (equal, or the dragged <colgroup> widths); content wraps instead of widening them */
      table-layout: fixed !important;
    }
    .ck-content table td, .ck-content table th,
    #fallback-content table td, #fallback-content table th {
      overflow-wrap: anywhere;
      word-break: break-word;
    }
    .ck-content table td img, .ck-content table th img,
    .ck-content table td figure, .ck-content table th figure {
      max-width: 100%;
      height: auto;
    }
    /* Table Caption */
    .ck-content figure.table figcaption,
    .ck-content .table > figcaption {
      display: block !important;
      width: 100% !important;
      box-sizing: border-box !important;
      text-align: center !important;
      font-size: 13px !important;
      color: #64748b !important;
      font-style: italic !important;
      padding: 6px 12px !important;
      margin-top: 6px !important;
      min-height: 28px !important;
      line-height: 1.5 !important;
      word-break: normal !important;
      white-space: normal !important;
    }
    .ck-content figure.table figcaption.ck-editor__nested-editable_focused,
    .ck-content figure.table figcaption.ck-focused,
    .ck-content .table > figcaption.ck-editor__nested-editable_focused,
    .ck-content .table > figcaption.ck-focused {
      border: 1px dashed #93c5fd !important;
      background: #f8faff !important;
      border-radius: 4px !important;
      outline: none !important;
    }
    .ck-content table td, .ck-content table th { border: 1px solid #cbd5e1; padding: 8px 12px; text-align: left; vertical-align: top; min-width: 48px; box-sizing: border-box; }
    .ck-content table th { background: #f1f5f9; font-weight: 600; color: #0f172a; }
    .ck-content table tr:nth-child(even) td { background: #f8fafc; }
    .ck-content table td.has-formula, .ck-content table th.has-formula,
    .ck-content table td[data-formula], .ck-content table th[data-formula] {
      position: relative !important;
      background-color: #f8faff !important;
      padding-right: 24px !important;
    }
    .formula-badge {
      position: absolute !important;
      top: 3px !important;
      right: 3px !important;
      z-index: 5 !important;
      display: inline-flex !important;
      align-items: center !important;
      justify-content: center !important;
      font-size: 10px !important;
      line-height: 1 !important;
      padding: 2px 4px !important;
      background: #eff6ff !important;
      color: #1d4ed8 !important;
      border: 1px solid #93c5fd !important;
      border-radius: 4px !important;
      font-weight: 700 !important;
      user-select: none !important;
      cursor: pointer !important;
      box-shadow: 0 1px 2px rgba(37, 99, 235, 0.1) !important;
      transition: all 0.15s ease !important;
    }
    .formula-badge:hover {
      background: #2563eb !important;
      color: #ffffff !important;
      border-color: #1d4ed8 !important;
      box-shadow: 0 2px 6px rgba(37, 99, 235, 0.25) !important;
      transform: scale(1.08) !important;
    }
    /* Highlight */
    .ck-content mark, .ck-content .marker-yellow { background: #fef08a; }
    .ck-content .marker-green { background: #bbf7d0; }
    .ck-content .marker-pink { background: #fbcfe8; }
    .ck-content .marker-blue { background: #bfdbfe; }
    .ck-content .pen-red { color: #dc2626; background: transparent; }
    .ck-content .pen-green { color: #16a34a; background: transparent; }
    /* Todo list - aligned cleanly without left border overflow */
    .ck-content .todo-list,
    .ck-content ul.todo-list,
    .ck-content ol.todo-list {
      list-style: none !important;
      padding-left: 32px !important;
      margin: 8px 0 !important;
    }
    .ck-content .todo-list li {
      position: relative !important;
      margin: 4px 0 !important;
      padding-left: 0 !important;
      display: block !important;
      line-height: 1.6 !important;
    }
    .ck-content .todo-list li .ck-todo-list__label,
    .ck-content .todo-list li label {
      position: absolute !important;
      left: -26px !important;
      top: 2px !important;
      margin: 0 !important;
      display: inline-flex !important;
      align-items: center !important;
      justify-content: center !important;
      cursor: pointer !important;
      user-select: none !important;
      vertical-align: middle !important;
    }
    .ck-content .todo-list li .ck-todo-list__label input[type="checkbox"],
    .ck-content .todo-list li label input[type="checkbox"],
    .ck-content .todo-list input[type="checkbox"] {
      cursor: pointer !important;
      margin: 0 !important;
      width: 16px !important;
      height: 16px !important;
      accent-color: #16a34a !important;
      vertical-align: middle !important;
    }
    .ck-content .todo-list .todo-list {
      padding-left: 28px !important;
    }
    /* Page break */
    .ck-content .page-break { page-break-after: always; border-top: 2px dashed #94a3b8; margin: 32px 0; padding: 8px 0; text-align: center; color: #94a3b8; font-size: 11px; }
    /* Horizontal line */
    .ck-content hr { border: none; border-top: 2px solid #e2e8f0; margin: 24px 0; }
    /* Image */
    .ck-content figure.image { margin: 16px auto; text-align: center; }
    .ck-content figure.image img { max-width: 100%; height: auto; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
    .ck-content figure.image figcaption { font-size: 13px; color: #64748b; margin-top: 8px; font-style: italic; }
    /* Media & Video Embed with Resizing Controls */
    .ck-content figure.media,
    .ck-content .media {
      position: relative !important;
      margin: 16px auto;
      max-width: 100%;
      box-sizing: border-box;
      transition: width 0.2s ease, max-width 0.2s ease;
      display: block !important;
      clear: both;
    }
    .ck-content figure.media iframe,
    .ck-content figure.media video,
    .ck-content .media iframe,
    .ck-content .media video {
      position: static !important;
      width: 100% !important;
      height: auto !important;
      aspect-ratio: 16 / 9 !important;
      min-height: 160px;
      border-radius: 8px;
      box-shadow: 0 4px 14px rgba(0,0,0,0.12);
      display: block;
    }
    .ck-content figure.media.media-align-left { margin-left: 0 !important; margin-right: auto !important; }
    .ck-content figure.media.media-align-center { margin-left: auto !important; margin-right: auto !important; }
    .ck-content figure.media.media-align-right { margin-left: auto !important; margin-right: 0 !important; }
    /* CKEditor blocks clicks on raw HTML embeds (iframe/video) while editing; allow them in Preview so they can play */
    .ck-editor__editable.ck-read-only .html-object-embed .html-object-embed__content { pointer-events: auto; }
    
    /* Video interactive floating resize toolbar */
    .video-resize-toolbar {
      position: fixed;
      background: #1e293b;
      color: white;
      border-radius: 8px;
      padding: 5px 10px;
      display: flex;
      align-items: center;
      gap: 6px;
      font-size: 11px;
      font-weight: 500;
      box-shadow: 0 8px 24px rgba(0,0,0,0.35);
      z-index: 99999;
      white-space: nowrap;
      user-select: none;
      transform: translateX(-50%);
    }
    .video-resize-toolbar button {
      background: #334155;
      color: #f1f5f9;
      border: 1px solid #475569;
      border-radius: 4px;
      padding: 3px 8px;
      font-size: 11px;
      cursor: pointer;
      transition: all 0.15s ease;
    }
    .video-resize-toolbar button:hover {
      background: #475569;
      color: #ffffff;
    }
    .video-resize-toolbar button.active {
      background: #3b82f6;
      border-color: #3b82f6;
      color: white;
    }
    .video-resize-toolbar input[type="range"] {
      width: 75px;
      cursor: pointer;
      accent-color: #3b82f6;
    }

    /* Video corner resize drag handle */
    .video-resize-handle {
      position: absolute;
      bottom: 4px;
      right: 4px;
      width: 14px;
      height: 14px;
      background: #3b82f6;
      border: 2px solid #ffffff;
      border-radius: 3px;
      cursor: se-resize;
      z-index: 100;
      box-shadow: 0 2px 6px rgba(0,0,0,0.3);
    }
    /* List styles */
    .ck-content ul, .ck-content ol { padding-left: 24px; margin: 8px 0; }
    .ck-content li { margin: 4px 0; }
    /* Link */
    .ck-content a { color: #2563eb; text-decoration: underline; }
    .ck-content a:hover { color: #1d4ed8; }
    /* Word count widget */
    .ck-word-count { font-size: 12px; color: #94a3b8; padding: 0 8px; display: flex; gap: 12px; }

    /* ====== SIDE PANEL ====== */
    #side-panel {
      width: 0; overflow: hidden; border-left: 1px solid #e2e8f0;
      background: #f8fafc; transition: width 0.3s ease; flex-shrink: 0;
      display: flex; flex-direction: column;
    }
    #side-panel.open { width: 320px; }
    #side-panel-header {
      display: flex; align-items: center; justify-content: space-between;
      padding: 12px 16px; border-bottom: 1px solid #e2e8f0;
      font-weight: 600; font-size: 14px; color: #0f172a; flex-shrink: 0;
    }
    #side-panel-header button { background: none; border: none; cursor: pointer; font-size: 18px; color: #64748b; }
    #side-panel-content {
      flex: 1; overflow-y: auto; padding: 16px;
    }
    /* ====== STATUS BAR ====== */
    #status-bar {
      display: flex; align-items: center; justify-content: space-between;
      padding: 4px 12px; background: #f8fafc; border-top: 1px solid #e2e8f0;
      font-size: 12px; color: #64748b; flex-shrink: 0; min-height: 28px;
    }
    #status-bar .status-section { display: flex; gap: 16px; align-items: center; }

    /* ====== REVISION HISTORY ====== */
    .revision-item {
      padding: 10px 12px; border: 1px solid #e2e8f0; border-radius: 8px;
      margin-bottom: 8px; cursor: pointer; transition: all 0.15s;
    }
    .revision-item:hover { background: #eff6ff; border-color: #93c5fd; }
    .revision-item.active { background: #dbeafe; border-color: #3b82f6; }
    .revision-item .rev-title { font-weight: 600; font-size: 13px; color: #0f172a; }
    .revision-item .rev-time { font-size: 11px; color: #94a3b8; margin-top: 2px; }
    .revision-item .rev-preview { font-size: 12px; color: #64748b; margin-top: 4px; max-height: 40px; overflow: hidden; }

    /* ====== TRACK CHANGES ====== */
    .change-item {
      padding: 10px 12px; border-radius: 8px; margin-bottom: 8px;
      font-size: 13px; border: 1px solid #e2e8f0;
    }
    .change-item.insertion { background: #f0fdf4; border-color: #86efac; }
    .change-item.deletion { background: #fef2f2; border-color: #fca5a5; }
    .change-item .change-author { font-weight: 600; color: #334155; }
    .change-item .change-time { font-size: 11px; color: #94a3b8; }
    .change-item .change-content { margin-top: 4px; }
    .change-item .change-actions { margin-top: 6px; display: flex; gap: 6px; }
    .change-item .change-actions button { padding: 3px 10px; border-radius: 4px; border: 1px solid #cbd5e1; background: white; cursor: pointer; font-size: 11px; }
    .change-item .change-actions .accept-btn { background: #16a34a; color: white; border-color: #16a34a; }
    .change-item .change-actions .reject-btn { background: #dc2626; color: white; border-color: #dc2626; }

    /* Track changes highlight in editor */
    .ck-content ins.track-change { background: #bbf7d0; text-decoration: none; border-bottom: 2px solid #16a34a; }
    .ck-content del.track-change { background: #fecaca; text-decoration: line-through; color: #dc2626; }

    /* ====== OUTLINE PANEL ====== */
    .outline-item {
      padding: 6px 8px; cursor: pointer; border-radius: 4px; font-size: 13px;
      transition: background 0.15s; margin-bottom: 2px; color: #334155;
    }
    .outline-item:hover { background: #e2e8f0; }
    .outline-item.level-1 { font-weight: 700; font-size: 14px; padding-left: 8px; }
    .outline-item.level-2 { padding-left: 20px; font-weight: 600; }
    .outline-item.level-3 { padding-left: 32px; }
    .outline-item.level-4 { padding-left: 44px; font-size: 12px; }
    .outline-item.level-5 { padding-left: 56px; font-size: 11px; }
    .outline-item.level-6 { padding-left: 68px; font-size: 11px; }

    /* ====== MENTION STYLES ====== */
    .ck-content .mention {
      background: #eff6ff; color: #2563eb; padding: 1px 6px; border-radius: 4px; font-weight: 500;
    }
    body.dark .ck-content .mention {
      background: #313244; color: #89b4fa;
    }

    /* ====== TABLE CELL REFERENCE PILL STYLES ====== */
    .ck-content .table-cell-ref,
    .ck-content span[data-cell-coord],
    .ck-content .mention[data-mention^="\$"],
    #fallback-content .table-cell-ref,
    #fallback-content span[data-cell-coord],
    #fallback-content .mention[data-mention^="\$"] {
      display: inline-flex !important;
      align-items: center;
      gap: 3px;
      background: #f0fdf4 !important;
      color: #15803d !important;
      border: 1px solid #86efac !important;
      border-radius: 5px;
      padding: 1px 6px;
      font-weight: 600;
      font-size: 0.95em;
      cursor: pointer;
      user-select: all;
      transition: all 0.15s ease;
      vertical-align: baseline;
      text-decoration: none !important;
    }
    .ck-content .table-cell-ref::before,
    .ck-content span[data-cell-coord]::before,
    .ck-content .mention[data-mention^="\$"]::before,
    #fallback-content .table-cell-ref::before,
    #fallback-content span[data-cell-coord]::before,
    #fallback-content .mention[data-mention^="\$"]::before {
      content: "📊 ";
      font-size: 0.85em;
      opacity: 0.85;
    }
    .ck-content .table-cell-ref:hover,
    .ck-content span[data-cell-coord]:hover,
    .ck-content .mention[data-mention^="\$"]:hover,
    #fallback-content .table-cell-ref:hover,
    #fallback-content span[data-cell-coord]:hover,
    #fallback-content .mention[data-mention^="\$"]:hover {
      background: #dcfce7 !important;
      border-color: #4ade80 !important;
      box-shadow: 0 1px 4px rgba(22, 101, 52, 0.2);
    }
    /* Anti-nesting: prevent nested borders or duplicate icons */
    .ck-content .table-cell-ref .table-cell-ref,
    .ck-content .mention[data-mention^="\$"] .table-cell-ref,
    .ck-content .table-cell-ref .mention,
    .ck-content span[data-cell-coord] span[data-cell-coord] {
      border: none !important;
      background: transparent !important;
      padding: 0 !important;
      box-shadow: none !important;
    }
    .ck-content .table-cell-ref .table-cell-ref::before,
    .ck-content .mention[data-mention^="\$"] .table-cell-ref::before,
    .ck-content .table-cell-ref .mention::before,
    .ck-content span[data-cell-coord] span[data-cell-coord]::before {
      content: "" !important;
      display: none !important;
    }
    body.dark .ck-content .table-cell-ref,
    body.dark .ck-content span[data-cell-coord],
    body.dark .ck-content .mention[data-mention^="\$"],
    body.dark #fallback-content .table-cell-ref,
    body.dark #fallback-content span[data-cell-coord],
    body.dark #fallback-content .mention[data-mention^="\$"] {
      background: #14532d !important;
      color: #86efac !important;
      border-color: #166534 !important;
    }
    /* Highlight for a referenced cell: an overlay above the table, so CKEditor re-renders and
       collapsed-border cell painting (no box-shadow on td) cannot hide it */
    @keyframes cellRefPulse {
      0%, 100% { background: rgba(34, 197, 94, 0.18); box-shadow: 0 0 0 0 rgba(34, 197, 94, 0.45); }
      50% { background: rgba(34, 197, 94, 0.32); box-shadow: 0 0 0 6px rgba(34, 197, 94, 0); }
    }
    .cell-ref-highlight-overlay {
      position: fixed;
      pointer-events: none;
      z-index: 9000;
      border: 2px solid #16a34a;
      border-radius: 3px;
      box-sizing: border-box;
      animation: cellRefPulse 0.9s ease-in-out 3;
      transition: opacity 0.3s ease;
    }
    /* ====== INLINE FORMULA PILL STYLES (OUTSIDE TABLES) ====== */
    .ck-content .inline-formula-pill,
    .ck-content span[data-formula]:not(td):not(th):not(.formula-badge),
    #fallback-content .inline-formula-pill,
    #fallback-content span[data-formula]:not(td):not(th):not(.formula-badge) {
      display: inline-flex !important;
      align-items: center;
      gap: 3px;
      background: #f5f3ff !important;
      color: #6d28d9 !important;
      border: 1px solid #c4b5fd !important;
      border-radius: 5px;
      padding: 1px 7px;
      font-weight: 600;
      font-size: 0.95em;
      cursor: pointer;
      user-select: all;
      transition: all 0.15s ease;
      vertical-align: baseline;
      text-decoration: none !important;
    }
    .ck-content .inline-formula-pill::before,
    .ck-content span[data-formula]:not(td):not(th):not(.formula-badge)::before,
    #fallback-content .inline-formula-pill::before,
    #fallback-content span[data-formula]:not(td):not(th):not(.formula-badge)::before {
      content: "fx ";
      font-style: italic;
      font-weight: 700;
      font-size: 0.88em;
      color: #7c3aed;
      opacity: 0.9;
    }
    .ck-content .inline-formula-pill:hover,
    .ck-content span[data-formula]:not(td):not(th):not(.formula-badge)::hover,
    #fallback-content .inline-formula-pill:hover,
    #fallback-content span[data-formula]:not(td):not(th):not(.formula-badge)::hover {
      background: #ede9fe !important;
      border-color: #a78bfa !important;
      box-shadow: 0 1px 4px rgba(109, 40, 217, 0.25);
    }
    /* Anti-nesting: prevent nested borders or duplicate icons */
    .ck-content .inline-formula-pill .inline-formula-pill,
    .ck-content .inline-formula-pill .table-cell-ref,
    .ck-content .table-cell-ref .inline-formula-pill {
      border: none !important;
      background: transparent !important;
      padding: 0 !important;
      box-shadow: none !important;
    }
    .ck-content .inline-formula-pill .inline-formula-pill::before {
      content: "" !important;
      display: none !important;
    }
    body.dark .ck-content .inline-formula-pill,
    body.dark .ck-content span[data-formula]:not(td):not(th):not(.formula-badge),
    body.dark #fallback-content .inline-formula-pill,
    body.dark #fallback-content span[data-formula]:not(td):not(th):not(.formula-badge) {
      background: #2e1065 !important;
      color: #ddd6fe !important;
      border-color: #5b21b6 !important;
    }
    body.dark .ck-content .inline-formula-pill::before,
    body.dark #fallback-content .inline-formula-pill::before {
      color: #c4b5fd !important;
    }
    /* Cell Reference Dropdown / Autocomplete styling */
    .ck.ck-list__item .table-cell-mention-btn {
      display: flex !important;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
      padding: 6px 10px !important;
      width: 100% !important;
      box-sizing: border-box;
      border: none !important;
      background: transparent;
      cursor: pointer;
    }
    .ck.ck-list__item .table-cell-mention-btn:hover {
      background: #f0fdf4 !important;
    }
    .cell-coord-badge {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      background: #dcfce7;
      color: #15803d;
      font-weight: bold;
      font-family: monospace;
      font-size: 11px;
      padding: 2px 6px;
      border-radius: 4px;
      border: 1px solid #86efac;
      flex-shrink: 0;
    }
    .cell-val-text {
      font-weight: 500;
      color: #1e293b;
      max-width: 170px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .cell-meta-text {
      font-size: 11px;
      color: #64748b;
      font-style: italic;
      flex-shrink: 0;
    }
    body.dark .cell-coord-badge {
      background: #14532d;
      color: #86efac;
      border-color: #166534;
    }
    body.dark .cell-val-text {
      color: #f1f5f9;
    }
    body.dark .cell-meta-text {
      color: #94a3b8;
    }
    /* Clean printing for reports */
    @media print {
      .table-cell-ref,
      span[data-cell-coord],
      .mention[data-mention^="\$"] {
        display: inline !important;
        background: transparent !important;
        color: inherit !important;
        border: none !important;
        padding: 0 !important;
        font-weight: inherit !important;
        box-shadow: none !important;
      }
      .table-cell-ref::before,
      span[data-cell-coord]::before,
      .mention[data-mention^="\$"]::before {
        display: none !important;
        content: "" !important;
      }
    }

    /* ====== SLASH MODAL STYLES ====== */
    .slash-item {
      display: flex; align-items: center; gap: 12px; padding: 8px 12px;
      border-radius: 8px; cursor: pointer; transition: background 0.15s; border: 1px solid transparent;
    }
    .slash-item:hover {
      background: #f1f5f9; border-color: #cbd5e1;
    }
    body.dark .slash-item:hover {
      background: #313244; border-color: #45475a;
    }
    .slash-icon {
      width: 32px; height: 32px; border-radius: 6px; background: #e2e8f0;
      display: flex; align-items: center; justify-content: center; font-weight: bold; font-size: 13px; color: #1e293b;
      flex-shrink: 0;
    }
    body.dark .slash-icon {
      background: #45475a; color: #cdd6f4;
    }
    .slash-name { font-weight: 600; font-size: 13px; color: #0f172a; }
    body.dark .slash-name { color: #cdd6f4; }
    .slash-desc { font-size: 11px; color: #64748b; }
    body.dark .slash-desc { color: #a6adc8; }

    /* ====== COMMENTS PANEL ====== */
    .comment-item {
      padding: 12px; border: 1px solid #e2e8f0; border-radius: 8px; margin-bottom: 8px;
    }
    .comment-item .comment-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; }
    .comment-item .comment-author { font-weight: 600; font-size: 13px; color: #0f172a; }
    .comment-item .comment-time { font-size: 11px; color: #94a3b8; }
    .comment-item .comment-text { font-size: 13px; color: #475569; line-height: 1.4; }
    .comment-item .comment-reply { margin-top: 8px; padding-top: 8px; border-top: 1px solid #e2e8f0; }
    .comment-reply-input { width: 100%; padding: 6px 8px; border: 1px solid #cbd5e1; border-radius: 4px; font-size: 12px; resize: none; }
    .add-comment-btn { width: 100%; padding: 8px; border: 2px dashed #cbd5e1; border-radius: 8px; background: transparent; cursor: pointer; color: #64748b; margin-top: 8px; }

    /* ====== TEMPLATE MODAL ====== */
    .modal-overlay {
      position: fixed; top: 0; left: 0; right: 0; bottom: 0;
      background: rgba(0,0,0,0.5); display: none; align-items: center;
      justify-content: center; z-index: 99999;
      padding: 16px;
      box-sizing: border-box;
    }
    .modal-overlay.show { display: flex; }
    .modal-box {
      background: white; border-radius: 12px; padding: 20px 24px; width: 92%;
      max-width: 620px; max-height: calc(100vh - 48px); overflow-y: auto;
      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
      box-sizing: border-box;
      scrollbar-width: thin;
    }
    .modal-box h2 { margin-bottom: 16px; color: #0f172a; }
    .modal-box .close-modal { float: right; background: none; border: none; font-size: 24px; cursor: pointer; color: #64748b; }
    .template-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: 12px; }
    .template-card {
      border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px;
      cursor: pointer; transition: all 0.15s; text-align: center;
    }
    .template-card:hover { border-color: #3b82f6; background: #eff6ff; transform: translateY(-2px); box-shadow: 0 4px 12px rgba(59,130,246,0.15); }
    .template-card .template-icon { font-size: 28px; margin-bottom: 8px; }
    .template-card .template-name { font-weight: 600; font-size: 13px; color: #0f172a; }
    .template-card .template-desc { font-size: 11px; color: #64748b; margin-top: 4px; }

    /* ====== MATH FORMULA MODAL ====== */
    .math-input { width: 100%; box-sizing: border-box; padding: 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-family: monospace; font-size: 14px; margin-bottom: 12px; }
    .math-preview { padding: 16px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; min-height: 60px; text-align: center; margin-bottom: 12px; overflow-x: auto; -webkit-overflow-scrolling: touch; max-width: 100%; box-sizing: border-box; }
    .modal-actions { display: flex; gap: 8px; justify-content: flex-end; }
    .modal-actions button { padding: 8px 16px; border-radius: 6px; border: 1px solid #cbd5e1; cursor: pointer; font-size: 13px; }
    .modal-actions .primary-btn { background: #3b82f6; color: white; border-color: #3b82f6; }

    /* ====== FIND & REPLACE ENHANCED ====== */
    .ck-content mark.search-highlight { background: #fbbf24; color: #000; }
    .ck-content mark.search-active { background: #f97316; color: white; }

    /* ====== PAGINATION INDICATOR ====== */
    .page-indicator { font-size: 11px; color: #94a3b8; }

    /* ====== DARK THEME ====== */
    body.dark { background-color: #1e1e2e; color: #cdd6f4; }
    body.dark #action-bar { background: #313244; border-color: #45475a; }
    body.dark #action-bar button, body.dark #action-bar select { background: #45475a; color: #cdd6f4; border-color: #585b70; }
    body.dark #action-bar button:hover { background: #585b70; }
    body.dark #action-bar button.active { background: #89b4fa; color: #1e1e2e; border-color: #89b4fa; }
    body.dark #action-bar .separator { background: #45475a; }
    body.dark .ck.ck-toolbar { background: #313244 !important; border-color: #45475a !important; }
    body.dark .ck.ck-toolbar .ck-toolbar__separator { background: #45475a !important; }
    body.dark .ck.ck-button, body.dark .ck.ck-dropdown__button { color: #cdd6f4 !important; }
    body.dark .ck.ck-button:hover, body.dark .ck.ck-dropdown__button:hover { background: #45475a !important; }
    body.dark .ck.ck-button.ck-on { background: #585b70 !important; color: #89b4fa !important; }
    body.dark .ck.ck-editor__main > .ck-editor__editable { background: #181825 !important; color: #cdd6f4 !important; }
    body.dark .ck.ck-dropdown__panel { background: #313244 !important; border-color: #45475a !important; }
    body.dark .ck.ck-list { background: #313244 !important; }
    body.dark .ck.ck-list__item .ck-button { color: #cdd6f4 !important; }
    body.dark .ck.ck-list__item .ck-button:hover { background: #45475a !important; }
    body.dark .ck.ck-dropdown__arrow { fill: #cdd6f4 !important; }
    body.dark .ck.ck-input { background: #45475a !important; color: #cdd6f4 !important; border-color: #585b70 !important; }
    body.dark .ck.ck-labeled-field-view > .ck.ck-labeled-field-view__input-wrapper > .ck.ck-label { color: #a6adc8 !important; }
    body.dark .ck.ck-balloon-panel { background: #313244 !important; border-color: #45475a !important; }
    body.dark .ck.ck-color-grid__tile { border-color: #45475a !important; }
    body.dark .ck-content h1, body.dark .ck-content h2, body.dark .ck-content h3, body.dark .ck-content h4 { color: #cdd6f4; }
    body.dark .ck-content blockquote { background: #313244; border-color: #89b4fa; color: #89b4fa; }
    body.dark .ck-content pre { background: #11111b; color: #a6e3a1; }
    body.dark .ck-content code { background: #313244; color: #f38ba8; }
    body.dark .ck-content table td, body.dark .ck-content table th { border-color: #45475a; }
    body.dark .ck-content table th { background: #313244; color: #cdd6f4; }
    body.dark .ck-content table tr:nth-child(even) td { background: #1e1e2e; }
    body.dark .ck-content hr { border-color: #45475a; }
    body.dark .ck-content a { color: #89b4fa; }
    body.dark #side-panel { background: #1e1e2e; border-color: #45475a; }
    body.dark #side-panel-header { border-color: #45475a; color: #cdd6f4; }
    body.dark #status-bar { background: #181825; border-color: #45475a; color: #a6adc8; }
    body.dark .revision-item { border-color: #45475a; }
    body.dark .revision-item:hover { background: #313244; border-color: #585b70; }
    body.dark .revision-item.active { background: #313244; border-color: #89b4fa; }
    body.dark .revision-item .rev-title { color: #cdd6f4; }
    body.dark .outline-item { color: #bac2de; }
    body.dark .outline-item:hover { background: #313244; }
    body.dark .change-item { border-color: #45475a; }
    body.dark .change-item.insertion { background: #1a2e1a; border-color: #2d5a2d; }
    body.dark .change-item.deletion { background: #2e1a1a; border-color: #5a2d2d; }
    body.dark .comment-item { border-color: #45475a; background: #181825; }
    body.dark .comment-item .comment-author { color: #cdd6f4; }
    body.dark .comment-item .comment-text { color: #bac2de; }
    body.dark .comment-reply-input { background: #313244; color: #cdd6f4; border-color: #45475a; }
    body.dark .add-comment-btn { border-color: #45475a; color: #a6adc8; }
    body.dark .modal-box { background: #1e1e2e; }
    body.dark .modal-box h2 { color: #cdd6f4; }
    body.dark .template-card { border-color: #45475a; }
    body.dark .template-card:hover { border-color: #89b4fa; background: #313244; }
    body.dark .template-card .template-name { color: #cdd6f4; }
    body.dark .template-card .template-desc { color: #a6adc8; }
    body.dark .math-input { background: #313244; color: #cdd6f4; border-color: #45475a; }
    body.dark .math-preview { background: #181825; border-color: #45475a; }
    body.dark .modal-actions button { background: #45475a; color: #cdd6f4; border-color: #585b70; }

    /* ====== FALLBACK EDITOR ====== */
    #fallback-container { display: none; flex-direction: column; height: 100%; width: 100%; }
    #fallback-toolbar { display: flex; flex-wrap: wrap; gap: 4px; padding: 8px; background: #f8fafc; border-bottom: 1px solid #e2e8f0; }
    #fallback-toolbar button, #fallback-toolbar select { padding: 6px 10px; border: 1px solid #cbd5e1; border-radius: 4px; background: white; cursor: pointer; font-size: 13px; }
    #fallback-toolbar button:hover { background: #e2e8f0; }
    #fallback-content { flex: 1; overflow-y: auto; padding: 24px 32px; font-size: 15px; line-height: 1.6; outline: none; }
    #fallback-content.show-blocks > * { outline: 1px dashed #94a3b8; outline-offset: 2px; }
    body.dark #fallback-container { border-color: #45475a; }
    body.dark #fallback-toolbar { background: #313244; border-color: #45475a; }
    body.dark #fallback-toolbar button, body.dark #fallback-toolbar select { background: #45475a; color: #cdd6f4; border-color: #585b70; }
    body.dark #fallback-content { background: #181825; color: #cdd6f4; }
    .fallback-sep { width: 1px; height: 20px; background: #e2e8f0; margin: 0 4px; align-self: center; }
    body.dark .fallback-sep { background: #585b70; }


    /* ====== DROPDOWN OVERFLOW & TABLE GRID FIX ====== */
    .ck.ck-dropdown__panel,
    .ck-dropdown__panel {
      max-height: min(440px, calc(100vh - 100px)) !important;
      overflow: visible !important;
      box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.2), 0 8px 10px -6px rgba(0, 0, 0, 0.1) !important;
      border-radius: 8px !important;
      z-index: 1000 !important;
    }
    .ck.ck-dropdown__panel .ck-list,
    .ck-dropdown__panel .ck-list {
      max-height: min(300px, calc(100vh - 140px)) !important;
      overflow-y: auto !important;
      overflow-x: hidden !important;
      -webkit-overflow-scrolling: touch !important;
      scrollbar-width: thin !important;
    }
    .ck.ck-dropdown__panel::-webkit-scrollbar,
    .ck-dropdown__panel::-webkit-scrollbar,
    .ck.ck-list::-webkit-scrollbar,
    .ck-list::-webkit-scrollbar {
      width: 6px !important;
      height: 6px !important;
    }
    .ck.ck-dropdown__panel::-webkit-scrollbar-track,
    .ck-dropdown__panel::-webkit-scrollbar-track,
    .ck.ck-list::-webkit-scrollbar-track,
    .ck-list::-webkit-scrollbar-track {
      background: transparent !important;
    }
    .ck.ck-dropdown__panel::-webkit-scrollbar-thumb,
    .ck-dropdown__panel::-webkit-scrollbar-thumb,
    .ck.ck-list::-webkit-scrollbar-thumb,
    .ck-list::-webkit-scrollbar-thumb {
      background: rgba(148, 163, 184, 0.6) !important;
      border-radius: 3px !important;
    }
    .ck.ck-dropdown__panel::-webkit-scrollbar-thumb:hover,
    .ck-dropdown__panel::-webkit-scrollbar-thumb:hover,
    .ck.ck-list::-webkit-scrollbar-thumb:hover,
    .ck-list::-webkit-scrollbar-thumb:hover {
      background: rgba(100, 116, 139, 0.9) !important;
    }

    /* Table insertion grid popup - exact 10x10 matrix layout */
    :root {
      --ck-insert-table-dropdown-padding: 8px;
      --ck-insert-table-dropdown-box-height: 18px;
      --ck-insert-table-dropdown-box-width: 18px;
      --ck-insert-table-dropdown-box-margin: 2px;
    }

    .ck.ck-insert-table-dropdown .ck-dropdown__panel,
    .ck-insert-table-dropdown .ck-dropdown__panel,
    .ck.ck-dropdown__panel:has(.ck-insert-table-dropdown__grid) {
      max-height: none !important;
      height: auto !important;
      width: 256px !important;
      min-width: 256px !important;
      max-width: 256px !important;
      overflow: visible !important;
      overflow-x: visible !important;
      overflow-y: visible !important;
      padding: 4px !important;
      box-sizing: border-box !important;
    }

    .ck .ck-insert-table-dropdown__grid {
      display: flex !important;
      flex-direction: row !important;
      flex-wrap: wrap !important;
      width: 240px !important;
      min-width: 240px !important;
      max-width: 240px !important;
      height: 240px !important;
      min-height: 240px !important;
      max-height: 240px !important;
      padding: 10px 10px 0 !important;
      margin: 0 auto !important;
      overflow: visible !important;
      box-sizing: border-box !important;
    }

    /* Override any global .ck.ck-button dimensions so 10x10 grid tiles stay exactly 18x18 */
    .ck.ck-button.ck-insert-table-dropdown-grid-box,
    .ck .ck-insert-table-dropdown-grid-box {
      width: 18px !important;
      height: 18px !important;
      min-width: 18px !important;
      max-width: 18px !important;
      min-height: 18px !important;
      max-height: 18px !important;
      padding: 0 !important;
      margin: 2px !important;
      border: 1px solid #cbd5e1 !important;
      border-radius: 2px !important;
      background: #ffffff !important;
      outline: none !important;
      box-sizing: border-box !important;
      transition: background-color 0.1s ease, border-color 0.1s ease !important;
      cursor: pointer !important;
    }

    .ck.ck-button.ck-insert-table-dropdown-grid-box.ck-on,
    .ck .ck-insert-table-dropdown-grid-box.ck-on {
      background: #bfdbfe !important;
      border-color: #2563eb !important;
    }

    .ck .ck-insert-table-dropdown__label {
      padding: 6px 4px 6px !important;
      text-align: center !important;
      font-size: 13px !important;
      font-weight: 600 !important;
      color: #1e293b !important;
      width: 100% !important;
      box-sizing: border-box !important;
    }

    /* Nested dropdowns inside grouped dropdown or split buttons */
    .ck-toolbar__grouped-dropdown .ck-dropdown__panel {
      overflow: visible !important;
      max-height: min(440px, calc(100vh - 100px)) !important;
    }
    .ck-toolbar__grouped-dropdown .ck-dropdown__panel .ck-dropdown__panel {
      position: absolute !important;
      z-index: 1001 !important;
      overflow: visible !important;
    }

    /* Balloon Panels Base */
    .ck.ck-balloon-panel,
    .ck-balloon-panel {
      z-index: 10000 !important;
    }
    .ck.ck-balloon-panel.balloon-clamped::before,
    .ck.ck-balloon-panel.balloon-clamped::after {
      display: none !important;
    }

    /* Only Form/Dialog Balloons (Table Properties, Cell Properties, Link Form) get card styling and scroll */
    .ck.ck-balloon-panel:has(.ck-form),
    .ck.ck-balloon-panel:has(.ck-table-properties-form),
    .ck.ck-balloon-panel:has(.ck-table-cell-properties-form),
    .ck.ck-balloon-panel_with-form {
      max-width: min(520px, calc(100vw - 16px)) !important;
      max-height: calc(100vh - 48px) !important;
      box-shadow: 0 16px 36px rgba(0, 0, 0, 0.22), 0 4px 12px rgba(0, 0, 0, 0.12) !important;
      border-radius: 10px !important;
      border: 1px solid #cbd5e1 !important;
      display: flex !important;
      flex-direction: column !important;
      overflow: hidden !important;
      background: #ffffff !important;
    }

    .ck.ck-balloon-panel:has(.ck-form) .ck-balloon-panel__content,
    .ck.ck-balloon-panel:has(.ck-table-properties-form) .ck-balloon-panel__content,
    .ck.ck-balloon-panel:has(.ck-table-cell-properties-form) .ck-balloon-panel__content,
    .ck.ck-balloon-panel_with-form .ck-balloon-panel__content {
      max-height: calc(100vh - 60px) !important;
      overflow-y: auto !important;
      overflow-x: hidden !important;
      -webkit-overflow-scrolling: touch !important;
      box-sizing: border-box !important;
      scrollbar-width: thin !important;
      scrollbar-color: #cbd5e1 transparent !important;
      padding: 0 !important;
    }

    /* CKEditor 41 wraps forms in .ck-balloon-rotator (no __content element): let it shrink and scroll
       inside the height-limited panel so Save/Cancel stay reachable */
    .ck.ck-balloon-panel:has(.ck-form) > .ck-balloon-rotator,
    .ck.ck-balloon-panel:has(.ck-table-properties-form) > .ck-balloon-rotator,
    .ck.ck-balloon-panel:has(.ck-table-cell-properties-form) > .ck-balloon-rotator,
    .ck.ck-balloon-panel_with-form > .ck-balloon-rotator {
      flex: 1 1 auto !important;
      min-height: 0 !important;
      overflow-y: auto !important;
      overflow-x: hidden !important;
      -webkit-overflow-scrolling: touch !important;
      scrollbar-width: thin !important;
      scrollbar-color: #cbd5e1 transparent !important;
    }

    .ck.ck-balloon-panel:has(.ck-form) .ck-balloon-panel__content::-webkit-scrollbar,
    .ck.ck-balloon-panel:has(.ck-table-properties-form) .ck-balloon-panel__content::-webkit-scrollbar,
    .ck.ck-balloon-panel:has(.ck-table-cell-properties-form) .ck-balloon-panel__content::-webkit-scrollbar {
      width: 5px;
    }
    .ck.ck-balloon-panel:has(.ck-form) .ck-balloon-panel__content::-webkit-scrollbar-thumb,
    .ck.ck-balloon-panel:has(.ck-table-properties-form) .ck-balloon-panel__content::-webkit-scrollbar-thumb,
    .ck.ck-balloon-panel:has(.ck-table-cell-properties-form) .ck-balloon-panel__content::-webkit-scrollbar-thumb {
      background: #cbd5e1;
      border-radius: 4px;
    }

    /* Contextual Toolbars (Table Toolbar, etc.) MUST be visible and horizontal */
    .ck.ck-balloon-panel:not(.ck-tooltip):not(:has(.ck-form)):not(:has(.ck-table-properties-form)):not(:has(.ck-table-cell-properties-form)) {
      overflow: visible !important;
      max-width: none !important;
      max-height: none !important;
      background: transparent !important;
      border: none !important;
      box-shadow: none !important;
    }

    .ck.ck-balloon-panel:not(.ck-tooltip):not(:has(.ck-form)):not(:has(.ck-table-properties-form)):not(:has(.ck-table-cell-properties-form)) .ck-balloon-panel__content {
      overflow: visible !important;
      max-height: none !important;
      padding: 0 !important;
    }

    /* Toolbar tooltips: dark chip with white text (the arrow follows --ck-color-panel-background) */
    .ck.ck-balloon-panel.ck-tooltip {
      --ck-color-panel-background: #1e293b;
      --ck-color-tooltip-background: #1e293b;
      --ck-color-tooltip-text: #ffffff;
      background: #1e293b !important;
      border: none !important;
      border-radius: 6px !important;
      box-shadow: 0 4px 12px rgba(15, 23, 42, 0.25) !important;
    }
    .ck.ck-balloon-panel.ck-tooltip .ck-tooltip__text {
      color: #ffffff !important;
      font-size: 12px !important;
      font-weight: 500 !important;
      padding: 4px 8px !important;
    }
    body.dark .ck.ck-balloon-panel.ck-tooltip {
      --ck-color-panel-background: #11111b;
      --ck-color-tooltip-background: #11111b;
      background: #11111b !important;
    }

    .ck.ck-balloon-panel .ck-toolbar {
      overflow: visible !important;
      display: flex !important;
      flex-direction: row !important;
      flex-wrap: nowrap !important;
      align-items: center !important;
      border-radius: 8px !important;
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.16), 0 2px 6px rgba(0, 0, 0, 0.08) !important;
      border: 1px solid #cbd5e1 !important;
      background: #ffffff !important;
      padding: 3px 6px !important;
    }

    .ck.ck-balloon-panel .ck-toolbar .ck-toolbar__items {
      overflow: visible !important;
      display: flex !important;
      flex-direction: row !important;
      flex-wrap: nowrap !important;
      align-items: center !important;
      gap: 2px !important;
    }

    /* Dropdown panels inside contextual toolbars (Row options, Column options, etc.) */
    .ck.ck-balloon-panel .ck-dropdown__panel {
      position: absolute !important;
      overflow: visible !important;
      z-index: 10005 !important;
      box-shadow: 0 10px 25px rgba(0, 0, 0, 0.18) !important;
      border-radius: 8px !important;
      border: 1px solid #cbd5e1 !important;
      background: #ffffff !important;
      max-height: min(400px, 80vh) !important;
    }

    .ck.ck-balloon-panel .ck-dropdown__panel .ck-list {
      max-height: min(380px, 75vh) !important;
      overflow-y: auto !important;
      overflow-x: hidden !important;
      padding: 4px 0 !important;
    }

    .ck.ck-balloon-panel .ck-dropdown__panel .ck-list__item {
      min-width: 170px !important;
    }

    .ck.ck-balloon-panel .ck-dropdown__panel .ck-button {
      padding: 6px 12px !important;
      font-size: 13px !important;
      width: 100% !important;
      justify-content: flex-start !important;
      text-align: left !important;
    }

    /* Table Properties & Cell Properties Form Polish */
    .ck.ck-table-properties-form,
    .ck.ck-table-cell-properties-form,
    .ck.ck-form {
      padding: 12px 14px !important;
      box-sizing: border-box !important;
    }

    .ck.ck-form__header {
      padding: 0 0 8px 0 !important;
      margin-bottom: 8px !important;
      border-bottom: 1px solid #e2e8f0 !important;
    }

    .ck.ck-form__header .ck-form__header__title {
      font-size: 14px !important;
      font-weight: 700 !important;
      color: #0f172a !important;
      letter-spacing: -0.2px;
    }

    .ck.ck-form__row {
      margin-bottom: 8px !important;
      display: flex !important;
      align-items: center !important;
      gap: 6px !important;
      flex-wrap: wrap !important;
    }

    .ck.ck-labeled-field-view {
      margin-bottom: 6px !important;
    }

    .ck.ck-labeled-field-view .ck-labeled-field-view__input-wrapper {
      margin-top: 2px !important;
    }

    .ck.ck-table-properties-form .ck-input,
    .ck.ck-table-cell-properties-form .ck-input {
      min-height: 28px !important;
      padding: 4px 8px !important;
      font-size: 12.5px !important;
      border-radius: 6px !important;
      border: 1px solid #cbd5e1 !important;
      background: #f8fafc !important;
      transition: all 0.15s ease !important;
    }

    .ck.ck-table-properties-form .ck-input:focus,
    .ck.ck-table-cell-properties-form .ck-input:focus {
      border-color: #3b82f6 !important;
      background: #ffffff !important;
      box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.15) !important;
    }

    /* Fix CKEditor Form & Media Dialog Button Icons */
    .ck.ck-media-form .ck-button .ck-icon,
    .ck.ck-form .ck-button .ck-icon,
    .ck.ck-button-save .ck-icon,
    .ck.ck-button-cancel .ck-icon,
    .ck.ck-button .ck-icon,
    .ck.ck-icon {
      width: 16px !important;
      height: 16px !important;
      min-width: 16px !important;
      min-height: 16px !important;
      max-width: 16px !important;
      max-height: 16px !important;
      display: inline-block !important;
      vertical-align: middle !important;
    }

    /* Media Embed Balloon Form Styling */
    .ck.ck-media-form {
      padding: 12px 14px !important;
      min-width: 320px !important;
      max-width: 480px !important;
      box-sizing: border-box !important;
    }
    .ck.ck-media-form .ck-labeled-field-view {
      margin-bottom: 6px !important;
    }
    .ck.ck-media-form .ck-labeled-field-view .ck-input {
      min-height: 36px !important;
      font-size: 13px !important;
      border: 1px solid #cbd5e1 !important;
      border-radius: 6px !important;
      padding: 6px 10px !important;
      width: 100% !important;
      box-sizing: border-box !important;
    }
    .ck.ck-media-form .ck-form__actions,
    .ck.ck-form__actions {
      display: flex !important;
      gap: 8px !important;
      justify-content: flex-end !important;
      align-items: center !important;
      margin-top: 10px !important;
      padding-top: 8px !important;
      border-top: 1px solid #f1f5f9 !important;
    }

    .ck.ck-button-save,
    .ck.ck-media-form .ck-button-save {
      background: #2563eb !important;
      color: #ffffff !important;
      border: 1px solid #2563eb !important;
      border-radius: 6px !important;
      padding: 6px 14px !important;
      font-weight: 600 !important;
      font-size: 12.5px !important;
      min-height: 32px !important;
      min-width: 36px !important;
      display: inline-flex !important;
      align-items: center !important;
      justify-content: center !important;
      gap: 6px !important;
      transition: all 0.15s ease !important;
      cursor: pointer !important;
      box-shadow: 0 1px 2px rgba(37, 99, 235, 0.2) !important;
    }
    .ck.ck-button-save:hover,
    .ck.ck-media-form .ck-button-save:hover {
      background: #1d4ed8 !important;
      border-color: #1d4ed8 !important;
    }
    .ck.ck-button-save .ck-icon,
    .ck.ck-button-save svg {
      color: #ffffff !important;
      fill: #ffffff !important;
      stroke: #ffffff !important;
    }
    .ck.ck-media-form .ck-button-save::after {
      content: "Insert";
      font-size: 12px;
      font-weight: 600;
      color: #ffffff;
      margin-left: 2px;
    }

    .ck.ck-button-cancel,
    .ck.ck-media-form .ck-button-cancel {
      border: 1px solid #cbd5e1 !important;
      border-radius: 6px !important;
      background: #ffffff !important;
      padding: 6px 14px !important;
      font-size: 12.5px !important;
      font-weight: 500 !important;
      min-height: 32px !important;
      min-width: 36px !important;
      color: #475569 !important;
      display: inline-flex !important;
      align-items: center !important;
      justify-content: center !important;
      gap: 6px !important;
      transition: all 0.15s ease !important;
      cursor: pointer !important;
    }
    .ck.ck-button-cancel:hover,
    .ck.ck-media-form .ck-button-cancel:hover {
      background: #f1f5f9 !important;
      border-color: #94a3b8 !important;
    }
    .ck.ck-button-cancel .ck-icon,
    .ck.ck-button-cancel svg {
      color: #475569 !important;
      fill: #475569 !important;
    }
    .ck.ck-media-form .ck-button-cancel::after {
      content: "Cancel";
      font-size: 12px;
      font-weight: 500;
      color: #475569;
      margin-left: 2px;
    }

    /* Dark mode for balloon forms and toolbars */
    body.dark .ck.ck-balloon-panel:has(.ck-form),
    body.dark .ck.ck-balloon-panel:has(.ck-media-form),
    body.dark .ck.ck-balloon-panel:has(.ck-table-properties-form),
    body.dark .ck.ck-balloon-panel:has(.ck-table-cell-properties-form) {
      background: #1e1e2e !important;
      border-color: #45475a !important;
      box-shadow: 0 16px 36px rgba(0, 0, 0, 0.4) !important;
    }
    body.dark .ck.ck-media-form .ck-labeled-field-view .ck-input {
      background: #181825 !important;
      color: #cdd6f4 !important;
      border-color: #45475a !important;
    }
    body.dark .ck.ck-media-form .ck-button-cancel {
      background: #313244 !important;
      color: #cdd6f4 !important;
      border-color: #45475a !important;
    }
    body.dark .ck.ck-media-form .ck-button-cancel::after {
      color: #cdd6f4 !important;
    }
    body.dark .ck.ck-media-form .ck-button-cancel .ck-icon,
    body.dark .ck.ck-media-form .ck-button-cancel svg {
      color: #cdd6f4 !important;
      fill: #cdd6f4 !important;
    }
    body.dark .ck.ck-balloon-panel .ck-toolbar {
      background: #1e1e2e !important;
      border-color: #45475a !important;
    }
    body.dark .ck.ck-balloon-panel .ck-dropdown__panel {
      background: #1e1e2e !important;
      border-color: #45475a !important;
    }
    body.dark .ck.ck-form__header {
      border-color: #313244 !important;
    }
    body.dark .ck.ck-form__header .ck-form__header__title {
      color: #cdd6f4 !important;
    }
    body.dark .ck.ck-table-properties-form .ck-input,
    body.dark .ck.ck-table-cell-properties-form .ck-input {
      background: #313244 !important;
      border-color: #45475a !important;
      color: #cdd6f4 !important;
    }
    body.dark .ck.ck-button-cancel {
      border-color: #45475a !important;
      color: #a6adc8 !important;
    }

    /* Comfortable touch tap targets */
    .ck.ck-list__item .ck-button,
    .ck-list__item .ck-button {
      min-height: 32px !important;
      padding: 6px 12px !important;
      font-size: 13px !important;
      border-radius: 4px !important;
      cursor: pointer !important;
    }

    /* Table Color Modal Components */
    .tbl-target-btn {
      padding: 6px 12px;
      border: 1px solid #cbd5e1;
      border-radius: 6px;
      background: #f8fafc;
      font-size: 12px;
      cursor: pointer;
      transition: all 0.15s ease;
      color: #334155;
      font-weight: 500;
    }
    .tbl-target-btn:hover { background: #e2e8f0; border-color: #94a3b8; }
    .tbl-target-btn.active {
      background: #3b82f6;
      color: #ffffff;
      border-color: #3b82f6;
      box-shadow: 0 2px 6px rgba(59,130,246,0.3);
    }
    .color-swatch {
      height: 32px;
      border-radius: 6px;
      cursor: pointer;
      transition: transform 0.15s ease, box-shadow 0.15s ease;
    }
    .color-swatch:hover {
      transform: scale(1.1);
      box-shadow: 0 3px 8px rgba(0,0,0,0.2);
    }
    body.dark .tbl-target-btn { background: #313244; color: #cdd6f4; border-color: #45475a; }
    body.dark .tbl-target-btn:hover { background: #45475a; }
    body.dark .tbl-target-btn.active { background: #89b4fa; color: #1e1e2e; border-color: #89b4fa; }
    body.dark #table-color-modal .modal-box { background: #1e1e2e; }
    body.dark #table-color-modal h2 { color: #cdd6f4; }
    body.dark #table-color-modal label { color: #cdd6f4 !important; }

    /* ====== RESPONSIVE BREAKPOINTS (TABLET, MOBILE, FOLDABLES, DESKTOP) ====== */
    /* 1. TABLET LANDSCAPE & COMPACT LAPTOPS (<= 1024px) */
    @media (max-width: 1024px) {
      .ck-content { padding: 16px 20px !important; }
      #side-panel.open { width: 280px; }
      .ck.ck-dropdown__panel { max-width: min(88vw, 340px) !important; }
    }

    /* 2. TABLET PORTRAIT & UNFOLDED FOLDABLES (<= 768px) */
    @media (max-width: 768px) {
      .ck-content { padding: 12px 16px !important; font-size: 14.5px !important; }
      #side-panel.open { width: 300px; }
      .modal-box { width: 92% !important; padding: 18px !important; max-height: 88dvh !important; }
      .ck.ck-balloon-panel { max-width: 92vw !important; }
    }

    /* 3. PHABLETS, LARGE PHONES & SPLIT SCREEN (<= 600px) */
    @media (max-width: 600px) {
      .ck-content { padding: 10px 12px !important; font-size: 14px !important; line-height: 1.6 !important; }
      .ck.ck-toolbar { padding: 2px 4px !important; }
      .ck.ck-button { min-width: 30px !important; min-height: 30px !important; padding: 3px !important; }
      #action-bar { padding: 4px 6px !important; min-height: 36px !important; gap: 4px !important; }
      #action-bar button, #action-bar select { padding: 4px 8px !important; font-size: 11px !important; }

      /* Mobile full-screen slide-in drawer for side panel */
      #side-panel.open {
        width: 100vw !important;
        position: fixed !important;
        top: 0 !important;
        left: 0 !important;
        right: 0 !important;
        bottom: 0 !important;
        z-index: 10000 !important;
        box-shadow: none !important;
      }
      #side-panel-header { padding: 12px 14px; }
      #side-panel-header button { padding: 6px 12px; font-size: 20px; }

      /* Modal sizing on mobile */
      .modal-box {
        width: 95% !important;
        max-height: 90dvh !important;
        padding: 14px 12px !important;
        border-radius: 10px !important;
      }
      .template-grid {
        grid-template-columns: repeat(2, 1fr) !important;
        gap: 8px !important;
      }

      /* Status bar responsive wrap */
      #status-bar {
        flex-wrap: wrap !important;
        gap: 4px 8px !important;
        padding: 3px 8px !important;
        font-size: 11px !important;
        min-height: auto !important;
      }
      #status-bar .status-section {
        gap: 8px !important;
      }

      /* Table responsive horizontal scroll */
      .ck-content figure.table,
      .ck-content .table {
        margin: 8px 0 !important;
        max-width: 100% !important;
        overflow-x: auto !important;
        -webkit-overflow-scrolling: touch !important;
        display: block !important;
      }
      .ck-content table,
      .ck-content figure.table table {
        display: table !important;
        width: 100% !important;
        border-collapse: collapse !important;
      }
      #btn-fullscreen, #btn-fullscreen + .separator { display: none !important; }
    }

    /* 4. STANDARD SMARTPHONES (<= 420px: iPhone, Galaxy, Pixel) */
    @media (max-width: 420px) {
      .ck-content { padding: 8px 10px !important; font-size: 13.5px !important; line-height: 1.5 !important; }
      #action-bar { padding: 3px 4px !important; min-height: 32px !important; gap: 3px !important; }
      #action-bar button, #action-bar select { padding: 3px 6px !important; font-size: 10.5px !important; border-radius: 4px !important; }
      .ck.ck-toolbar { padding: 1px 2px !important; }
      .ck.ck-button { min-width: 28px !important; min-height: 28px !important; padding: 2px !important; }
      .ck.ck-dropdown__panel { max-width: 94vw !important; }
      .ck.ck-balloon-panel { max-width: 96vw !important; }
      #status-bar { padding: 2px 6px !important; font-size: 10px !important; }
      #status-bar .status-section:last-child { display: none !important; }
      .modal-box { width: 97% !important; padding: 10px 10px !important; max-height: 92dvh !important; }
      .template-grid { grid-template-columns: 1fr !important; }
      
      /* Table styling modal on small phones */
      .color-swatch-grid {
        grid-template-columns: repeat(auto-fill, minmax(34px, 1fr)) !important;
        gap: 4px !important;
      }
      .color-swatch { height: 28px !important; }
      .tbl-target-btn { padding: 4px 8px !important; font-size: 11px !important; }
    }

    /* 5. ULTRA-NARROW FOLDABLE COVER SCREENS (<= 340px: Galaxy Z Fold closed, mini displays) */
    @media (max-width: 340px) {
      .ck-content { padding: 6px 6px !important; font-size: 12.5px !important; line-height: 1.45 !important; }
      #action-bar { padding: 2px 3px !important; min-height: 30px !important; gap: 2px !important; }
      #action-bar button, #action-bar select { padding: 2px 5px !important; font-size: 9.5px !important; border-radius: 3px !important; }
      .ck.ck-toolbar { padding: 1px 1px !important; }
      .ck.ck-button { min-width: 26px !important; min-height: 26px !important; padding: 1px !important; }
      .ck.ck-dropdown__panel { max-width: 96vw !important; }
      .ck.ck-balloon-panel { max-width: 98vw !important; }
      #status-bar { padding: 2px 4px !important; font-size: 9.5px !important; }
      #status-bar .status-section:last-child { display: none !important; }
      .modal-box { width: 98% !important; padding: 8px 8px !important; max-height: 94dvh !important; border-radius: 8px !important; }
      .modal-box h2 { font-size: 14px !important; margin-bottom: 6px !important; }
      .color-swatch-grid {
        grid-template-columns: repeat(auto-fill, minmax(28px, 1fr)) !important;
        gap: 3px !important;
      }
      .color-swatch { height: 24px !important; }
      .tbl-target-btn { padding: 3px 6px !important; font-size: 10px !important; }
      .math-input { padding: 6px !important; font-size: 12px !important; }
      .math-preview { min-height: 40px !important; padding: 8px !important; }
    }

    /* 6. SHORT VIEWPORTS / MOBILE LANDSCAPE (height <= 500px) */
    @media (max-height: 500px) {
      #action-bar { min-height: 30px !important; padding: 2px 6px !important; }
      #action-bar button, #action-bar select { padding: 2px 6px !important; font-size: 10.5px !important; }
      .ck.ck-toolbar { padding: 1px 4px !important; }
      .ck.ck-button { min-width: 26px !important; min-height: 26px !important; }
      #status-bar { min-height: 20px !important; padding: 1px 6px !important; font-size: 10px !important; }
      .modal-box { max-height: 96dvh !important; padding: 10px !important; }
    }

    /* ====== RTL & LTR BIDIRECTIONAL TEXT STYLES ====== */
    .ck-content[dir="rtl"],
    #fallback-content[dir="rtl"] {
      direction: rtl !important;
      text-align: right !important;
    }
    .ck-content[dir="rtl"] p,
    .ck-content[dir="rtl"] h1,
    .ck-content[dir="rtl"] h2,
    .ck-content[dir="rtl"] h3,
    .ck-content[dir="rtl"] h4,
    .ck-content[dir="rtl"] h5,
    .ck-content[dir="rtl"] h6,
    .ck-content[dir="rtl"] div:not(.math-block):not(.media),
    .ck-content[dir="rtl"] li,
    .ck-content[dir="rtl"] table td,
    .ck-content[dir="rtl"] table th,
    #fallback-content[dir="rtl"] p,
    #fallback-content[dir="rtl"] h1,
    #fallback-content[dir="rtl"] h2,
    #fallback-content[dir="rtl"] h3,
    #fallback-content[dir="rtl"] li,
    #fallback-content[dir="rtl"] table td,
    #fallback-content[dir="rtl"] table th {
      direction: rtl !important;
      text-align: right !important;
    }
    .ck-content[dir="rtl"] ul,
    .ck-content[dir="rtl"] ol,
    #fallback-content[dir="rtl"] ul,
    #fallback-content[dir="rtl"] ol {
      padding-right: 28px !important;
      padding-left: 0 !important;
    }
    .ck-content[dir="rtl"] blockquote,
    #fallback-content[dir="rtl"] blockquote {
      border-right: 4px solid #3b82f6 !important;
      border-left: none !important;
      border-radius: 8px 0 0 8px !important;
      text-align: right !important;
      direction: rtl !important;
    }
    .ck-content[dir="ltr"],
    #fallback-content[dir="ltr"] {
      direction: ltr !important;
      text-align: left !important;
    }
    .ck-content[dir="ltr"] p,
    .ck-content[dir="ltr"] h1,
    .ck-content[dir="ltr"] h2,
    .ck-content[dir="ltr"] h3,
    .ck-content[dir="ltr"] h4,
    .ck-content[dir="ltr"] h5,
    .ck-content[dir="ltr"] h6,
    .ck-content[dir="ltr"] div:not(.math-block):not(.media),
    .ck-content[dir="ltr"] li,
    .ck-content[dir="ltr"] table td,
    .ck-content[dir="ltr"] table th,
    #fallback-content[dir="ltr"] p,
    #fallback-content[dir="ltr"] h1,
    #fallback-content[dir="ltr"] h2,
    #fallback-content[dir="ltr"] h3,
    #fallback-content[dir="ltr"] li,
    #fallback-content[dir="ltr"] table td,
    #fallback-content[dir="ltr"] table th {
      direction: ltr !important;
      text-align: left !important;
    }

    /* ====== PRINT STYLES ====== */
    @page {
      size: A4 portrait;
      margin: 15mm 15mm 15mm 15mm;
    }
    @media print {
      /* Hide non-printable interactive chrome, toolbars, buttons, and popups */
      #action-bar,
      #status-bar,
      #side-panel,
      .ck.ck-editor__top,
      .ck-toolbar,
      .ck.ck-toolbar,
      .video-resize-toolbar,
      .video-resize-handle,
      .formula-badge,
      .modal-overlay,
      .ck-balloon-panel,
      .ck-balloon-rotator,
      #toast-notification,
      .ck-editor__nested-editable_focused,
      .ck-widget__resizer {
        display: none !important;
        visibility: hidden !important;
      }

      /* Reset viewport/height and overflow locks so print layout engine can paginate naturally across multiple pages */
      html, body {
        width: 100% !important;
        height: auto !important;
        min-height: 0 !important;
        max-height: none !important;
        overflow: visible !important;
        overflow-x: visible !important;
        overflow-y: visible !important;
        position: static !important;
        background: #ffffff !important;
        color: #000000 !important;
        margin: 0 !important;
        padding: 0 !important;
        -webkit-print-color-adjust: exact !important;
        print-color-adjust: exact !important;
      }

      #app-container,
      #editor-wrapper,
      #editor-main {
        display: block !important;
        width: 100% !important;
        height: auto !important;
        min-height: 0 !important;
        max-height: none !important;
        overflow: visible !important;
        overflow-x: visible !important;
        overflow-y: visible !important;
        position: static !important;
        margin: 0 !important;
        padding: 0 !important;
      }

      .ck.ck-editor {
        display: block !important;
        width: 100% !important;
        height: auto !important;
        min-height: 0 !important;
        max-height: none !important;
        overflow: visible !important;
        position: static !important;
        border: none !important;
        box-shadow: none !important;
      }

      .ck.ck-editor__main {
        display: block !important;
        width: 100% !important;
        height: auto !important;
        min-height: 0 !important;
        max-height: none !important;
        overflow: visible !important;
        position: static !important;
      }

      .ck.ck-editor__main > .ck-editor__editable,
      .ck-content,
      #fallback-content {
        display: block !important;
        width: 100% !important;
        height: auto !important;
        min-height: 0 !important;
        max-height: none !important;
        overflow: visible !important;
        position: static !important;
        padding: 0 !important;
        margin: 0 !important;
        border: none !important;
        box-shadow: none !important;
        background: #ffffff !important;
        color: #000000 !important;
      }

      /* Clean page break support */
      .page-break,
      .ck-content .page-break,
      [data-page-break] {
        display: block !important;
        clear: both !important;
        page-break-after: always !important;
        break-after: page !important;
        page-break-before: auto !important;
        break-before: auto !important;
        height: 0 !important;
        min-height: 0 !important;
        margin: 0 !important;
        padding: 0 !important;
        border: none !important;
        visibility: hidden !important;
      }

      /* Avoid awkward cuts inside blocks */
      h1, h2, h3, h4, h5, h6 {
        page-break-after: avoid !important;
        break-after: avoid !important;
      }

      figure.table,
      .ck-content table,
      table {
        page-break-inside: auto !important;
        break-inside: auto !important;
        width: 100% !important;
        max-width: 100% !important;
        border-collapse: collapse !important;
      }

      tr, th, td {
        page-break-inside: avoid !important;
        break-inside: avoid !important;
      }

      figure.image,
      figure.media,
      .media,
      img,
      pre,
      blockquote,
      .math-block {
        page-break-inside: avoid !important;
        break-inside: avoid !important;
        max-width: 100% !important;
      }

      figure.media iframe,
      figure.media video,
      .media iframe,
      .media video {
        max-width: 100% !important;
        box-shadow: none !important;
      }
    }
  </style>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/mammoth/1.8.0/mammoth.browser.min.js"></script>
</head>
<body class="$darkClass">
  <div id="app-container">
    <!-- ==== ACTION BAR (Premium-like features) ==== -->
    <div id="action-bar">
      <!-- <button onclick="toggleFullscreen()" id="btn-fullscreen" title="Toggle Fullscreen (Maximize Editor)" style="background:#eff6ff;color:#1d4ed8;font-weight:600;border-color:#bfdbfe;">⛶ Fullscreen</button>
      <div class="separator"></div> -->
      <button onclick="exportToPDF()" title="Export to PDF (opens Print, then choose Save as PDF)">📄 PDF</button>
      <button onclick="exportToWord()" title="Export to Word (.docx)">📝 Word</button>
      <button onclick="importFromWord()" title="Import a document (Word, HTML, RTF or TXT)">📂 Import</button>
      <button onclick="printEditor()" title="Print">🖨️ Print</button>
      <div class="separator"></div>
      <!-- <button onclick="toggleTrackChanges()" id="btn-track-changes" title="Track Changes">📋 Track</button> -->
      <!-- <button onclick="openPanel('comments')" title="Comments">💬 Comments</button> -->
      <button onclick="openPanel('revisions')" title="Revision History">🕐 History</button>
      <button onclick="openPanel('outline')" title="Document Outline">📑 Outline</button>
      <div class="separator"></div>
      <button onclick="showFormulaHelpModal()" title="Add or edit a formula in the selected table cell">⚡ Formulas (Auto)</button>
      <button onclick="openTableColorModal()" id="btn-table-color" title="Color Table Cells, Columns, Rows or Entire Table" style="background:#fef3c7;color:#92400e;font-weight:600;border-color:#fcd34d;">🎨 Table Color</button>
      <button onclick="showCellRefModal()" id="btn-cell-ref" title="Reference Table Cell in Text (Type \$ or \$A1)" style="background:#f0fdf4;color:#15803d;font-weight:600;border-color:#bbf7d0;">🔗 Ref Cell (\$)</button>
      <div class="separator"></div>
      <button onclick="showTemplateModal()" title="Insert Template" style="display:none;">📋 Templates</button>
      <button onclick="openAiPromptModal()" id="btn-ai-generate" title="Generate with AI (Type or Speak)" style="background:#f5f3ff;color:#7c3aed;font-weight:600;border-color:#ddd6fe;display:inline-flex;align-items:center;gap:4px;">✨ Generate</button>
      <button onclick="toggleDirectVoiceInput()" id="btn-voice-to-text" title="Voice to Text — Dictate speech directly into document" style="background:#fef2f2;color:#dc2626;font-weight:600;border-color:#fecaca;display:inline-flex;align-items:center;gap:4px;"><span id="btn-voice-icon">🎙️</span><span id="btn-voice-label">Voice to Text</span></button>
      <button onclick="showMathModal()" id="btn-math" title="Insert Math Equation" style="display:none;">∑ Math</button>
      <button onclick="insertPageBreak()" title="Insert Page Break">📃 Page Break</button>
      <button onclick="openVideoModal()" id="btn-video" title="Insert & Resize Video (YouTube, Vimeo, MP4)" style="background:#ede9fe;color:#5b21b6;border-color:#ddd6fe;font-weight:600;">🎬 Video</button>
      <button onclick="showSlashModal()" title="Slash Commands & Quick Insert (Cmd+/)" style="display:none;">⚡ / Slash</button>
      <button onclick="toggleShowBlocks()" id="btn-show-blocks" title="Show Blocks" style="display:none;">¶ Blocks</button>
      <div class="separator"></div>
      <button onclick="formatPainter()" id="btn-format-painter" title="Format Painter" style="display:none;">🖌️ Painter</button>
      <button onclick="harmonizeSelectionStyles()" id="btn-harmonize" title="Match Document Style (Normalize fonts/sizes in pasted content)" style="display:none;background:#f0fdf4;color:#166534;border-color:#bbf7d0;font-weight:600;">🧹 Harmonize</button>
      <button onclick="toggleReadonly()" id="btn-readonly" title="Toggle Preview (Read Only)">👁️ Preview</button>
      <select onchange="changeLanguage(this.value)" id="select-dir" title="Text Direction">
        <option value="ltr" $ltrSelected>LTR</option>
        <option value="rtl" $rtlSelected>RTL</option>
      </select>
    </div>

    <!-- ==== EDITOR + SIDE PANEL ==== -->
    <div id="editor-wrapper">
      <div id="editor-main">
        <!-- Loading Spinner -->
        <div id="editor-loading" style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:240px;color:#64748b;font-size:13px;gap:12px;">
          <div style="width:28px;height:28px;border:3px solid #e2e8f0;border-top-color:#3b82f6;border-radius:50%;animation:spin 0.8s linear infinite;"></div>
          <span>Loading editor controls...</span>
          <button id="btn-force-fallback" onclick="initFallback()" style="display:none;padding:5px 12px;border:1px solid #cbd5e1;background:#fff;border-radius:6px;font-size:12px;color:#2563eb;cursor:pointer;font-weight:500;">Use Standard Editor</button>
        </div>

        <div id="editor" style="display:none;"></div>

        <div id="fallback-container" style="display:none;">
          <div id="fallback-toolbar">
            <select onchange="formatDoc('formatBlock', this.value)" title="Style">
              <option value="p">Paragraph</option>
              <option value="h1">Heading 1</option>
              <option value="h2">Heading 2</option>
              <option value="h3">Heading 3</option>
              <option value="h4">Heading 4</option>
              <option value="h5">Heading 5</option>
              <option value="h6">Heading 6</option>
              <option value="pre">Code Block</option>
              <option value="blockquote">Quote</option>
            </select>
            <select onchange="formatDoc('fontName', this.value)" title="Font Family">
              <option value="Arial, sans-serif">Arial</option>
              <option value="Calibri, sans-serif">Calibri</option>
              <option value="'Segoe UI', sans-serif">Segoe UI</option>
              <option value="'Times New Roman', serif">Times New Roman</option>
              <option value="Georgia, serif">Georgia</option>
              <option value="Roboto, sans-serif">Roboto</option>
              <option value="'Courier New', monospace">Courier New</option>
            </select>
            <select onchange="formatDoc('fontSize', this.value)" title="Font Size">
              <option value="2">Small (10pt)</option>
              <option value="3" selected>Normal (12pt)</option>
              <option value="4">Medium (14pt)</option>
              <option value="5">Large (18pt)</option>
              <option value="6">Extra Large (24pt)</option>
              <option value="7">Huge (36pt)</option>
            </select>
            <div class="fallback-sep"></div>
            <button onclick="formatDoc('bold')" title="Bold"><b>B</b></button>
            <button onclick="formatDoc('italic')" title="Italic"><i>I</i></button>
            <button onclick="formatDoc('underline')" title="Underline"><u>U</u></button>
            <button onclick="formatDoc('strikeThrough')" title="Strikethrough"><s>S</s></button>
            <button onclick="formatDoc('subscript')" title="Subscript">X<sub>2</sub></button>
            <button onclick="formatDoc('superscript')" title="Superscript">X<sup>2</sup></button>
            <div class="fallback-sep"></div>
            <label title="Text Color" style="display:inline-flex;align-items:center;padding:2px 6px;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;background:#fff;font-size:12px;gap:4px;">
              <span style="font-weight:bold;color:#2563eb;">A</span>
              <input type="color" onchange="formatDoc('foreColor', this.value)" value="#000000" style="width:18px;height:18px;border:none;padding:0;background:none;cursor:pointer;">
            </label>
            <label title="Highlight Color" style="display:inline-flex;align-items:center;padding:2px 6px;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;background:#fff;font-size:12px;gap:4px;">
              <span style="background:#fef08a;padding:0 2px;font-weight:bold;">H</span>
              <input type="color" onchange="formatDoc('hiliteColor', this.value)" value="#ffff00" style="width:18px;height:18px;border:none;padding:0;background:none;cursor:pointer;">
            </label>
            <div class="fallback-sep"></div>
            <button onclick="formatDoc('justifyLeft')" title="Align Left">⇤</button>
            <button onclick="formatDoc('justifyCenter')" title="Align Center">⇥⇤</button>
            <button onclick="formatDoc('justifyRight')" title="Align Right">⇥</button>
            <button onclick="formatDoc('justifyFull')" title="Justify">≡</button>
            <div class="fallback-sep"></div>
            <button onclick="formatDoc('insertUnorderedList')" title="Bulleted List">• List</button>
            <button onclick="formatDoc('insertOrderedList')" title="Numbered List">1. List</button>
            <button onclick="formatDoc('outdent')" title="Outdent">← Out</button>
            <button onclick="formatDoc('indent')" title="Indent">In →</button>
            <div class="fallback-sep"></div>
            <button onclick="insertFallbackTable()" title="Insert Table">📊 Table</button>
            <button onclick="insertFallbackLink()" title="Insert Link">🔗 Link</button>
            <button onclick="insertFallbackHorizontalRule()" title="Horizontal Line">― Line</button>
            <button onclick="formatDoc('removeFormat')" title="Clear Formatting">🧹 Clear</button>
            <div class="fallback-sep"></div>
            <button onclick="toggleDirectVoiceInput()" id="fallback-btn-voice" title="Voice to Text (Dictate)" style="color:#dc2626;font-weight:600;">🎙️ Voice</button>
            <div class="fallback-sep"></div>
            <button onclick="formatDoc('undo')" title="Undo">↺</button>
            <button onclick="formatDoc('redo')" title="Redo">↻</button>
          </div>
          <div id="fallback-content" contenteditable="true"></div>
        </div>
      </div>

      <!-- Side Panel -->
      <div id="side-panel">
        <div id="side-panel-header">
          <span id="side-panel-title">Panel</span>
          <button onclick="closePanel()">&times;</button>
        </div>
        <div id="side-panel-content"></div>
      </div>
    </div>

    <!-- ==== STATUS BAR ==== -->
    <div id="status-bar">
      <div class="status-section">
        <span id="word-count">Words: 0</span>
        <span id="char-count">Characters: 0</span>
        <span id="para-count">Paragraphs: 0</span>
      </div>
      <div class="status-section">
        <span id="track-status">Track Changes: Off</span>
        <span class="page-indicator" id="page-indicator">Page 1</span>
      </div>
    </div>
  <!-- ==== AI GENERATE & VOICE MODAL ==== -->
  <div class="modal-overlay" id="ai-prompt-modal">
    <div class="modal-box" style="max-width:580px;box-shadow:0 20px 40px rgba(0,0,0,0.3);border-radius:14px;">
      <button class="close-modal" onclick="closeAiPromptModal()">&times;</button>
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:6px;">
        <span style="font-size:22px;">✨</span>
        <h2 style="margin:0;font-size:18px;color:#1e293b;">Generate with AI</h2>
      </div>
      <p style="margin-bottom:14px;color:#64748b;font-size:13px;line-height:1.4;">Type your prompt or click the microphone to speak. You can edit the text before sending to the API.</p>
      
      <!-- Input container with embedded mic button -->
      <div style="position:relative;margin-bottom:12px;">
        <textarea id="ai-prompt-input" rows="5" placeholder="Type prompt here, or click mic to speak (e.g. Generate a summary table with 5 sample items)..." style="width:100%;padding:12px 50px 12px 14px;border:1px solid #cbd5e1;border-radius:10px;font-size:14px;font-family:inherit;box-sizing:border-box;resize:vertical;min-height:110px;line-height:1.5;outline:none;" oninput="updateAiModalState()"></textarea>
        <button type="button" id="ai-prompt-mic-btn" onclick="toggleAiPromptMic()" title="Tap to speak into text box" style="position:absolute;right:10px;bottom:14px;background:#f8fafc;border:1px solid #cbd5e1;border-radius:50%;width:36px;height:36px;display:flex;align-items:center;justify-content:center;cursor:pointer;font-size:17px;box-shadow:0 2px 5px rgba(0,0,0,0.06);transition:all 0.2s;">🎤</button>
      </div>

      <!-- Live Mic Recording Indicator Banner -->
      <div id="ai-mic-status" style="display:none;align-items:center;gap:10px;background:#fef2f2;border:1px solid #fecaca;padding:9px 14px;border-radius:8px;margin-bottom:12px;font-size:13px;color:#b91c1c;">
        <span style="display:inline-block;width:10px;height:10px;background:#ef4444;border-radius:50%;animation:pulse 1s infinite;"></span>
        <span id="ai-mic-status-text" style="flex:1;font-weight:500;">Listening… speak now. Words will appear in the box above.</span>
        <button type="button" onclick="stopAiPromptMic()" style="background:#ef4444;color:white;border:none;border-radius:6px;padding:4px 10px;font-size:11px;font-weight:700;cursor:pointer;">Stop Mic</button>
      </div>

      <!-- Error banner if API or Speech fails -->
      <div id="ai-error-banner" style="display:none;background:#fef2f2;border:1px solid #fecaca;padding:8px 12px;border-radius:8px;margin-bottom:12px;font-size:13px;color:#dc2626;"></div>

      <div class="modal-actions" style="display:flex;justify-content:space-between;align-items:center;margin-top:12px;">
        <button type="button" onclick="clearAiPromptInput()" style="background:transparent;border:none;color:#64748b;cursor:pointer;font-size:13px;text-decoration:underline;">Clear text</button>
        <div style="display:flex;gap:10px;">
          <button type="button" onclick="closeAiPromptModal()" style="padding:9px 16px;border-radius:8px;border:1px solid #cbd5e1;background:#fff;cursor:pointer;font-size:13px;">Cancel</button>
          <button type="button" class="primary-btn" id="btn-call-api" onclick="submitAiPromptToApi()" style="padding:9px 20px;border-radius:8px;background:#7c3aed;color:#fff;font-weight:600;border:none;cursor:pointer;display:inline-flex;align-items:center;gap:6px;font-size:13px;box-shadow:0 2px 6px rgba(124,58,237,0.3);">
            <span id="btn-call-api-spinner" style="display:none;width:14px;height:14px;border:2px solid #ffffff;border-top-color:transparent;border-radius:50%;animation:spin 0.8s linear infinite;"></span>
            <span id="btn-call-api-text">✨ Generate</span>
          </button>
        </div>
      </div>
    </div>
  </div>

  <!-- ==== TEMPLATE MODAL ==== -->
  <div class="modal-overlay" id="template-modal">
    <div class="modal-box">
      <button class="close-modal" onclick="closeTemplateModal()">&times;</button>
      <h2>📋 Insert Template</h2>
      <div class="template-grid" id="template-grid"></div>
    </div>
  </div>

  <!-- ==== MATH FORMULA MODAL ==== -->
  <div class="modal-overlay" id="math-modal">
    <div class="modal-box">
      <button class="close-modal" onclick="closeMathModal()">&times;</button>
      <h2>∑ Insert Math Equation</h2>
      <p style="margin-bottom:12px;color:#64748b;font-size:13px;">Enter LaTeX notation (e.g., \\\\frac{a}{b}, x^2 + y^2 = z^2, \\\\int_0^1 f(x)dx)</p>
      <input type="text" class="math-input" id="math-input" placeholder="Enter LaTeX formula..." oninput="previewMath()">
      <div class="math-preview" id="math-preview">Preview will appear here</div>
      <div class="modal-actions">
        <button onclick="closeMathModal()">Cancel</button>
        <button class="primary-btn" onclick="insertMathFormula()">Insert</button>
      </div>
    </div>
  </div>

  <!-- ==== SLASH COMMANDS MODAL ==== -->
  <div class="modal-overlay" id="slash-modal">
    <div class="modal-box" style="max-width:550px;">
      <button class="close-modal" onclick="closeSlashModal()">&times;</button>
      <h2>⚡ Quick Insert & Slash Commands</h2>
      <p style="margin-bottom:12px;color:#64748b;font-size:13px;">Press <kbd style="background:#e2e8f0;padding:2px 6px;border-radius:4px;font-family:monospace;">Cmd+/</kbd> or <kbd style="background:#e2e8f0;padding:2px 6px;border-radius:4px;font-family:monospace;">Ctrl+/</kbd> anytime, or click any item to insert.</p>
      <input type="text" id="slash-search" placeholder="Filter commands (e.g. table, code, math, heading)..." oninput="filterSlashCommands()" style="width:100%;padding:10px 14px;border:1px solid #cbd5e1;border-radius:8px;font-size:14px;margin-bottom:14px;box-sizing:border-box;">
      <div id="slash-list" style="max-height:360px;overflow-y:auto;display:flex;flex-direction:column;gap:4px;"></div>
    </div>
  </div>

  <!-- ==== FORMULA HELP & EDITOR MODAL ==== -->
  <div class="modal-overlay" id="formula-modal">
    <div class="modal-box" style="max-width:580px;max-height:min(90vh,90dvh);overflow-y:auto;padding:18px 22px;">
      <button class="close-modal" onclick="closeFormulaHelpModal()">&times;</button>
      <h2 id="formula-modal-title" style="margin:0 0 12px 0;font-size:17px;display:flex;align-items:center;gap:8px;">🧮 Table Formula Editor</h2>
      
      <!-- Interactive Cell Formula Editor -->
      <div id="formula-editor-section" style="background:#f0f7ff;border:1px solid #bfdbfe;border-radius:10px;padding:14px;margin-bottom:14px;">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
          <span style="font-weight:700;color:#1e40af;font-size:13px;display:flex;align-items:center;gap:6px;" id="formula-cell-coord">📍 Target Cell: None selected</span>
          <span style="font-size:11px;color:#2563eb;background:#dbeafe;padding:2px 8px;border-radius:12px;font-weight:600;">⚡ Auto-Calculates Live</span>
        </div>
        <div style="display:flex;gap:8px;margin-bottom:8px;">
          <input type="text" id="formula-editor-input" placeholder="e.g. =SUM(A1+A2) or =A1*B1" style="flex:1;padding:9px 12px;border:1.5px solid #93c5fd;border-radius:6px;font-family:monospace;font-size:13.5px;outline:none;" oninput="updateFormulaLivePreview()" onkeydown="if(event.key==='Enter')applyCurrentCellFormula();">
          <button id="formula-apply-btn" onclick="applyCurrentCellFormula()" class="primary-btn" style="padding:7px 16px;font-size:13px;background:#2563eb;color:white;border-radius:6px;border:none;cursor:pointer;font-weight:600;box-shadow:0 1px 2px rgba(37,99,235,0.2);">Apply</button>
          <button id="formula-clear-btn" onclick="clearCurrentCellFormula()" style="padding:7px 12px;font-size:13px;background:#fee2e2;color:#b91c1c;border:1px solid #fca5a5;border-radius:6px;cursor:pointer;font-weight:500;" title="Remove or clear formula">Clear</button>
        </div>

        <!-- Live Calculation Preview -->
        <div id="formula-preview-row" style="display:flex;align-items:center;justify-content:space-between;background:#ffffff;border:1px dashed #93c5fd;border-radius:6px;padding:6px 10px;margin-bottom:10px;">
          <span style="font-size:12px;color:#475569;font-weight:500;">📊 Live Result Preview:</span>
          <span id="formula-live-preview-val" style="font-size:13px;font-weight:700;font-family:monospace;color:#16a34a;">--</span>
        </div>

        <!-- Math Operator & Function Buttons -->
        <div style="display:flex;flex-wrap:wrap;gap:5px;align-items:center;margin-bottom:8px;">
          <span style="font-size:11px;color:#475569;font-weight:600;">Operators:</span>
          <button type="button" onclick="insertFormulaToken('+')" style="padding:3px 9px;font-size:12px;background:#ffffff;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;font-weight:700;color:#1e293b;">+</button>
          <button type="button" onclick="insertFormulaToken('-')" style="padding:3px 9px;font-size:12px;background:#ffffff;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;font-weight:700;color:#1e293b;">-</button>
          <button type="button" onclick="insertFormulaToken('*')" style="padding:3px 9px;font-size:12px;background:#ffffff;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;font-weight:700;color:#1e293b;">&times;</button>
          <button type="button" onclick="insertFormulaToken('/')" style="padding:3px 9px;font-size:12px;background:#ffffff;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;font-weight:700;color:#1e293b;">&divide;</button>
          <button type="button" onclick="insertFormulaToken('(')" style="padding:3px 9px;font-size:12px;background:#ffffff;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;font-weight:700;color:#1e293b;">(</button>
          <button type="button" onclick="insertFormulaToken(')')" style="padding:3px 9px;font-size:12px;background:#ffffff;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;font-weight:700;color:#1e293b;">)</button>
          <button type="button" onclick="insertFormulaToken(', ')" style="padding:3px 9px;font-size:12px;background:#ffffff;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;font-weight:700;color:#1e293b;">,</button>
          <button type="button" onclick="insertFormulaToken(':')" style="padding:3px 9px;font-size:12px;background:#ffffff;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;font-weight:700;color:#1e293b;">:</button>
        </div>

        <div style="display:flex;flex-wrap:wrap;gap:5px;align-items:center;">
          <span style="font-size:11px;color:#475569;font-weight:600;">Functions:</span>
          <button type="button" onclick="wrapOrSetFormulaFunction('SUM')" style="font-size:11px;padding:3px 8px;background:#eff6ff;border:1px solid #bfdbfe;border-radius:4px;cursor:pointer;color:#1d4ed8;font-weight:600;">SUM(&hellip;)</button>
          <button type="button" onclick="wrapOrSetFormulaFunction('AVG')" style="font-size:11px;padding:3px 8px;background:#eff6ff;border:1px solid #bfdbfe;border-radius:4px;cursor:pointer;color:#1d4ed8;font-weight:600;">AVG(&hellip;)</button>
          <button type="button" onclick="wrapOrSetFormulaFunction('COUNT')" style="font-size:11px;padding:3px 8px;background:#eff6ff;border:1px solid #bfdbfe;border-radius:4px;cursor:pointer;color:#1d4ed8;font-weight:600;">COUNT(&hellip;)</button>
          <button type="button" onclick="wrapOrSetFormulaFunction('MAX')" style="font-size:11px;padding:3px 8px;background:#eff6ff;border:1px solid #bfdbfe;border-radius:4px;cursor:pointer;color:#1d4ed8;font-weight:600;">MAX(&hellip;)</button>
          <button type="button" onclick="wrapOrSetFormulaFunction('MIN')" style="font-size:11px;padding:3px 8px;background:#eff6ff;border:1px solid #bfdbfe;border-radius:4px;cursor:pointer;color:#1d4ed8;font-weight:600;">MIN(&hellip;)</button>
          <button type="button" onclick="setFormulaInput('=SUM(ABOVE)')" style="font-size:11px;padding:3px 8px;background:#f8fafc;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;color:#475569;font-weight:500;">=SUM(ABOVE)</button>
        </div>
      </div>

      <!-- Interactive Table Cells Grid: Click cell to insert into formula -->
      <div style="background:#ffffff;border:1px solid #e2e8f0;border-radius:10px;padding:12px;margin-bottom:14px;">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
          <span style="font-weight:600;color:#0f172a;font-size:12.5px;">📍 Click Table Cells to Add to Formula:</span>
          <span style="font-size:11px;color:#64748b;">Click cell to insert coordinate</span>
        </div>
        <div id="formula-cells-picker-grid" style="display:grid;grid-template-columns:repeat(auto-fill, minmax(110px, 1fr));gap:6px;max-height:160px;overflow-y:auto;padding:2px;">
          <!-- Dynamically populated -->
        </div>
      </div>
      
      <div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;padding:12px;margin-bottom:14px;font-size:13px;">
        <div style="font-weight:600;margin-bottom:6px;color:#1e293b;">📍 How Cell Coordinates Work</div>
        <p style="margin:0 0 6px 0;color:#64748b;font-size:12px;">Columns are letters (<strong>A, B, C...</strong>) and rows are numbers (<strong>1, 2, 3...</strong>):</p>
        <div style="display:grid;grid-template-columns:70px 1fr 1fr;gap:1px;background:#cbd5e1;border:1px solid #cbd5e1;border-radius:6px;overflow:hidden;margin:6px 0;font-size:12px;">
          <div style="background:#f1f5f9;padding:6px;font-weight:600;text-align:center;"></div>
          <div style="background:#f1f5f9;padding:6px;font-weight:600;text-align:center;">Column A</div>
          <div style="background:#f1f5f9;padding:6px;font-weight:600;text-align:center;">Column B</div>
          <div style="background:#f1f5f9;padding:6px;font-weight:600;text-align:center;">Row 1</div>
          <div style="background:#ffffff;padding:6px;">Cell <strong>A1</strong> (e.g. 120)</div>
          <div style="background:#ffffff;padding:6px;">Cell <strong>B1</strong></div>
          <div style="background:#f1f5f9;padding:6px;font-weight:600;text-align:center;">Row 2</div>
          <div style="background:#ffffff;padding:6px;">Cell <strong>A2</strong> (e.g. 230)</div>
          <div style="background:#ffffff;padding:6px;">Cell <strong>B2</strong></div>
          <div style="background:#f1f5f9;padding:6px;font-weight:600;text-align:center;">Row 3</div>
          <div style="background:#eff6ff;padding:6px;">Cell <strong>A3</strong> (e.g. <code>=SUM(A1+A2)</code>)</div>
          <div style="background:#ffffff;padding:6px;">Cell <strong>B3</strong></div>
        </div>
      </div>

      <div style="display:flex;flex-direction:column;gap:8px;font-size:13px;margin-bottom:16px;">
        <div style="padding:8px 12px;background:#eff6ff;border-radius:6px;border-left:3px solid #3b82f6;">
          <strong>Addition & Sum:</strong> <code>=SUM(A1+A2)</code> or <code>=A1+A2</code> or <code>=SUM(A1:A2)</code>
        </div>
        <div style="padding:8px 12px;background:#f0fdf4;border-radius:6px;border-left:3px solid #22c55e;">
          <strong>Average:</strong> <code>=AVG(A1:A2)</code> or <code>=AVERAGE(A1:A2)</code>
        </div>
        <div style="padding:8px 12px;background:#fefce8;border-radius:6px;border-left:3px solid #eab308;">
          <strong>Arithmetic:</strong> <code>=A1 * B1</code> &nbsp;|&nbsp; <code>=A1 - A2</code> &nbsp;|&nbsp; <code>=A1 / 2</code>
        </div>
        <div style="padding:8px 12px;background:#faf5ff;border-radius:6px;border-left:3px solid #a855f7;">
          <strong>Min, Max, Count:</strong> <code>=MIN(A1:A5)</code> &nbsp;|&nbsp; <code>=MAX(A1:A5)</code> &nbsp;|&nbsp; <code>=COUNT(A1:A5)</code>
        </div>
      </div>

      <div class="modal-actions">
        <button class="primary-btn" onclick="closeFormulaHelpModal();">✓ Done</button>
      </div>
    </div>
  </div>

  <!-- ==== TABLE COLOR & STYLING MODAL ==== -->
  <div class="modal-overlay" id="table-color-modal">
    <div class="modal-box" style="max-width:520px;max-height:min(90vh,90dvh);overflow-y:auto;padding:16px 20px;display:flex;flex-direction:column;gap:10px;">
      <div style="display:flex;justify-content:space-between;align-items:center;border-bottom:1px solid #e2e8f0;padding-bottom:8px;">
        <div style="display:flex;align-items:center;gap:8px;">
          <h2 style="font-size:16px;margin:0;color:#0f172a;">🎨 Table Styling & Color</h2>
          <span id="tbl-color-target-info" style="font-size:11px;background:#eff6ff;color:#1d4ed8;padding:2px 8px;border-radius:12px;font-weight:600;border:1px solid #bfdbfe;">Active Table</span>
        </div>
        <button class="close-modal" onclick="closeTableColorModal()" style="font-size:20px;padding:0 4px;line-height:1;">&times;</button>
      </div>

      <!-- Target Selection -->
      <div>
        <label style="font-weight:600;font-size:11.5px;display:block;margin-bottom:5px;color:#334155;">1. Choose Target:</label>
        <div style="display:flex;gap:5px;flex-wrap:wrap;">
          <button type="button" class="tbl-target-btn active" data-target="cell" onclick="setTableColorTarget('cell')" style="padding:4px 9px;font-size:11.5px;">🔲 Current Cell</button>
          <button type="button" class="tbl-target-btn" data-target="col" onclick="setTableColorTarget('col')" style="padding:4px 9px;font-size:11.5px;">🏛️ Entire Column</button>
          <button type="button" class="tbl-target-btn" data-target="row" onclick="setTableColorTarget('row')" style="padding:4px 9px;font-size:11.5px;">➖ Entire Row</button>
          <button type="button" class="tbl-target-btn" data-target="table" onclick="setTableColorTarget('table')" style="padding:4px 9px;font-size:11.5px;">📊 Entire Table</button>
          <button type="button" class="tbl-target-btn" data-target="header" onclick="setTableColorTarget('header')" style="padding:4px 9px;font-size:11.5px;">🏷️ Header Row</button>
          <button type="button" class="tbl-target-btn" data-target="zebra" onclick="setTableColorTarget('zebra')" style="padding:4px 9px;font-size:11.5px;">🦓 Zebra Stripes</button>
        </div>
      </div>

      <!-- Color Presets -->
      <div>
        <label style="font-weight:600;font-size:11.5px;display:block;margin-bottom:5px;color:#334155;">2. Select Background Color:</label>
        <div class="color-swatch-grid" style="display:grid;grid-template-columns:repeat(auto-fill, minmax(36px, 1fr));gap:5px;">
          <button type="button" class="color-swatch" style="height:26px;background:#ffffff;border:1px solid #cbd5e1;" title="Clear / White" onclick="applyPresetBg('#ffffff')"></button>
          <button type="button" class="color-swatch" style="height:26px;background:#eff6ff;border:1px solid #bfdbfe;" title="Soft Blue" onclick="applyPresetBg('#eff6ff')"></button>
          <button type="button" class="color-swatch" style="height:26px;background:#f0fdf4;border:1px solid #bbf7d0;" title="Soft Green" onclick="applyPresetBg('#f0fdf4')"></button>
          <button type="button" class="color-swatch" style="height:26px;background:#fefce8;border:1px solid #fef08a;" title="Soft Yellow" onclick="applyPresetBg('#fefce8')"></button>
          <button type="button" class="color-swatch" style="height:26px;background:#faf5ff;border:1px solid #e9d5ff;" title="Soft Purple" onclick="applyPresetBg('#faf5ff')"></button>
          <button type="button" class="color-swatch" style="height:26px;background:#fef2f2;border:1px solid #fecaca;" title="Soft Red" onclick="applyPresetBg('#fef2f2')"></button>
          <button type="button" class="color-swatch" style="height:26px;background:#f1f5f9;border:1px solid #cbd5e1;" title="Slate Gray" onclick="applyPresetBg('#f1f5f9')"></button>
          <button type="button" class="color-swatch" style="height:26px;background:#e0e7ff;border:1px solid #c7d2fe;" title="Indigo Light" onclick="applyPresetBg('#e0e7ff')"></button>
          <button type="button" class="color-swatch" style="height:26px;background:#ccfbf1;border:1px solid #99f6e4;" title="Teal Light" onclick="applyPresetBg('#ccfbf1')"></button>
          <button type="button" class="color-swatch" style="height:26px;background:#ffedd5;border:1px solid #fed7aa;" title="Orange Light" onclick="applyPresetBg('#ffedd5')"></button>
          <button type="button" class="color-swatch" style="height:26px;background:#2563eb;border:1px solid #1d4ed8;" title="Royal Blue" onclick="applyPresetBg('#2563eb')"></button>
          <button type="button" class="color-swatch" style="height:26px;background:#1e293b;border:1px solid #0f172a;" title="Dark Slate" onclick="applyPresetBg('#1e293b')"></button>
        </div>
        <div style="display:flex;align-items:center;gap:8px;margin-top:8px;">
          <label style="font-size:11.5px;color:#475569;font-weight:500;">Custom:</label>
          <input type="color" id="tbl-custom-bg" value="#3b82f6" style="width:34px;height:26px;padding:1px;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;" onchange="applyCustomBg(this.value)">
          <button type="button" onclick="clearTableBg()" style="padding:3px 8px;font-size:11px;border:1px solid #cbd5e1;background:#fff;border-radius:4px;cursor:pointer;">Clear Background</button>
        </div>
      </div>

      <!-- Border Color & Text Color Options -->
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;padding:8px;background:#f8fafc;border:1px solid #e2e8f0;border-radius:6px;">
        <div>
          <label style="font-weight:600;font-size:11.5px;display:block;margin-bottom:4px;color:#334155;">Border Color:</label>
          <div style="display:flex;align-items:center;gap:5px;">
            <input type="color" id="tbl-border-color" value="#cbd5e1" style="width:32px;height:24px;padding:1px;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;" onchange="applyBorderColor(this.value)">
            <button type="button" onclick="applyBorderColor('#cbd5e1')" style="padding:2px 6px;font-size:10.5px;border:1px solid #cbd5e1;background:#fff;border-radius:4px;cursor:pointer;">Default</button>
            <button type="button" onclick="applyBorderColor('#3b82f6')" style="padding:2px 6px;font-size:10.5px;border:1px solid #93c5fd;background:#eff6ff;color:#1d4ed8;border-radius:4px;cursor:pointer;">Blue</button>
          </div>
        </div>
        <div>
          <label style="font-weight:600;font-size:11.5px;display:block;margin-bottom:4px;color:#334155;">Text Color:</label>
          <div style="display:flex;align-items:center;gap:5px;">
            <input type="color" id="tbl-text-color" value="#0f172a" style="width:32px;height:24px;padding:1px;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;" onchange="applyTextColor(this.value)">
            <button type="button" onclick="applyTextColor('#0f172a')" style="padding:2px 6px;font-size:10.5px;border:1px solid #cbd5e1;background:#fff;border-radius:4px;cursor:pointer;">Dark</button>
            <button type="button" onclick="applyTextColor('#ffffff')" style="padding:2px 6px;font-size:10.5px;border:1px solid #475569;background:#1e293b;color:#fff;border-radius:4px;cursor:pointer;">White</button>
          </div>
        </div>
      </div>

      <!-- 3. Row & Column Quick Actions -->
      <div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:6px;padding:8px 10px;">
        <label style="font-weight:600;font-size:11.5px;display:block;margin-bottom:6px;color:#334155;">3. Row &amp; Column Quick Actions:</label>
        <div style="display:flex;gap:5px;flex-wrap:wrap;">
          <button type="button" onclick="insertTableRow(true)" style="padding:4px 8px;font-size:11px;background:#ffffff;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;font-weight:500;">⬆️ Row Above</button>
          <button type="button" onclick="insertTableRow(false)" style="padding:4px 8px;font-size:11px;background:#ffffff;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;font-weight:500;">⬇️ Row Below</button>
          <button type="button" onclick="deleteTableRow()" style="padding:4px 8px;font-size:11px;background:#fee2e2;color:#b91c1c;border:1px solid #fca5a5;border-radius:4px;cursor:pointer;font-weight:500;">🗑️ Del Row</button>
          <button type="button" onclick="insertTableColumn(true)" style="padding:4px 8px;font-size:11px;background:#ffffff;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;font-weight:500;">⬅️ Col Left</button>
          <button type="button" onclick="insertTableColumn(false)" style="padding:4px 8px;font-size:11px;background:#ffffff;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;font-weight:500;">➡️ Col Right</button>
          <button type="button" onclick="deleteTableColumn()" style="padding:4px 8px;font-size:11px;background:#fee2e2;color:#b91c1c;border:1px solid #fca5a5;border-radius:4px;cursor:pointer;font-weight:500;">🗑️ Del Col</button>
          <button type="button" onclick="closeTableColorModal();showFormulaHelpModal();" style="padding:4px 8px;font-size:11px;background:#eff6ff;color:#1d4ed8;border:1px solid #93c5fd;border-radius:4px;cursor:pointer;font-weight:600;">🧮 Formula</button>
        </div>
      </div>

      <div class="modal-actions" style="margin-top:4px;padding-top:8px;border-top:1px solid #e2e8f0;display:flex;justify-content:space-between;align-items:center;">
        <button type="button" onclick="harmonizeActiveTable()" style="padding:5px 10px;background:#f0fdf4;color:#166534;border:1px solid #86efac;border-radius:6px;font-size:11.5px;cursor:pointer;font-weight:600;display:flex;align-items:center;gap:4px;">🧹 Harmonize Table</button>
        <button class="primary-btn" onclick="closeTableColorModal()" style="padding:5px 16px;font-size:12px;">Done</button>
      </div>
    </div>
  </div>

  <!-- ==== TABLE CELL REFERENCE PICKER MODAL ==== -->
  <div class="modal-overlay" id="cell-ref-modal">
    <div class="modal-box" style="max-width:680px;width:95%;">
      <button class="close-modal" onclick="closeCellRefModal()">&times;</button>
      <h2 style="display:flex;align-items:center;gap:8px;">🔗 Reference Table Cell in Text</h2>
      <p style="margin-bottom:12px;color:#64748b;font-size:12.5px;">Click any cell from your document's tables below or type coordinate (e.g. <strong>\$A1</strong>) to insert a live reactive reference.</p>

      <div style="display:flex;gap:8px;margin-bottom:12px;align-items:center;">
        <input type="text" id="cell-ref-search" placeholder="🔍 Search cell value, header, or coordinate (e.g. A1, Team A)..." 
               style="flex:1;padding:8px 12px;border:1px solid #cbd5e1;border-radius:6px;font-size:13px;outline:none;"
               oninput="renderCellRefPickerGrid()">
        <select id="cell-ref-table-select" style="padding:8px 12px;border:1px solid #cbd5e1;border-radius:6px;font-size:13px;"
                onchange="renderCellRefPickerGrid()">
        </select>
      </div>

      <!-- Live interactive table cell grid -->
      <div id="cell-ref-grid-container" style="max-height:280px;overflow:auto;border:1px solid #cbd5e1;border-radius:8px;padding:8px;background:#f8fafc;">
      </div>

      <div style="display:flex;justify-content:space-between;align-items:center;margin-top:14px;padding-top:10px;border-top:1px solid #e2e8f0;">
        <span style="font-size:12px;color:#64748b;">
          💡 Pro-tip: You can also type <strong>\$</strong> anywhere to open auto-complete, or type <strong>\$A1</strong> directly!
        </span>
        <button class="primary-btn" onclick="closeCellRefModal()" style="padding:6px 16px;font-size:12px;">Close</button>
      </div>
    </div>
  </div>

  <!-- ==== VIDEO ATTACHMENT & RESIZE MODAL ==== -->
  <div class="modal-overlay" id="video-modal">
    <div class="modal-box" style="max-width:520px;">
      <button class="close-modal" onclick="closeVideoModal()">&times;</button>
      <h2>🎬 Video Attachment & Sizing</h2>
      <p style="margin-bottom:12px;color:#64748b;font-size:12px;">Insert YouTube, Vimeo, or local video file with custom display size and alignment.</p>

      <!-- Video Source Tabs -->
      <div style="display:flex;gap:8px;margin-bottom:12px;border-bottom:1px solid #e2e8f0;padding-bottom:8px;">
        <button type="button" id="tab-video-url" class="tbl-target-btn active" onclick="switchVideoTab('url')">🌐 Video URL</button>
        <button type="button" id="tab-video-file" class="tbl-target-btn" onclick="switchVideoTab('file')">📁 Upload Video File</button>
      </div>

      <!-- URL Input -->
      <div id="video-tab-url-content" style="margin-bottom:14px;">
        <label style="font-weight:600;font-size:12px;display:block;margin-bottom:4px;color:#334155;">Video URL (YouTube, Vimeo, or MP4):</label>
        <input type="text" id="video-url-input" placeholder="https://www.youtube.com/watch?v=... or https://example.com/video.mp4" style="width:100%;padding:8px 10px;border:1px solid #cbd5e1;border-radius:6px;font-size:13px;box-sizing:border-box;">
      </div>

      <!-- File Upload Input -->
      <div id="video-tab-file-content" style="margin-bottom:14px;display:none;">
        <label style="font-weight:600;font-size:12px;display:block;margin-bottom:4px;color:#334155;">Select Local Video File (.mp4, .webm, .mov):</label>
        <input type="file" id="video-file-input" accept="video/mp4,video/webm,video/ogg,video/quicktime" style="width:100%;padding:6px;border:1px dashed #cbd5e1;border-radius:6px;font-size:12px;background:#f8fafc;box-sizing:border-box;">
      </div>

      <!-- Initial Size Selection -->
      <div style="margin-bottom:14px;">
        <label style="font-weight:600;font-size:12px;display:block;margin-bottom:6px;color:#334155;">Choose Display Size:</label>
        <div style="display:flex;gap:6px;flex-wrap:wrap;">
          <button type="button" class="video-size-opt tbl-target-btn" data-size="25%" onclick="selectVideoInitialSize('25%')">25% (Compact)</button>
          <button type="button" class="video-size-opt tbl-target-btn active" data-size="50%" onclick="selectVideoInitialSize('50%')">50% (Half)</button>
          <button type="button" class="video-size-opt tbl-target-btn" data-size="75%" onclick="selectVideoInitialSize('75%')">75% (Large)</button>
          <button type="button" class="video-size-opt tbl-target-btn" data-size="100%" onclick="selectVideoInitialSize('100%')">100% (Full)</button>
        </div>
      </div>

      <!-- Initial Alignment -->
      <div style="margin-bottom:16px;">
        <label style="font-weight:600;font-size:12px;display:block;margin-bottom:6px;color:#334155;">Alignment:</label>
        <div style="display:flex;gap:6px;">
          <button type="button" class="video-align-opt tbl-target-btn" data-align="left" onclick="selectVideoInitialAlign('left')">⬅️ Left</button>
          <button type="button" class="video-align-opt tbl-target-btn active" data-align="center" onclick="selectVideoInitialAlign('center')">⏺️ Center</button>
          <button type="button" class="video-align-opt tbl-target-btn" data-align="right" onclick="selectVideoInitialAlign('right')">➡️ Right</button>
        </div>
      </div>

      <div class="modal-actions">
        <button type="button" onclick="closeVideoModal()">Cancel</button>
        <button type="button" class="primary-btn" onclick="insertConfiguredVideo()">Insert Video</button>
      </div>
    </div>
  </div>

  <!-- Floating Voice Input Transcription Bar -->
  <div id="voice-live-bar" style="display:none;flex-direction:column;position:fixed;bottom:24px;left:50%;transform:translateX(-50%);width:min(640px, calc(100vw - 32px));box-sizing:border-box;background:#0f172a;color:#f8fafc;padding:10px 14px;border-radius:16px;box-shadow:0 12px 30px rgba(0,0,0,0.35);z-index:999999;gap:8px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;font-size:13px;border:1px solid #334155;">
    <div id="voice-live-text" style="max-height:min(40vh, 220px);overflow-y:auto;white-space:pre-wrap;overflow-wrap:anywhere;line-height:1.5;font-weight:500;"><span id="voice-live-final"></span><span id="voice-live-interim" style="color:#94a3b8;">Listening… Speak into microphone</span></div>
    <div style="display:flex;align-items:center;gap:6px;">
      <span style="display:inline-block;width:10px;height:10px;background:#ef4444;border-radius:50%;box-shadow:0 0 8px #ef4444;animation:voicePulse 1.2s infinite;"></span>
      <span id="voice-live-count" style="flex:1;font-size:11px;color:#94a3b8;">Listening…</span>
      <button type="button" onclick="stopDirectVoiceInput(true)" style="background:#10b981;color:white;border:none;border-radius:14px;padding:4px 12px;font-size:11px;font-weight:700;cursor:pointer;line-height:1.2;display:inline-flex;align-items:center;gap:3px;" title="Insert transcribed text into editor">✓ Insert</button>
      <button type="button" onclick="sendVoiceToAiModal()" style="background:#7c3aed;color:white;border:none;border-radius:14px;padding:4px 10px;font-size:11px;font-weight:700;cursor:pointer;line-height:1.2;display:inline-flex;align-items:center;gap:3px;" title="Send spoken text to AI Generate">✨ AI</button>
      <button type="button" onclick="stopDirectVoiceInput(false)" style="background:#334155;color:#94a3b8;border:none;border-radius:14px;padding:4px 8px;font-size:11px;font-weight:600;cursor:pointer;line-height:1.2;" title="Cancel">✕</button>
    </div>
  </div>

  <script>
    /* ====== AI PROMPT & SPEECH RECOGNITION (GENERATE MODAL) ====== */
    let aiSpeechRec = null;
    let isAiListening = false;
    let aiPromptPreSpeech = '';
    let aiPromptAccumulated = '';

    function openAiPromptModal() {
      const modal = document.getElementById('ai-prompt-modal');
      const input = document.getElementById('ai-prompt-input');
      const errBanner = document.getElementById('ai-error-banner');
      if (errBanner) {
        errBanner.textContent = '';
        errBanner.style.display = 'none';
      }
      resetAiApiButton();
      if (modal) modal.classList.add('show');
      if (input) {
        setTimeout(function() { input.focus(); }, 120);
      }
    }

    function closeAiPromptModal() {
      stopAiPromptMic();
      const modal = document.getElementById('ai-prompt-modal');
      if (modal) modal.classList.remove('show');
    }

    function clearAiPromptInput() {
      const input = document.getElementById('ai-prompt-input');
      if (input) {
        input.value = '';
        input.focus();
      }
      updateAiModalState();
    }

    function updateAiModalState() {
      const errBanner = document.getElementById('ai-error-banner');
      if (errBanner && errBanner.style.display !== 'none') {
        errBanner.style.display = 'none';
      }
    }

    function toggleAiPromptMic() {
      if (isAiListening) {
        stopAiPromptMic();
      } else {
        startAiPromptMic();
      }
    }

    function startAiPromptMic() {
      const SpeechRec = window.SpeechRecognition || window.webkitSpeechRecognition;
      if (!SpeechRec) {
        alert('Speech recognition is not supported in this browser. Please use Chrome, Edge, or Safari.');
        return;
      }

      const input = document.getElementById('ai-prompt-input');
      aiPromptPreSpeech = (input ? input.value : '');
      if (aiPromptPreSpeech.length > 0 && !aiPromptPreSpeech.endsWith(' ') && !aiPromptPreSpeech.endsWith('\\n')) {
        aiPromptPreSpeech += ' ';
      }
      aiPromptAccumulated = '';

      try {
        aiSpeechRec = new SpeechRec();
        aiSpeechRec.continuous = true;
        aiSpeechRec.interimResults = true;
        const dirEl = document.getElementById('select-dir');
        aiSpeechRec.lang = (dirEl && dirEl.value === 'rtl') ? 'ar-SA' : 'en-US';

        const micBtn = document.getElementById('ai-prompt-mic-btn');
        if (micBtn) {
          micBtn.style.background = '#dc2626';
          micBtn.style.color = '#ffffff';
          micBtn.style.borderColor = '#b91c1c';
          micBtn.innerHTML = '⏹️';
        }
        isAiListening = true;

        const micStatus = document.getElementById('ai-mic-status');
        const micStatusText = document.getElementById('ai-mic-status-text');
        if (micStatus) micStatus.style.display = 'flex';
        if (micStatusText) micStatusText.textContent = 'Listening… speak now. Words will appear in the box.';

        aiSpeechRec.onresult = function(event) {
          let interim = '';
          for (let i = event.resultIndex; i < event.results.length; ++i) {
            if (event.results[i].isFinal) {
              aiPromptAccumulated += event.results[i][0].transcript + ' ';
            } else {
              interim += event.results[i][0].transcript;
            }
          }
          if (input) {
            input.value = aiPromptPreSpeech + aiPromptAccumulated + interim;
            input.scrollTop = input.scrollHeight;
          }
        };

        aiSpeechRec.onerror = function(event) {
          console.warn('AI speech error:', event.error);
          if (event.error === 'not-allowed') {
            alert('Microphone access was denied. Please allow microphone permission in your browser address bar.');
          }
          stopAiPromptMic();
        };

        aiSpeechRec.onend = function() {
          if (isAiListening) {
            stopAiPromptMic();
          }
        };

        aiSpeechRec.start();
      } catch (err) {
        console.error('Failed to start speech recognition:', err);
        stopAiPromptMic();
      }
    }

    function stopAiPromptMic() {
      isAiListening = false;
      if (aiSpeechRec) {
        try { aiSpeechRec.stop(); } catch(_) {}
        aiSpeechRec = null;
      }

      const micBtn = document.getElementById('ai-prompt-mic-btn');
      if (micBtn) {
        micBtn.style.background = '#f8fafc';
        micBtn.style.color = 'inherit';
        micBtn.style.borderColor = '#cbd5e1';
        micBtn.innerHTML = '🎤';
      }

      const micStatus = document.getElementById('ai-mic-status');
      if (micStatus) micStatus.style.display = 'none';

      const input = document.getElementById('ai-prompt-input');
      if (input) {
        input.value = input.value.trim();
        input.focus();
      }
    }

    function resetAiApiButton() {
      const btn = document.getElementById('btn-call-api');
      const spinner = document.getElementById('btn-call-api-spinner');
      const text = document.getElementById('btn-call-api-text');
      if (btn) btn.disabled = false;
      if (spinner) spinner.style.display = 'none';
      if (text) text.textContent = '✨ Generate';
    }

    function submitAiPromptToApi() {
      stopAiPromptMic();
      const input = document.getElementById('ai-prompt-input');
      const promptText = (input ? input.value : '').trim();

      if (!promptText) {
        const errBanner = document.getElementById('ai-error-banner');
        if (errBanner) {
          errBanner.textContent = 'Please type your instruction or click the mic to speak first.';
          errBanner.style.display = 'block';
        }
        if (input) input.focus();
        return;
      }

      const btn = document.getElementById('btn-call-api');
      const spinner = document.getElementById('btn-call-api-spinner');
      const text = document.getElementById('btn-call-api-text');
      if (btn) btn.disabled = true;
      if (spinner) spinner.style.display = 'inline-block';
      if (text) text.textContent = 'Calling API…';

      // Send the reviewed/edited prompt text to Flutter / backend API
      postToFlutter({ type: 'ai_generate_request', text: promptText });
    }

    // Compatibility alias
    function toggleVoiceInput() {
      openAiPromptModal();
    }

    /* ====== DIRECT VOICE-TO-TEXT INPUT (DICTATION) ====== */
    let directVoiceRec = null;
    let isDirectVoiceListening = false;
    let directVoiceFinalText = '';
    let directVoiceInterimText = '';
    let directVoiceRestarts = 0;

    /* Shows the whole transcript live (final text + greyed interim words), scrolled to the newest words */
    function renderVoiceLiveText() {
      const finalEl = document.getElementById('voice-live-final');
      const interimEl = document.getElementById('voice-live-interim');
      const box = document.getElementById('voice-live-text');
      const countEl = document.getElementById('voice-live-count');
      const finalText = directVoiceFinalText.trim();
      const interim = directVoiceInterimText.trim();
      if (finalEl) finalEl.textContent = finalText;
      if (interimEl) {
        interimEl.textContent = (finalText && interim ? ' ' : '') + interim;
        if (!finalText && !interim) interimEl.textContent = 'Listening… Speak into microphone';
      }
      if (countEl) {
        const words = (finalText + ' ' + interim).trim().split(/ +/).filter(Boolean).length;
        countEl.textContent = words ? 'Listening… ' + words + (words === 1 ? ' word' : ' words') : 'Listening…';
      }
      if (box) box.scrollTop = box.scrollHeight;
    }

    function toggleDirectVoiceInput() {
      if (isDirectVoiceListening) {
        stopDirectVoiceInput(true);
      } else {
        startDirectVoiceInput();
      }
    }
    window.toggleDirectVoiceInput = toggleDirectVoiceInput;

    function startDirectVoiceInput() {
      const SpeechRec = window.SpeechRecognition || window.webkitSpeechRecognition;
      if (!SpeechRec) {
        alert('Speech recognition is not supported in this browser. Please use Chrome, Edge, or Safari.');
        return;
      }

      if (isAiListening) stopAiPromptMic();

      directVoiceFinalText = '';
      directVoiceInterimText = '';
      directVoiceRestarts = 0;

      try {
        directVoiceRec = new SpeechRec();
        directVoiceRec.continuous = true;
        directVoiceRec.interimResults = true;
        const dirEl = document.getElementById('select-dir');
        directVoiceRec.lang = (dirEl && dirEl.value === 'rtl') ? 'ar-SA' : 'en-US';

        const btn = document.getElementById('btn-voice-to-text');
        const icon = document.getElementById('btn-voice-icon');
        const label = document.getElementById('btn-voice-label');
        if (btn) btn.classList.add('listening');
        if (icon) icon.textContent = '⏹️';
        if (label) label.textContent = 'Stop Voice';
        if (btn) btn.title = 'Stop dictation and insert the text';

        const fallbackBtn = document.getElementById('fallback-btn-voice');
        if (fallbackBtn) {
          fallbackBtn.style.color = '#dc2626';
          fallbackBtn.textContent = '⏹️ Stop';
        }

        const bar = document.getElementById('voice-live-bar');
        if (bar) bar.style.display = 'flex';
        renderVoiceLiveText();

        isDirectVoiceListening = true;

        directVoiceRec.onresult = function(event) {
          let interim = '';
          for (let i = event.resultIndex; i < event.results.length; ++i) {
            if (event.results[i].isFinal) {
              directVoiceFinalText += event.results[i][0].transcript + ' ';
            } else {
              interim += event.results[i][0].transcript;
            }
          }
          directVoiceInterimText = interim;
          directVoiceRestarts = 0;
          renderVoiceLiveText();
        };

        directVoiceRec.onerror = function(event) {
          console.warn('Direct voice error:', event.error);
          if (event.error === 'not-allowed' || event.error === 'service-not-allowed') {
            alert('Microphone access was denied. Please allow microphone permission in your browser address bar.');
            stopDirectVoiceInput(false);
          }
          /* Other errors (no-speech, network, ...) end the session; onend restarts it and keeps the text */
        };

        directVoiceRec.onend = function() {
          if (!isDirectVoiceListening) return;
          /* Browsers end a "continuous" session after silence or ~1 min; keep dictating until the user stops */
          if (directVoiceInterimText) {
            directVoiceFinalText += directVoiceInterimText + ' ';
            directVoiceInterimText = '';
          }
          if (directVoiceRestarts < 5) {
            directVoiceRestarts++;
            try { directVoiceRec.start(); return; } catch (_) {}
          }
          stopDirectVoiceInput(true);
        };

        directVoiceRec.start();
        showToastMsg('🎙️ Listening… Speak into microphone');
      } catch (err) {
        console.error('Failed to start direct voice recognition:', err);
        stopDirectVoiceInput(false);
      }
    }
    window.startDirectVoiceInput = startDirectVoiceInput;

    function stopDirectVoiceInput(insert) {
      if (insert === undefined) insert = true;
      const wasListening = isDirectVoiceListening;
      isDirectVoiceListening = false;

      if (directVoiceRec) {
        try { directVoiceRec.stop(); } catch(_) {}
        directVoiceRec = null;
      }

      const btn = document.getElementById('btn-voice-to-text');
      const icon = document.getElementById('btn-voice-icon');
      const label = document.getElementById('btn-voice-label');
      if (btn) btn.classList.remove('listening');
      if (icon) icon.textContent = '🎙️';
      if (label) label.textContent = 'Voice to Text';
      if (btn) btn.title = 'Voice to Text — Dictate speech directly into document';

      const fallbackBtn = document.getElementById('fallback-btn-voice');
      if (fallbackBtn) {
        fallbackBtn.style.color = '#dc2626';
        fallbackBtn.textContent = '🎙️ Voice';
      }

      const bar = document.getElementById('voice-live-bar');
      if (bar) bar.style.display = 'none';

      if (insert && wasListening) {
        const fullText = (directVoiceFinalText + ' ' + directVoiceInterimText).trim();
        if (fullText) {
          insertDirectVoiceText(fullText);
        }
      }
    }
    window.stopDirectVoiceInput = stopDirectVoiceInput;

    function stopVoiceInput() {
      stopDirectVoiceInput(true);
    }
    window.stopVoiceInput = stopVoiceInput;

    function insertDirectVoiceText(text) {
      if (!text) return;
      if (editorInstance) {
        try {
          editorInstance.model.change(writer => {
            const sel = editorInstance.model.document.selection;
            writer.insertText(text + ' ', sel.getFirstPosition());
          });
          editorInstance.editing.view.focus();
          postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
          showToastMsg('✓ Voice inserted: "' + (text.length > 28 ? text.slice(0, 28) + '…' : text) + '"');
        } catch (e) {
          console.warn('insertDirectVoiceText error:', e);
          insertSlashHtml('<span>' + escapeHtml(text) + ' </span>');
        }
      } else if (isFallback) {
        const fc = document.getElementById('fallback-content');
        if (fc) {
          fc.focus();
          document.execCommand('insertText', false, text + ' ');
          updateFallbackStats();
          postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
          showToastMsg('✓ Voice inserted');
        }
      }
    }
    window.insertDirectVoiceText = insertDirectVoiceText;

    function sendVoiceToAiModal() {
      const fullText = (directVoiceFinalText + ' ' + directVoiceInterimText).trim();
      stopDirectVoiceInput(false);
      openAiPromptModal();
      const input = document.getElementById('ai-prompt-input');
      if (input && fullText) {
        input.value = fullText;
        updateAiModalState();
      }
    }
    window.sendVoiceToAiModal = sendVoiceToAiModal;

    function toggleFullscreen() {
      const container = document.getElementById('app-container');
      const btn = document.getElementById('btn-fullscreen');
      const isFull = container.classList.toggle('fullscreen-mode');
      if (isFull) {
        try {
          if (container.requestFullscreen) {
            container.requestFullscreen().catch(function() {});
          } else if (container.webkitRequestFullscreen) {
            container.webkitRequestFullscreen();
          }
        } catch(e) {}
        if (btn) {
          btn.innerHTML = '✕ Exit';
          btn.style.background = '#fee2e2';
          btn.style.color = '#b91c1c';
          btn.style.borderColor = '#fca5a5';
        }
      } else {
        try {
          if (document.fullscreenElement && document.exitFullscreen) {
            document.exitFullscreen().catch(function() {});
          } else if (document.webkitFullscreenElement && document.webkitExitFullscreen) {
            document.webkitExitFullscreen();
          }
        } catch(e) {}
        if (btn) {
          btn.innerHTML = '⛶ Fullscreen';
          btn.style.background = '#eff6ff';
          btn.style.color = '#1d4ed8';
          btn.style.borderColor = '#bfdbfe';
        }
      }
    }
    document.addEventListener('fullscreenchange', function() {
      const container = document.getElementById('app-container');
      const btn = document.getElementById('btn-fullscreen');
      const isFull = !!document.fullscreenElement;
      if (container && !isFull) {
        container.classList.remove('fullscreen-mode');
      }
      if (btn) {
        btn.innerHTML = isFull ? '✕ Exit' : '⛶ Fullscreen';
        btn.style.background = isFull ? '#fee2e2' : '#eff6ff';
        btn.style.color = isFull ? '#b91c1c' : '#1d4ed8';
        btn.style.borderColor = isFull ? '#fca5a5' : '#bfdbfe';
      }
    });

    /* ====== GLOBALS ====== */
    const EDITOR_ID = $editorIdJson;
    let initialContent = $initialJson;
    const placeholderText = $placeholderJson;
    let currentTextDir = '$initialDir';
    let editorInstance = null;
    let isFallback = false;
    let scriptLoaded = false;
    let trackChangesEnabled = false;
    let showBlocksEnabled = false;
    let isReadonly = false;
    let formatPainterActive = false;
    let formatPainterStyle = null;
    let revisions = [];
    let comments = [];
    let trackedChanges = [];
    let currentPanel = null;
    window._mediaStyleRegistry = {};

    function postToFlutter(msg) {
      msg.editorId = EDITOR_ID;
      window.parent.postMessage(JSON.stringify(msg), '*');
    }

    /* ====== ASYNC SCRIPT LOADER ====== */
    function loadExternalScript(src, timeoutMs = 1500) {
      return new Promise((resolve, reject) => {
        const s = document.createElement('script');
        s.src = src;
        s.async = true;
        let done = false;
        const timer = setTimeout(() => {
          if (!done) {
            done = true;
            try { s.remove(); } catch(e) {}
            reject(new Error('Timeout loading ' + src));
          }
        }, timeoutMs);
        s.onload = () => {
          if (!done) {
            done = true;
            clearTimeout(timer);
            resolve();
          }
        };
        s.onerror = (e) => {
          if (!done) {
            done = true;
            clearTimeout(timer);
            try { s.remove(); } catch(err) {}
            reject(new Error('Failed to load ' + src));
          }
        };
        document.head.appendChild(s);
      });
    }

    /* ====== CKEDITOR 5 INIT ====== */
    function checkAndInitCKEditor() {
      // 1. If CKEditor is already loaded
      if (typeof CKEDITOR !== 'undefined' && CKEDITOR.ClassicEditor) {
        scriptLoaded = true;
        initCKEditor();
        return;
      }

      // Show manual fallback button after 600ms if network is slow
      setTimeout(() => {
        const btn = document.getElementById('btn-force-fallback');
        if (btn && !editorInstance && !isFallback) {
          btn.style.display = 'inline-block';
        }
      }, 600);

      // Load CKEditor Super Build dynamically with strict 1500ms timeout
      loadExternalScript('https://cdn.ckeditor.com/ckeditor5/41.4.2/super-build/ckeditor.js', 1500)
        .then(() => {
          if (typeof CKEDITOR !== 'undefined' && CKEDITOR.ClassicEditor) {
            scriptLoaded = true;
            initCKEditor();
          } else {
            console.warn('CKEditor object missing after script load, switching to fallback');
            initFallback();
          }
        })
        .catch(err => {
          console.warn('CKEditor CDN load failed or timed out (1.5s), switching to fallback:', err);
          initFallback();
        });

      // Background load KaTeX for math equations (non-blocking)
      loadExternalScript('https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js', 6000)
        .catch(() => {});
    }

    // Call immediately without waiting for DOMContentLoaded
    checkAndInitCKEditor();

    function initCKEditor() {
      if (editorInstance || isFallback) return;
      if (typeof CKEDITOR === 'undefined' || !CKEDITOR.ClassicEditor) {
        initFallback();
        return;
      }
      const editorEl = document.querySelector('#editor');
      if (!editorEl) {
        initFallback();
        return;
      }
      editorEl.style.display = 'block';

      try {
        const createPromise = CKEDITOR.ClassicEditor
          .create(editorEl, {
          toolbar: {
            items: [
              'undo', 'redo', '|',
              'heading', '|',
              'fontSize', 'fontFamily', 'fontColor', 'fontBackgroundColor', '|',
              'bold', 'italic', 'underline', 'strikethrough',
              'subscript', 'superscript', 'code', 'removeFormat', '|',
              'highlight', '|',
              'alignment', '|',
              'bulletedList', 'numberedList', 'todoList',
              'outdent', 'indent', '|',
              'link', 'insertImage', 'insertTable', 'mediaEmbed',
              'codeBlock', 'blockQuote', 'horizontalLine',
              'htmlEmbed', '|',
              'specialCharacters', 'pageBreak', '|',
              'findAndReplace', 'selectAll', '|',
              'showBlocks'
            ],
            shouldNotGroupWhenFull: true
          },
          removePlugins: [
            'CKBox', 'CKBoxImageEdit', 'CKBoxUtils', 'CKFinder', 'EasyImage',
            'RealTimeCollaborativeComments',
            'RealTimeCollaborativeTrackChanges',
            'RealTimeCollaborativeRevisionHistory',
            'PresenceList',
            'Comments', 'CommentsOnly', 'CommentsArchive',
            'TrackChanges', 'TrackChangesData',
            'RevisionHistory',
            'Pagination', 'WProofreader', 'MathType',
            'SlashCommand', 'Template', 'DocumentOutline', 'FormatPainter',
            'TableOfContents', 'PasteFromOfficeEnhanced', 'CaseChange',
            'AIAssistant', 'ExportPdf', 'ExportWord', 'ImportWord',
            'MultiLevelList',
            'CloudServices'
          ],
          fontSize: {
            options: [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 24, 26, 28, 30, 32, 36, 40, 48, 60, 72],
            supportAllValues: true
          },
          fontFamily: {
            options: [
              'default',
              'Calibri, Candara, Segoe, "Segoe UI", Optima, Arial, sans-serif',
              'Cambria, Cochin, Georgia, Times, "Times New Roman", serif',
              'Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
              'Roboto, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
              'Open Sans, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
              'Lato, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
              'Montserrat, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
              'Poppins, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
              'Segoe UI, Tahoma, Geneva, Verdana, sans-serif',
              'Arial, Helvetica, sans-serif',
              'Helvetica, Arial, sans-serif',
              'Times New Roman, Times, Baskerville, Georgia, serif',
              'Georgia, serif',
              'Garamond, Baskerville, Caslon, serif',
              'Palatino, "Palatino Linotype", "Book Antiqua", Georgia, serif',
              'Century Gothic, "Apple Gothic", sans-serif',
              'Trebuchet MS, "Lucida Grande", "Lucida Sans Unicode", sans-serif',
              'Verdana, Geneva, sans-serif',
              'Tahoma, Geneva, sans-serif',
              'Courier New, Courier, monospace',
              'Consolas, Monaco, monospace',
              'Fira Code, monospace',
              'Impact, Haettenschweiler, "Franklin Gothic Bold", Charcoal, sans-serif',
              'Comic Sans MS, "Comic Sans", cursive'
            ],
            supportAllValues: true
          },
          heading: {
            options: [
              { model: 'paragraph', title: 'Paragraph', class: 'ck-heading_paragraph' },
              { model: 'heading1', view: 'h1', title: 'Heading 1', class: 'ck-heading_heading1' },
              { model: 'heading2', view: 'h2', title: 'Heading 2', class: 'ck-heading_heading2' },
              { model: 'heading3', view: 'h3', title: 'Heading 3', class: 'ck-heading_heading3' },
              { model: 'heading4', view: 'h4', title: 'Heading 4', class: 'ck-heading_heading4' },
              { model: 'heading5', view: 'h5', title: 'Heading 5', class: 'ck-heading_heading5' },
              { model: 'heading6', view: 'h6', title: 'Heading 6', class: 'ck-heading_heading6' }
            ]
          },
          list: {
            properties: {
              styles: true,
              startIndex: true,
              reversed: true
            }
          },
          mention: {
            feeds: [
              {
                marker: '@',
                feed: [
                  '@alex', '@sarah', '@john', '@emma', '@doctor', '@admin', '@analyst', '@clinical_lead'
                ],
                minimumCharacters: 1
              },
              {
                marker: '#',
                feed: [
                  '#lims', '#urgent', '#review', '#approved', '#pending', '#clinical', '#protocol', '#sample'
                ],
                minimumCharacters: 1
              },
              {
                marker: '\$',
                feed: getTableCellMentionsFeed,
                minimumCharacters: 0,
                itemRenderer: renderTableCellMentionItem
              }
            ]
          },
          highlight: {
            options: [
              { model: 'yellowMarker', class: 'marker-yellow', title: 'Yellow Marker', color: '#fdfd77', type: 'marker' },
              { model: 'greenMarker', class: 'marker-green', title: 'Green Marker', color: '#63f963', type: 'marker' },
              { model: 'pinkMarker', class: 'marker-pink', title: 'Pink Marker', color: '#fc7999', type: 'marker' },
              { model: 'blueMarker', class: 'marker-blue', title: 'Blue Marker', color: '#72ccfd', type: 'marker' },
              { model: 'redPen', class: 'pen-red', title: 'Red Pen', color: '#e91313', type: 'pen' },
              { model: 'greenPen', class: 'pen-green', title: 'Green Pen', color: '#118800', type: 'pen' }
            ]
          },
          table: {
            contentToolbar: [
              'tableColumn', 'tableRow', 'mergeTableCells',
              'tableProperties', 'tableCellProperties', 'toggleTableCaption'
            ],
            tableProperties: {
              borderColors: [
                { color: '#000000', label: 'Black' }, { color: '#4b5563', label: 'Gray' },
                { color: '#dc2626', label: 'Red' }, { color: '#2563eb', label: 'Blue' },
                { color: '#16a34a', label: 'Green' }, { color: '#ca8a04', label: 'Yellow' },
                { color: '#9333ea', label: 'Purple' }, { color: '#ea580c', label: 'Orange' }
              ],
              backgroundColors: [
                { color: '#ffffff', label: 'White' }, { color: '#f8fafc', label: 'Light Gray' },
                { color: '#fef2f2', label: 'Light Red' }, { color: '#eff6ff', label: 'Light Blue' },
                { color: '#f0fdf4', label: 'Light Green' }, { color: '#fefce8', label: 'Light Yellow' },
                { color: '#faf5ff', label: 'Light Purple' }, { color: '#fff7ed', label: 'Light Orange' },
                { color: '#1e293b', label: 'Dark Blue' }, { color: '#0f172a', label: 'Dark' }
              ],
              defaultProperties: {
                borderStyle: 'solid',
                borderWidth: '1px'
              }
            },
            tableCellProperties: {
              borderColors: [
                { color: '#000000', label: 'Black' }, { color: '#4b5563', label: 'Gray' },
                { color: '#dc2626', label: 'Red' }, { color: '#2563eb', label: 'Blue' },
                { color: '#16a34a', label: 'Green' }, { color: '#ca8a04', label: 'Yellow' },
                { color: '#9333ea', label: 'Purple' }, { color: '#ea580c', label: 'Orange' }
              ],
              backgroundColors: [
                { color: '#ffffff', label: 'White' }, { color: '#f8fafc', label: 'Light Gray' },
                { color: '#fef2f2', label: 'Light Red' }, { color: '#eff6ff', label: 'Light Blue' },
                { color: '#f0fdf4', label: 'Light Green' }, { color: '#fefce8', label: 'Light Yellow' },
                { color: '#faf5ff', label: 'Light Purple' }, { color: '#fff7ed', label: 'Light Orange' },
                { color: '#1e293b', label: 'Dark Blue' }, { color: '#0f172a', label: 'Dark' }
              ],
              defaultProperties: {
                horizontalAlignment: 'left',
                verticalAlignment: 'middle'
              }
            }
          },
          image: {
            toolbar: [
              'imageTextAlternative', 'toggleImageCaption', '|',
              'imageStyle:inline', 'imageStyle:block', 'imageStyle:side', '|',
              'resizeImage', '|',
              'linkImage'
            ],
            insert: {
              type: 'auto',
              integrations: ['upload', 'url']
            },
            upload: { types: ['jpeg', 'png', 'gif', 'bmp', 'webp', 'tiff', 'svg+xml'] },
            resizeUnit: 'px',
            resizeOptions: [
              { name: 'resizeImage:original', value: null, label: 'Original' },
              { name: 'resizeImage:25', value: '25', label: '25%' },
              { name: 'resizeImage:50', value: '50', label: '50%' },
              { name: 'resizeImage:75', value: '75', label: '75%' }
            ]
          },
          link: {
            addTargetToExternalLinks: true,
            defaultProtocol: 'https://',
            decorators: {
              openInNewTab: {
                mode: 'manual',
                label: 'Open in a new tab',
                attributes: { target: '_blank', rel: 'noopener noreferrer' }
              },
              toggleDownloadable: {
                mode: 'manual',
                label: 'Downloadable',
                attributes: { download: 'file' }
              }
            }
          },
          mediaEmbed: { previewsInData: true },
          codeBlock: {
            languages: [
              { language: 'plaintext', label: 'Plain text' },
              { language: 'c', label: 'C' },
              { language: 'cs', label: 'C#' },
              { language: 'cpp', label: 'C++' },
              { language: 'css', label: 'CSS' },
              { language: 'diff', label: 'Diff' },
              { language: 'html', label: 'HTML' },
              { language: 'java', label: 'Java' },
              { language: 'javascript', label: 'JavaScript' },
              { language: 'json', label: 'JSON' },
              { language: 'php', label: 'PHP' },
              { language: 'python', label: 'Python' },
              { language: 'ruby', label: 'Ruby' },
              { language: 'typescript', label: 'TypeScript' },
              { language: 'xml', label: 'XML' },
              { language: 'dart', label: 'Dart' },
              { language: 'sql', label: 'SQL' },
              { language: 'bash', label: 'Bash' },
              { language: 'yaml', label: 'YAML' },
              { language: 'go', label: 'Go' },
              { language: 'rust', label: 'Rust' },
              { language: 'kotlin', label: 'Kotlin' },
              { language: 'swift', label: 'Swift' }
            ]
          },
          htmlSupport: {
            allow: [
              { name: /.*/, attributes: true, classes: true, styles: true }
            ]
          },
          wordCount: {
            onUpdate: (stats) => {
              document.getElementById('word-count').textContent = 'Words: ' + stats.words;
              document.getElementById('char-count').textContent = 'Characters: ' + stats.characters;
            }
          },
          placeholder: placeholderText || 'Start typing...',
          language: 'en'
        });

        const timeoutPromise = new Promise((_, reject) => {
          setTimeout(() => reject(new Error('CKEditor creation timed out after 2500ms')), 2500);
        });

        Promise.race([createPromise, timeoutPromise])
        .then(editor => {
          if (isFallback) {
            try { editor.destroy(); } catch (e) {}
            return;
          }
          editorInstance = editor;
          window.editorInstance = editor;

          // Clear any loading indicator
          const loadingEl = document.getElementById('editor-loading');
          if (loadingEl) loadingEl.style.display = 'none';

          /* Register dataFormula & dataFormulaVal attributes on tableCell and dir attribute on block */
          try {
            editor.model.schema.extend('tableCell', { allowAttributes: ['dataFormula', 'dataFormulaVal'] });
            editor.conversion.attributeToAttribute({
              model: 'dataFormula',
              view: 'data-formula'
            });
            editor.conversion.attributeToAttribute({
              model: 'dataFormulaVal',
              view: 'data-formula-val'
            });
            editor.model.schema.extend('\$block', { allowAttributes: ['dir'] });
            try {
              editor.model.schema.setAttributeProperties('dir', { copyOnEnter: true });
            } catch (propErr) {}
            editor.conversion.attributeToAttribute({
              model: 'dir',
              view: 'dir'
            });

            /* Register tableCellRef attribute on \$text for permanent, live table cell reference pills */
            editor.model.schema.extend('\$text', { allowAttributes: ['tableCellRef'] });
            try {
              editor.model.schema.setAttributeProperties('tableCellRef', { isFormatting: true, copyOnEnter: false });
            } catch (tcrPropErr) {}

            editor.conversion.for('downcast').attributeToElement({
              model: 'tableCellRef',
              view: (val, { writer }) => {
                let coord = 'A1';
                let tIdx = 0;
                if (typeof val === 'string') {
                  coord = val.toUpperCase();
                } else if (val && typeof val === 'object') {
                  coord = (val.coord || 'A1').toUpperCase();
                  tIdx = val.tableIdx !== undefined ? val.tableIdx : 0;
                }
                const token = '\$' + (tIdx > 0 ? ('T' + (tIdx + 1) + ':' + coord) : coord);
                return writer.createAttributeElement('span', {
                  class: 'table-cell-ref mention',
                  'data-cell-coord': coord,
                  'data-table-idx': String(tIdx),
                  'data-mention': token,
                  title: 'Table cell ' + coord + ' (Live Link)'
                }, { priority: 25 });
              }
            });

            editor.conversion.for('upcast').elementToAttribute({
              view: {
                name: 'span',
                classes: 'table-cell-ref'
              },
              model: {
                key: 'tableCellRef',
                value: viewElement => {
                  let coord = viewElement.getAttribute('data-cell-coord');
                  let tIdx = parseInt(viewElement.getAttribute('data-table-idx'), 10) || 0;
                  if (!coord) {
                    let m = viewElement.getAttribute('data-mention') || '';
                    if (m.indexOf('\$') === 0) m = m.substring(1);
                    if (m.toUpperCase().indexOf('T') === 0 && m.indexOf(':') !== -1) {
                      const p = m.split(':');
                      tIdx = parseInt(p[0].substring(1), 10) - 1 || 0;
                      m = p[1];
                    }
                    coord = m.toUpperCase();
                  }
                  return { coord: coord || 'A1', tableIdx: tIdx };
                }
              }
            });

            editor.conversion.for('upcast').elementToAttribute({
              view: {
                name: 'span',
                attributes: {
                  'data-cell-coord': true
                }
              },
              model: {
                key: 'tableCellRef',
                value: viewElement => {
                  const coord = (viewElement.getAttribute('data-cell-coord') || 'A1').toUpperCase();
                  const tIdx = parseInt(viewElement.getAttribute('data-table-idx'), 10) || 0;
                  return { coord: coord, tableIdx: tIdx };
                }
              }
            });

            editor.conversion.for('upcast').elementToAttribute({
              view: {
                name: 'span',
                attributes: {
                  'data-mention': /^\\\$[A-Za-z0-9:]+\$/
                }
              },
              model: {
                key: 'tableCellRef',
                value: viewElement => {
                  let m = viewElement.getAttribute('data-mention') || '';
                  let tIdx = parseInt(viewElement.getAttribute('data-table-idx'), 10) || 0;
                  let coord = viewElement.getAttribute('data-cell-coord');
                  if (!coord) {
                    if (m.indexOf('\$') === 0) m = m.substring(1);
                    if (m.toUpperCase().indexOf('T') === 0 && m.indexOf(':') !== -1) {
                      const p = m.split(':');
                      tIdx = parseInt(p[0].substring(1), 10) - 1 || 0;
                      m = p[1];
                    }
                    coord = m.toUpperCase();
                  }
                  return { coord: coord || 'A1', tableIdx: tIdx };
                }
              }
            });

            /* Register inlineFormula attribute on \$text for live formula calculations in text outside tables */
            editor.model.schema.extend('\$text', { allowAttributes: ['inlineFormula'] });
            try {
              editor.model.schema.setAttributeProperties('inlineFormula', { isFormatting: true, copyOnEnter: false });
            } catch (infPropErr) {}

            editor.conversion.for('downcast').attributeToElement({
              model: 'inlineFormula',
              view: (val, { writer }) => {
                let formula = '=';
                let tIdx = 0;
                if (typeof val === 'string') {
                  formula = val;
                } else if (val && typeof val === 'object') {
                  formula = val.formula || '=';
                  tIdx = val.tableIdx !== undefined ? val.tableIdx : 0;
                }
                return writer.createAttributeElement('span', {
                  class: 'inline-formula-pill',
                  'data-formula': formula,
                  'data-table-idx': String(tIdx),
                  title: 'Formula: ' + formula + ' (Live Calculation - Click to edit)'
                }, { priority: 25 });
              }
            });

            editor.conversion.for('upcast').elementToAttribute({
              view: {
                name: 'span',
                classes: 'inline-formula-pill'
              },
              model: {
                key: 'inlineFormula',
                value: viewElement => {
                  const formula = viewElement.getAttribute('data-formula') || viewElement.getAttribute('data-cell-formula') || '=';
                  const tIdx = parseInt(viewElement.getAttribute('data-table-idx'), 10) || 0;
                  return { formula: formula, tableIdx: tIdx };
                }
              }
            });

            editor.conversion.for('upcast').elementToAttribute({
              view: {
                name: 'span',
                attributes: {
                  'data-formula': true
                }
              },
              model: {
                key: 'inlineFormula',
                value: viewElement => {
                  if (viewElement.parent && (viewElement.parent.name === 'tableCell' || viewElement.parent.name === 'table')) {
                    return null;
                  }
                  const formula = viewElement.getAttribute('data-formula') || '=';
                  const tIdx = parseInt(viewElement.getAttribute('data-table-idx'), 10) || 0;
                  return { formula: formula, tableIdx: tIdx };
                }
              }
            });

            // Post-fixer: Automatically promote any \$ mention to a permanent tableCellRef attribute
            editor.model.document.registerPostFixer(writer => {
              let changed = false;
              try {
                const changes = editor.model.document.differ.getChanges();
                for (const entry of changes) {
                  if (entry.type === 'insert' || entry.type === 'attribute') {
                    const range = entry.range || (entry.position ? writer.createRange(entry.position, entry.position.getShiftedBy(entry.length || 1)) : null);
                    if (!range) continue;
                    for (const item of range.getItems()) {
                      if (item.is && item.is('\$text')) {
                        const m = item.getAttribute('mention');
                        if (m && (m.coord || (m.id && m.id.indexOf('\$') === 0))) {
                          let coord = m.coord;
                          let tIdx = m.tableIdx || 0;
                          if (!coord && m.id) {
                            let cleanId = m.id.indexOf('\$') === 0 ? m.id.substring(1) : m.id;
                            if (cleanId.toUpperCase().indexOf('T') === 0 && cleanId.indexOf(':') !== -1) {
                              const parts = cleanId.split(':');
                              tIdx = parseInt(parts[0].substring(1), 10) - 1 || 0;
                              cleanId = parts[1];
                            }
                            coord = cleanId.toUpperCase();
                          }
                          if (coord) {
                            const curRef = item.getAttribute('tableCellRef');
                            if (!curRef || curRef.coord !== coord || curRef.tableIdx !== tIdx) {
                              writer.setAttribute('tableCellRef', { coord: coord, tableIdx: tIdx }, item);
                              changed = true;
                            }
                            // Strip volatile mention attribute so CKEditor Mention post-fixer never removes the formatting
                            if (item.hasAttribute('mention')) {
                              writer.removeAttribute('mention', item);
                              changed = true;
                            }
                          }
                        }
                      }
                    }
                  }
                }
              } catch (pfErr) {}
              return changed;
            });
          } catch (e) {
            console.warn('schema registration error:', e);
          }

          try {
            if (initialContent) {
              const cleanInitial = sanitizeTableHtml(initialContent);
              const detectedDir = detectHtmlDirection(cleanInitial);
              currentTextDir = detectedDir;
              const sel = document.getElementById('select-dir');
              if (sel) sel.value = detectedDir;

              extractAndSeedFormulasFromHtml(cleanInitial);
              extractAndSeedMediaStylesFromHtml(cleanInitial);
              editor.setData(cleanInitial);
              restoreTodoCheckedState(editor, cleanInitial);
              setTimeout(() => {
                changeLanguage(detectedDir, false);
                scanAndRegisterTableFormulas();
                evaluateAllTableFormulas(false);
                reapplyAllMediaStyles();
              }, 100);
              setTimeout(() => {
                scanAndRegisterTableFormulas();
                evaluateAllTableFormulas(false);
                reapplyAllMediaStyles();
              }, 350);
              setTimeout(() => {
                scanAndRegisterTableFormulas();
                evaluateAllTableFormulas(false);
                reapplyAllMediaStyles();
              }, 700);
            } else if (currentTextDir === 'rtl') {
              changeLanguage('rtl', false);
            }
          } catch (e) {
            console.warn('initialContent setup error:', e);
          }

          /* Set up Base64 image upload adapter */
          editor.plugins.get('FileRepository').createUploadAdapter = (loader) => {
            return new Base64UploadAdapter(loader);
          };

          /* Re-apply media styles on CKEditor view render */
          try {
            if (editor.editing && editor.editing.view && editor.editing.view.document) {
              editor.editing.view.document.on('render', () => {
                reapplyAllMediaStyles();
              });
            }
          } catch(e) {}

          /* Content change listener - always use getEditorData() to preserve table formulas & media sizes */
          editor.model.document.on('change:data', (evt, batch) => {
            pruneDeadTableFormulas();
            reapplyAllMediaStyles();
            const data = getEditorData();
            postToFlutter({ type: 'ckeditor_change', html: data });
            updateParaCount();
            updatePageIndicator();
            if (trackChangesEnabled) recordChange();
            scheduleOutlineRefresh();
            // Restoring a revision or syncing formula results must not create new revisions
            if (!isRestoringRevision && !window._isUpdatingFormula) {
              markRevisionDirty();
              autoSaveRevision();
            }
            // Only recalculate formulas if this is a real user edit batch, not an internal non-undoable formula sync
            if (!window._isUpdatingFormula && (!batch || batch.isUndoable !== false)) {
              scheduleLiveFormulaRecalc();
            }
          });

          /* Attach live input/keyup/keydown listeners on editable DOM */
          try {
            if (editor.ui && editor.ui.view && editor.ui.view.editable && editor.ui.view.editable.element) {
              const el = editor.ui.view.editable.element;
              el.addEventListener('input', scheduleLiveFormulaRecalc);
              el.addEventListener('keyup', scheduleLiveFormulaRecalc);
              el.addEventListener('keydown', function(e) {
                // Also recalc after arrow keys (user navigated to a different cell)
                if (['ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Delete','Backspace'].includes(e.key)) {
                  scheduleLiveFormulaRecalc();
                }
              });
              // Attach media listeners safely without mutating CKEditor's widget DOM
              attachMediaListeners();

              /* Universal Paste Sanitizer & Style Normalizer */
              editor.editing.view.document.on('clipboardInput', (evt, data) => {
                const dataTransfer = data.dataTransfer;
                const rawHtml = dataTransfer.getData('text/html');
                if (rawHtml) {
                  try {
                    const cleanHtml = sanitizePastedHtml(rawHtml);
                    if (cleanHtml && cleanHtml.trim()) {
                      const viewFragment = editor.data.processor.toView(cleanHtml);
                      const modelFragment = editor.data.toModel(viewFragment);
                      editor.model.insertContent(modelFragment);
                      evt.stop();
                      setTimeout(() => {
                        attachMediaListeners();
                        attachMediaDragHandles();
                        scheduleLiveFormulaRecalc();
                      }, 120);
                    }
                  } catch(err) {
                    console.warn('Paste sanitization error, falling back to default:', err);
                  }
                }
              });

              // Initial media setup
              setTimeout(() => {
                attachMediaListeners();
                attachMediaDragHandles();
              }, 200);
            }
          } catch(e) {}

          /* Initial formula check & 100% automatic calculation */
          setTimeout(() => { autoUpdateTableFormulasDOM(); }, 150);
          setTimeout(() => { autoUpdateTableFormulasDOM(); }, 400);
          setTimeout(() => { autoUpdateTableFormulasDOM(); }, 800);

          /* Track paragraph count */
          updateParaCount();
          updatePageIndicator();

          try { installBlockNavigation(editor); } catch (e) { console.warn('Block navigation setup failed:', e); }
          const showBlocksCmd = editor.commands.get('showBlocks');
          if (showBlocksCmd) showBlocksCmd.on('change:value', updateShowBlocksButton);
          updateShowBlocksButton();

          /* Initial revision */
          saveRevision('Initial version');

          postToFlutter({ type: 'ckeditor_ready' });
        })
        .catch(err => {
          console.warn('CKEditor init failed, falling back:', err);
          editorInstance = null;
          initFallback();
        });
      } catch (syncErr) {
        console.warn('CKEditor synchronous init failed, falling back:', syncErr);
        editorInstance = null;
        initFallback();
      }
    }

    /* Base64 Upload Adapter for images */
    class Base64UploadAdapter {
      constructor(loader) { this.loader = loader; }
      upload() {
        return this.loader.file.then(file => new Promise((resolve, reject) => {
          const reader = new FileReader();
          reader.onload = () => resolve({ default: reader.result });
          reader.onerror = (err) => reject(err);
          reader.readAsDataURL(file);
        }));
      }
      abort() {}
    }

    /* ====== FALLBACK ====== */
    function initFallback() {
      if (isFallback) return;
      if (editorInstance) return;
      isFallback = true;
      const loadingEl = document.getElementById('editor-loading');
      if (loadingEl) loadingEl.style.display = 'none';
      const editorEl = document.getElementById('editor');
      if (editorEl) editorEl.style.display = 'none';
      const container = document.getElementById('fallback-container');
      if (container) container.style.display = 'flex';
      const content = document.getElementById('fallback-content');
      if (content) {
        if (initialContent) {
          try {
            content.innerHTML = sanitizeTableHtml(initialContent);
          } catch (e) {
            content.innerHTML = initialContent;
          }
        }
        if (currentTextDir === 'rtl' || detectHtmlDirection(initialContent) === 'rtl') {
          changeLanguage('rtl', false);
        }
        content.addEventListener('input', () => {
          updateFallbackStats();
          postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
        });
        updateFallbackStats();
      }
      postToFlutter({ type: 'ckeditor_ready' });
    }

    function updateFallbackStats() {
      const content = document.getElementById('fallback-content');
      if (!content) return;
      scheduleOutlineRefresh();
      const text = content.innerText || content.textContent || '';
      const words = text.trim() ? text.trim().split(/\\s+/).length : 0;
      const chars = text.length;
      const paras = content.querySelectorAll('p, h1, h2, h3, h4, h5, h6, div, li').length || (words > 0 ? 1 : 0);
      const wc = document.getElementById('word-count');
      if (wc) wc.textContent = 'Words: ' + words;
      const cc = document.getElementById('char-count');
      if (cc) cc.textContent = 'Characters: ' + chars;
      const pc = document.getElementById('para-count');
      if (pc) pc.textContent = 'Paragraphs: ' + paras;
    }

    function formatDoc(cmd, value = null) {
      document.execCommand(cmd, false, value);
      const content = document.getElementById('fallback-content');
      if (content) {
        updateFallbackStats();
        postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
      }
    }

    function insertFallbackTable() {
      const html = '<table border="1" style="border-collapse:collapse;width:100%;margin:10px 0;">' +
        '<tr><th style="padding:8px;background:#e2e8f0;">Header 1</th><th style="padding:8px;background:#e2e8f0;">Header 2</th></tr>' +
        '<tr><td style="padding:8px;">Cell 1</td><td style="padding:8px;">Cell 2</td></tr></table><p>&nbsp;</p>';
      document.execCommand('insertHTML', false, html);
      updateFallbackStats();
      postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
    }

    function insertFallbackLink() {
      const url = prompt('Enter URL:', 'https://');
      if (url) formatDoc('createLink', url);
    }

    function insertFallbackHorizontalRule() {
      formatDoc('insertHorizontalRule');
    }

    /* ====== EXPORT TO PDF ====== */
    function exportToPDF() {
      // Trigger native browser print dialog with full multi-page vector layout and Save as PDF
      window.print();
    }

    /* ====== EXPORT TO WORD (REAL .DOCX) ====== */
    function generateDocxZipBlob(files) {
      const crcTable = new Uint32Array(256);
      for (let i = 0; i < 256; i++) {
        let c = i;
        for (let k = 0; k < 8; k++) {
          c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
        }
        crcTable[i] = c;
      }
      function calcCrc32(bytes) {
        let crc = 0xFFFFFFFF;
        for (let i = 0; i < bytes.length; i++) {
          crc = (crc >>> 8) ^ crcTable[(crc ^ bytes[i]) & 0xFF];
        }
        return (crc ^ 0xFFFFFFFF) >>> 0;
      }

      const textEncoder = new TextEncoder();
      const entries = [];
      let offset = 0;

      for (const f of files) {
        const nameBytes = textEncoder.encode(f.name);
        const dataBytes = (f.data instanceof Uint8Array) ? f.data : textEncoder.encode(f.data);
        const crc = calcCrc32(dataBytes);

        const localHdr = new Uint8Array(30 + nameBytes.length);
        const view = new DataView(localHdr.buffer);
        view.setUint32(0, 0x04034b50, true);
        view.setUint16(4, 20, true);
        view.setUint16(6, 0, true);
        view.setUint16(8, 0, true);
        view.setUint16(10, 0, true);
        view.setUint16(12, 0, true);
        view.setUint32(14, crc, true);
        view.setUint32(18, dataBytes.length, true);
        view.setUint32(22, dataBytes.length, true);
        view.setUint16(26, nameBytes.length, true);
        view.setUint16(28, 0, true);
        localHdr.set(nameBytes, 30);

        entries.push({ nameBytes, dataBytes, crc, offset, localHdr });
        offset += localHdr.length + dataBytes.length;
      }

      const cdHeaders = [];
      let cdSize = 0;
      for (const e of entries) {
        const cdHdr = new Uint8Array(46 + e.nameBytes.length);
        const view = new DataView(cdHdr.buffer);
        view.setUint32(0, 0x02014b50, true);
        view.setUint16(4, 20, true);
        view.setUint16(6, 20, true);
        view.setUint16(8, 0, true);
        view.setUint16(10, 0, true);
        view.setUint16(12, 0, true);
        view.setUint16(14, 0, true);
        view.setUint32(16, e.crc, true);
        view.setUint32(20, e.dataBytes.length, true);
        view.setUint32(24, e.dataBytes.length, true);
        view.setUint16(28, e.nameBytes.length, true);
        view.setUint16(30, 0, true);
        view.setUint16(32, 0, true);
        view.setUint16(34, 0, true);
        view.setUint16(36, 0, true);
        view.setUint32(38, 0, true);
        view.setUint32(42, e.offset, true);
        cdHdr.set(e.nameBytes, 46);

        cdHeaders.push(cdHdr);
        cdSize += cdHdr.length;
      }

      const eocd = new Uint8Array(22);
      const eocdView = new DataView(eocd.buffer);
      eocdView.setUint32(0, 0x06054b50, true);
      eocdView.setUint16(4, 0, true);
      eocdView.setUint16(6, 0, true);
      eocdView.setUint16(8, entries.length, true);
      eocdView.setUint16(10, entries.length, true);
      eocdView.setUint32(12, cdSize, true);
      eocdView.setUint32(16, offset, true);
      eocdView.setUint16(20, 0, true);

      const parts = [];
      for (const e of entries) {
        parts.push(e.localHdr);
        parts.push(e.dataBytes);
      }
      for (const cd of cdHeaders) {
        parts.push(cd);
      }
      parts.push(eocd);

      return new Blob(parts, { type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' });
    }

    function exportToWord() {
      let data = getEditorData();
      if (!data) return;

      const isRtl = (document.querySelector('.ck-content') && document.querySelector('.ck-content').getAttribute('dir') === 'rtl');

      const parser = new DOMParser();
      const doc = parser.parseFromString(data, 'text/html');

      function escapeXml(str) {
        if (!str) return '';
        return str
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;')
          .replace(/"/g, '&quot;')
          .replace(/'/g, '&apos;');
      }

      function hexColor(str) {
        if (!str) return null;
        const m = str.match(/#([0-9a-fA-F]{6})/);
        if (m) return m[1].toUpperCase();
        const rgb = str.match(/rgb\\((\\d+),\\s*(\\d+),\\s*(\\d+)\\)/);
        if (rgb) {
          const r = parseInt(rgb[1]).toString(16).padStart(2, '0');
          const g = parseInt(rgb[2]).toString(16).padStart(2, '0');
          const b = parseInt(rgb[3]).toString(16).padStart(2, '0');
          return (r + g + b).toUpperCase();
        }
        return null;
      }

      function processRuns(element, inheritedStyles = {}) {
        let runsXml = '';
        element.childNodes.forEach(child => {
          if (child.nodeType === Node.TEXT_NODE) {
            const text = child.nodeValue;
            if (!text) return;
            let rPr = '';
            if (inheritedStyles.bold) rPr += '<w:b/><w:bCs/>';
            if (inheritedStyles.italic) rPr += '<w:i/><w:iCs/>';
            if (inheritedStyles.underline) rPr += '<w:u w:val="single"/>';
            if (inheritedStyles.strike) rPr += '<w:strike/>';
            if (inheritedStyles.color) rPr += '<w:color w:val="' + inheritedStyles.color + '"/>';
            if (inheritedStyles.highlight) rPr += '<w:highlight w:val="' + inheritedStyles.highlight + '"/>';
            if (inheritedStyles.size) rPr += '<w:sz w:val="' + inheritedStyles.size + '"/><w:szCs w:val="' + inheritedStyles.size + '"/>';
            if (inheritedStyles.font) rPr += '<w:rFonts w:ascii="' + escapeXml(inheritedStyles.font) + '" w:hAnsi="' + escapeXml(inheritedStyles.font) + '" w:cs="' + escapeXml(inheritedStyles.font) + '"/>';

            runsXml += '<w:r>' + (rPr ? '<w:rPr>' + rPr + '</w:rPr>' : '') +
              '<w:t xml:space="preserve">' + escapeXml(text) + '</w:t></w:r>';
          } else if (child.nodeType === Node.ELEMENT_NODE) {
            const tag = child.tagName.toLowerCase();
            const childStyles = Object.assign({}, inheritedStyles);

            if (tag === 'b' || tag === 'strong' || child.style.fontWeight === 'bold' || parseInt(child.style.fontWeight) >= 600) {
              childStyles.bold = true;
            }
            if (tag === 'i' || tag === 'em' || child.style.fontStyle === 'italic') {
              childStyles.italic = true;
            }
            if (tag === 'u' || (child.style.textDecoration && child.style.textDecoration.includes('underline'))) {
              childStyles.underline = true;
            }
            if (tag === 's' || tag === 'strike' || tag === 'del' || (child.style.textDecoration && child.style.textDecoration.includes('line-through'))) {
              childStyles.strike = true;
            }
            if (child.style.color) {
              const c = hexColor(child.style.color);
              if (c) childStyles.color = c;
            }
            if (tag === 'mark' || child.style.backgroundColor) {
              childStyles.highlight = 'yellow';
            }
            if (child.style.fontSize) {
              const ptMatch = child.style.fontSize.match(/([0-9.]+)(?:px|pt)?/);
              if (ptMatch) {
                const pt = parseFloat(ptMatch[1]);
                childStyles.size = Math.round(pt * 2);
              }
            }
            if (child.style.fontFamily) {
              childStyles.font = child.style.fontFamily.split(',')[0].replace(/['"]/g, '').trim();
            }

            if (tag === 'br') {
              runsXml += '<w:r><w:br/></w:r>';
            } else {
              runsXml += processRuns(child, childStyles);
            }
          }
        });
        return runsXml;
      }

      function processParagraph(pElem, defaultHeading = null) {
        let pPr = '';
        let tag = pElem.tagName ? pElem.tagName.toLowerCase() : 'p';
        const elDir = pElem.getAttribute('dir') || (isRtl ? 'rtl' : 'ltr');
        const isElemRtl = (elDir === 'rtl');

        const isHeading = defaultHeading || ['h1','h2','h3','h4','h5','h6'].includes(tag);
        if (isHeading) {
          const level = defaultHeading || tag;
          const hMap = { h1: 36, h2: 30, h3: 26, h4: 24, h5: 22, h6: 20 };
          const sz = hMap[level] || 24;
          pPr += '<w:pStyle w:val="Heading' + level.charAt(1) + '"/>';
          pPr += '<w:rPr><w:b/><w:bCs/><w:sz w:val="' + sz + '"/><w:szCs w:val="' + sz + '"/></w:rPr>';
        }

        const align = pElem.style.textAlign || (isElemRtl ? 'right' : 'left');
        if (align === 'center') pPr += '<w:jc w:val="center"/>';
        else if (align === 'right') pPr += '<w:jc w:val="right"/>';
        else if (align === 'justify') pPr += '<w:jc w:val="both"/>';
        else if (align === 'left') pPr += '<w:jc w:val="left"/>';

        if (isElemRtl) {
          pPr += '<w:bidi/>';
        }

        if (tag === 'blockquote' || (pElem.closest && pElem.closest('blockquote'))) {
          pPr += '<w:ind w:left="720"/>';
        }

        if ((pElem.classList && pElem.classList.contains('page-break')) || (pElem.querySelector && pElem.querySelector('.page-break'))) {
          return '<w:p><w:r><w:br w:type="page"/></w:r></w:p>';
        }

        const runs = processRuns(pElem, isHeading ? { bold: true } : {});
        return '<w:p>' + (pPr ? '<w:pPr>' + pPr + '</w:pPr>' : '') + runs + '</w:p>';
      }

      function processTable(tableElem) {
        let tblXml = '<w:tbl>';
        tblXml += '<w:tblPr>' +
          '<w:tblW w:w="5000" w:type="pct"/>' +
          '<w:tblBorders>' +
          '<w:top w:val="single" w:sz="4" w:space="0" w:color="94A3B8"/>' +
          '<w:left w:val="single" w:sz="4" w:space="0" w:color="94A3B8"/>' +
          '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="94A3B8"/>' +
          '<w:right w:val="single" w:sz="4" w:space="0" w:color="94A3B8"/>' +
          '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>' +
          '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="CBD5E1"/>' +
          '</w:tblBorders>' +
          (isRtl ? '<w:bidiVisual/>' : '') +
          '</w:tblPr>';

        const rows = tableElem.querySelectorAll('tr');
        rows.forEach(tr => {
          tblXml += '<w:tr>';
          const cells = tr.querySelectorAll('th, td');
          cells.forEach(cell => {
            const isTh = cell.tagName.toLowerCase() === 'th';
            let tcPr = '';
            if (isTh) {
              tcPr += '<w:shd w:val="clear" w:color="auto" w:fill="F1F5F9"/>';
            }
            const colspan = cell.getAttribute('colspan');
            if (colspan && parseInt(colspan) > 1) {
              tcPr += '<w:gridSpan w:val="' + colspan + '"/>';
            }

            tblXml += '<w:tc>' + (tcPr ? '<w:tcPr>' + tcPr + '</w:tcPr>' : '');
            const cellParas = cell.querySelectorAll('p');
            if (cellParas.length > 0) {
              cellParas.forEach(p => { tblXml += processParagraph(p); });
            } else {
              tblXml += processParagraph(cell);
            }
            tblXml += '</w:tc>';
          });
          tblXml += '</w:tr>';
        });
        tblXml += '</w:tbl>';
        return tblXml;
      }

      let bodyXml = '';
      const topChildren = doc.body.childNodes;
      topChildren.forEach(child => {
        if (child.nodeType === Node.TEXT_NODE) {
          if (child.nodeValue.trim()) {
            bodyXml += '<w:p><w:r><w:t xml:space="preserve">' + escapeXml(child.nodeValue.trim()) + '</w:t></w:r></w:p>';
          }
        } else if (child.nodeType === Node.ELEMENT_NODE) {
          const tag = child.tagName.toLowerCase();
          if (tag === 'table' || child.querySelector('table')) {
            const tbl = tag === 'table' ? child : child.querySelector('table');
            bodyXml += processTable(tbl);
          } else if (tag === 'ul' || tag === 'ol') {
            const items = child.querySelectorAll('li');
            items.forEach((li, idx) => {
              const bullet = (tag === 'ol') ? ((idx + 1) + '. ') : '• ';
              let pPr = '<w:ind w:left="720"/>';
              if (isRtl) pPr += '<w:bidi/><w:jc w:val="right"/>';
              bodyXml += '<w:p><w:pPr>' + pPr + '</w:pPr>' +
                '<w:r><w:t xml:space="preserve">' + bullet + '</w:t></w:r>' +
                processRuns(li) + '</w:p>';
            });
          } else if (tag === 'hr') {
            bodyXml += '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="CBD5E1"/></w:pBdr></w:pPr></w:p>';
          } else {
            bodyXml += processParagraph(child);
          }
        }
      });

      if (!bodyXml) {
        bodyXml = '<w:p><w:r><w:t></w:t></w:r></w:p>';
      }

      bodyXml += '<w:sectPr>' +
        '<w:pgSz w:w="12240" w:h="15840"/>' +
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>' +
        (isRtl ? '<w:bidi/>' : '') +
        '</w:sectPr>';

      const documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">' +
        '<w:body>' + bodyXml + '</w:body></w:document>';

      const contentTypesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
        '<Default Extension="xml" ContentType="application/xml"/>' +
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' +
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>' +
        '</Types>';

      const relsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>' +
        '</Relationships>';

      const wordRelsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' +
        '</Relationships>';

      const stylesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">' +
        '<w:docDefaults>' +
        '<w:rPrDefault>' +
        '<w:rPr>' +
        '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>' +
        '<w:sz w:val="22"/>' +
        '<w:szCs w:val="22"/>' +
        '</w:rPr>' +
        '</w:rPrDefault>' +
        '</w:docDefaults>' +
        '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:rPr><w:b/><w:bCs/><w:sz w:val="36"/><w:szCs w:val="36"/></w:rPr></w:style>' +
        '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:rPr><w:b/><w:bCs/><w:sz w:val="30"/><w:szCs w:val="30"/></w:rPr></w:style>' +
        '<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:rPr><w:b/><w:bCs/><w:sz w:val="26"/><w:szCs w:val="26"/></w:rPr></w:style>' +
        '</w:styles>';

      const files = [
        { name: '[Content_Types].xml', data: contentTypesXml },
        { name: '_rels/.rels', data: relsXml },
        { name: 'word/_rels/document.xml.rels', data: wordRelsXml },
        { name: 'word/styles.xml', data: stylesXml },
        { name: 'word/document.xml', data: documentXml }
      ];

      const zipBlob = generateDocxZipBlob(files);
      const url = URL.createObjectURL(zipBlob);
      const a = document.createElement('a');
      a.href = url;
      a.download = 'document.docx';
      a.click();
      URL.revokeObjectURL(url);
    }

    /* ====== IMPORT FROM WORD (.DOCX / .HTML / .TXT) ====== */
    async function extractDocxXmlFromZip(arrayBuffer) {
      try {
        const view = new DataView(arrayBuffer);
        const bytes = new Uint8Array(arrayBuffer);
        const len = bytes.length;

        // 1. Locate End of Central Directory (EOCD) by scanning backwards
        let eocdOffset = -1;
        for (let i = len - 22; i >= Math.max(0, len - 65557); i--) {
          if (view.getUint32(i, true) === 0x06054b50) {
            eocdOffset = i;
            break;
          }
        }

        let docXmlEntry = null;

        if (eocdOffset !== -1) {
          const cdCount = view.getUint16(eocdOffset + 10, true);
          const cdOffset = view.getUint32(eocdOffset + 16, true);
          let p = cdOffset;
          for (let k = 0; k < cdCount && p < eocdOffset; k++) {
            if (view.getUint32(p, true) !== 0x02014b50) break;
            const method = view.getUint16(p + 10, true);
            const compSize = view.getUint32(p + 20, true);
            const nameLen = view.getUint16(p + 28, true);
            const extraLen = view.getUint16(p + 30, true);
            const commentLen = view.getUint16(p + 32, true);
            const localHdrOffset = view.getUint32(p + 42, true);
            const nameBytes = bytes.subarray(p + 46, p + 46 + nameLen);
            const fileName = new TextDecoder('utf-8').decode(nameBytes);

            if (fileName === 'word/document.xml') {
              docXmlEntry = { localHdrOffset: localHdrOffset, compSize: compSize, method: method };
              break;
            }
            p += 46 + nameLen + extraLen + commentLen;
          }
        }

        // Fallback: Scan local headers from beginning
        if (!docXmlEntry) {
          let pos = 0;
          while (pos < len - 30) {
            if (view.getUint32(pos, true) === 0x04034b50) {
              const method = view.getUint16(pos + 8, true);
              const compSize = view.getUint32(pos + 18, true);
              const nameLen = view.getUint16(pos + 26, true);
              const extraLen = view.getUint16(pos + 28, true);
              const nameBytes = bytes.subarray(pos + 30, pos + 30 + nameLen);
              const fileName = new TextDecoder('utf-8').decode(nameBytes);
              if (fileName === 'word/document.xml') {
                docXmlEntry = { localHdrOffset: pos, compSize: compSize, method: method };
                break;
              }
              pos += 30 + nameLen + extraLen + compSize;
            } else {
              pos++;
            }
          }
        }

        if (!docXmlEntry) return null;

        const lhOffset = docXmlEntry.localHdrOffset;
        if (view.getUint32(lhOffset, true) !== 0x04034b50) return null;
        const lhNameLen = view.getUint16(lhOffset + 26, true);
        const lhExtraLen = view.getUint16(lhOffset + 28, true);
        const dataStart = lhOffset + 30 + lhNameLen + lhExtraLen;
        const compData = bytes.subarray(dataStart, dataStart + docXmlEntry.compSize);

        if (docXmlEntry.method === 0) {
          return new TextDecoder('utf-8').decode(compData);
        } else if (docXmlEntry.method === 8) {
          if (typeof DecompressionStream !== 'undefined') {
            const ds = new DecompressionStream('deflate-raw');
            const writer = ds.writable.getWriter();
            writer.write(compData);
            writer.close();
            const res = new Response(ds.readable);
            const decompBuf = await res.arrayBuffer();
            return new TextDecoder('utf-8').decode(decompBuf);
          }
        }
      } catch(e) {
        console.warn('Docx extraction error:', e);
      }
      return null;
    }

    function convertDocxXmlToHtml(xmlStr) {
      if (!xmlStr) return '<p>Unable to extract text from Word document.</p>';
      try {
        const parser = new DOMParser();
        const xmlDoc = parser.parseFromString(xmlStr, 'text/xml');
        const body = xmlDoc.getElementsByTagName('w:body')[0] || xmlDoc.documentElement;
        if (!body) return '<p>Empty document.</p>';

        function escapeXmlText(str) {
          return (str || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
        }

        function parseRunNode(rNode) {
          let text = '';
          const rPr = rNode.getElementsByTagName('w:rPr')[0];
          const isBold = rPr && rPr.getElementsByTagName('w:b').length > 0;
          const isItalic = rPr && rPr.getElementsByTagName('w:i').length > 0;
          const isUnderline = rPr && rPr.getElementsByTagName('w:u').length > 0;
          const isStrike = rPr && rPr.getElementsByTagName('w:strike').length > 0;

          for (let i = 0; i < rNode.childNodes.length; i++) {
            const child = rNode.childNodes[i];
            const localName = child.localName || child.nodeName.split(':').pop();
            if (localName === 't') {
              text += escapeXmlText(child.textContent || '');
            } else if (localName === 'br') {
              text += '<br>';
            } else if (localName === 'tab') {
              text += '&emsp;';
            }
          }

          if (!text) return '';
          if (isBold) text = '<strong>' + text + '</strong>';
          if (isItalic) text = '<em>' + text + '</em>';
          if (isUnderline) text = '<u>' + text + '</u>';
          if (isStrike) text = '<s>' + text + '</s>';
          return text;
        }

        function parseParagraphNode(pNode) {
          let pText = '';
          const pPr = pNode.getElementsByTagName('w:pPr')[0];
          let headingLevel = 0;
          if (pPr) {
            const pStyle = pPr.getElementsByTagName('w:pStyle')[0];
            if (pStyle) {
              const val = (pStyle.getAttribute('w:val') || pStyle.getAttribute('val') || '').toLowerCase();
              if (val.includes('heading1') || val === '1') headingLevel = 1;
              else if (val.includes('heading2') || val === '2') headingLevel = 2;
              else if (val.includes('heading3') || val === '3') headingLevel = 3;
              else if (val.includes('heading4') || val === '4') headingLevel = 4;
            }
          }

          for (let i = 0; i < pNode.childNodes.length; i++) {
            const child = pNode.childNodes[i];
            const localName = child.localName || child.nodeName.split(':').pop();
            if (localName === 'r') {
              pText += parseRunNode(child);
            }
          }

          if (!pText.trim()) return '';
          if (headingLevel > 0) {
            return '<h' + headingLevel + '>' + pText + '</h' + headingLevel + '>';
          }
          return '<p>' + pText + '</p>';
        }

        function parseTableNode(tblNode) {
          let tblHtml = '<figure class="table"><table style="border-collapse:collapse;width:100%;border:1px solid #cbd5e1;"><tbody>';
          const rows = tblNode.getElementsByTagName('w:tr');
          for (let r = 0; r < rows.length; r++) {
            tblHtml += '<tr>';
            const cells = rows[r].getElementsByTagName('w:tc');
            for (let c = 0; c < cells.length; c++) {
              let cellContent = '';
              const paras = cells[c].getElementsByTagName('w:p');
              for (let p = 0; p < paras.length; p++) {
                const pStr = parseParagraphNode(paras[p]);
                if (pStr) cellContent += pStr;
              }
              tblHtml += '<td style="border:1px solid #cbd5e1;padding:6px 10px;">' + (cellContent || '<p>&nbsp;</p>') + '</td>';
            }
            tblHtml += '</tr>';
          }
          tblHtml += '</tbody></table></figure>';
          return tblHtml;
        }

        let resultHtml = '';
        for (let i = 0; i < body.childNodes.length; i++) {
          const child = body.childNodes[i];
          const localName = child.localName || child.nodeName.split(':').pop();
          if (localName === 'p') {
            resultHtml += parseParagraphNode(child);
          } else if (localName === 'tbl') {
            resultHtml += parseTableNode(child);
          }
        }

        return resultHtml || '<p>Empty document content.</p>';
      } catch(e) {
        console.warn('Docx XML parse error:', e);
        return '<p>Error rendering Word document XML.</p>';
      }
    }

    function importFromWord() {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = '.doc,.docx,.html,.htm,.rtf,.txt';
      input.onchange = (e) => {
        const file = e.target.files[0];
        if (!file) return;

        const fileName = (file.name || '').toLowerCase();

        if (fileName.endsWith('.txt')) {
          const reader = new FileReader();
          reader.onload = (ev) => {
            const text = ev.target.result;
            const html = '<p>' + text.replace(/\\n\\n/g, '</p><p>').replace(/\\n/g, '<br>') + '</p>';
            setEditorData(html);
          };
          reader.readAsText(file);
        } else if (fileName.endsWith('.html') || fileName.endsWith('.htm')) {
          const reader = new FileReader();
          reader.onload = (ev) => setEditorData(ev.target.result);
          reader.readAsText(file);
        } else if (fileName.endsWith('.docx')) {
          const reader = new FileReader();
          reader.onload = async (ev) => {
            const buffer = ev.target.result;

            // 1. Try Mammoth if available (or dynamically load)
            if (typeof mammoth === 'undefined') {
              try {
                await loadExternalScript('https://cdnjs.cloudflare.com/ajax/libs/mammoth/1.8.0/mammoth.browser.min.js', 2500);
              } catch(err) {
                console.warn('Mammoth CDN unavailable, using native docx parser');
              }
            }

            if (typeof mammoth !== 'undefined' && mammoth.convertToHtml) {
              try {
                const res = await mammoth.convertToHtml({ arrayBuffer: buffer });
                if (res && res.value && res.value.trim().length > 0) {
                  setEditorData(res.value);
                  return;
                }
              } catch(err) {
                console.warn('Mammoth conversion error, falling back to native parser:', err);
              }
            }

            // 2. Native DOCX ZIP + XML extraction fallback
            const xml = await extractDocxXmlFromZip(buffer);
            if (xml) {
              const html = convertDocxXmlToHtml(xml);
              setEditorData(html);
            } else {
              alert('Could not parse Word .docx document. Please make sure the file is a valid .docx document.');
            }
          };
          reader.readAsArrayBuffer(file);
        } else {
          // Legacy .doc or .rtf
          const reader = new FileReader();
          reader.onload = (ev) => {
            const content = ev.target.result;
            const text = new TextDecoder('utf-8', {fatal: false}).decode(new Uint8Array(content));
            const words = text.split(/[^A-Za-z0-9.,!?'"\\-:;()\\[\\]{}_+=/\\%@#*]+/).filter(w => w.length > 2 && !w.includes('Content_Types') && !w.includes('word/'));
            if (words.length > 0) {
              setEditorData('<p>' + words.join(' ').substring(0, 50000) + '</p>');
            } else {
              alert('Legacy .doc binary format cannot be parsed directly. Please save the file as modern .docx or .html and try again.');
            }
          };
          reader.readAsArrayBuffer(file);
        }
      };
      input.click();
    }

    /* ====== PRINT ====== */
    function printEditor() { window.print(); }

    /* ====== TRACK CHANGES ====== */
    function toggleTrackChanges() {
      trackChangesEnabled = !trackChangesEnabled;
      const btn = document.getElementById('btn-track-changes');
      if (btn) btn.classList.toggle('active', trackChangesEnabled);
      document.getElementById('track-status').textContent = 'Track Changes: ' + (trackChangesEnabled ? 'On' : 'Off');
      if (trackChangesEnabled) openPanel('changes');
    }

    let lastTrackedContent = '';
    function recordChange() {
      const data = getEditorData();
      if (!data || data === lastTrackedContent) return;

      const change = {
        id: Date.now(),
        type: data.length > lastTrackedContent.length ? 'insertion' : 'deletion',
        author: 'Current User',
        time: new Date().toLocaleTimeString(),
        preview: getTextPreview(data, 60)
      };
      trackedChanges.unshift(change);
      if (trackedChanges.length > 100) trackedChanges.pop();
      lastTrackedContent = data;
      if (currentPanel === 'changes') renderChangesPanel();
    }

    /* ====== REVISION HISTORY ====== */
    let autoSaveTimer = null;
    let revisionSeq = 0;
    /* Revision the editor currently shows unchanged; null once the user edits after it */
    let activeRevisionId = null;
    let isRestoringRevision = false;

    function autoSaveRevision() {
      clearTimeout(autoSaveTimer);
      autoSaveTimer = setTimeout(() => {
        saveRevision('Auto-save');
      }, 30000); /* Auto-save every 30 seconds of inactivity */
    }

    function markRevisionDirty() {
      if (activeRevisionId === null) return;
      activeRevisionId = null;
      if (currentPanel === 'revisions') renderRevisionsPanel();
    }

    function saveRevision(label) {
      clearTimeout(autoSaveTimer);
      /* Nothing edited since the shown revision -> nothing new to save */
      if (activeRevisionId !== null && revisions.some(r => r.id === activeRevisionId)) return;
      const data = getEditorData();
      if (!data) return;
      const existing = revisions.find(r => r.content === data);
      if (existing) {
        activeRevisionId = existing.id;
        if (currentPanel === 'revisions') renderRevisionsPanel();
        return;
      }

      const rev = {
        id: ++revisionSeq,
        label: label || 'Revision ' + (revisions.length + 1),
        time: new Date().toLocaleString(),
        content: data,
        preview: getTextPreview(data, 80)
      };
      revisions.unshift(rev);
      activeRevisionId = rev.id;
      if (revisions.length > 50) revisions.pop();
      if (currentPanel === 'revisions') renderRevisionsPanel();
    }

    function restoreRevision(id) {
      const rev = revisions.find(r => r.id === id);
      if (!rev || rev.id === activeRevisionId) return;
      /* Keep unsaved edits so they can be restored later (no-op if nothing changed) */
      saveRevision('Before restore');
      clearTimeout(autoSaveTimer);
      isRestoringRevision = true;
      try {
        window._lastExportedHtml = null; /* setEditorData skips html matching the last export */
        setEditorData(rev.content);
      } finally {
        /* setEditorData post-processes the content ~80ms later; ignore those changes too */
        setTimeout(() => { isRestoringRevision = false; }, 250);
      }
      activeRevisionId = rev.id;
      if (currentPanel === 'revisions') renderRevisionsPanel();
    }

    /* ====== COMMENTS ====== */
    function addComment() {
      const text = prompt('Enter your comment:');
      if (!text) return;
      comments.push({
        id: Date.now(),
        author: 'Current User',
        time: new Date().toLocaleString(),
        text: text,
        replies: [],
        resolved: false
      });
      renderCommentsPanel();
    }

    function replyToComment(id) {
      const text = prompt('Enter reply:');
      if (!text) return;
      const comment = comments.find(c => c.id === id);
      if (comment) {
        comment.replies.push({
          author: 'Current User',
          time: new Date().toLocaleTimeString(),
          text: text
        });
        renderCommentsPanel();
      }
    }

    function resolveComment(id) {
      const comment = comments.find(c => c.id === id);
      if (comment) { comment.resolved = true; renderCommentsPanel(); }
    }

    function deleteComment(id) {
      comments = comments.filter(c => c.id !== id);
      renderCommentsPanel();
    }

    /* ====== DOCUMENT OUTLINE ====== */
    function buildOutline() {
      const data = getEditorData();
      if (!data) return [];
      const parser = new DOMParser();
      const doc = parser.parseFromString(data, 'text/html');
      const headings = doc.querySelectorAll('h1, h2, h3, h4, h5, h6');
      const items = [];
      headings.forEach((h, i) => {
        items.push({
          level: parseInt(h.tagName.charAt(1)),
          text: h.textContent.trim(),
          index: i
        });
      });
      return items;
    }

    function scrollToHeading(index) {
      if (!editorInstance) return;
      const editable = document.querySelector('.ck-content');
      if (!editable) return;
      const headings = editable.querySelectorAll('h1, h2, h3, h4, h5, h6');
      if (headings[index]) {
        headings[index].scrollIntoView({ behavior: 'smooth', block: 'center' });
        headings[index].style.transition = 'background 0.3s';
        headings[index].style.background = '#fef08a';
        setTimeout(() => { headings[index].style.background = ''; }, 1500);
      }
    }

    /* ====== SIDE PANEL RENDERING ====== */
    function openPanel(type) {
      currentPanel = type;
      const panel = document.getElementById('side-panel');
      const title = document.getElementById('side-panel-title');
      panel.classList.add('open');
      switch(type) {
        case 'revisions': title.textContent = '🕐 Revision History'; renderRevisionsPanel(); break;
        case 'outline': title.textContent = '📑 Document Outline'; renderOutlinePanel(); break;
        case 'comments': title.textContent = '💬 Comments'; renderCommentsPanel(); break;
        case 'changes': title.textContent = '📋 Track Changes'; renderChangesPanel(); break;
      }
    }

    function closePanel() {
      document.getElementById('side-panel').classList.remove('open');
      currentPanel = null;
    }

    function renderRevisionsPanel() {
      const container = document.getElementById('side-panel-content');
      if (revisions.length === 0) {
        container.innerHTML = '<p style="color:#94a3b8;text-align:center;margin-top:40px;">No revisions yet</p>';
        return;
      }
      let html = '<button onclick="saveRevision(&quot;Manual Save&quot;)" style="width:100%;padding:8px;margin-bottom:12px;border:1px solid #3b82f6;border-radius:6px;background:#eff6ff;color:#2563eb;cursor:pointer;font-size:13px;">💾 Save Revision Now</button>';
      revisions.forEach((rev) => {
        const isActive = rev.id === activeRevisionId;
        html += '<div class="revision-item' + (isActive ? ' active' : '') + '" onclick="restoreRevision(' + rev.id + ')">' +
          '<div class="rev-title">' + escapeHtml(rev.label) + (isActive ? ' <span style="font-weight:400;font-size:11px;color:#2563eb;">(current)</span>' : '') + '</div>' +
          '<div class="rev-time">' + rev.time + '</div>' +
          '<div class="rev-preview">' + escapeHtml(rev.preview) + '</div></div>';
      });
      container.innerHTML = html;
    }

    /* An open Outline must follow the document (imports, typing, Flutter sync), not show a stale snapshot */
    let outlineRefreshTimer = null;
    function scheduleOutlineRefresh() {
      if (currentPanel !== 'outline') return;
      clearTimeout(outlineRefreshTimer);
      outlineRefreshTimer = setTimeout(() => {
        if (currentPanel === 'outline') renderOutlinePanel();
      }, 150);
    }

    function renderOutlinePanel() {
      const container = document.getElementById('side-panel-content');
      const items = buildOutline();
      if (items.length === 0) {
        container.innerHTML = '<p style="color:#94a3b8;text-align:center;margin-top:40px;">No headings found.<br>Add headings to see the outline.</p>';
        return;
      }
      let html = '';
      items.forEach((item) => {
        html += '<div class="outline-item level-' + item.level + '" onclick="scrollToHeading(' + item.index + ')">' +
          escapeHtml(item.text) + '</div>';
      });
      container.innerHTML = html;
    }

    function renderCommentsPanel() {
      const container = document.getElementById('side-panel-content');
      let html = '';
      const activeComments = comments.filter(c => !c.resolved);
      const resolvedComments = comments.filter(c => c.resolved);

      if (activeComments.length === 0 && resolvedComments.length === 0) {
        html = '<p style="color:#94a3b8;text-align:center;margin-top:40px;">No comments yet</p>';
      }

      activeComments.forEach(c => {
        html += '<div class="comment-item">' +
          '<div class="comment-header"><span class="comment-author">' + escapeHtml(c.author) + '</span><span class="comment-time">' + c.time + '</span></div>' +
          '<div class="comment-text">' + escapeHtml(c.text) + '</div>';
        c.replies.forEach(r => {
          html += '<div class="comment-reply"><span style="font-weight:600;font-size:12px;">' + escapeHtml(r.author) + '</span> <span style="font-size:11px;color:#94a3b8;">' + r.time + '</span><div style="font-size:12px;color:#475569;margin-top:2px;">' + escapeHtml(r.text) + '</div></div>';
        });
        html += '<div style="margin-top:8px;display:flex;gap:6px;">' +
          '<button onclick="replyToComment(' + c.id + ')" style="padding:3px 8px;border:1px solid #cbd5e1;border-radius:4px;background:white;cursor:pointer;font-size:11px;">Reply</button>' +
          '<button onclick="resolveComment(' + c.id + ')" style="padding:3px 8px;border:1px solid #16a34a;border-radius:4px;background:#f0fdf4;cursor:pointer;font-size:11px;color:#16a34a;">Resolve</button>' +
          '<button onclick="deleteComment(' + c.id + ')" style="padding:3px 8px;border:1px solid #dc2626;border-radius:4px;background:#fef2f2;cursor:pointer;font-size:11px;color:#dc2626;">Delete</button>' +
          '</div></div>';
      });

      if (resolvedComments.length > 0) {
        html += '<div style="margin-top:16px;padding-top:12px;border-top:1px solid #e2e8f0;"><div style="font-weight:600;font-size:12px;color:#94a3b8;margin-bottom:8px;">RESOLVED</div>';
        resolvedComments.forEach(c => {
          html += '<div class="comment-item" style="opacity:0.6;"><div class="comment-header"><span class="comment-author">' + escapeHtml(c.author) + '</span><span class="comment-time">' + c.time + '</span></div>' +
            '<div class="comment-text">' + escapeHtml(c.text) + '</div>' +
            '<button onclick="deleteComment(' + c.id + ')" style="margin-top:6px;padding:2px 8px;border:1px solid #dc2626;border-radius:4px;background:#fef2f2;cursor:pointer;font-size:11px;color:#dc2626;">Delete</button></div>';
        });
        html += '</div>';
      }

      html += '<button class="add-comment-btn" onclick="addComment()">+ Add Comment</button>';
      container.innerHTML = html;
    }

    function renderChangesPanel() {
      const container = document.getElementById('side-panel-content');
      if (trackedChanges.length === 0) {
        container.innerHTML = '<p style="color:#94a3b8;text-align:center;margin-top:40px;">No changes tracked yet.<br>Start editing with Track Changes on.</p>';
        return;
      }
      let html = '<button onclick="acceptAllChanges()" style="width:48%;padding:6px;margin-right:4%;border:1px solid #16a34a;border-radius:4px;background:#f0fdf4;cursor:pointer;font-size:12px;color:#16a34a;">✓ Accept All</button>' +
        '<button onclick="rejectAllChanges()" style="width:48%;padding:6px;border:1px solid #dc2626;border-radius:4px;background:#fef2f2;cursor:pointer;font-size:12px;color:#dc2626;">✗ Reject All</button>' +
        '<div style="margin-top:12px;">';
      trackedChanges.slice(0, 30).forEach(c => {
        html += '<div class="change-item ' + c.type + '">' +
          '<div><span class="change-author">' + escapeHtml(c.author) + '</span> <span class="change-time">' + c.time + '</span></div>' +
          '<div class="change-content">' + (c.type === 'insertion' ? '+ ' : '- ') + escapeHtml(c.preview) + '</div></div>';
      });
      html += '</div>';
      container.innerHTML = html;
    }

    function acceptAllChanges() {
      trackedChanges = [];
      renderChangesPanel();
    }
    function rejectAllChanges() {
      if (revisions.length > 1) restoreRevision(revisions[revisions.length - 1].id);
      trackedChanges = [];
      renderChangesPanel();
    }

    /* ====== TEMPLATES ====== */
    const templates = [
      { name: 'Meeting Notes', icon: '📝', desc: 'Structured meeting minutes', content: '<h2>Meeting Notes</h2><p><strong>Date:</strong> ' + new Date().toLocaleDateString() + '</p><p><strong>Attendees:</strong></p><ul><li>Name 1</li><li>Name 2</li></ul><h3>Agenda</h3><ol><li>Topic 1</li><li>Topic 2</li></ol><h3>Action Items</h3><ul class="todo-list"><li><label><input type="checkbox"> Action item 1</label></li><li><label><input type="checkbox"> Action item 2</label></li></ul>' },
      { name: 'Project Proposal', icon: '📊', desc: 'Business proposal template', content: '<h1>Project Proposal</h1><h2>Executive Summary</h2><p>Brief overview of the project...</p><h2>Objectives</h2><ul><li>Objective 1</li><li>Objective 2</li></ul><h2>Timeline</h2><table><tr><th>Phase</th><th>Duration</th><th>Status</th></tr><tr><td>Planning</td><td>2 weeks</td><td>Pending</td></tr><tr><td>Development</td><td>4 weeks</td><td>Pending</td></tr><tr><td>Testing</td><td>2 weeks</td><td>Pending</td></tr></table><h2>Budget</h2><p>Estimated cost: ...</p>' },
      { name: 'Technical Doc', icon: '⚙️', desc: 'API/Technical documentation', content: '<h1>Technical Documentation</h1><h2>Overview</h2><p>Description of the system/API...</p><h2>Architecture</h2><p>System architecture description...</p><h2>API Reference</h2><h3>GET /api/resource</h3><p>Retrieves a list of resources.</p><pre><code class="language-json">{\\n  "data": [],\\n  "total": 0\\n}</code></pre><h3>POST /api/resource</h3><p>Creates a new resource.</p>' },
      { name: 'Report', icon: '📈', desc: 'Professional report layout', content: '<h1>Report Title</h1><p><em>Prepared by: Your Name</em></p><p><em>Date: ' + new Date().toLocaleDateString() + '</em></p><hr><h2>1. Introduction</h2><p>Background information...</p><h2>2. Findings</h2><p>Key findings and analysis...</p><h2>3. Recommendations</h2><ol><li>First recommendation</li><li>Second recommendation</li></ol><h2>4. Conclusion</h2><p>Summary and next steps...</p>' },
      { name: 'Invoice', icon: '💰', desc: 'Simple invoice template', content: '<h1 style="text-align:center">INVOICE</h1><table><tr><td><strong>From:</strong><br>Your Company<br>Address Line 1<br>City, State</td><td style="text-align:right"><strong>Invoice #:</strong> 001<br><strong>Date:</strong> ' + new Date().toLocaleDateString() + '</td></tr></table><hr><table><tr><th>Description</th><th>Qty</th><th>Rate</th><th>Amount</th></tr><tr><td>Service/Product 1</td><td>1</td><td>USD 100</td><td>USD 100</td></tr><tr><td>Service/Product 2</td><td>2</td><td>USD 50</td><td>USD 100</td></tr><tr><td colspan="3" style="text-align:right"><strong>Total:</strong></td><td><strong>USD 200</strong></td></tr></table>' },
      { name: 'Resume/CV', icon: '👤', desc: 'Professional resume format', content: '<h1>Your Name</h1><p>Email: your@email.com | Phone: (123) 456-7890 | Location: City, State</p><hr><h2>Professional Summary</h2><p>Experienced professional with expertise in...</p><h2>Work Experience</h2><h3>Job Title — Company Name</h3><p><em>Jan 2020 – Present</em></p><ul><li>Achievement or responsibility 1</li><li>Achievement or responsibility 2</li></ul><h2>Education</h2><h3>Degree — University Name</h3><p><em>Graduated: 2019</em></p><h2>Skills</h2><p>Skill 1, Skill 2, Skill 3, Skill 4</p>' },
      { name: 'Letter', icon: '✉️', desc: 'Formal letter template', content: '<p>' + new Date().toLocaleDateString() + '</p><p><br></p><p>Recipient Name<br>Company Name<br>Address</p><p><br></p><p>Dear [Recipient],</p><p><br></p><p>I am writing to...</p><p><br></p><p>Sincerely,</p><p><br></p><p>Your Name<br>Your Title</p>' },
      { name: 'Lab Report', icon: '🔬', desc: 'Scientific lab report', content: '<h1>Lab Report</h1><p><strong>Experiment:</strong> Title</p><p><strong>Date:</strong> ' + new Date().toLocaleDateString() + '</p><p><strong>Researcher:</strong> Name</p><h2>Objective</h2><p>The purpose of this experiment...</p><h2>Materials</h2><ul><li>Material 1</li><li>Material 2</li></ul><h2>Procedure</h2><ol><li>Step 1</li><li>Step 2</li></ol><h2>Results</h2><table><tr><th>Sample</th><th>Measurement</th><th>Observation</th></tr><tr><td>A</td><td>10.5</td><td>Normal</td></tr></table><h2>Conclusion</h2><p>Based on the results...</p>' }
    ];

    function showTemplateModal() {
      const grid = document.getElementById('template-grid');
      let html = '';
      templates.forEach((t, i) => {
        html += '<div class="template-card" onclick="insertTemplate(' + i + ')">' +
          '<div class="template-icon">' + t.icon + '</div>' +
          '<div class="template-name">' + t.name + '</div>' +
          '<div class="template-desc">' + t.desc + '</div></div>';
      });
      grid.innerHTML = html;
      document.getElementById('template-modal').classList.add('show');
    }

    function closeTemplateModal() {
      document.getElementById('template-modal').classList.remove('show');
    }

    function insertTemplate(index) {
      const tmpl = templates[index];
      if (tmpl) {
        const current = getEditorData() || '';
        setEditorData(current + tmpl.content);
        closeTemplateModal();
      }
    }

    /* ====== MATH EQUATIONS ====== */
    function showMathModal() {
      document.getElementById('math-modal').classList.add('show');
      document.getElementById('math-input').value = '';
      document.getElementById('math-preview').innerHTML = 'Preview will appear here';
    }

    function closeMathModal() {
      document.getElementById('math-modal').classList.remove('show');
    }

    function previewMath() {
      const input = document.getElementById('math-input').value;
      const preview = document.getElementById('math-preview');
      if (!input.trim()) { preview.innerHTML = 'Preview will appear here'; return; }
      try {
        if (typeof katex !== 'undefined') {
          katex.render(input, preview, { throwOnError: false, displayMode: true });
        } else {
          preview.textContent = input;
        }
      } catch(e) { preview.textContent = 'Invalid formula'; }
    }

    function insertMathFormula() {
      const input = document.getElementById('math-input').value;
      if (!input.trim()) return;
      let mathHtml = '';
      try {
        if (typeof katex !== 'undefined') {
          mathHtml = katex.renderToString(input, { throwOnError: false, displayMode: true });
        } else {
          mathHtml = '<span style="font-family:serif;font-style:italic;">' + escapeHtml(input) + '</span>';
        }
      } catch(e) {
        mathHtml = '<span style="font-family:serif;font-style:italic;">' + escapeHtml(input) + '</span>';
      }
      const block = '<div style="text-align:center;margin:16px 0;padding:12px;background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;" class="math-block" data-formula="' + escapeHtml(input) + '">' + mathHtml + '</div>';
      const current = getEditorData() || '';
      setEditorData(current + block);
      closeMathModal();
    }

    /* ====== PAGE BREAK ====== */
    function insertPageBreak() {
      if (editorInstance) {
        try { editorInstance.execute('pageBreak'); } catch(e) {
          const current = getEditorData() || '';
          setEditorData(current + '<div class="page-break" style="page-break-after:always;border-top:2px dashed #94a3b8;margin:32px 0;padding:8px 0;text-align:center;color:#94a3b8;font-size:11px;">— Page Break —</div>');
        }
      }
    }

    /* ====== SHOW BLOCKS ====== */
    function toggleShowBlocks() {
      const cmd = editorInstance && editorInstance.commands.get('showBlocks');
      if (cmd) {
        /* The command owns the state, so this button and CKEditor's own toolbar button can never disagree */
        try { editorInstance.execute('showBlocks'); } catch(e) {}
        editorInstance.editing.view.focus();
      } else {
        showBlocksEnabled = !showBlocksEnabled;
        const fc = document.getElementById('fallback-content');
        if (fc) fc.classList.toggle('show-blocks', showBlocksEnabled);
      }
      updateShowBlocksButton();
    }

    function updateShowBlocksButton() {
      const cmd = editorInstance && editorInstance.commands.get('showBlocks');
      if (cmd) showBlocksEnabled = !!cmd.value;
      const btn = document.getElementById('btn-show-blocks');
      if (!btn) return;
      btn.classList.toggle('active', showBlocksEnabled);
      btn.textContent = showBlocksEnabled ? '✕ Hide Blocks' : '¶ Blocks';
      btn.title = showBlocksEnabled ? 'Hide block outlines' : 'Show block outlines';
    }

    /* ====== LEAVING THE LAST BLOCK ======
       A code block, quote, list or heading at the very end of the document has no line after it, and CKEditor's
       exits (Enter x3 in code, Enter on an empty quote line) are hard to discover. Arrow Down/Right at its end, or a
       click in the empty space below it, opens a new paragraph after it. */
    /* A paragraph that is not a list item is already a normal line to type on */
    function isPlainParagraph(element) {
      return element.is('element', 'paragraph') && !element.hasAttribute('listItemId');
    }

    function getTrailingBlockToEscape(editor, direction) {
      const model = editor.model;
      const selection = model.document.selection;
      const root = model.document.getRoot();
      const last = root.getChild(root.childCount - 1);
      if (!last || isPlainParagraph(last)) return null;
      /* A selected widget (table, video, line...) at the end: typing would replace it, so step past it */
      const selected = selection.getSelectedElement();
      if (selected) return selected === last ? last : null;
      if (!selection.isCollapsed) return null;
      const pos = selection.getFirstPosition();
      let top = pos.parent;
      while (top && top.parent && top.parent !== root) top = top.parent;
      if (top !== last) return null;
      if (direction === 'down' && last.is('element', 'table')) {
        /* Arrow Down from the last row would select the whole table */
        const rows = Array.from(last.getChildren()).filter(n => n.is('element', 'tableRow'));
        return pos.findAncestor('tableRow') === rows[rows.length - 1] ? last : null;
      }
      const rest = model.createRange(pos, model.createPositionAt(last, 'end'));
      for (const item of rest.getItems()) {
        if (item.is('\$textProxy') || item.is('element')) return null;
      }
      return last;
    }

    function insertParagraphAfter(editor, block) {
      editor.model.change(writer => {
        const paragraph = writer.createElement('paragraph');
        writer.insert(paragraph, block, 'after');
        writer.setSelection(paragraph, 0);
      });
      editor.editing.view.focus();
      editor.editing.view.scrollToTheSelection();
    }

    function installBlockNavigation(editor) {
      /* The capture context runs before CKEditor's own table/widget arrow handling (which would select the whole table) */
      editor.editing.view.document.on('arrowKey', (evt, data) => {
        if (data.shiftKey || data.altKey || data.ctrlKey || data.metaKey) return;
        const forwardKey = currentTextDir === 'rtl' ? 37 : 39;
        const direction = data.keyCode === 40 ? 'down' : (data.keyCode === forwardKey ? 'right' : null);
        if (!direction) return;
        const block = getTrailingBlockToEscape(editor, direction);
        if (!block) return;
        insertParagraphAfter(editor, block);
        data.preventDefault();
        evt.stop();
      }, { context: '\$capture', priority: 'highest' });

      const editable = editor.ui.getEditableElement();
      if (!editable) return;
      editable.addEventListener('mousedown', (e) => {
        if (e.target !== editable || editor.isReadOnly) return;
        const root = editor.model.document.getRoot();
        const last = root.getChild(root.childCount - 1);
        if (!last || isPlainParagraph(last)) return;
        const viewEl = editor.editing.mapper.toViewElement(last);
        const domEl = viewEl ? editor.editing.view.domConverter.mapViewToDom(viewEl) : null;
        if (!domEl || e.clientY <= domEl.getBoundingClientRect().bottom) return;
        e.preventDefault();
        insertParagraphAfter(editor, last);
      });
    }

    /* ====== FORMAT PAINTER ====== */
    function formatPainter() {
      formatPainterActive = !formatPainterActive;
      document.getElementById('btn-format-painter').classList.toggle('active', formatPainterActive);
      if (formatPainterActive) {
        /* Capture current selection format */
        const sel = window.getSelection ? window.getSelection() : null;
        if (sel && sel.rangeCount > 0) {
          const range = sel.getRangeAt(0);
          const parent = range.commonAncestorContainer.parentElement;
          if (parent) {
            formatPainterStyle = parent.style.cssText;
          }
        }
      }
    }

    /* ====== READ ONLY / PREVIEW ====== */
    function toggleReadonly() {
      isReadonly = !isReadonly;
      const btn = document.getElementById('btn-readonly');
      if (btn) {
        btn.classList.toggle('active', isReadonly);
        btn.innerHTML = isReadonly ? '✏️ Edit' : '👁️ Preview';
        btn.title = isReadonly ? 'Exit Preview (Enable Editing)' : 'Toggle Preview (Read Only)';
      }
      if (editorInstance) {
        if (isReadonly) {
          editorInstance.enableReadOnlyMode('custom-lock');
        } else {
          editorInstance.disableReadOnlyMode('custom-lock');
        }
      }
      if (isFallback) {
        const fc = document.getElementById('fallback-content');
        if (fc) fc.contentEditable = isReadonly ? 'false' : 'true';
      }
    }

    /* ====== TEXT DIRECTION ====== */
    function detectHtmlDirection(html) {
      if (!html || typeof html !== 'string') return 'ltr';
      if (/dir=["']rtl["']/i.test(html) || /direction\\s*:\\s*rtl/i.test(html)) {
        return 'rtl';
      }
      return 'ltr';
    }

    function changeLanguage(dir, notify = true) {
      dir = (dir === 'rtl') ? 'rtl' : 'ltr';
      currentTextDir = dir;

      const sel = document.getElementById('select-dir');
      if (sel && sel.value !== dir) sel.value = dir;

      const editables = document.querySelectorAll('.ck-content, .ck-editor__editable, #fallback-content, #editor');
      editables.forEach(el => {
        el.setAttribute('dir', dir);
        el.style.direction = dir;
        el.style.textAlign = (dir === 'rtl' ? 'right' : 'left');
      });

      const editorMain = document.getElementById('editor-main');
      if (editorMain) {
        editorMain.setAttribute('dir', dir);
        editorMain.style.direction = dir;
      }

      if (editorInstance) {
        try {
          if (editorInstance.editing && editorInstance.editing.view) {
            editorInstance.editing.view.change(writer => {
              const root = editorInstance.editing.view.document.getRoot();
              if (root) {
                writer.setAttribute('dir', dir, root);
                writer.setStyle('direction', dir, root);
                writer.setStyle('text-align', (dir === 'rtl' ? 'right' : 'left'), root);
              }
            });
          }
        } catch(e) {}

        try {
          const targetAlign = (dir === 'rtl') ? 'right' : 'left';
          const schema = editorInstance.model.schema;
          editorInstance.model.change(writer => {
            const root = editorInstance.model.document.getRoot();
            if (!root) return;
            const range = editorInstance.model.createRangeIn(root);
            for (const item of range.getItems()) {
              if (item.is && item.is('element')) {
                if (schema.checkAttribute(item, 'dir')) {
                  writer.setAttribute('dir', dir, item);
                }
                if (schema.checkAttribute(item, 'alignment')) {
                  writer.setAttribute('alignment', targetAlign, item);
                }
              }
            }
          });
        } catch(e) {
          console.warn('changeLanguage model update error:', e);
        }
      }

      if (isFallback) {
        const fc = document.getElementById('fallback-content');
        if (fc) {
          fc.setAttribute('dir', dir);
          fc.style.direction = dir;
          fc.style.textAlign = (dir === 'rtl' ? 'right' : 'left');
        }
      }

      if (notify) {
        postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
      }
    }

    /* Unique table identification - attached in memory to HTMLTableElement and DOM attribute so instances are never confused */
    function getTableUid(table) {
      if (!table) return 'tbl_0';
      let uid = (table.getAttribute && table.getAttribute('data-table-uid')) || table._tableUid;
      if (!uid) {
        const liveTables = getEditorLiveTables();
        const idx = Math.max(0, liveTables.indexOf(table));
        uid = 'tbl_' + idx;
      }
      table._tableUid = uid;
      if (table.setAttribute && !table.getAttribute('data-table-uid')) {
        try { table.setAttribute('data-table-uid', uid); } catch(e) {}
      }
      return uid;
    }

    function pruneDeadTableFormulas() {
      if (!window._tableFormulaRegistry) return;
      const liveTables = getEditorLiveTables();
      if (liveTables.length === 0) return;

      for (let k in window._tableFormulaRegistry) {
        let isAlive = false;
        for (let tIdx = 0; tIdx < liveTables.length; tIdx++) {
          const t = liveTables[tIdx];
          const uid = getTableUid(t);
          if (k.startsWith(uid + '_') || k.startsWith(tIdx + '_')) {
            const suffix = k.startsWith(uid + '_') ? k.substring(uid.length + 1) : k.substring(String(tIdx).length + 1);
            const parts = suffix.split('_');
            const r = parseInt(parts[0], 10);
            const c = parseInt(parts[1], 10);
            if (!isNaN(r) && !isNaN(c) && t.rows && r < t.rows.length && c < (t.rows[r]?.cells?.length || 0)) {
              isAlive = true;
            }
            break;
          }
        }
        if (!isAlive) {
          delete window._tableFormulaRegistry[k];
        }
      }
    }

    /* Dedicated helper: selects only editor tables and ignores any tables in modals or popups */
    function getEditorLiveTables() {
      const tables = Array.from(document.querySelectorAll('.ck-content table, .ck-editor__editable table, #fallback-content table'));
      return tables.filter(t => !t.closest('.modal-overlay') && !t.closest('.modal-box') && !t.closest('.ck-dropdown'));
    }

    function extractFormulaFromTitle(title) {
      if (!title || typeof title !== 'string') return null;
      const idx = title.indexOf('Formula:');
      if (idx === -1) return null;
      let cand = title.substring(idx + 8).trim();
      cand = cand.replace(/\\s*\\([Cc]lick[^)]*\\)/g, '').trim();
      cand = cleanFormulaText(cand);
      return cand.startsWith('=') ? cand : null;
    }

    function sanitizeTableHtml(html) {
      if (!html || typeof html !== 'string' || html.indexOf('<table') === -1) return html;
      try {
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        const tables = doc.querySelectorAll('table');
        if (tables.length === 0) return html;

        // Remove all legacy .formula-badge elements
        doc.querySelectorAll('.formula-badge').forEach(b => b.remove());

        tables.forEach(table => {
          for (let r = 0; r < table.rows.length; r++) {
            for (let c = 0; c < table.rows[r].cells.length; c++) {
              const cell = table.rows[r].cells[c];

              let formula = cell.getAttribute('data-formula') || extractFormulaFromTitle(cell.getAttribute('title'));
              if (!formula) {
                const childF = cell.querySelector('[data-formula]');
                if (childF) formula = childF.getAttribute('data-formula');
              }
              if (!formula) {
                const childT = cell.querySelector('[title*="Formula:"]');
                if (childT) formula = extractFormulaFromTitle(childT.getAttribute('title'));
              }

              // Strip accidental 'fx' suffix from cell text (e.g. 12fx -> 12, 206fx -> 206)
              const walker = doc.createTreeWalker(cell, NodeFilter.SHOW_TEXT, null, false);
              let node;
              while (node = walker.nextNode()) {
                if (/\\b\\d+\\s*fx\\b/i.test(node.nodeValue)) {
                  node.nodeValue = node.nodeValue.replace(/(\\d+)\\s*fx\\b/gi, '\$1');
                } else if (node.nodeValue.trim() === 'fx') {
                  node.nodeValue = '';
                }
              }

              if (formula) formula = cleanFormulaText(formula);
              if (formula && formula.startsWith('=')) {
                cell.setAttribute('data-formula', formula);
                cell.setAttribute('title', 'Formula: ' + formula);
                cell.classList.add('has-formula');
              }
            }
          }
        });

        return doc.body.innerHTML;
      } catch (e) {
        console.warn('sanitizeTableHtml error:', e);
        return html;
      }
    }

    function cleanAndExportFormulasInHtml(html) {
      if (!html || typeof html !== 'string' || html.indexOf('<table') === -1) return html;
      try {
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        const tables = doc.querySelectorAll('table');
        if (tables.length === 0) return html;

        // Remove all legacy .formula-badge spans
        doc.querySelectorAll('.formula-badge').forEach(b => b.remove());

        const liveTables = getEditorLiveTables();

        tables.forEach((t, tIdx) => {
          const liveT = liveTables[tIdx];
          const tableUid = liveT ? getTableUid(liveT) : null;
          const rows = t.rows;
          for (let r = 0; r < rows.length; r++) {
            const cells = rows[r].cells;
            for (let c = 0; c < cells.length; c++) {
              const cell = cells[c];
              const regKey = tableUid ? (tableUid + '_' + r + '_' + c) : null;
              let formula = null;
              if (liveT && liveT.rows && liveT.rows[r] && liveT.rows[r].cells && liveT.rows[r].cells[c]) {
                const liveC = liveT.rows[r].cells[c];
                formula = liveC.getAttribute('data-formula') || extractFormulaFromTitle(liveC.getAttribute('title'));
                if (!formula) {
                  const childF = liveC.querySelector('[data-formula]');
                  if (childF) formula = childF.getAttribute('data-formula');
                }
                if (!formula) {
                  const childT = liveC.querySelector('[title*="Formula:"]');
                  if (childT) formula = extractFormulaFromTitle(childT.getAttribute('title'));
                }
              }
              if (!formula && cell.getAttribute('data-formula')) {
                formula = cell.getAttribute('data-formula');
              }
              if (!formula && cell.getAttribute('title')) {
                formula = extractFormulaFromTitle(cell.getAttribute('title'));
              }
              if (!formula && regKey && window._tableFormulaRegistry && window._tableFormulaRegistry[regKey]) {
                formula = window._tableFormulaRegistry[regKey];
              }
              if (!formula && window._tableFormulaRegistry && window._tableFormulaRegistry[tIdx + '_' + r + '_' + c]) {
                formula = window._tableFormulaRegistry[tIdx + '_' + r + '_' + c];
                if (regKey) window._tableFormulaRegistry[regKey] = formula;
              }

              // Strip accidental 'fx' suffix from cell text
              const walker = doc.createTreeWalker(cell, NodeFilter.SHOW_TEXT, null, false);
              let node;
              while (node = walker.nextNode()) {
                if (/\\b\\d+\\s*fx\\b/i.test(node.nodeValue)) {
                  node.nodeValue = node.nodeValue.replace(/(\\d+)\\s*fx\\b/gi, '\$1');
                } else if (node.nodeValue.trim() === 'fx') {
                  node.nodeValue = '';
                }
              }

              if (formula) formula = cleanFormulaText(formula);
              if (formula && formula.startsWith('=')) {
                window._tableFormulaRegistry = window._tableFormulaRegistry || {};
                if (regKey) window._tableFormulaRegistry[regKey] = formula;
                window._tableFormulaRegistry[tIdx + '_' + r + '_' + c] = formula;
                cell.setAttribute('data-formula', formula);
                cell.setAttribute('title', 'Formula: ' + formula);
                cell.classList.add('has-formula');
                let cellVal = null;
                if (liveT && liveT.rows && liveT.rows[r] && liveT.rows[r].cells && liveT.rows[r].cells[c]) {
                  cellVal = liveT.rows[r].cells[c].getAttribute('data-formula-val');
                }
                if (!cellVal) cellVal = cell.getAttribute('data-formula-val');
                if (cellVal != null && cellVal !== '') {
                  cell.setAttribute('data-formula-val', cellVal);
                }
              } else {
                cell.removeAttribute('data-formula');
                cell.removeAttribute('title');
                cell.classList.remove('has-formula');
                if (regKey && window._tableFormulaRegistry) {
                  delete window._tableFormulaRegistry[regKey];
                }
              }
              // Clean out any span that might be inside cell
              cell.querySelectorAll('.formula-badge').forEach(b => b.remove());
            }
          }
        });

        // Ensure table cell references in text have fresh values from tables
        const allSpans = Array.from(doc.querySelectorAll('.table-cell-ref, .mention, span[data-cell-coord]'));
        const refSpans = allSpans.filter(s => s.classList.contains('table-cell-ref') || s.hasAttribute('data-cell-coord') || (s.getAttribute('data-mention') && s.getAttribute('data-mention').indexOf('\$') === 0));
        refSpans.forEach(span => {
          let rawCoord = span.getAttribute('data-cell-coord');
          let tIdx = 0;
          if (!rawCoord) {
            const mentionId = span.getAttribute('data-mention') || '';
            if (mentionId.indexOf('\$') === 0) {
              let cleanId = mentionId.substring(1);
              if (cleanId.toUpperCase().indexOf('T') === 0 && cleanId.indexOf(':') !== -1) {
                const parts = cleanId.split(':');
                tIdx = parseInt(parts[0].substring(1), 10) - 1 || 0;
                cleanId = parts[1];
              }
              rawCoord = cleanId.toUpperCase();
            }
          } else {
            const tAttr = span.getAttribute('data-table-idx');
            if (tAttr) tIdx = parseInt(tAttr, 10);
          }
          if (rawCoord) {
            const targetTable = tables[tIdx] || tables[0];
            if (targetTable) {
              const pos = parseCellCoord(rawCoord);
              if (pos && pos.row >= 0 && pos.row < targetTable.rows.length && pos.col >= 0 && pos.col < targetTable.rows[pos.row].cells.length) {
                const targetCell = targetTable.rows[pos.row].cells[pos.col];
                const formulaVal = targetCell.getAttribute('data-formula-val');
                const freshVal = (formulaVal != null && formulaVal !== '') ? formulaVal : cleanFormulaText(targetCell.innerText || targetCell.textContent || '');
                if (freshVal) {
                  span.textContent = freshVal;
                  span.setAttribute('title', 'Table cell ' + rawCoord + ': "' + freshVal + '" (Live Link)');
                }
              }
            }
            span.classList.add('table-cell-ref');
            span.classList.add('mention');
            span.setAttribute('data-cell-coord', rawCoord);
            span.setAttribute('data-table-idx', tIdx);
            if (!span.getAttribute('data-mention')) {
              const token = '\$' + (tIdx > 0 ? ('T' + (tIdx + 1) + ':' + rawCoord) : rawCoord);
              span.setAttribute('data-mention', token);
            }
          }
        });

        // Ensure inline formulas in text have fresh calculated values from tables
        const formulaSpans = Array.from(doc.querySelectorAll('.inline-formula-pill, span[data-formula]')).filter(s => !s.closest('td, th'));
        formulaSpans.forEach(span => {
          const formula = span.getAttribute('data-formula') || span.getAttribute('data-inline-formula');
          if (formula && formula.startsWith('=')) {
            let tIdx = parseInt(span.getAttribute('data-table-idx'), 10) || 0;
            const targetTable = tables[tIdx] || tables[0];
            if (targetTable) {
              const grid = [];
              for (let r = 0; r < targetTable.rows.length; r++) {
                grid[r] = [];
                for (let c = 0; c < targetTable.rows[r].cells.length; c++) {
                  const curCell = targetTable.rows[r].cells[c];
                  grid[r][c] = curCell.getAttribute('data-formula-val') || cleanFormulaText(curCell.innerText || curCell.textContent || '');
                }
              }
              const res = evaluateFormulaString(formula, grid, -1, -1);
              if (res !== null && !isNaN(res)) {
                span.textContent = String(res);
                span.setAttribute('title', 'Formula: ' + formula + ' = ' + res + ' (Live Calculation)');
              }
            }
            span.classList.add('inline-formula-pill');
            span.setAttribute('data-formula', formula);
            span.setAttribute('data-table-idx', tIdx);
          }
        });

        return doc.body.innerHTML;
      } catch (e) {
        console.warn('cleanAndExportFormulasInHtml error:', e);
        return html;
      }
    }

    function injectFormulasIntoHtml(html) {
      return cleanAndExportFormulasInHtml(html);
    }

    function cleanAndExportMediaStylesInHtml(html) {
      if (!html || html.indexOf('<figure') === -1) return html;
      try {
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        const figures = doc.querySelectorAll('figure.media, figure');
        let modified = false;
        figures.forEach(fig => {
          const url = getMediaUrlFromFigure(fig);
          if (url && window._mediaStyleRegistry && window._mediaStyleRegistry[url]) {
            const reg = window._mediaStyleRegistry[url];
            const rawStyle = fig.getAttribute('style') || '';
            const filtered = rawStyle.split(';').map(s => s.trim()).filter(s => {
              const lower = s.toLowerCase();
              return lower &&
                !lower.startsWith('width:') &&
                !lower.startsWith('max-width:') &&
                !lower.startsWith('margin:') &&
                !lower.startsWith('margin-left:') &&
                !lower.startsWith('margin-right:');
            });
            filtered.push('width:' + reg.width);
            filtered.push('max-width:' + (reg.maxWidth || reg.width));
            filtered.push('margin:' + (reg.margin || '16px auto'));
            fig.setAttribute('style', filtered.join('; ') + ';');
            fig.setAttribute('data-media-width', reg.width);
            modified = true;
          }
        });
        if (modified) {
          return doc.body.innerHTML;
        }
      } catch(e) {
        console.warn('cleanAndExportMediaStylesInHtml error:', e);
      }
      return html;
    }

    function extractAndSeedMediaStylesFromHtml(html) {
      if (!html || html.indexOf('<figure') === -1) return;
      try {
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        const figures = doc.querySelectorAll('figure.media, figure');
        figures.forEach(fig => {
          const url = getMediaUrlFromFigure(fig);
          const rawStyle = fig.getAttribute('style') || '';
          if (url && rawStyle) {
            let width = '';
            let margin = '';
            rawStyle.split(';').forEach(part => {
              const kv = part.split(':');
              if (kv.length >= 2) {
                const k = kv[0].trim().toLowerCase();
                const v = kv.slice(1).join(':').trim();
                if (k === 'width') width = v;
                if (k === 'margin') margin = v;
              }
            });
            if (width) {
              window._mediaStyleRegistry = window._mediaStyleRegistry || {};
              window._mediaStyleRegistry[url] = {
                width: width,
                maxWidth: width,
                margin: margin || '16px auto',
                style: rawStyle
              };
            }
          }
        });
      } catch(e) {
        console.warn('extractAndSeedMediaStylesFromHtml error:', e);
      }
    }

    function applyDirectionToHtml(html, dir) {
      if (!html || typeof html !== 'string') return html;
      try {
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        const targetDir = (dir === 'rtl') ? 'rtl' : 'ltr';
        const targetAlign = (targetDir === 'rtl') ? 'right' : 'left';

        const blocks = doc.querySelectorAll('p, h1, h2, h3, h4, h5, h6, blockquote, ul, ol, table, div:not(.media):not(.page-break)');

        if (blocks.length === 0 && doc.body.textContent.trim()) {
          const p = doc.createElement('p');
          p.setAttribute('dir', targetDir);
          p.style.textAlign = targetAlign;
          p.innerHTML = doc.body.innerHTML;
          doc.body.innerHTML = '';
          doc.body.appendChild(p);
        } else {
          blocks.forEach(el => {
            el.setAttribute('dir', targetDir);
            const currentAlign = el.style.textAlign;
            if (!currentAlign || currentAlign === 'left' || currentAlign === 'right') {
              el.style.textAlign = targetAlign;
            }
          });
        }

        return doc.body.innerHTML;
      } catch (e) {
        console.warn('applyDirectionToHtml error:', e);
        return html;
      }
    }

    function getEditorData() {
      let data = '';
      if (editorInstance) {
        data = editorInstance.getData();
      } else if (isFallback) {
        data = document.getElementById('fallback-content').innerHTML;
      }
      data = applyDirectionToHtml(data, currentTextDir);
      data = cleanAndExportFormulasInHtml(data);
      data = cleanAndExportMediaStylesInHtml(data);
      window._lastExportedHtml = data;
      return data;
    }

    function extractAndSeedFormulasFromHtml(html) {
      try {
        if (!html || html.indexOf('<table') === -1) return;
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        const tables = doc.querySelectorAll('table');
        window._tableFormulaRegistry = window._tableFormulaRegistry || {};
        tables.forEach((t, tIdx) => {
          const tableUid = t.getAttribute('data-table-uid');
          for (let r = 0; r < t.rows.length; r++) {
            for (let c = 0; c < t.rows[r].cells.length; c++) {
              const cell = t.rows[r].cells[c];
              let formula = cell.getAttribute('data-formula') || extractFormulaFromTitle(cell.getAttribute('title'));
              if (!formula) {
                const childF = cell.querySelector('[data-formula]');
                if (childF) formula = childF.getAttribute('data-formula');
              }
              if (!formula) {
                const childT = cell.querySelector('[title*="Formula:"]');
                if (childT) formula = extractFormulaFromTitle(childT.getAttribute('title'));
              }
              if (!formula) {
                const rawTxt = (cell.innerText || cell.textContent || '').trim();
                const cleanTxt = cleanFormulaText(rawTxt);
                if (looksLikeFormula(cleanTxt)) formula = cleanTxt;
              }
              if (formula) {
                const cleanF = normalizeFormulaString(formula);
                if (cleanF && cleanF.startsWith('=')) {
                  if (tableUid) window._tableFormulaRegistry[tableUid + '_' + r + '_' + c] = cleanF;
                  window._tableFormulaRegistry[tIdx + '_' + r + '_' + c] = cleanF;
                }
              }
            }
          }
        });
      } catch(e) {
        console.warn('extractAndSeedFormulasFromHtml error:', e);
      }
    }

    /* CKEditor 41 writes a to-do item whose paragraph has attributes (this app always adds dir/alignment) as
       <label class="todo-list__label_without-description"><input checked></label><p>..</p>, but cannot read the
       checked state back from that form. Re-apply it from the HTML to the to-do items, which share its order. */
    function restoreTodoCheckedState(editor, html) {
      if (!editor || !html || html.indexOf('todo-list') === -1) return;
      try {
        const doc = new DOMParser().parseFromString(html, 'text/html');
        const checkedFlags = Array.from(doc.querySelectorAll('ul.todo-list li')).map(li => {
          const box = Array.from(li.querySelectorAll('input[type=checkbox]')).find(i => i.closest('li') === li);
          return !!(box && box.hasAttribute('checked'));
        });
        if (!checkedFlags.some(Boolean)) return;

        const model = editor.model;
        const items = [];
        const seen = new Map();
        for (const value of model.createRangeIn(model.document.getRoot()).getWalker({ ignoreElementEnd: true })) {
          const el = value.item;
          if (!el.is('element') || el.getAttribute('listType') !== 'todo') continue;
          const id = el.getAttribute('listItemId');
          if (!seen.has(id)) { seen.set(id, []); items.push(id); }
          seen.get(id).push(el);
        }
        model.enqueueChange({ isUndoable: false }, writer => {
          items.forEach((id, i) => {
            if (!checkedFlags[i]) return;
            for (const block of seen.get(id)) {
              if (!block.getAttribute('todoListChecked')) writer.setAttribute('todoListChecked', true, block);
            }
          });
        });
      } catch (e) {
        console.warn('restoreTodoCheckedState error:', e);
      }
    }

    function setEditorData(html) {
      if (window._lastExportedHtml && (html === window._lastExportedHtml || html.trim() === window._lastExportedHtml.trim())) {
        return;
      }

      const cleanHtml = sanitizeTableHtml(html);
      extractAndSeedFormulasFromHtml(cleanHtml);
      extractAndSeedMediaStylesFromHtml(cleanHtml);

      if (editorInstance) {
        const currentData = getEditorData();
        if (currentData === cleanHtml || currentData.trim() === cleanHtml.trim()) {
          reapplyAllMediaStyles();
          return;
        }

        const detected = detectHtmlDirection(cleanHtml);
        currentTextDir = detected;
        const sel = document.getElementById('select-dir');
        if (sel) sel.value = detected;

        editorInstance.setData(cleanHtml);
        restoreTodoCheckedState(editorInstance, cleanHtml);
        setTimeout(() => {
          changeLanguage(detected, false);
          scanAndRegisterTableFormulas();
          evaluateAllTableFormulas(false);
          reapplyAllMediaStyles();
        }, 80);
      } else if (isFallback) {
        const detected = detectHtmlDirection(cleanHtml);
        currentTextDir = detected;
        const sel = document.getElementById('select-dir');
        if (sel) sel.value = detected;

        document.getElementById('fallback-content').innerHTML = cleanHtml;
        changeLanguage(detected, false);
        scheduleOutlineRefresh();
        setTimeout(() => {
          scanAndRegisterTableFormulas();
          evaluateAllTableFormulas(false);
          reapplyAllMediaStyles();
        }, 80);
        postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
      }
    }

    function getTextPreview(html, maxLen) {
      const div = document.createElement('div');
      div.innerHTML = html;
      const text = div.textContent || div.innerText || '';
      return text.substring(0, maxLen) + (text.length > maxLen ? '...' : '');
    }

    function escapeHtml(str) {
      const div = document.createElement('div');
      div.appendChild(document.createTextNode(str));
      return div.innerHTML;
    }

    function updateParaCount() {
      const data = getEditorData();
      if (!data) return;
      const parser = new DOMParser();
      const doc = parser.parseFromString(data, 'text/html');
      const paras = doc.body.children.length;
      document.getElementById('para-count').textContent = 'Paragraphs: ' + paras;
    }

    /* The element that actually scrolls the document (.ck-editor__main in the normal layout) */
    function getEditorScrollContainer(editable) {
      for (let el = editable; el && el !== document.body; el = el.parentElement) {
        const overflowY = getComputedStyle(el).overflowY;
        if ((overflowY === 'auto' || overflowY === 'scroll') && el.scrollHeight > el.clientHeight + 1) return el;
      }
      return document.scrollingElement || document.documentElement;
    }

    function updatePageIndicator() {
      const editable = document.querySelector('.ck-content, #fallback-content');
      const indicator = document.getElementById('page-indicator');
      if (!editable || !indicator) return;
      /* Estimate page based on content height (A4 ≈ 1120px at 96dpi) */
      const pageHeight = 1120;
      const contentHeight = editable.scrollHeight;
      const pages = Math.max(1, Math.ceil(contentHeight / pageHeight));

      const scroller = getEditorScrollContainer(editable);
      const isPageScroller = scroller === document.scrollingElement || scroller === document.documentElement;
      const viewTop = isPageScroller ? 0 : scroller.getBoundingClientRect().top;
      const viewHeight = isPageScroller ? window.innerHeight : scroller.clientHeight;
      /* Page under the middle of the visible area; the last page once scrolled to the bottom */
      const visibleTopInContent = viewTop - editable.getBoundingClientRect().top;
      const atBottom = scroller.scrollTop + scroller.clientHeight >= scroller.scrollHeight - 2;
      let currentPage = atBottom && scroller.scrollTop > 0
        ? pages
        : Math.floor((visibleTopInContent + viewHeight / 2) / pageHeight) + 1;
      currentPage = Math.min(pages, Math.max(1, currentPage));
      indicator.textContent = 'Page ' + currentPage + ' of ' + pages;
    }

    let pageIndicatorFrame = 0;
    function schedulePageIndicatorUpdate() {
      if (pageIndicatorFrame) return;
      pageIndicatorFrame = requestAnimationFrame(() => {
        pageIndicatorFrame = 0;
        updatePageIndicator();
      });
    }
    /* scroll does not bubble; capture catches the editor's inner scroll container too */
    window.addEventListener('scroll', schedulePageIndicatorUpdate, true);
    window.addEventListener('resize', schedulePageIndicatorUpdate);

    /* ====== UNIVERSAL TABLE FORMULA EVALUATOR ====== */
    function cleanFormulaText(raw) {
      if (!raw) return '';
      let s = String(raw);
      let clean = '';
      for (let i = 0; i < s.length; i++) {
        const c = s.charCodeAt(i);
        if (c === 8203 || c === 8204 || c === 8205 || c === 65279) continue;
        if (c === 160 || c === 10 || c === 13 || c === 9) { clean += ' '; continue; }
        clean += s[i];
      }
      clean = clean.trim();
      clean = clean.replace(/\\s*\\bfx\\b/gi, '').trim();
      const idx = clean.indexOf('=');
      if (idx !== -1) {
        const before = clean.substring(0, idx).trim();
        if (before === '') {
          return clean.substring(idx).trim();
        }
      }
      return clean;
    }

    function looksLikeFormula(raw) {
      if (!raw) return false;
      const s = cleanFormulaText(raw).trim().toUpperCase();
      if (s.startsWith('=')) return true;
      if (/^(SUM|AVG|AVERAGE|COUNT|MAX|MIN|PRODUCT|ROUND)\\s*\\(/i.test(s)) return true;
      if (/^[A-Z]+[0-9]+\\s*[+\\-*/]/.test(s)) return true;
      return false;
    }

    function normalizeFormulaString(raw) {
      if (!raw) return '';
      let s = cleanFormulaText(raw);
      if (s.startsWith('=')) {
        s = s.substring(1).trim();
      }
      // If user typed e.g. (SUM(A3+B3+C3+D3) with extra leading paren
      let openCount = s.split('(').length - 1;
      let closeCount = s.split(')').length - 1;
      if (s.startsWith('(') && openCount > closeCount) {
        s = s.substring(1).trim();
        openCount--;
      }
      // Auto-close any unclosed parens at the end
      while (openCount > closeCount) {
        s += ')';
        closeCount++;
      }
      return s ? ('=' + s) : '';
    }

    function extractNumber(raw) {
      if (!raw) return 0;
      let s = String(raw).trim();
      if (s.indexOf('fx') !== -1) {
        s = s.replace(/\\s*\\bfx\\b/gi, '').trim();
      }
      let numStr = '';
      let hasDot = false;
      let isNegative = false;
      for (let i = 0; i < s.length; i++) {
        const ch = s[i];
        if (ch >= '0' && ch <= '9') {
          numStr += ch;
        } else if (ch === '-' && numStr.length === 0) {
          isNegative = true;
        } else if (ch === '.' && !hasDot) {
          numStr += '.';
          hasDot = true;
        }
      }
      if (!numStr) return 0;
      const val = parseFloat(numStr);
      return isNaN(val) ? 0 : (isNegative ? -val : val);
    }

    function parseCellCoord(coordStr) {
      if (!coordStr || typeof coordStr !== 'string') return null;
      const s = coordStr.trim().toUpperCase();
      let colLetters = '', rowDigits = '';
      let i = 0;
      while (i < s.length && s.charCodeAt(i) >= 65 && s.charCodeAt(i) <= 90) {
        colLetters += s[i];
        i++;
      }
      while (i < s.length && s.charCodeAt(i) >= 48 && s.charCodeAt(i) <= 57) {
        rowDigits += s[i];
        i++;
      }
      if (colLetters.length === 0 || rowDigits.length === 0 || i !== s.length) return null;
      let col = 0;
      for (let c = 0; c < colLetters.length; c++) {
        col = col * 26 + (colLetters.charCodeAt(c) - 64);
      }
      return { col: col - 1, row: parseInt(rowDigits, 10) - 1 };
    }

    function evaluateFormulaString(formulaStr, grid, currentR, currentC) {
      if (!formulaStr) return null;
      let rawExpr = cleanFormulaText(formulaStr);
      if (rawExpr.indexOf('=') === 0) {
        rawExpr = rawExpr.substring(1).trim();
      }
      if (!rawExpr) return null;

      // Normalize table prefixes, dollar signs, and bracketed pill notations:
      rawExpr = rawExpr.replace(/\\\$?T[0-9]+:([A-Za-z]+[0-9]+)/gi, '\$1');
      rawExpr = rawExpr.replace(/\\\$([A-Za-z]+[0-9]+)/g, '\$1');
      rawExpr = rawExpr.replace(/\\[(?:📊|fx)?\\s*([0-9]+(?:\\.[0-9]+)?)\\s*\\]/gi, '\$1');

      function getCellValue(cCoord) {
        const pos = parseCellCoord(cCoord);
        if (!pos) return 0;
        if (pos.row >= 0 && pos.row < grid.length && pos.col >= 0 && pos.col < grid[pos.row].length) {
          return extractNumber(grid[pos.row][pos.col]);
        }
        return 0;
      }

      function getRangeValues(c1, c2) {
        const p1 = parseCellCoord(c1);
        const p2 = parseCellCoord(c2);
        if (!p1 || !p2) return [];
        const minR = Math.min(p1.row, p2.row), maxR = Math.max(p1.row, p2.row);
        const minC = Math.min(p1.col, p2.col), maxC = Math.max(p1.col, p2.col);
        const vals = [];
        for (let r = minR; r <= maxR; r++) {
          for (let c = minC; c <= maxC; c++) {
            if (r === currentR && c === currentC) continue;
            if (r >= 0 && r < grid.length && c >= 0 && c < grid[r].length) {
              const raw = grid[r][c];
              if (raw && /[0-9]/.test(String(raw))) {
                vals.push(extractNumber(raw));
              }
            }
          }
        }
        return vals;
      }

      function getAboveValues() {
        const vals = [];
        for (let r = 0; r < currentR; r++) {
          if (r < grid.length && currentC < grid[r].length) {
            const raw = grid[r][currentC];
            if (raw && /[0-9]/.test(String(raw))) {
              vals.push(extractNumber(raw));
            }
          }
        }
        return vals;
      }

      function getLeftValues() {
        const vals = [];
        for (let c = 0; c < currentC; c++) {
          if (currentR < grid.length && c < grid[currentR].length) {
            const raw = grid[currentR][c];
            if (raw && /[0-9]/.test(String(raw))) {
              vals.push(extractNumber(raw));
            }
          }
        }
        return vals;
      }

      function getRightValues() {
        const vals = [];
        if (currentR < grid.length) {
          for (let c = currentC + 1; c < grid[currentR].length; c++) {
            const raw = grid[currentR][c];
            if (raw && /[0-9]/.test(String(raw))) {
              vals.push(extractNumber(raw));
            }
          }
        }
        return vals;
      }

      function getBelowValues() {
        const vals = [];
        for (let r = currentR + 1; r < grid.length; r++) {
          if (currentC < grid[r].length) {
            const raw = grid[r][currentC];
            if (raw && /[0-9]/.test(String(raw))) {
              vals.push(extractNumber(raw));
            }
          }
        }
        return vals;
      }

      let expr = rawExpr;

      // Normalize spaces around parentheses: e.g. SUM ( ABOVE ) -> SUM(ABOVE)
      expr = expr.split('(').map(function(s) { return s.trimEnd(); }).join('(').split(')').map(function(s) { return s.trimStart(); }).join(')');

      // 1. SUM(ABOVE), SUM(UP), SUM()
      expr = expr.replace(/SUM\\(\\s*(?:ABOVE|UP)?\\s*\\)/gi, () => {
        const vals = getAboveValues();
        return vals.reduce((a, b) => a + b, 0);
      });

      // 2. AVG(ABOVE), AVERAGE(ABOVE)
      expr = expr.replace(/(?:AVG|AVERAGE)\\(\\s*(?:ABOVE|UP)?\\s*\\)/gi, () => {
        const vals = getAboveValues();
        return vals.length > 0 ? (vals.reduce((a, b) => a + b, 0) / vals.length) : 0;
      });

      // 3. MIN(ABOVE)
      expr = expr.replace(/MIN\\(\\s*(?:ABOVE|UP)?\\s*\\)/gi, () => {
        const vals = getAboveValues();
        return vals.length > 0 ? Math.min.apply(null, vals) : 0;
      });

      // 4. MAX(ABOVE)
      expr = expr.replace(/MAX\\(\\s*(?:ABOVE|UP)?\\s*\\)/gi, () => {
        const vals = getAboveValues();
        return vals.length > 0 ? Math.max.apply(null, vals) : 0;
      });

      // 5. COUNT(ABOVE)
      expr = expr.replace(/COUNT\\(\\s*(?:ABOVE|UP)?\\s*\\)/gi, () => {
        return getAboveValues().length;
      });

      // 6. SUM(LEFT)
      expr = expr.replace(/SUM\\(\\s*LEFT\\s*\\)/gi, () => {
        const vals = getLeftValues();
        return vals.reduce((a, b) => a + b, 0);
      });

      // 6a. AVG(LEFT), AVERAGE(LEFT)
      expr = expr.replace(/(?:AVG|AVERAGE)\\(\\s*LEFT\\s*\\)/gi, () => {
        const vals = getLeftValues();
        return vals.length > 0 ? (vals.reduce((a, b) => a + b, 0) / vals.length) : 0;
      });

      // 6b. MIN(LEFT), MAX(LEFT), COUNT(LEFT)
      expr = expr.replace(/MIN\\(\\s*LEFT\\s*\\)/gi, () => {
        const vals = getLeftValues();
        return vals.length > 0 ? Math.min.apply(null, vals) : 0;
      });
      expr = expr.replace(/MAX\\(\\s*LEFT\\s*\\)/gi, () => {
        const vals = getLeftValues();
        return vals.length > 0 ? Math.max.apply(null, vals) : 0;
      });
      expr = expr.replace(/COUNT\\(\\s*LEFT\\s*\\)/gi, () => {
        return getLeftValues().length;
      });

      // 6c. Directional RIGHT functions
      expr = expr.replace(/SUM\\(\\s*RIGHT\\s*\\)/gi, () => {
        const vals = getRightValues();
        return vals.reduce((a, b) => a + b, 0);
      });
      expr = expr.replace(/(?:AVG|AVERAGE)\\(\\s*RIGHT\\s*\\)/gi, () => {
        const vals = getRightValues();
        return vals.length > 0 ? (vals.reduce((a, b) => a + b, 0) / vals.length) : 0;
      });
      expr = expr.replace(/MIN\\(\\s*RIGHT\\s*\\)/gi, () => {
        const vals = getRightValues();
        return vals.length > 0 ? Math.min.apply(null, vals) : 0;
      });
      expr = expr.replace(/MAX\\(\\s*RIGHT\\s*\\)/gi, () => {
        const vals = getRightValues();
        return vals.length > 0 ? Math.max.apply(null, vals) : 0;
      });
      expr = expr.replace(/COUNT\\(\\s*RIGHT\\s*\\)/gi, () => {
        return getRightValues().length;
      });

      // 6d. Directional BELOW / DOWN functions
      expr = expr.replace(/SUM\\(\\s*(?:BELOW|DOWN)\\s*\\)/gi, () => {
        const vals = getBelowValues();
        return vals.reduce((a, b) => a + b, 0);
      });
      expr = expr.replace(/(?:AVG|AVERAGE)\\(\\s*(?:BELOW|DOWN)\\s*\\)/gi, () => {
        const vals = getBelowValues();
        return vals.length > 0 ? (vals.reduce((a, b) => a + b, 0) / vals.length) : 0;
      });
      expr = expr.replace(/MIN\\(\\s*(?:BELOW|DOWN)\\s*\\)/gi, () => {
        const vals = getBelowValues();
        return vals.length > 0 ? Math.min.apply(null, vals) : 0;
      });
      expr = expr.replace(/MAX\\(\\s*(?:BELOW|DOWN)\\s*\\)/gi, () => {
        const vals = getBelowValues();
        return vals.length > 0 ? Math.max.apply(null, vals) : 0;
      });
      expr = expr.replace(/COUNT\\(\\s*(?:BELOW|DOWN)\\s*\\)/gi, () => {
        return getBelowValues().length;
      });

      // 7. SUM(A1:A2) or SUM(A1..A2)
      expr = expr.replace(/SUM\\(\\s*([A-Za-z]+[0-9]+)\\s*(?::|\\.\\.)\\s*([A-Za-z]+[0-9]+)\\s*\\)/gi, (m, c1, c2) => {
        const vals = getRangeValues(c1, c2);
        return vals.reduce((a, b) => a + b, 0);
      });

      // 8. AVG(A1:A2)
      expr = expr.replace(/(?:AVG|AVERAGE)\\(\\s*([A-Za-z]+[0-9]+)\\s*(?::|\\.\\.)\\s*([A-Za-z]+[0-9]+)\\s*\\)/gi, (m, c1, c2) => {
        const vals = getRangeValues(c1, c2);
        return vals.length > 0 ? (vals.reduce((a, b) => a + b, 0) / vals.length) : 0;
      });

      // 9. MIN(A1:A2)
      expr = expr.replace(/MIN\\(\\s*([A-Za-z]+[0-9]+)\\s*(?::|\\.\\.)\\s*([A-Za-z]+[0-9]+)\\s*\\)/gi, (m, c1, c2) => {
        const vals = getRangeValues(c1, c2);
        return vals.length > 0 ? Math.min.apply(null, vals) : 0;
      });

      // 10. MAX(A1:A2)
      expr = expr.replace(/MAX\\(\\s*([A-Za-z]+[0-9]+)\\s*(?::|\\.\\.)\\s*([A-Za-z]+[0-9]+)\\s*\\)/gi, (m, c1, c2) => {
        const vals = getRangeValues(c1, c2);
        return vals.length > 0 ? Math.max.apply(null, vals) : 0;
      });

      // 11. COUNT(A1:A2)
      expr = expr.replace(/COUNT\\(\\s*([A-Za-z]+[0-9]+)\\s*(?::|\\.\\.)\\s*([A-Za-z]+[0-9]+)\\s*\\)/gi, (m, c1, c2) => {
        return getRangeValues(c1, c2).length;
      });

      // 12. Helper for comma-separated arguments: SUM(A1, A2, 10), AVG(A1, B1), etc.
      const parseCommaVals = (inner) => {
        const parts = inner.split(',');
        const vals = [];
        for (let i = 0; i < parts.length; i++) {
          let p = parts[i].trim();
          p = p.replace(/^\\\$?T[0-9]+:/i, '').replace(/^\\\$/, '');
          const coord = parseCellCoord(p);
          if (coord) vals.push(getCellValue(p));
          else { const n = parseFloat(p); if (!isNaN(n)) vals.push(n); }
        }
        return vals;
      };

      expr = expr.replace(/SUM\\(([^)]+)\\)/gi, (m, inner) => {
        if (inner.indexOf(',') !== -1) {
          const vals = parseCommaVals(inner);
          return vals.reduce((a, b) => a + b, 0);
        }
        return '(' + inner + ')';
      });

      expr = expr.replace(/(?:AVG|AVERAGE)\\(([^)]+)\\)/gi, (m, inner) => {
        if (inner.indexOf(',') !== -1) {
          const vals = parseCommaVals(inner);
          return vals.length > 0 ? (vals.reduce((a, b) => a + b, 0) / vals.length) : 0;
        }
        return '(' + inner + ')';
      });

      expr = expr.replace(/MIN\\(([^)]+)\\)/gi, (m, inner) => {
        if (inner.indexOf(',') !== -1) {
          const vals = parseCommaVals(inner);
          return vals.length > 0 ? Math.min.apply(null, vals) : 0;
        }
        return '(' + inner + ')';
      });

      expr = expr.replace(/MAX\\(([^)]+)\\)/gi, (m, inner) => {
        if (inner.indexOf(',') !== -1) {
          const vals = parseCommaVals(inner);
          return vals.length > 0 ? Math.max.apply(null, vals) : 0;
        }
        return '(' + inner + ')';
      });

      expr = expr.replace(/COUNT\\(([^)]+)\\)/gi, (m, inner) => {
        if (inner.indexOf(',') !== -1) {
          const vals = parseCommaVals(inner);
          return vals.length;
        }
        return '(' + inner + ')';
      });

      // 13. Replace individual coordinates like A1, A2, B3 (with optional \$) with cell values
      expr = expr.replace(/\\\$?([A-Za-z]+[0-9]+)/g, (match, coordName) => {
        const coord = parseCellCoord(coordName);
        if (coord) {
          return getCellValue(coordName);
        }
        return match;
      });

      // Safely evaluate math expression using robust parser (no Function/eval, no SyntaxErrors)
      return safeEvalMath(expr);
    }

    function safeEvalMath(expr) {
      if (!expr || typeof expr !== 'string') return null;
      var tokens = [];
      var i = 0;
      expr = expr.trim();
      while (i < expr.length) {
        var ch = expr.charAt(i);
        if (ch === ' ' || ch === '\\t') {
          i++;
          continue;
        }
        if (ch === '+' || ch === '-' || ch === '*' || ch === '/' || ch === '(' || ch === ')' || ch === '%') {
          tokens.push(ch);
          i++;
          continue;
        }
        if ((ch >= '0' && ch <= '9') || ch === '.') {
          var numStr = '';
          while (i < expr.length) {
            var c = expr.charAt(i);
            if ((c >= '0' && c <= '9') || c === '.') {
              numStr += c;
              i++;
            } else {
              break;
            }
          }
          var num = parseFloat(numStr);
          if (isNaN(num)) return null;
          tokens.push(num);
          continue;
        }
        return null;
      }

      if (tokens.length === 0) return null;

      // Handle unary plus/minus
      var processed = [];
      for (var j = 0; j < tokens.length; j++) {
        var t = tokens[j];
        if ((t === '-' || t === '+') && (j === 0 || tokens[j - 1] === '(' || tokens[j - 1] === '+' || tokens[j - 1] === '-' || tokens[j - 1] === '*' || tokens[j - 1] === '/')) {
          if (j + 1 < tokens.length && typeof tokens[j + 1] === 'number') {
            processed.push(t === '-' ? -tokens[j + 1] : tokens[j + 1]);
            j++;
          } else {
            return null;
          }
        } else {
          processed.push(t);
        }
      }

      // Check adjacent numbers without operator
      for (var k = 0; k < processed.length - 1; k++) {
        if (typeof processed[k] === 'number' && typeof processed[k + 1] === 'number') {
          return null;
        }
      }

      var pos = 0;
      function parseExpr() {
        var val = parseTerm();
        if (val === null) return null;
        while (pos < processed.length && (processed[pos] === '+' || processed[pos] === '-')) {
          var op = processed[pos++];
          var nextVal = parseTerm();
          if (nextVal === null) return null;
          if (op === '+') val += nextVal;
          else val -= nextVal;
        }
        return val;
      }

      function parseTerm() {
        var val = parseFactor();
        if (val === null) return null;
        while (pos < processed.length && (processed[pos] === '*' || processed[pos] === '/')) {
          var op = processed[pos++];
          var nextVal = parseFactor();
          if (nextVal === null) return null;
          if (op === '*') val *= nextVal;
          else {
            if (nextVal === 0) return 0;
            val /= nextVal;
          }
        }
        return val;
      }

      /* Postfix % (as in Excel): divides the number or bracketed group before it by 100, binding tighter than * and / */
      function parseFactor() {
        var val = parsePrimary();
        if (val === null) return null;
        while (pos < processed.length && processed[pos] === '%') {
          pos++;
          val /= 100;
        }
        return val;
      }

      function parsePrimary() {
        if (pos >= processed.length) return null;
        var t = processed[pos++];
        if (typeof t === 'number') return t;
        if (t === '(') {
          var val = parseExpr();
          if (pos >= processed.length || processed[pos++] !== ')') return null;
          return val;
        }
        return null;
      }

      var result = parseExpr();
      if (pos !== processed.length || result === null || !isFinite(result)) return null;
      return Math.round(result * 10000) / 10000;
    }

    window._tableFormulaRegistry = window._tableFormulaRegistry || {};

    function _getModelCellText(cell) {
      let text = '';
      try {
        for (const child of cell.getChildren()) {
          if (child.is && (child.is('\$text') || child.is('text'))) {
            text += child.data;
          } else if (child.getChildren) {
            text += _getModelCellText(child);
          }
        }
      } catch(e) {}
      return text.trim();
    }

    function _removeModelFormulaAttribute(editor, tableIdx, r, c) {
      try {
        if (!editor || !editor.model) return;
        const root = editor.model.document.getRoot();
        let curT = 0;
        for (const child of root.getChildren()) {
          if (child.name === 'table') {
            if (curT === tableIdx) {
              const rows = Array.from(child.getChildren()).filter(n => n.name === 'tableRow');
              if (rows[r]) {
                const cells = Array.from(rows[r].getChildren()).filter(n => n.name === 'tableCell');
                const targetCell = cells[c];
                if (targetCell && (targetCell.hasAttribute('dataFormula') || targetCell.hasAttribute('dataFormulaVal'))) {
                  const removeAttr = (writer) => {
                    try {
                      writer.removeAttribute('dataFormula', targetCell);
                      writer.removeAttribute('dataFormulaVal', targetCell);
                    } catch(e) {}
                  };
                  let batch = null;
                  if (typeof editor.model.createBatch === 'function') {
                    try { batch = editor.model.createBatch({ isUndoable: false }); } catch (e) { batch = null; }
                  }
                  if (batch && typeof editor.model.enqueueChange === 'function') {
                    editor.model.enqueueChange(batch, removeAttr);
                  } else if (typeof editor.model.change === 'function') {
                    editor.model.change(removeAttr);
                  }
                }
              }
              break;
            }
            curT++;
          }
        }
      } catch(e) {}
    }

    function scanAndRegisterTableFormulas() {
      const liveTables = getEditorLiveTables();
      window._tableFormulaRegistry = window._tableFormulaRegistry || {};
      const validKeys = new Set();

      liveTables.forEach((table, tableIdx) => {
        const tableUid = getTableUid(table);
        const rows = table.rows;
        if (!rows) return;
        for (let r = 0; r < rows.length; r++) {
          for (let c = 0; c < rows[r].cells.length; c++) {
            const cell = rows[r].cells[c];
            const regKey = tableUid + '_' + r + '_' + c;
            const idxKey = tableIdx + '_' + r + '_' + c;
            validKeys.add(regKey);
            validKeys.add(idxKey);

            let rawText = '';
            for (let n of cell.childNodes) {
              if (n.classList && n.classList.contains('formula-badge')) continue;
              rawText += (n.innerText || n.textContent || '');
            }
            rawText = rawText.replace(/\\bfx\\b/gi, '').trim();
            const cleanTxt = cleanFormulaText(rawText);

            // Find formula from cell attributes, children, or registry
            let formula = null;
            if (looksLikeFormula(cleanTxt)) {
              formula = normalizeFormulaString(cleanTxt);
            } else if (cell.getAttribute && cell.getAttribute('data-formula')) {
              formula = normalizeFormulaString(cell.getAttribute('data-formula'));
            } else if (cell.getAttribute && cell.getAttribute('title')) {
              const f = extractFormulaFromTitle(cell.getAttribute('title'));
              if (f) formula = normalizeFormulaString(f);
            } else if (cell.querySelector && cell.querySelector('[data-formula]')) {
              formula = normalizeFormulaString(cell.querySelector('[data-formula]').getAttribute('data-formula'));
            } else if (window._tableFormulaRegistry[regKey]) {
              formula = normalizeFormulaString(window._tableFormulaRegistry[regKey]);
            } else if (window._tableFormulaRegistry[idxKey]) {
              formula = normalizeFormulaString(window._tableFormulaRegistry[idxKey]);
            }

            const isFocused = cell.contains(document.activeElement);

            // User ONLY overwrites formula if actively typing/editing THIS SPECIFIC cell and entered non-formula plain text
            if (isFocused && !looksLikeFormula(cleanTxt) && cleanTxt !== '') {
              const lastVal = cell.getAttribute ? cell.getAttribute('data-formula-val') : null;
              // If user actively changed cell content to something other than the calculated value:
              if (lastVal !== null && cleanTxt !== lastVal) {
                // User intentionally replaced formula with static text
                if (cell.removeAttribute) {
                  cell.removeAttribute('data-formula');
                  cell.removeAttribute('title');
                  cell.removeAttribute('data-formula-val');
                  cell.classList.remove('has-formula');
                }
                const b = cell.querySelector('.formula-badge');
                if (b) b.remove();
                delete window._tableFormulaRegistry[regKey];
                delete window._tableFormulaRegistry[idxKey];
                if (editorInstance && editorInstance.model) {
                  _removeModelFormulaAttribute(editorInstance, tableIdx, r, c);
                }
                continue;
              }
            }

            if (formula && formula.startsWith('=')) {
              window._tableFormulaRegistry[regKey] = formula;
              window._tableFormulaRegistry[idxKey] = formula;
              cell.setAttribute('data-formula', formula);
              cell.setAttribute('title', 'Formula: ' + formula + ' (Click fx to edit)');
              cell.classList.add('has-formula');
            }
          }
        }
      });

      // Prune keys only for cells or tables that have actually been deleted from DOM
      for (let k in window._tableFormulaRegistry) {
        if (!validKeys.has(k)) {
          delete window._tableFormulaRegistry[k];
        }
      }
    }

    function getCellFormula(cell, tableIdx, r, c) {
      if (!cell) return null;
      const table = cell.closest('table');
      const tableUid = table ? getTableUid(table) : null;
      const liveTables = getEditorLiveTables();
      const tIdx = (tableIdx !== undefined && tableIdx !== null) ? tableIdx : (table ? Math.max(0, liveTables.indexOf(table)) : 0);
      const row = cell.closest('tr');
      const rIdx = (r !== undefined) ? r : (row ? row.rowIndex : 0);
      const cIdx = (c !== undefined) ? c : (cell.cellIndex !== undefined ? cell.cellIndex : 0);
      const regKey = tableUid ? (tableUid + '_' + rIdx + '_' + cIdx) : null;
      const idxKey = tIdx + '_' + rIdx + '_' + cIdx;

      // 1. Direct text check
      let rawText = '';
      for (let n of cell.childNodes) {
        if (n.classList && n.classList.contains('formula-badge')) continue;
        rawText += (n.innerText || n.textContent || '');
      }
      const directText = cleanFormulaText(rawText);
      if (looksLikeFormula(directText)) {
        const nf = normalizeFormulaString(directText);
        if (regKey) window._tableFormulaRegistry[regKey] = nf;
        window._tableFormulaRegistry[idxKey] = nf;
        return nf;
      }

      // 2. data-formula attribute on cell or child
      if (cell.getAttribute && cell.getAttribute('data-formula')) {
        const nf = normalizeFormulaString(cell.getAttribute('data-formula'));
        if (regKey) window._tableFormulaRegistry[regKey] = nf;
        window._tableFormulaRegistry[idxKey] = nf;
        return nf;
      }
      if (cell.getAttribute && cell.getAttribute('title')) {
        const f = extractFormulaFromTitle(cell.getAttribute('title'));
        if (f) {
          const nf = normalizeFormulaString(f);
          if (regKey) window._tableFormulaRegistry[regKey] = nf;
          window._tableFormulaRegistry[idxKey] = nf;
          return nf;
        }
      }
      if (cell.querySelector) {
        const withFormula = cell.querySelectorAll('[data-formula]');
        for (let i = 0; i < withFormula.length; i++) {
          const nf = normalizeFormulaString(withFormula[i].getAttribute('data-formula'));
          if (nf) {
            if (regKey) window._tableFormulaRegistry[regKey] = nf;
            window._tableFormulaRegistry[idxKey] = nf;
            return nf;
          }
        }
        const withTitle = cell.querySelectorAll('[title*="Formula:"]');
        for (let i = 0; i < withTitle.length; i++) {
          const f = extractFormulaFromTitle(withTitle[i].getAttribute('title'));
          if (f) {
            const nf = normalizeFormulaString(f);
            if (regKey) window._tableFormulaRegistry[regKey] = nf;
            window._tableFormulaRegistry[idxKey] = nf;
            return nf;
          }
        }
      }

      // 3. Registry check (by tableUid key or by index key)
      const regFormula = (regKey && window._tableFormulaRegistry && window._tableFormulaRegistry[regKey]) ||
                         (window._tableFormulaRegistry && window._tableFormulaRegistry[idxKey]);
      if (regFormula) {
        const nf = normalizeFormulaString(regFormula);
        if (cell.setAttribute) {
          cell.setAttribute('data-formula', nf);
          cell.setAttribute('title', 'Formula: ' + nf + ' (Click fx to edit)');
          cell.classList.add('has-formula');
        }
        if (regKey) window._tableFormulaRegistry[regKey] = nf;
        window._tableFormulaRegistry[idxKey] = nf;
        return nf;
      }

      return null;
    }

    function evaluateAllTableFormulas(showToast = false) {
      autoUpdateTableFormulasDOM();
      if (showToast) {
        showToastMsg('⚡ Table formulas calculated in real time');
      }
    }

    let _liveFormulaTimer = null;

    function scheduleLiveFormulaRecalc() {
      if (_liveFormulaTimer) clearTimeout(_liveFormulaTimer);
      _liveFormulaTimer = setTimeout(() => {
        try {
          autoUpdateTableFormulasDOM();
        } catch (e) {
          console.warn('Auto formula recalc error:', e);
        }
      }, 20);
    }
    window.scheduleLiveFormulaRecalc = scheduleLiveFormulaRecalc;

    function _syncModelFormulaCell(editor, tableIdx, r, c, resStr, formula) {
      try {
        if (!editor || !editor.model) return;
        const root = editor.model.document.getRoot();
        let curT = 0;
        for (const child of root.getChildren()) {
          if (child.name === 'table') {
            if (curT === tableIdx) {
              const rows = Array.from(child.getChildren()).filter(n => n.name === 'tableRow');
              if (rows[r]) {
                const cells = Array.from(rows[r].getChildren()).filter(n => n.name === 'tableCell');
                const targetCell = cells[c];
                if (targetCell) {
                  const currentText = _getModelCellText(targetCell);
                  const currentFormula = targetCell.getAttribute('dataFormula');
                  const currentVal = targetCell.getAttribute('dataFormulaVal');
                  // Only touch model if text, formula, or formulaVal actually changed!
                  if (currentText === String(resStr).trim() && currentFormula === formula && currentVal === String(resStr)) {
                    return;
                  }
                  
                  const updateCell = (writer) => {
                    const range = writer.createRangeIn(targetCell);
                    writer.remove(range);
                    const p = writer.createElement('paragraph');
                    writer.insert(p, targetCell, 0);
                    writer.insertText(String(resStr), { bold: true }, p, 0);
                    if (formula) {
                      try {
                        writer.setAttribute('dataFormula', formula, targetCell);
                        writer.setAttribute('dataFormulaVal', String(resStr), targetCell);
                      } catch (e) {}
                    }
                  };

                  // CRITICAL: Use non-undoable batch so formula sync NEVER enters undo history!
                  let batch = null;
                  if (typeof editor.model.createBatch === 'function') {
                    try { batch = editor.model.createBatch({ isUndoable: false }); } catch (e) { batch = null; }
                  }
                  if (batch && typeof editor.model.enqueueChange === 'function') {
                    editor.model.enqueueChange(batch, updateCell);
                  } else if (typeof editor.model.change === 'function') {
                    editor.model.change(updateCell);
                  }
                }
              }
              break;
            }
            curT++;
          }
        }
      } catch(e) {
        console.warn('Model cell sync error:', e);
      }
    }

    function ensureFormulaBadgesDOM() {
      try {
        const liveTables = getEditorLiveTables();
        liveTables.forEach((table, tableIdx) => {
          for (let r = 0; r < table.rows.length; r++) {
            for (let c = 0; c < table.rows[r].cells.length; c++) {
              const cell = table.rows[r].cells[c];
              const formula = getCellFormula(cell, tableIdx, r, c);
              if (formula && formula.startsWith('=')) {
                // Remove legacy badge inside p if present
                const p = cell.querySelector('p');
                if (p) {
                  const pBadge = p.querySelector('.formula-badge');
                  if (pBadge) pBadge.remove();
                }
                let badge = cell.querySelector('.formula-badge');
                if (!badge) {
                  badge = document.createElement('span');
                  badge.className = 'formula-badge';
                  badge.setAttribute('contenteditable', 'false');
                  badge.setAttribute('data-formula', formula);
                  badge.title = 'Formula: ' + formula + ' (Click to edit)';
                  badge.textContent = 'fx';
                  cell.appendChild(badge);
                } else {
                  badge.setAttribute('data-formula', formula);
                  badge.title = 'Formula: ' + formula + ' (Click to edit)';
                  if (badge.parentElement !== cell) {
                    cell.appendChild(badge);
                  }
                }
              } else {
                const leftovers = cell.querySelectorAll('.formula-badge');
                leftovers.forEach(b => b.remove());
              }
            }
          }
        });
      } catch (e) {
        console.warn('ensureFormulaBadgesDOM error:', e);
      }
    }
    window.ensureFormulaBadgesDOM = ensureFormulaBadgesDOM;

    function autoUpdateTableFormulasDOM(forceCell = null) {
      /* An explicit apply (forceCell) must not be dropped just because a background recalc ran moments ago */
      if (window._isUpdatingFormula && !forceCell) return;
      const liveTables = getEditorLiveTables();
      if (liveTables.length === 0) return;

      window._isUpdatingFormula = true;
      try {
        scanAndRegisterTableFormulas();

        let anyUpdated = false;

        liveTables.forEach((liveTable, tableIdx) => {
          const liveRows = liveTable.rows;
          if (!liveRows || liveRows.length === 0) return;

          // 1. Check if table has any formula
          let hasFormula = false;
          for (let r = 0; r < liveRows.length; r++) {
            for (let c = 0; c < liveRows[r].cells.length; c++) {
              if (getCellFormula(liveRows[r].cells[c], tableIdx, r, c)) {
                hasFormula = true;
                break;
              }
            }
            if (hasFormula) break;
          }
          if (!hasFormula) return;

          // 2. Build live grid from live DOM values
          const grid = [];
          for (let r = 0; r < liveRows.length; r++) {
            grid[r] = [];
            for (let c = 0; c < liveRows[r].cells.length; c++) {
              const liveCell = liveRows[r].cells[c];
              grid[r][c] = cleanFormulaText(liveCell.innerText || liveCell.textContent || '');
            }
          }

          // 3. Recalculate formula cells and update LIVE DOM (up to 3 passes for chained formulas)
          let pass = 0;
          while (pass < 3) {
            let passUpdated = false;
            for (let r = 0; r < liveRows.length; r++) {
              for (let c = 0; c < liveRows[r].cells.length; c++) {
                const liveCell = liveRows[r].cells[c];
                // CRITICAL: Protect the active cell currently being edited/typed in unless explicitly forced
                if (liveCell !== forceCell && liveCell.contains(document.activeElement)) {
                  continue;
                }
                const formula = getCellFormula(liveCell, tableIdx, r, c);
                if (formula && formula.startsWith('=')) {
                  const res = evaluateFormulaString(formula, grid, r, c);
                  if (res !== null) {
                    const resStr = String(res);
                    liveCell.setAttribute('data-formula', formula);
                    liveCell.setAttribute('title', 'Formula: ' + formula + ' (Click fx to edit)');
                    liveCell.setAttribute('data-formula-val', resStr);
                    liveCell.classList.add('has-formula');

                    /* CKEditor renders a lone attribute-less paragraph in a cell as a bogus <span>, not <p> */
                    let p = liveCell.querySelector('p, .ck-table-bogus-paragraph');
                    if (!p) {
                      p = document.createElement('p');
                      liveCell.innerHTML = '';
                      liveCell.appendChild(p);
                    }
                    let strong = p.querySelector('strong');
                    if (!strong) {
                      strong = document.createElement('strong');
                      p.prepend(strong);
                    }
                    if (strong.textContent !== resStr) {
                      strong.textContent = resStr;
                      anyUpdated = true;
                      passUpdated = true;
                    }
                    strong.setAttribute('data-formula', formula);

                    // Ensure interactive .formula-badge is attached directly to liveCell (td/th), NOT inside <p>
                    const oldPBadge = p.querySelector('.formula-badge');
                    if (oldPBadge) oldPBadge.remove();

                    let badge = liveCell.querySelector('.formula-badge');
                    if (!badge) {
                      badge = document.createElement('span');
                      badge.className = 'formula-badge';
                      badge.setAttribute('contenteditable', 'false');
                      badge.setAttribute('data-formula', formula);
                      badge.title = 'Formula: ' + formula + ' (Click to edit)';
                      badge.textContent = 'fx';
                      liveCell.appendChild(badge);
                    } else {
                      badge.setAttribute('data-formula', formula);
                      badge.title = 'Formula: ' + formula + ' (Click to edit)';
                      if (badge.parentElement !== liveCell) {
                        liveCell.appendChild(badge);
                      }
                    }

                    // Update grid so chained formulas work instantly
                    grid[r][c] = resStr;

                    // Keep CKEditor model in sync (non-undoable batch). CKEditor reverts DOM-only edits, so without
                    // this the result never shows. The cell being typed in is skipped above, and writing another
                    // cell does not move the caret; only avoid interrupting IME composition.
                    const isComposing = editorInstance && editorInstance.editing.view.document.isComposing;
                    if (editorInstance && (!isComposing || forceCell)) {
                      _syncModelFormulaCell(editorInstance, tableIdx, r, c, resStr, formula);
                    }
                  }
                }
              }
            }
            if (!passUpdated) break;
            pass++;
          }
        });

        // 4. Ensure interactive .formula-badge is present on all formula cells after any model downcast
        ensureFormulaBadgesDOM();
        setTimeout(ensureFormulaBadgesDOM, 30);
        setTimeout(ensureFormulaBadgesDOM, 100);

        // 5. Update all table cell references and inline document formulas across document in real time
        updateTableCellReferencesDOM();
        setTimeout(updateTableCellReferencesDOM, 30);
        setTimeout(updateTableCellReferencesDOM, 100);

        updateInlineFormulasDOM();
        setTimeout(updateInlineFormulasDOM, 30);
        setTimeout(updateInlineFormulasDOM, 100);

        if (anyUpdated) {
          postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
        }
      } finally {
        setTimeout(() => {
          window._isUpdatingFormula = false;
        }, 50);
      }
    }
    window.autoUpdateTableFormulasDOM = autoUpdateTableFormulasDOM;

    function evaluateTableFormulas() {
      autoUpdateTableFormulasDOM();
    }

    // Live formula recalculation and cell reference resolution on any input/keyup at document level
    /* Typing in a dialog (e.g. the formula bar) is not a document edit */
    function isEventInsideModal(e) {
      return !!(e.target && e.target.closest && e.target.closest('.modal-overlay'));
    }

    document.addEventListener('input', function(e) {
      if (isEventInsideModal(e)) return;
      scheduleLiveFormulaRecalc();
      if (!e.data || e.data === ' ' || e.data === '.' || e.data === ',' || e.data === ';' || e.data === ')') {
        checkAndResolveDirectCellRef(editorInstance);
        checkAndResolveDirectFormula(editorInstance);
      }
    }, true);
    document.addEventListener('keyup', function(e) {
      if (isEventInsideModal(e)) return;
      scheduleLiveFormulaRecalc();
      if (e.key === ' ' || e.key === 'Enter' || e.key === ')') {
        checkAndResolveDirectCellRef(editorInstance);
        checkAndResolveDirectFormula(editorInstance);
      }
    }, true);

    // Recalculate when cell loses focus
    document.addEventListener('focusout', function(e) {
      if (e.target && e.target.closest && e.target.closest('table')) {
        setTimeout(() => {
          scanAndRegisterTableFormulas();
          autoUpdateTableFormulasDOM();
          if (editorInstance && editorInstance.model) {
            syncAllModelFormulaCells();
          }
        }, 40);
      }
    }, true);

    function syncAllModelFormulaCells() {
      if (!editorInstance || !editorInstance.model) return;
      try {
        const liveTables = getEditorLiveTables();
        liveTables.forEach((table, tableIdx) => {
          const tableUid = getTableUid(table);
          for (let r = 0; r < table.rows.length; r++) {
            for (let c = 0; c < table.rows[r].cells.length; c++) {
              const regKey = tableUid + '_' + r + '_' + c;
              if (window._tableFormulaRegistry && window._tableFormulaRegistry[regKey]) {
                const cell = table.rows[r].cells[c];
                const strong = cell.querySelector('strong');
                const formula = window._tableFormulaRegistry[regKey];
                const text = strong ? strong.textContent : cleanFormulaText(cell.innerText || '');
                if (text) {
                  _syncModelFormulaCell(editorInstance, tableIdx, r, c, text, formula);
                }
              }
            }
          }
        });
      } catch (e) {}
    }

    // Recalculate on Enter/Tab in table cell
    document.addEventListener('keydown', function(e) {
      if (!e.target || !e.target.closest || !e.target.closest('.ck-editor__editable, #fallback-content')) return;
      if (e.key === 'Enter' || e.key === 'Tab') {
        /* The cursor's own cell, not the last cell ever clicked (that blocked Enter all over the document) */
        const cell = getSelectionTableCell();
        if (cell) {
          const raw = cleanFormulaText(cell.innerText || cell.textContent || '');
          if (looksLikeFormula(raw) && e.key === 'Enter') {
            e.preventDefault();
            e.stopPropagation();
          }
          setTimeout(() => {
            scanAndRegisterTableFormulas();
            autoUpdateTableFormulasDOM();
          }, 30);
        }
      }
    }, true);

    // Click on fx badge or table cell reference pill
    document.addEventListener('click', function(e) {
      const cell = e.target.closest('td, th');
      if (cell) {
        lastActiveTableCell = cell;
      }
      // If formula modal is open, clicking a cell in any editor table inserts its coordinate into formula
      const formulaModal = document.getElementById('formula-modal');
      if (formulaModal && formulaModal.classList.contains('show') && cell && !cell.closest('#formula-modal')) {
        const row = cell.closest('tr');
        const rIdx = row ? row.rowIndex : 0;
        const cIdx = cell.cellIndex !== undefined ? cell.cellIndex : 0;
        const coord = getCellCoordString(cIdx, rIdx);
        insertFormulaCellCoord(coord);
        e.preventDefault();
        e.stopPropagation();
        return;
      }
      const formulaPill = e.target.closest('.inline-formula-pill, span[data-formula]:not(td):not(th)');
      if (formulaPill && !formulaPill.closest('.formula-badge')) {
        e.preventDefault();
        e.stopPropagation();
        openInlineFormulaEditor(formulaPill);
        return;
      }
      const pill = e.target.closest('.table-cell-ref, .mention, span[data-cell-coord]');
      if (pill && (pill.classList.contains('table-cell-ref') || pill.hasAttribute('data-cell-coord') || (pill.getAttribute('data-mention') && pill.getAttribute('data-mention').indexOf('\$') === 0))) {
        let coord = pill.getAttribute('data-cell-coord') || pill.getAttribute('data-mention') || '';
        if (coord.indexOf('\$') === 0) coord = coord.substring(1);
        let tableIdx = parseInt(pill.getAttribute('data-table-idx'), 10) || 0;
        /* Legacy "T2:A1" style coordinates carry the table number themselves */
        const tableMatch = /^T([0-9]+):(.+)\$/i.exec(coord);
        if (tableMatch) { tableIdx = parseInt(tableMatch[1], 10) - 1; coord = tableMatch[2]; }
        if (coord) {
          highlightReferencedTableCell(coord, tableIdx);
        }
        return;
      }
      const badge = e.target.closest('.formula-badge');
      if (badge) {
        e.preventDefault();
        e.stopPropagation();
        const targetCell = badge.closest('td, th') || cell;
        if (targetCell) {
          window._targetFormulaCell = targetCell;
          lastActiveTableCell = targetCell;
          openCellFormulaEditor(targetCell);
        }
        return;
      }
    }, true);

    // Double-click on formula cell to open formula editor modal
    document.addEventListener('dblclick', function(e) {
      const cell = e.target.closest('td, th');
      if (cell) {
        lastActiveTableCell = cell;
        const formula = getCellFormula(cell);
        if (formula && formula.startsWith('=')) {
          e.preventDefault();
          e.stopPropagation();
          window._targetFormulaCell = cell;
          openCellFormulaEditor(cell);
        }
      }
    }, true);

    function isCurrentSelectionInTable() {
      const sel = window.getSelection ? window.getSelection() : null;
      if (sel && sel.anchorNode) {
        const node = sel.anchorNode.nodeType === Node.ELEMENT_NODE ? sel.anchorNode : sel.anchorNode.parentElement;
        if (node && node.closest('td, th')) return true;
      }
      if (document.activeElement && document.activeElement.closest && document.activeElement.closest('td, th')) {
        return true;
      }
      if (editorInstance && editorInstance.model) {
        try {
          const pos = editorInstance.model.document.selection.getFirstPosition();
          let parent = pos ? pos.parent : null;
          while (parent) {
            if (parent.name === 'tableCell') return true;
            parent = parent.parent;
          }
        } catch (e) {}
      }
      return false;
    }

    /* DOM td/th of the cell holding the editor selection (model first: the toolbar click may move DOM focus) */
    function getSelectionTableCell() {
      if (editorInstance && editorInstance.model) {
        try {
          const selection = editorInstance.model.document.selection;
          const pos = selection.getFirstPosition();
          let modelCell = pos ? pos.findAncestor('tableCell') : null;
          if (!modelCell && editorInstance.plugins.has('TableUtils')) {
            modelCell = editorInstance.plugins.get('TableUtils').getSelectionAffectedTableCells(selection)[0] || null;
          }
          if (modelCell) {
            const viewCell = editorInstance.editing.mapper.toViewElement(modelCell);
            const domCell = viewCell ? editorInstance.editing.view.domConverter.mapViewToDom(viewCell) : null;
            if (domCell && document.contains(domCell)) return domCell;
          }
        } catch (e) {}
      }
      const sel = window.getSelection ? window.getSelection() : null;
      if (sel && sel.anchorNode) {
        const node = sel.anchorNode.nodeType === Node.ELEMENT_NODE ? sel.anchorNode : sel.anchorNode.parentElement;
        const cell = node ? node.closest('td, th') : null;
        if (cell && document.contains(cell)) return cell;
      }
      return null;
    }

    function resolveTargetCell() {
      let cell = window._targetFormulaCell;
      if (cell && document.contains(cell)) return cell;
      if (window._targetFormulaCoord) {
        const liveTables = getEditorLiveTables();
        const { tableIdx, r, c } = window._targetFormulaCoord;
        if (liveTables[tableIdx] && liveTables[tableIdx].rows && liveTables[tableIdx].rows[r] && liveTables[tableIdx].rows[r].cells && liveTables[tableIdx].rows[r].cells[c]) {
          const liveCell = liveTables[tableIdx].rows[r].cells[c];
          window._targetFormulaCell = liveCell;
          lastActiveTableCell = liveCell;
          return liveCell;
        }
      }
      return lastActiveTableCell || getActiveTableCell();
    }

    function showFormulaHelpModal() {
      const liveTables = getEditorLiveTables();
      if (!liveTables || liveTables.length === 0) {
        showToastMsg('⚠️ Please insert a table first before using formulas.');
        return;
      }

      if (isCurrentSelectionInTable()) {
        /* Target the cell under the cursor; the remembered cell is from the previous time the editor opened */
        let cell = getSelectionTableCell() || resolveTargetCell();
        if (cell && document.contains(cell)) {
          openCellFormulaEditor(cell);
          return;
        }
      }

      openInlineFormulaEditor(window._targetInlineFormulaPill);
    }

    function openCellFormulaEditor(cell) {
      if (!cell) {
        cell = resolveTargetCell();
      }
      if (!cell || !document.contains(cell)) {
        openInlineFormulaEditor(null);
        return;
      }
      window._formulaEditorMode = 'cell';
      window._targetFormulaCell = cell;
      window._targetInlineFormulaPill = null;
      lastActiveTableCell = cell;

      const modal = document.getElementById('formula-modal');
      const input = document.getElementById('formula-editor-input');
      const coordLabel = document.getElementById('formula-cell-coord');
      const title = document.getElementById('formula-modal-title');
      const applyBtn = document.getElementById('formula-apply-btn');
      const clearBtn = document.getElementById('formula-clear-btn');

      const table = cell.closest('table');
      const liveTables = getEditorLiveTables();
      const tableIdx = Math.max(0, liveTables.indexOf(table));
      const row = cell.closest('tr');
      const rIdx = row ? row.rowIndex : 0;
      const cIdx = cell.cellIndex !== undefined ? cell.cellIndex : 0;
      window._targetFormulaCoord = { tableIdx, r: rIdx, c: cIdx };

      const coordName = getCellCoordString(cIdx, rIdx);

      const currentFormula = getCellFormula(cell, tableIdx, rIdx, cIdx) || cell.getAttribute('data-formula') || '';
      if (title) title.textContent = '🧮 Table Formula: Cell ' + coordName;
      if (coordLabel) coordLabel.textContent = '📍 Target Cell: ' + coordName;
      if (applyBtn) applyBtn.textContent = 'Apply';
      if (clearBtn) clearBtn.textContent = 'Clear';
      if (input) input.value = currentFormula || (rIdx > 0 ? '=SUM(ABOVE)' : '=');

      // Populate interactive table cells picker grid
      renderFormulaModalCellGrid(table, rIdx, cIdx);

      // Update live preview immediately
      updateFormulaLivePreview();

      if (modal) modal.classList.add('show');
      setTimeout(() => {
        if (input) {
          input.focus();
          const len = input.value.length;
          input.setSelectionRange(len, len);
        }
      }, 80);
    }
    window.openCellFormulaEditor = openCellFormulaEditor;

    function openInlineFormulaEditor(formulaPill) {
      const liveTables = getEditorLiveTables();
      if (!liveTables || liveTables.length === 0) {
        showToastMsg('⚠️ Please insert a table first before using formulas.');
        return;
      }

      window._formulaEditorMode = 'inline';
      window._targetInlineFormulaPill = formulaPill || null;
      window._targetFormulaCell = null;

      const modal = document.getElementById('formula-modal');
      const input = document.getElementById('formula-editor-input');
      const coordLabel = document.getElementById('formula-cell-coord');
      const title = document.getElementById('formula-modal-title');
      const applyBtn = document.getElementById('formula-apply-btn');
      const clearBtn = document.getElementById('formula-clear-btn');

      let tableIdx = 0;
      let currentFormula = '';

      if (formulaPill) {
        currentFormula = formulaPill.getAttribute('data-formula') || formulaPill.getAttribute('data-inline-formula') || '';
        tableIdx = parseInt(formulaPill.getAttribute('data-table-idx'), 10) || 0;
      }
      window._targetFormulaCoord = { tableIdx: tableIdx, r: -1, c: -1 };

      if (title) title.textContent = formulaPill ? '🧮 Edit Document Formula' : '🧮 Insert Table Formula in Text';
      if (coordLabel) coordLabel.textContent = formulaPill ? ('📍 Formula: ' + currentFormula) : '📍 Insert Live Formula into Document';
      if (applyBtn) applyBtn.textContent = formulaPill ? 'Update' : 'Insert Formula';
      if (clearBtn) clearBtn.textContent = formulaPill ? 'Remove' : 'Clear';
      if (input) input.value = currentFormula || '=SUM(A1+A2)';

      const table = liveTables[tableIdx] || liveTables[0];
      renderFormulaModalCellGrid(table, -1, -1);
      updateFormulaLivePreview();

      if (modal) modal.classList.add('show');
      setTimeout(() => {
        if (input) {
          input.focus();
          const len = input.value.length;
          input.setSelectionRange(len, len);
        }
      }, 80);
    }
    window.openInlineFormulaEditor = openInlineFormulaEditor;

    function renderFormulaModalCellGrid(table, targetR, targetC) {
      const gridContainer = document.getElementById('formula-cells-picker-grid');
      if (!gridContainer) return;
      gridContainer.innerHTML = '';

      if (!table || !table.rows || table.rows.length === 0) {
        gridContainer.innerHTML = '<span style="font-size:12px;color:#94a3b8;padding:8px;">No table cells available</span>';
        return;
      }

      for (let r = 0; r < table.rows.length; r++) {
        const row = table.rows[r];
        for (let c = 0; c < row.cells.length; c++) {
          const cell = row.cells[c];
          const coord = getCellCoordString(c, r);
          const isTarget = (r === targetR && c === targetC);
          const rawVal = cell.getAttribute('data-formula-val') || cleanFormulaText(cell.innerText || cell.textContent || '');
          const hasFormula = cell.getAttribute('data-formula') != null;

          const btn = document.createElement('button');
          btn.type = 'button';
          btn.style.padding = '5px 8px';
          btn.style.borderRadius = '6px';
          btn.style.border = isTarget ? '1.5px dashed #3b82f6' : '1px solid #cbd5e1';
          btn.style.background = isTarget ? '#eff6ff' : '#ffffff';
          btn.style.cursor = isTarget ? 'default' : 'pointer';
          btn.style.display = 'flex';
          btn.style.flexDirection = 'column';
          btn.style.alignItems = 'flex-start';
          btn.style.gap = '2px';
          btn.style.textAlign = 'left';
          btn.style.transition = 'all 0.15s ease';
          btn.title = isTarget ? ('Target Cell ' + coord + ' (Self)') : ('Click to insert ' + coord + ' into formula');

          if (!isTarget) {
            btn.onmouseenter = function() {
              btn.style.background = '#dbeafe';
              btn.style.borderColor = '#2563eb';
            };
            btn.onmouseleave = function() {
              btn.style.background = '#ffffff';
              btn.style.borderColor = '#cbd5e1';
            };
            btn.onclick = function() {
              insertFormulaCellCoord(coord);
            };
          }

          const topRow = document.createElement('div');
          topRow.style.display = 'flex';
          topRow.style.alignItems = 'center';
          topRow.style.justifyContent = 'space-between';
          topRow.style.width = '100%';

          const coordBadge = document.createElement('span');
          coordBadge.style.fontWeight = '700';
          coordBadge.style.fontSize = '11px';
          coordBadge.style.fontFamily = 'monospace';
          coordBadge.style.color = isTarget ? '#2563eb' : (hasFormula ? '#7c3aed' : '#0f172a');
          coordBadge.textContent = coord + (isTarget ? ' (Target)' : '');

          topRow.appendChild(coordBadge);

          const valText = document.createElement('span');
          valText.style.fontSize = '11px';
          valText.style.color = '#475569';
          valText.style.maxWidth = '100%';
          valText.style.overflow = 'hidden';
          valText.style.textOverflow = 'ellipsis';
          valText.style.whiteSpace = 'nowrap';
          valText.textContent = rawVal ? ('= ' + rawVal) : '(empty)';

          btn.appendChild(topRow);
          btn.appendChild(valText);
          gridContainer.appendChild(btn);
        }
      }
    }
    window.renderFormulaModalCellGrid = renderFormulaModalCellGrid;

    function insertFormulaCellCoord(coord) {
      const input = document.getElementById('formula-editor-input');
      if (!input) return;
      let val = input.value || '';
      if (!val || val.trim() === '') {
        val = '=';
      } else if (!val.startsWith('=')) {
        val = '=' + val;
      }

      const start = input.selectionStart != null ? input.selectionStart : val.length;
      const end = input.selectionEnd != null ? input.selectionEnd : val.length;

      let before = val.substring(0, start);
      const after = val.substring(end);

      const trimmedBefore = before.trim();
      if (trimmedBefore.endsWith('(') || trimmedBefore.endsWith('+') || trimmedBefore.endsWith('-') ||
          trimmedBefore.endsWith('*') || trimmedBefore.endsWith('/') || trimmedBefore.endsWith(',') ||
          trimmedBefore.endsWith(':') || trimmedBefore === '=') {
        // Safe to append directly
      } else if (trimmedBefore.length > 1) {
        // Automatically insert '+' if user clicks two cell cards sequentially
        before = before.trimEnd() + ' + ';
      }

      input.value = before + coord + after;
      const newCursorPos = (before + coord).length;
      input.focus();
      input.setSelectionRange(newCursorPos, newCursorPos);
      updateFormulaLivePreview();
    }
    window.insertFormulaCellCoord = insertFormulaCellCoord;

    function insertFormulaToken(token) {
      const input = document.getElementById('formula-editor-input');
      if (!input) return;
      let val = input.value || '';
      if (!val || val.trim() === '') {
        val = '=';
      } else if (!val.startsWith('=')) {
        val = '=' + val;
      }

      const start = input.selectionStart != null ? input.selectionStart : val.length;
      const end = input.selectionEnd != null ? input.selectionEnd : val.length;

      const before = val.substring(0, start);
      const after = val.substring(end);

      input.value = before + token + after;
      const newCursorPos = (before + token).length;
      input.focus();
      input.setSelectionRange(newCursorPos, newCursorPos);
      updateFormulaLivePreview();
    }
    window.insertFormulaToken = insertFormulaToken;

    function wrapOrSetFormulaFunction(fnName) {
      const input = document.getElementById('formula-editor-input');
      if (!input) return;
      let val = (input.value || '').trim();
      if (val.startsWith('=')) val = val.substring(1).trim();

      if (!val || val === 'SUM(ABOVE)' || val === 'AVG(ABOVE)') {
        input.value = '=' + fnName + '()';
        const insidePos = ('=' + fnName + '(').length;
        input.focus();
        input.setSelectionRange(insidePos, insidePos);
      } else if (/^[A-Z]+\\s*\\(/.test(val) && val.indexOf(')') !== -1) {
        input.value = '=' + val.replace(/^[A-Z]+/i, fnName);
        input.focus();
      } else {
        input.value = '=' + fnName + '(' + val + ')';
        input.focus();
      }
      updateFormulaLivePreview();
    }
    window.wrapOrSetFormulaFunction = wrapOrSetFormulaFunction;

    function updateFormulaLivePreview() {
      const input = document.getElementById('formula-editor-input');
      const previewEl = document.getElementById('formula-live-preview-val');
      if (!input || !previewEl) return;

      const raw = (input.value || '').trim();
      if (!raw || raw === '=') {
        previewEl.textContent = '--';
        previewEl.style.color = '#94a3b8';
        return;
      }

      const liveTables = getEditorLiveTables();
      let table = null;
      let targetR = -1;
      let targetC = -1;

      if (window._formulaEditorMode === 'cell') {
        const cell = resolveTargetCell();
        table = cell ? cell.closest('table') : null;
        const row = cell ? cell.closest('tr') : null;
        targetR = row ? row.rowIndex : (window._targetFormulaCoord ? window._targetFormulaCoord.r : 0);
        targetC = cell ? (cell.cellIndex !== undefined ? cell.cellIndex : 0) : (window._targetFormulaCoord ? window._targetFormulaCoord.c : 0);
      } else {
        const tIdx = (window._targetFormulaCoord && window._targetFormulaCoord.tableIdx !== undefined) ? window._targetFormulaCoord.tableIdx : 0;
        table = liveTables[tIdx] || liveTables[0];
      }

      if (!table) {
        previewEl.textContent = '(Select table/cell)';
        previewEl.style.color = '#94a3b8';
        return;
      }

      const grid = [];
      for (let r = 0; r < table.rows.length; r++) {
        grid[r] = [];
        for (let c = 0; c < table.rows[r].cells.length; c++) {
          const curCell = table.rows[r].cells[c];
          grid[r][c] = curCell.getAttribute('data-formula-val') || cleanFormulaText(curCell.innerText || curCell.textContent || '');
        }
      }

      const normalized = normalizeFormulaString(raw);
      const res = evaluateFormulaString(normalized, grid, targetR, targetC);

      if (res !== null && !isNaN(res)) {
        previewEl.textContent = '= ' + String(res);
        previewEl.style.color = '#16a34a';
      } else {
        previewEl.textContent = '⚠️ Waiting for complete formula';
        previewEl.style.color = '#eab308';
      }
    }
    window.updateFormulaLivePreview = updateFormulaLivePreview;

    function setFormulaInput(val) {
      const input = document.getElementById('formula-editor-input');
      if (input) {
        input.value = val;
        input.focus();
        updateFormulaLivePreview();
      }
    }
    window.setFormulaInput = setFormulaInput;

    function applyCurrentCellFormula() {
      const input = document.getElementById('formula-editor-input');
      const rawVal = (input ? input.value : '').trim();
      if (!rawVal || rawVal === '=') {
        showToastMsg('⚠️ Please enter a formula (e.g. =SUM(A1+A2) or =A1*B1)');
        return;
      }
      const formula = normalizeFormulaString(rawVal);

      if (window._formulaEditorMode === 'inline') {
        applyInlineFormula(formula);
        return;
      }

      const cell = resolveTargetCell();
      if (!cell || !document.contains(cell)) {
        applyInlineFormula(formula);
        return;
      }

      const table = cell.closest('table');
      const tableUid = getTableUid(table);
      const liveTables = getEditorLiveTables();
      const tableIdx = Math.max(0, liveTables.indexOf(table));
      const r = cell.closest('tr') ? cell.closest('tr').rowIndex : 0;
      const c = cell.cellIndex !== undefined ? cell.cellIndex : 0;
      const regKey = tableUid + '_' + r + '_' + c;
      const idxKey = tableIdx + '_' + r + '_' + c;

      window._tableFormulaRegistry = window._tableFormulaRegistry || {};
      window._tableFormulaRegistry[regKey] = formula;
      window._tableFormulaRegistry[idxKey] = formula;

      cell.setAttribute('data-formula', formula);
      cell.setAttribute('title', 'Formula: ' + formula + ' (Click fx to edit)');
      cell.classList.add('has-formula');

      closeFormulaHelpModal();
      autoUpdateTableFormulasDOM(cell);
      ensureFormulaBadgesDOM();
      setTimeout(ensureFormulaBadgesDOM, 30);
      setTimeout(ensureFormulaBadgesDOM, 100);
      showToastMsg('⚡ Formula applied: ' + formula);
      postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
    }
    window.applyCurrentCellFormula = applyCurrentCellFormula;

    function applyInlineFormula(formula) {
      const liveTables = getEditorLiveTables();
      if (!liveTables || liveTables.length === 0) {
        showToastMsg('⚠️ Please insert a table first');
        closeFormulaHelpModal();
        return;
      }
      const tIdx = (window._targetFormulaCoord && window._targetFormulaCoord.tableIdx !== undefined) ? window._targetFormulaCoord.tableIdx : 0;
      const table = liveTables[tIdx] || liveTables[0];
      const grid = [];
      for (let r = 0; r < table.rows.length; r++) {
        grid[r] = [];
        for (let c = 0; c < table.rows[r].cells.length; c++) {
          const curCell = table.rows[r].cells[c];
          grid[r][c] = curCell.getAttribute('data-formula-val') || cleanFormulaText(curCell.innerText || curCell.textContent || '');
        }
      }

      const res = evaluateFormulaString(formula, grid, -1, -1);
      const displayVal = (res !== null && !isNaN(res)) ? String(res) : formula;

      insertOrUpdateInlineFormula(formula, displayVal, window._targetInlineFormulaPill, tIdx);
      closeFormulaHelpModal();
      showToastMsg('⚡ Inserted formula: ' + formula + ' (= ' + displayVal + ')');
    }
    window.applyInlineFormula = applyInlineFormula;

    function clearCurrentCellFormula() {
      if (window._formulaEditorMode === 'inline') {
        const pill = window._targetInlineFormulaPill;
        if (pill) {
          if (pill.parentNode) {
            const textNode = document.createTextNode(pill.textContent || '');
            pill.parentNode.replaceChild(textNode, pill);
          }
          if (editorInstance && editorInstance.model) {
            updateInlineFormulasDOM();
          }
          showToastMsg('🗑 Formula removed; converted to static text');
          postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
        }
        const input = document.getElementById('formula-editor-input');
        if (input) input.value = '';
        closeFormulaHelpModal();
        return;
      }

      const cell = resolveTargetCell();
      if (cell && document.contains(cell)) {
        const table = cell.closest('table');
        const tableUid = getTableUid(table);
        const liveTables = getEditorLiveTables();
        const tableIdx = Math.max(0, liveTables.indexOf(table));
        const r = cell.closest('tr') ? cell.closest('tr').rowIndex : 0;
        const c = cell.cellIndex !== undefined ? cell.cellIndex : 0;
        const regKey = tableUid + '_' + r + '_' + c;
        const idxKey = tableIdx + '_' + r + '_' + c;
        if (window._tableFormulaRegistry) {
          delete window._tableFormulaRegistry[regKey];
          delete window._tableFormulaRegistry[idxKey];
        }
        cell.removeAttribute('data-formula');
        cell.removeAttribute('title');
        cell.removeAttribute('data-formula-val');
        cell.classList.remove('has-formula');
        const badge = cell.querySelector('.formula-badge');
        if (badge) badge.remove();
        const strong = cell.querySelector('strong');
        if (strong) strong.removeAttribute('data-formula');

        if (editorInstance && editorInstance.model) {
          _removeModelFormulaAttribute(editorInstance, tableIdx, r, c);
        }
        ensureFormulaBadgesDOM();
        setTimeout(ensureFormulaBadgesDOM, 30);

        showToastMsg('🗑 Formula removed; cell is now static number');
        postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
      }
      closeFormulaHelpModal();
    }
    window.clearCurrentCellFormula = clearCurrentCellFormula;

    function closeFormulaHelpModal() {
      const modal = document.getElementById('formula-modal');
      if (modal) modal.classList.remove('show');
    }
    window.closeFormulaHelpModal = closeFormulaHelpModal;

    /* ====== TABLE CELL REFERENCE SYSTEM ====== */

    function getCellCoordString(colIdx, rowIdx) {
      let colLetters = '';
      let c = colIdx + 1;
      while (c > 0) {
        let rem = (c - 1) % 26;
        colLetters = String.fromCharCode(65 + rem) + colLetters;
        c = Math.floor((c - 1) / 26);
      }
      return colLetters + (rowIdx + 1);
    }

    function getTableCellMentionsFeed(queryText) {
      const liveTables = getEditorLiveTables();
      if (!liveTables || liveTables.length === 0) return [];

      const query = (queryText || '').trim().toLowerCase();
      const items = [];

      liveTables.forEach((table, tIdx) => {
        const rows = table.rows;
        if (!rows || rows.length === 0) return;

        for (let r = 0; r < rows.length; r++) {
          const cells = rows[r].cells;
          for (let c = 0; c < cells.length; c++) {
            const cell = cells[c];
            const coord = getCellCoordString(c, r);
            const cellText = cleanFormulaText(cell.innerText || cell.textContent || '');
            const formula = cell.getAttribute('data-formula');
            const formulaVal = cell.getAttribute('data-formula-val');
            const displayVal = (formulaVal != null && formulaVal !== '') ? formulaVal : (cellText || formula || '');

            let headerLabel = '';
            if (r > 0 && rows[0].cells[c]) {
              headerLabel = cleanFormulaText(rows[0].cells[c].innerText || '');
            }
            let rowLabel = '';
            if (c > 0 && rows[r].cells[0]) {
              rowLabel = cleanFormulaText(rows[r].cells[0].innerText || '');
            }

            const shortId = '\$' + coord;
            const fullId = (liveTables.length > 1 ? ('\$T' + (tIdx + 1) + ':' + coord) : shortId);

            if (query) {
              const matchCoord = coord.toLowerCase().includes(query) || shortId.toLowerCase().includes(query);
              const matchVal = displayVal.toLowerCase().includes(query);
              const matchHeader = headerLabel.toLowerCase().includes(query);
              const matchRow = rowLabel.toLowerCase().includes(query);
              if (!matchCoord && !matchVal && !matchHeader && !matchRow) {
                continue;
              }
            }

            items.push({
              id: shortId,
              fullId: fullId,
              coord: coord,
              tableIdx: tIdx,
              r: r,
              c: c,
              val: displayVal,
              header: headerLabel,
              rowLabel: rowLabel,
              text: displayVal || shortId
            });
          }
        }
      });

      return items.slice(0, 35);
    }

    function renderTableCellMentionItem(item) {
      const btn = document.createElement('button');
      btn.className = 'ck-button table-cell-mention-btn';
      btn.type = 'button';

      const left = document.createElement('div');
      left.style.display = 'flex';
      left.style.alignItems = 'center';
      left.style.gap = '6px';
      left.style.overflow = 'hidden';

      const badge = document.createElement('span');
      badge.className = 'cell-coord-badge';
      badge.textContent = item.coord;

      const val = document.createElement('span');
      val.className = 'cell-val-text';
      val.textContent = item.val || '(empty)';

      left.appendChild(badge);
      left.appendChild(val);
      btn.appendChild(left);

      if (item.header || item.rowLabel) {
        const meta = document.createElement('span');
        meta.className = 'cell-meta-text';
        meta.textContent = item.header ? ('Col: ' + item.header) : ('Row: ' + item.rowLabel);
        btn.appendChild(meta);
      }

      return btn;
    }

    function updateTableCellReferencesDOM() {
      try {
        const liveTables = getEditorLiveTables();
        if (!liveTables || liveTables.length === 0) return;

        // 1. If CKEditor is active, update references via model transactions (non-undoable batch)
        if (editorInstance && editorInstance.model) {
          try {
            const model = editorInstance.model;
            const root = model.document.getRoot();
            if (root) {
              const refItems = [];
              const scanModel = (parent) => {
                for (const child of parent.getChildren()) {
                  if (child.is && child.is('\$text')) {
                    const ref = child.getAttribute('tableCellRef');
                    const mention = child.getAttribute('mention');
                    let coord = '';
                    let tIdx = 0;
                    if (ref) {
                      coord = typeof ref === 'string' ? ref : (ref.coord || '');
                      tIdx = typeof ref === 'object' && ref.tableIdx !== undefined ? ref.tableIdx : 0;
                    } else if (mention && (mention.coord || (mention.id && mention.id.indexOf('\$') === 0))) {
                      coord = mention.coord || mention.id.replace('\$', '').toUpperCase();
                      tIdx = mention.tableIdx || 0;
                    }
                    if (coord) {
                      refItems.push({
                        item: child,
                        coord: coord.toUpperCase(),
                        tableIdx: tIdx
                      });
                    }
                  } else if (child.getChildren) {
                    scanModel(child);
                  }
                }
              };
              scanModel(root);

              const toUpdate = [];
              for (const entry of refItems) {
                const table = liveTables[entry.tableIdx] || liveTables[0];
                if (!table) continue;
                const pos = parseCellCoord(entry.coord);
                if (!pos) continue;

                if (pos.row >= 0 && pos.row < table.rows.length && pos.col >= 0 && pos.col < table.rows[pos.row].cells.length) {
                  const cell = table.rows[pos.row].cells[pos.col];
                  const formulaVal = cell.getAttribute('data-formula-val');
                  const freshVal = (formulaVal != null && formulaVal !== '') 
                      ? formulaVal 
                      : cleanFormulaText(cell.innerText || cell.textContent || '');

                  if (freshVal && entry.item.data !== freshVal) {
                    toUpdate.push({
                      item: entry.item,
                      coord: entry.coord,
                      tableIdx: entry.tableIdx,
                      freshVal: freshVal
                    });
                  }
                }
              }

              if (toUpdate.length > 0) {
                // Apply updates in reverse order so position shifts don't affect previous items
                toUpdate.reverse();
                const updateWriter = (writer) => {
                  for (const u of toUpdate) {
                    const range = writer.createRangeOn(u.item);
                    const attrs = {};
                    for (const [k, v] of u.item.getAttributes()) {
                      attrs[k] = v;
                    }
                    attrs.tableCellRef = { coord: u.coord, tableIdx: u.tableIdx };
                    // Ensure volatile mention attribute is not present so built-in post-fixer never interferes
                    delete attrs.mention;
                    writer.remove(range);
                    writer.insertText(u.freshVal, attrs, range.start);
                  }
                };

                let batch = null;
                if (typeof model.createBatch === 'function') {
                  try { batch = model.createBatch({ isUndoable: false }); } catch (e) { batch = null; }
                }
                if (batch && typeof model.enqueueChange === 'function') {
                  model.enqueueChange(batch, updateWriter);
                } else if (typeof model.change === 'function') {
                  model.change(updateWriter);
                }
              }
            }
          } catch (modelErr) {
            console.warn('updateModelCellReferences error:', modelErr);
          }
        }

        // 2. Ensure all DOM spans have the proper class, data attributes and titles
        const allSpans = Array.from(document.querySelectorAll('.ck-content .mention, .ck-content .table-cell-ref, .ck-content span[data-cell-coord], #fallback-content .table-cell-ref, #fallback-content .mention, #fallback-content span[data-cell-coord]'));
        const refSpans = allSpans.filter(s => s.classList.contains('table-cell-ref') || s.hasAttribute('data-cell-coord') || (s.getAttribute('data-mention') && s.getAttribute('data-mention').indexOf('\$') === 0));

        refSpans.forEach(span => {
          let rawCoord = span.getAttribute('data-cell-coord');
          let tIdx = 0;
          if (!rawCoord) {
            const mentionId = span.getAttribute('data-mention') || '';
            if (mentionId.indexOf('\$') === 0) {
              let cleanId = mentionId.substring(1);
              if (cleanId.toUpperCase().indexOf('T') === 0 && cleanId.indexOf(':') !== -1) {
                const parts = cleanId.split(':');
                tIdx = parseInt(parts[0].substring(1), 10) - 1 || 0;
                cleanId = parts[1];
              }
              rawCoord = cleanId.toUpperCase();
            }
          } else {
            const tAttr = span.getAttribute('data-table-idx');
            if (tAttr) tIdx = parseInt(tAttr, 10);
          }

          if (!rawCoord) return;

          if (!span.classList.contains('table-cell-ref')) {
            span.classList.add('table-cell-ref');
          }
          span.setAttribute('data-cell-coord', rawCoord);
          span.setAttribute('data-table-idx', tIdx);
          if (!span.getAttribute('data-mention')) {
            const token = '\$' + (tIdx > 0 ? ('T' + (tIdx + 1) + ':' + rawCoord) : rawCoord);
            span.setAttribute('data-mention', token);
          }

          const table = liveTables[tIdx] || liveTables[0];
          if (!table) return;

          const pos = parseCellCoord(rawCoord);
          if (!pos) return;

          if (pos.row >= 0 && pos.row < table.rows.length && pos.col >= 0 && pos.col < table.rows[pos.row].cells.length) {
            const cell = table.rows[pos.row].cells[pos.col];
            const formulaVal = cell.getAttribute('data-formula-val');
            const freshVal = (formulaVal != null && formulaVal !== '') 
                ? formulaVal 
                : cleanFormulaText(cell.innerText || cell.textContent || '');

            span.setAttribute('title', 'Table cell ' + rawCoord + ': "' + (freshVal || '') + '" (Live Link)');

            // For fallback mode or if editorInstance is not managing this DOM node
            if (isFallback || !editorInstance) {
              const currentText = (span.innerText || span.textContent || '').trim();
              if (freshVal && currentText !== freshVal) {
                span.textContent = freshVal;
              }
            }
          }
        });
      } catch (e) {
        console.warn('updateTableCellReferencesDOM error:', e);
      }
    }
    window.updateTableCellReferencesDOM = updateTableCellReferencesDOM;

    function _syncModelMentionText(editor, spanElement, newText) {
      // Handled cleanly via model traversal in updateTableCellReferencesDOM
      if (!editor || !editor.model) return;
      const liveTables = getEditorLiveTables();
      if (liveTables && liveTables.length > 0) {
        updateTableCellReferencesDOM();
      }
    }

    function checkAndResolveDirectCellRef(editor) {
      if (!editor || !editor.model) return;
      try {
        const liveTables = getEditorLiveTables();
        if (liveTables.length === 0) return;

        const model = editor.model;
        const sel = model.document.selection;
        if (!sel.isCollapsed) return;

        const pos = sel.getFirstPosition();
        const parent = pos.parent;
        if (!parent || parent.name === 'tableCell' || parent.name === 'codeBlock') return;

        for (const child of parent.getChildren()) {
          if (child.is && child.is('\$text') && !child.getAttribute('tableCellRef')) {
            const text = child.data;
            const regex = /(?:^|\\s)\$([A-Za-z]+[0-9]+)/g;
            let match;
            while ((match = regex.exec(text)) !== null) {
              const afterIdx = match.index + match[0].length;
              if (afterIdx < text.length && !/[\\s,.;:!?]/.test(text[afterIdx])) continue;

              const coord = match[1].toUpperCase();
              const fullMatch = '\$' + match[1];
              const matchIndex = match.index + (match[0].startsWith(' ') ? 1 : 0);

              const parsed = parseCellCoord(coord);
              if (!parsed) continue;

              const table = liveTables[0];
              if (parsed.row >= 0 && parsed.row < table.rows.length && parsed.col >= 0 && parsed.col < table.rows[parsed.row].cells.length) {
                const cell = table.rows[parsed.row].cells[parsed.col];
                const formulaVal = cell.getAttribute('data-formula-val');
                const val = (formulaVal != null && formulaVal !== '') 
                    ? formulaVal 
                    : cleanFormulaText(cell.innerText || cell.textContent || '') || fullMatch;

                model.change(writer => {
                  const startPos = writer.createPositionAt(child, matchIndex);
                  const endPos = writer.createPositionAt(child, matchIndex + fullMatch.length);
                  const range = writer.createRange(startPos, endPos);
                  writer.remove(range);
                  const refText = writer.createText(val, {
                    tableCellRef: {
                      coord: coord,
                      tableIdx: 0
                    }
                  });
                  writer.insert(refText, startPos);
                });
                setTimeout(updateTableCellReferencesDOM, 10);
                break;
              }
            }
          }
        }
      } catch (e) {
        console.warn('checkAndResolveDirectCellRef error:', e);
      }
    }

    function checkAndResolveDirectFormula(editor) {
      if (!editor || !editor.model) return;
      try {
        const liveTables = getEditorLiveTables();
        if (liveTables.length === 0) return;

        const model = editor.model;
        const sel = model.document.selection;
        if (!sel.isCollapsed) return;

        const pos = sel.getFirstPosition();
        const parent = pos.parent;
        if (!parent || parent.name === 'tableCell' || parent.name === 'codeBlock') return;

        const table = liveTables[0];
        const grid = [];
        for (let r = 0; r < table.rows.length; r++) {
          grid[r] = [];
          for (let c = 0; c < table.rows[r].cells.length; c++) {
            const curCell = table.rows[r].cells[c];
            grid[r][c] = curCell.getAttribute('data-formula-val') || cleanFormulaText(curCell.innerText || curCell.textContent || '');
          }
        }

        // Pattern 1: A single text node containing typed formula (e.g. =SUM(A1+A2) or =\$A1+\$A2 or =A1*1.5)
        for (const child of parent.getChildren()) {
          if (child.is && child.is('\$text') && !child.getAttribute('inlineFormula') && !child.getAttribute('tableCellRef')) {
            const text = child.data;
            const fRegex = /(?:^|\\s)(=(?:(?:SUM|AVG|AVERAGE|COUNT|MAX|MIN|PRODUCT|ROUND)\\s*\\([^)]+\\)|(?:\\\$?[A-Za-z]+[0-9]+)\\s*(?:[\\+\\-\\*\\/]\\s*(?:\\\$?[A-Za-z]+[0-9]+|\\d+(?:\\.\\d+)?))+))/gi;
            let match;
            while ((match = fRegex.exec(text)) !== null) {
              const afterIdx = match.index + match[0].length;
              if (afterIdx < text.length && !/[\\s,.;:!?]/.test(text[afterIdx])) continue;

              const formulaRaw = match[1].trim();
              const matchIndex = match.index + (match[0].startsWith(' ') ? 1 : 0);

              const res = evaluateFormulaString(formulaRaw, grid, -1, -1);
              if (res !== null && !isNaN(res)) {
                const displayVal = String(res);
                model.change(writer => {
                  const startPos = writer.createPositionAt(child, matchIndex);
                  const endPos = writer.createPositionAt(child, matchIndex + formulaRaw.length);
                  const range = writer.createRange(startPos, endPos);
                  writer.remove(range);
                  const formulaText = writer.createText(displayVal, {
                    inlineFormula: {
                      formula: formulaRaw,
                      tableIdx: 0
                    }
                  });
                  writer.insert(formulaText, startPos);
                });
                setTimeout(updateInlineFormulasDOM, 10);
                return;
              }
            }
          }
        }

        // Pattern 2: Sequence of siblings where user typed `= SUM( [📊 23] + [📊 33] )`
        const children = Array.from(parent.getChildren());
        for (let i = 0; i < children.length; i++) {
          const startNode = children[i];
          if (startNode.is && startNode.is('\$text') && !startNode.getAttribute('inlineFormula') && !startNode.getAttribute('tableCellRef')) {
            const text = startNode.data;
            const eqIdx = text.lastIndexOf('=');
            if (eqIdx !== -1) {
              let formulaParts = [text.substring(eqIdx)];
              let endNode = startNode;
              let endOffset = text.length;
              let hasCellRef = false;
              let isComplete = false;

              for (let j = i + 1; j < children.length; j++) {
                const nextNode = children[j];
                if (nextNode.is && nextNode.is('\$text')) {
                  const ref = nextNode.getAttribute('tableCellRef');
                  if (ref) {
                    hasCellRef = true;
                    formulaParts.push(ref.coord || 'A1');
                    endNode = nextNode;
                    endOffset = nextNode.data.length;
                  } else if (!nextNode.getAttribute('inlineFormula')) {
                    formulaParts.push(nextNode.data);
                    endNode = nextNode;
                    endOffset = nextNode.data.length;
                    if (nextNode.data.includes(')')) {
                      isComplete = true;
                      endOffset = nextNode.data.indexOf(')') + 1;
                      break;
                    }
                  } else {
                    break;
                  }
                } else {
                  break;
                }
              }

              if (hasCellRef && (isComplete || formulaParts.join('').includes('+') || formulaParts.join('').includes('-') || formulaParts.join('').includes('*'))) {
                const combinedFormula = formulaParts.join('').trim();
                const res = evaluateFormulaString(combinedFormula, grid, -1, -1);
                if (res !== null && !isNaN(res)) {
                  const displayVal = String(res);
                  model.change(writer => {
                    const startPos = writer.createPositionAt(startNode, eqIdx);
                    const endPos = writer.createPositionAt(endNode, endOffset);
                    const range = writer.createRange(startPos, endPos);
                    writer.remove(range);
                    const formulaText = writer.createText(displayVal, {
                      inlineFormula: {
                        formula: combinedFormula,
                        tableIdx: 0
                      }
                    });
                    writer.insert(formulaText, startPos);
                  });
                  setTimeout(updateInlineFormulasDOM, 10);
                  return;
                }
              }
            }
          }
        }
      } catch (e) {
        console.warn('checkAndResolveDirectFormula error:', e);
      }
    }
    window.checkAndResolveDirectFormula = checkAndResolveDirectFormula;

    function insertOrUpdateInlineFormula(formula, displayVal, targetPill, tableIdx) {
      if (tableIdx === undefined || tableIdx === null) tableIdx = 0;
      if (!formula.startsWith('=')) formula = '=' + formula;

      if (editorInstance && editorInstance.model) {
        try {
          editorInstance.model.change(writer => {
            const formulaData = {
              formula: formula,
              tableIdx: tableIdx
            };
            const sel = editorInstance.model.document.selection;
            const textNode = writer.createText(displayVal, {
              inlineFormula: formulaData
            });
            editorInstance.model.insertContent(textNode, sel);
            editorInstance.model.insertContent(writer.createText(' '), sel);
          });
          setTimeout(updateInlineFormulasDOM, 20);
          postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
          return;
        } catch (e) {
          console.warn('insertOrUpdateInlineFormula model error:', e);
        }
      }

      // Fallback mode or fallback DOM:
      const pillHtml = '<span class="inline-formula-pill" data-formula="' + formula + '" data-table-idx="' + tableIdx + '" title="Formula: ' + formula + ' (Live Calculation)">' + displayVal + '</span>&nbsp;';
      if (targetPill && targetPill.parentNode) {
        targetPill.outerHTML = pillHtml;
      } else {
        document.execCommand('insertHTML', false, pillHtml);
      }
      postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
    }
    window.insertOrUpdateInlineFormula = insertOrUpdateInlineFormula;

    function updateInlineFormulasDOM() {
      try {
        const liveTables = getEditorLiveTables();
        if (!liveTables || liveTables.length === 0) return;

        // Build grids for each table
        const grids = liveTables.map(t => {
          const g = [];
          for (let r = 0; r < t.rows.length; r++) {
            g[r] = [];
            for (let c = 0; c < t.rows[r].cells.length; c++) {
              const curCell = t.rows[r].cells[c];
              g[r][c] = curCell.getAttribute('data-formula-val') || cleanFormulaText(curCell.innerText || curCell.textContent || '');
            }
          }
          return g;
        });

        // 1. Update CKEditor Model
        if (editorInstance && editorInstance.model) {
          const model = editorInstance.model;
          const root = model.document.getRoot();
          if (root) {
            const formulaItems = [];
            const scanModel = (parent) => {
              for (const child of parent.getChildren()) {
                if (child.is && child.is('\$text')) {
                  const inf = child.getAttribute('inlineFormula');
                  if (inf) {
                    const formula = typeof inf === 'string' ? inf : (inf.formula || '');
                    const tIdx = (typeof inf === 'object' && inf.tableIdx !== undefined) ? inf.tableIdx : 0;
                    if (formula) {
                      formulaItems.push({ item: child, formula: formula, tableIdx: tIdx });
                    }
                  }
                } else if (child.getChildren) {
                  scanModel(child);
                }
              }
            };
            scanModel(root);

            const toUpdate = [];
            for (const entry of formulaItems) {
              const grid = grids[entry.tableIdx] || grids[0];
              if (!grid) continue;
              const res = evaluateFormulaString(entry.formula, grid, -1, -1);
              if (res !== null && !isNaN(res)) {
                const freshVal = String(res);
                if (entry.item.data !== freshVal) {
                  toUpdate.push({
                    item: entry.item,
                    formula: entry.formula,
                    tableIdx: entry.tableIdx,
                    freshVal: freshVal
                  });
                }
              }
            }

            if (toUpdate.length > 0) {
              toUpdate.reverse();
              const updateWriter = (writer) => {
                for (const u of toUpdate) {
                  const range = writer.createRangeOn(u.item);
                  const attrs = {};
                  for (const [k, v] of u.item.getAttributes()) {
                    attrs[k] = v;
                  }
                  attrs.inlineFormula = { formula: u.formula, tableIdx: u.tableIdx };
                  writer.remove(range);
                  writer.insertText(u.freshVal, attrs, range.start);
                }
              };

              let batch = null;
              if (typeof model.createBatch === 'function') {
                try { batch = model.createBatch({ isUndoable: false }); } catch (e) { batch = null; }
              }
              if (batch && typeof model.enqueueChange === 'function') {
                model.enqueueChange(batch, updateWriter);
              } else if (typeof model.change === 'function') {
                model.change(updateWriter);
              }
            }
          }
        }

        // 2. Also ensure DOM spans have correct class, data-formula, and titles
        const allFormulaSpans = Array.from(document.querySelectorAll('.ck-content .inline-formula-pill, .ck-content span[data-formula], #fallback-content .inline-formula-pill, #fallback-content span[data-formula]'));
        allFormulaSpans.forEach(span => {
          if (span.closest('td, th')) return;

          const formula = span.getAttribute('data-formula') || span.getAttribute('data-inline-formula');
          if (!formula) return;

          let tIdx = parseInt(span.getAttribute('data-table-idx'), 10) || 0;
          const grid = grids[tIdx] || grids[0];
          if (!grid) return;

          const res = evaluateFormulaString(formula, grid, -1, -1);
          if (res !== null && !isNaN(res)) {
            const freshVal = String(res);
            span.setAttribute('title', 'Formula: ' + formula + ' = ' + freshVal + ' (Live Calculation - Click to edit)');
            if (isFallback || !editorInstance) {
              const curText = (span.innerText || span.textContent || '').trim();
              if (curText !== freshVal) {
                span.textContent = freshVal;
              }
            }
          }
        });
      } catch (e) {
        console.warn('updateInlineFormulasDOM error:', e);
      }
    }
    window.updateInlineFormulasDOM = updateInlineFormulasDOM;

    let cellRefHighlight = null;
    function highlightReferencedTableCell(coord, tableIdx) {
      const pos = parseCellCoord(coord);
      if (!pos) return;
      const liveTables = getEditorLiveTables();
      const tIdx = tableIdx || 0;
      const table = liveTables && liveTables[tIdx];
      const cell = table && table.rows[pos.row] ? table.rows[pos.row].cells[pos.col] : null;
      /* One overlay at a time; it follows the cell while the smooth scroll runs */
      if (cellRefHighlight) { cancelAnimationFrame(cellRefHighlight.frame); cellRefHighlight.el.remove(); cellRefHighlight = null; }
      if (!cell) {
        showToastMsg('⚠️ Cell ' + coord + ' was not found in table ' + (tIdx + 1));
        return;
      }
      cell.scrollIntoView({ behavior: 'smooth', block: 'center' });

      const el = document.createElement('div');
      el.className = 'cell-ref-highlight-overlay';
      document.body.appendChild(el);
      const scroller = getEditorScrollContainer(cell);
      const until = performance.now() + 2600;
      const state = { el: el, frame: 0 };
      cellRefHighlight = state;
      const follow = () => {
        if (!document.contains(cell) || performance.now() > until) {
          el.style.opacity = '0';
          setTimeout(() => el.remove(), 300);
          if (cellRefHighlight === state) cellRefHighlight = null;
          return;
        }
        const r = cell.getBoundingClientRect();
        const clip = scroller && scroller !== document.scrollingElement ? scroller.getBoundingClientRect() : { top: 0, bottom: window.innerHeight };
        const top = Math.max(r.top, clip.top);
        const bottom = Math.min(r.bottom, clip.bottom);
        el.style.display = bottom > top ? 'block' : 'none';
        el.style.left = r.left + 'px';
        el.style.top = top + 'px';
        el.style.width = r.width + 'px';
        el.style.height = Math.max(0, bottom - top) + 'px';
        state.frame = requestAnimationFrame(follow);
      };
      follow();
      showToastMsg('📍 Linked table cell ' + coord + ' highlighted');
    }

    // Modal picker implementation
    function showCellRefModal() {
      const liveTables = getEditorLiveTables();
      if (!liveTables || liveTables.length === 0) {
        showToastMsg('⚠️ Please insert a table first before referencing cells.');
        return;
      }
      const select = document.getElementById('cell-ref-table-select');
      if (select) {
        select.innerHTML = '';
        liveTables.forEach((t, i) => {
          const opt = document.createElement('option');
          opt.value = i;
          opt.textContent = 'Table ' + (i + 1) + ' (' + t.rows.length + ' rows × ' + (t.rows[0] ? t.rows[0].cells.length : 0) + ' cols)';
          select.appendChild(opt);
        });
      }
      renderCellRefPickerGrid();
      const modal = document.getElementById('cell-ref-modal');
      modal.classList.add('show');
      setTimeout(() => {
        const search = document.getElementById('cell-ref-search');
        if (search) search.focus();
      }, 100);
    }
    window.showCellRefModal = showCellRefModal;

    function closeCellRefModal() {
      document.getElementById('cell-ref-modal').classList.remove('show');
    }
    window.closeCellRefModal = closeCellRefModal;

    function renderCellRefPickerGrid() {
      const container = document.getElementById('cell-ref-grid-container');
      if (!container) return;

      const liveTables = getEditorLiveTables();
      const select = document.getElementById('cell-ref-table-select');
      const tableIdx = select ? parseInt(select.value, 10) || 0 : 0;
      const searchInput = document.getElementById('cell-ref-search');
      const query = (searchInput ? searchInput.value : '').trim().toLowerCase();

      container.innerHTML = '';

      const table = liveTables[tableIdx] || liveTables[0];
      if (!table) {
        container.innerHTML = '<p style="color:#64748b;text-align:center;padding:20px;">No tables found</p>';
        return;
      }

      const grid = document.createElement('div');
      grid.style.display = 'grid';
      grid.style.gridTemplateColumns = 'repeat(auto-fill, minmax(130px, 1fr))';
      grid.style.gap = '8px';

      let matchCount = 0;

      for (let r = 0; r < table.rows.length; r++) {
        const cells = table.rows[r].cells;
        for (let c = 0; c < cells.length; c++) {
          const cell = cells[c];
          const coord = getCellCoordString(c, r);
          const cellText = cleanFormulaText(cell.innerText || cell.textContent || '');
          const formulaVal = cell.getAttribute('data-formula-val');
          const displayVal = (formulaVal != null && formulaVal !== '') ? formulaVal : cellText;

          let header = '';
          if (r > 0 && table.rows[0].cells[c]) {
            header = cleanFormulaText(table.rows[0].cells[c].innerText || '');
          }

          if (query) {
            const mCoord = coord.toLowerCase().includes(query) || ('\$' + coord).toLowerCase().includes(query);
            const mVal = displayVal.toLowerCase().includes(query);
            const mHead = header.toLowerCase().includes(query);
            if (!mCoord && !mVal && !mHead) continue;
          }

          matchCount++;
          const card = document.createElement('div');
          card.style.background = '#ffffff';
          card.style.border = '1px solid #cbd5e1';
          card.style.borderRadius = '6px';
          card.style.padding = '6px 8px';
          card.style.cursor = 'pointer';
          card.style.display = 'flex';
          card.style.flexDirection = 'column';
          card.style.gap = '3px';
          card.style.transition = 'all 0.15s ease';
          card.style.boxShadow = '0 1px 2px rgba(0,0,0,0.04)';

          card.onmouseenter = function() {
            card.style.borderColor = '#3b82f6';
            card.style.background = '#eff6ff';
          };
          card.onmouseleave = function() {
            card.style.borderColor = '#cbd5e1';
            card.style.background = '#ffffff';
          };
          card.onclick = (function(coordVal, textVal, tIdxVal) {
            return function() {
              insertCellReference(coordVal, textVal, tIdxVal);
            };
          })(coord, displayVal, tableIdx);

          const topRow = document.createElement('div');
          topRow.style.display = 'flex';
          topRow.style.alignItems = 'center';
          topRow.style.justifyContent = 'space-between';

          const badge = document.createElement('span');
          badge.style.fontWeight = 'bold';
          badge.style.fontFamily = 'monospace';
          badge.style.fontSize = '11px';
          badge.style.background = '#dcfce7';
          badge.style.color = '#15803d';
          badge.style.padding = '1px 5px';
          badge.style.borderRadius = '3px';
          badge.textContent = coord;

          const headSpan = document.createElement('span');
          headSpan.style.fontSize = '10px';
          headSpan.style.color = '#94a3b8';
          headSpan.style.overflow = 'hidden';
          headSpan.style.textOverflow = 'ellipsis';
          headSpan.style.whiteSpace = 'nowrap';
          headSpan.style.maxWidth = '65px';
          headSpan.textContent = header ? ('• ' + header) : '';

          topRow.appendChild(badge);
          topRow.appendChild(headSpan);

          const valDiv = document.createElement('div');
          valDiv.style.fontSize = '12px';
          valDiv.style.fontWeight = '600';
          valDiv.style.color = '#1e293b';
          valDiv.style.overflow = 'hidden';
          valDiv.style.textOverflow = 'ellipsis';
          valDiv.style.whiteSpace = 'nowrap';
          valDiv.title = displayVal || '(empty)';
          valDiv.textContent = displayVal || '(empty)';

          card.appendChild(topRow);
          card.appendChild(valDiv);
          grid.appendChild(card);
        }
      }

      if (matchCount === 0) {
        container.innerHTML = '<p style="color:#64748b;text-align:center;padding:24px;">No cells match "' + query + '"</p>';
      } else {
        container.appendChild(grid);
      }
    }
    window.renderCellRefPickerGrid = renderCellRefPickerGrid;

    function insertCellReference(coord, val, tableIdx) {
      if (tableIdx === undefined || tableIdx === null) tableIdx = 0;
      closeCellRefModal();
      coord = (coord || 'A1').toUpperCase();
      const token = '\$' + (tableIdx > 0 ? ('T' + (tableIdx + 1) + ':' + coord) : coord);
      const displayText = val || token;

      if (editorInstance) {
        try {
          editorInstance.model.change(writer => {
            const sel = editorInstance.model.document.selection;
            const refData = {
              coord: coord,
              tableIdx: tableIdx
            };
            const textNode = writer.createText(displayText, {
              tableCellRef: refData
            });
            editorInstance.model.insertContent(textNode, sel);
            editorInstance.model.insertContent(writer.createText(' '), sel);
          });
          setTimeout(updateTableCellReferencesDOM, 20);
          showToastMsg('✓ Inserted live reference to ' + coord + ' ("' + displayText + '")');
        } catch (e) {
          console.warn('insertCellReference model error:', e);
        }
      } else if (isFallback) {
        const fc = document.getElementById('fallback-content');
        if (fc) {
          const pill = '<span class="mention table-cell-ref" data-mention="' + token + '" data-cell-coord="' + coord + '" data-table-idx="' + tableIdx + '" title="Table cell ' + coord + ': &quot;' + displayText + '&quot; (Live Link)">' + displayText + '</span>&nbsp;';
          document.execCommand('insertHTML', false, pill);
          showToastMsg('✓ Inserted live reference to ' + coord + ' ("' + displayText + '")');
        }
      }
    }
    window.insertCellReference = insertCellReference;

    /* ====== TABLE COLOR & STYLING LOGIC ====== */
    let lastActiveTableCell = null;
    let currentTableTarget = 'cell';

    document.addEventListener('click', function(e) {
      const cell = e.target.closest('td, th');
      if (cell) lastActiveTableCell = cell;
    }, true);

    document.addEventListener('selectionchange', function() {
      const sel = window.getSelection ? window.getSelection() : null;
      if (sel && sel.anchorNode) {
        const node = sel.anchorNode.nodeType === Node.ELEMENT_NODE ? sel.anchorNode : sel.anchorNode.parentElement;
        const cell = node ? node.closest('td, th') : null;
        if (cell) lastActiveTableCell = cell;
      }
    });

    function getActiveTableCell() {
      const sel = window.getSelection ? window.getSelection() : null;
      if (sel && sel.anchorNode) {
        const node = sel.anchorNode.nodeType === Node.ELEMENT_NODE ? sel.anchorNode : sel.anchorNode.parentElement;
        const cell = node ? node.closest('td, th') : null;
        if (cell && document.contains(cell)) {
          lastActiveTableCell = cell;
          return cell;
        }
      }
      if (document.activeElement) {
        const cell = document.activeElement.closest('td, th');
        if (cell && document.contains(cell)) {
          lastActiveTableCell = cell;
          return cell;
        }
      }
      if (lastActiveTableCell && document.contains(lastActiveTableCell)) {
        return lastActiveTableCell;
      }
      return null;
    }

    function openTableColorModal() {
      let cell = getActiveTableCell();
      if (!cell) {
        const anyCell = document.querySelector('.ck-content table td, .ck-content table th, #fallback-content table td, #fallback-content table th, table td, table th');
        if (anyCell) {
          lastActiveTableCell = anyCell;
          cell = anyCell;
        } else {
          showToastMsg('⚠️ Please insert or click inside a table first!');
          return;
        }
      }
      const coordEl = document.getElementById('tbl-color-target-info');
      if (coordEl && cell) {
        const r = cell.closest('tr') ? cell.closest('tr').rowIndex : 0;
        const c = cell.cellIndex !== undefined ? cell.cellIndex : 0;
        const colLetter = String.fromCharCode(65 + (c % 26));
        coordEl.textContent = 'Active: Cell ' + colLetter + (r + 1);
      }
      document.getElementById('table-color-modal').classList.add('show');
    }

    function closeTableColorModal() {
      document.getElementById('table-color-modal').classList.remove('show');
    }

    function setTableColorTarget(target) {
      currentTableTarget = target;
      document.querySelectorAll('.tbl-target-btn').forEach(btn => {
        btn.classList.toggle('active', btn.getAttribute('data-target') === target);
      });
    }

    /* Each control changes only its own property: background, border or text color */
    function applyPresetBg(bg) {
      applyTableFormatting({ bg: bg });
    }

    function applyCustomBg(bg) {
      applyTableFormatting({ bg: bg });
    }

    function clearTableBg() {
      applyTableFormatting({ bg: '' });
    }

    function applyBorderColor(borderColor) {
      applyTableFormatting({ border: borderColor });
    }

    function applyTextColor(txtColor) {
      applyTableFormatting({ text: txtColor });
    }

    /* Model table cells the color target should affect, resolved from the editor selection */
    function getTargetModelTableCells(editor) {
      const tableUtils = editor.plugins.get('TableUtils');
      const selection = editor.model.document.selection;
      let selectedCells = tableUtils.getSelectionAffectedTableCells(selection);
      if (selectedCells.length === 0) {
        /* Selection left the table (e.g. focus moved to the modal) - fall back to the last clicked cell */
        const domCell = getActiveTableCell();
        if (domCell) {
          try {
            const viewCell = editor.editing.view.domConverter.mapDomToView(domCell);
            const modelCell = viewCell ? editor.editing.mapper.toModelElement(viewCell) : null;
            if (modelCell && modelCell.is('element', 'tableCell')) selectedCells = [modelCell];
          } catch (e) {}
        }
      }
      if (selectedCells.length === 0) return [];

      const anchor = selectedCells[0];
      const table = anchor.findAncestor('table');
      if (!table) return [];
      if (currentTableTarget === 'cell') return selectedCells;

      const anchorLoc = tableUtils.getCellLocation(anchor);
      const headingRows = table.getAttribute('headingRows') || 1;
      const result = [];
      for (const row of table.getChildren()) {
        if (!row.is('element', 'tableRow')) continue;
        for (const cell of row.getChildren()) {
          if (!cell.is('element', 'tableCell')) continue;
          const loc = tableUtils.getCellLocation(cell);
          const rowSpan = parseInt(cell.getAttribute('rowspan') || 1, 10);
          const colSpan = parseInt(cell.getAttribute('colspan') || 1, 10);
          const coversRow = anchorLoc.row >= loc.row && anchorLoc.row < loc.row + rowSpan;
          const coversCol = anchorLoc.column >= loc.column && anchorLoc.column < loc.column + colSpan;
          if ((currentTableTarget === 'row' && coversRow) ||
              (currentTableTarget === 'col' && coversCol) ||
              (currentTableTarget === 'header' && loc.row < headingRows) ||
              currentTableTarget === 'table' || currentTableTarget === 'zebra') {
            result.push({ cell: cell, row: loc.row });
          }
        }
      }
      return result.map(r => (currentTableTarget === 'zebra' ? r : r.cell));
    }

    function zebraBg(bgColor, rowIdx) {
      if (bgColor === undefined) return undefined;
      return rowIdx % 2 === 0 ? (bgColor || '#f8fafc') : '#ffffff';
    }

    function applyTableFormatting(opts) {
      const bgColor = opts.bg;
      const borderColor = opts.border;
      const txtColor = opts.text;

      if (editorInstance && editorInstance.model) {
        const editor = editorInstance;
        let targets = [];
        try { targets = getTargetModelTableCells(editor); } catch (e) { console.warn('Table target error:', e); }
        if (targets.length === 0) {
          showToastMsg('⚠️ Click inside a table cell first!');
          return;
        }
        const schema = editor.model.schema;
        const setTextAttr = (writer, cell, key, value) => {
          const ranges = schema.getValidRanges([writer.createRangeIn(cell)], key);
          for (const range of ranges) {
            if (value === '' || value === null) writer.removeAttribute(key, range);
            else writer.setAttribute(key, value, range);
          }
        };
        const styleCell = (writer, cell, bg) => {
          if (bg !== undefined) {
            if (bg === '') writer.removeAttribute('tableCellBackgroundColor', cell);
            else writer.setAttribute('tableCellBackgroundColor', bg, cell);
          }
          if (borderColor !== undefined) {
            if (borderColor === '') {
              writer.removeAttribute('tableCellBorderColor', cell);
            } else {
              writer.setAttribute('tableCellBorderColor', borderColor, cell);
              /* A color alone is invisible without a border style/width */
              if (!cell.getAttribute('tableCellBorderStyle')) writer.setAttribute('tableCellBorderStyle', 'solid', cell);
              if (!cell.getAttribute('tableCellBorderWidth')) writer.setAttribute('tableCellBorderWidth', '1px', cell);
            }
          }
          if (txtColor !== undefined) setTextAttr(writer, cell, 'fontColor', txtColor);
          if (currentTableTarget === 'header') setTextAttr(writer, cell, 'bold', true);
        };
        try {
          editor.model.change(writer => {
            if (currentTableTarget === 'zebra') {
              /* Background stripes alternate rows; border/text pickers apply to every row */
              targets.forEach(t => styleCell(writer, t.cell, zebraBg(bgColor, t.row)));
            } else {
              targets.forEach(cell => styleCell(writer, cell, bgColor));
            }
          });
        } catch (e) {
          console.warn('Model table formatting error:', e);
          showToastMsg('⚠️ Could not apply table formatting');
          return;
        }
        showToastMsg('🎨 Table formatting updated!');
        return;
      }

      /* Fallback editor (plain contenteditable): style the DOM directly */
      const cell = getActiveTableCell();
      if (!cell || !cell.closest('table')) {
        showToastMsg('⚠️ Click inside a table cell first!');
        return;
      }
      const table = cell.closest('table');
      const row = cell.closest('tr');
      const colIdx = cell.cellIndex !== undefined ? cell.cellIndex : 0;
      const applyToDomCell = (c, bg) => {
        if (!c) return;
        if (bg !== undefined) c.style.backgroundColor = bg;
        if (txtColor !== undefined) c.style.color = txtColor;
        if (borderColor !== undefined) {
          c.style.borderColor = borderColor;
          if (borderColor) {
            c.style.borderWidth = c.style.borderWidth || '1px';
            c.style.borderStyle = c.style.borderStyle || 'solid';
          }
        }
        if (currentTableTarget === 'header') c.style.fontWeight = '700';
      };
      for (let i = 0; i < table.rows.length; i++) {
        const r = table.rows[i];
        for (let j = 0; j < r.cells.length; j++) {
          const c = r.cells[j];
          const hit = currentTableTarget === 'table' || currentTableTarget === 'zebra' ||
            (currentTableTarget === 'cell' && c === cell) ||
            (currentTableTarget === 'row' && r === row) ||
            (currentTableTarget === 'col' && j === colIdx) ||
            (currentTableTarget === 'header' && i === 0);
          if (!hit) continue;
          applyToDomCell(c, currentTableTarget === 'zebra' ? zebraBg(bgColor, i) : bgColor);
        }
      }
      if (typeof updateFallbackStats === 'function') updateFallbackStats();
      postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
      showToastMsg('🎨 Table formatting updated!');
    }

    /* ====== TABLE ROW & COLUMN EDITING UTILITIES ====== */
    function insertTableRow(above) {
      if (editorInstance) {
        editorInstance.execute(above ? 'insertTableRowAbove' : 'insertTableRowBelow');
        setTimeout(() => { scanAndRegisterTableFormulas(); autoUpdateTableFormulasDOM(); }, 60);
      } else {
        const cell = window._targetFormulaCell || lastActiveTableCell || getActiveTableCell();
        if (cell && cell.closest('table')) {
          const table = cell.closest('table');
          const row = cell.closest('tr');
          const rIdx = row ? row.rowIndex : 0;
          const newRow = table.insertRow(above ? rIdx : rIdx + 1);
          const colCount = row ? row.cells.length : 1;
          for (let i = 0; i < colCount; i++) {
            const c = newRow.insertCell();
            c.innerHTML = '<p><br></p>';
            c.style.border = '1px solid #cbd5e1';
            c.style.padding = '8px 12px';
          }
        }
      }
      showToastMsg('➕ ' + (above ? 'Row inserted above' : 'Row inserted below'));
    }

    function deleteTableRow() {
      if (editorInstance) {
        editorInstance.execute('deleteTableRow');
        setTimeout(() => { scanAndRegisterTableFormulas(); autoUpdateTableFormulasDOM(); }, 60);
      } else {
        const cell = window._targetFormulaCell || lastActiveTableCell || getActiveTableCell();
        if (cell && cell.closest('tr')) {
          cell.closest('tr').remove();
        }
      }
      showToastMsg('🗑️ Row deleted');
    }

    function insertTableColumn(left) {
      if (editorInstance) {
        editorInstance.execute(left ? 'insertTableColumnLeft' : 'insertTableColumnRight');
        setTimeout(() => { scanAndRegisterTableFormulas(); autoUpdateTableFormulasDOM(); }, 60);
      } else {
        const cell = window._targetFormulaCell || lastActiveTableCell || getActiveTableCell();
        if (cell && cell.closest('table')) {
          const table = cell.closest('table');
          const cIdx = cell.cellIndex !== undefined ? cell.cellIndex : 0;
          const targetIdx = left ? cIdx : cIdx + 1;
          for (let r = 0; r < table.rows.length; r++) {
            const c = table.rows[r].insertCell(targetIdx);
            c.innerHTML = '<p><br></p>';
            c.style.border = '1px solid #cbd5e1';
            c.style.padding = '8px 12px';
          }
        }
      }
      showToastMsg('➕ ' + (left ? 'Column inserted left' : 'Column inserted right'));
    }

    function deleteTableColumn() {
      if (editorInstance) {
        editorInstance.execute('deleteTableColumn');
        setTimeout(() => { scanAndRegisterTableFormulas(); autoUpdateTableFormulasDOM(); }, 60);
      } else {
        const cell = window._targetFormulaCell || lastActiveTableCell || getActiveTableCell();
        if (cell && cell.closest('table')) {
          const table = cell.closest('table');
          const cIdx = cell.cellIndex !== undefined ? cell.cellIndex : 0;
          for (let r = 0; r < table.rows.length; r++) {
            if (table.rows[r].cells[cIdx]) {
              table.rows[r].deleteCell(cIdx);
            }
          }
        }
      }
      showToastMsg('🗑️ Column deleted');
    }

    /* ====== UNIVERSAL PASTE SANITIZER & NORMALIZER ====== */
    function sanitizePastedHtml(rawHtml) {
      if (!rawHtml) return '';
      const parser = new DOMParser();
      const doc = parser.parseFromString(rawHtml, 'text/html');
      const body = doc.body;

      // 1. Remove Office / Word specific junk tags
      body.querySelectorAll('o\\:p, xml, style, meta, link, title').forEach(el => el.remove());

      // 2. Process all elements
      const all = body.querySelectorAll('*');
      all.forEach(el => {
        // Strip foreign font families so text inherits the active document font
        if (el.style.fontFamily) el.style.fontFamily = '';

        // Normalize arbitrary foreign font sizes (preserve semantic headings h1-h6 and code)
        if (el.style.fontSize) {
          const tag = el.tagName.toLowerCase();
          if (!['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'code', 'pre'].includes(tag)) {
            el.style.fontSize = '';
          }
        }

        // Strip foreign line-height
        if (el.style.lineHeight) el.style.lineHeight = '';

        // Strip mso-* styles
        const styleAttr = el.getAttribute('style') || '';
        if (styleAttr.includes('mso-') || styleAttr.includes('tab-stops:')) {
          const clean = styleAttr
            .split(';')
            .map(s => s.trim())
            .filter(s => s && !s.startsWith('mso-') && !s.startsWith('tab-stops:'))
            .join('; ');
          if (clean) {
            el.setAttribute('style', clean);
          } else {
            el.removeAttribute('style');
          }
        }

        // For table elements: clean fixed heights and widths so they are fluid and uniform
        const tag = el.tagName.toLowerCase();
        if (['table', 'tr', 'td', 'th'].includes(tag)) {
          el.removeAttribute('height');
          el.style.height = '';
          el.style.minHeight = '';
          el.style.maxHeight = '';
          
          const w = el.getAttribute('width') || el.style.width;
          if (w && (w.endsWith('pt') || w.endsWith('px') || !isNaN(Number(w)))) {
            el.removeAttribute('width');
            el.style.width = '';
          }
        }

        // Unwrap empty/styleless spans
        if (tag === 'span') {
          const st = el.getAttribute('style');
          if ((!st || !st.trim()) && !el.className && !el.attributes.length) {
            while (el.firstChild) {
              el.parentNode.insertBefore(el.firstChild, el);
            }
            el.remove();
          }
        }
      });

      return body.innerHTML;
    }

    function harmonizeActiveTable() {
      const cell = getActiveTableCell();
      if (!cell) {
        showToastMsg('⚠️ Click inside a table first!');
        return;
      }
      const table = cell.closest('table');
      if (!table) return;

      for (let r = 0; r < table.rows.length; r++) {
        const row = table.rows[r];
        row.removeAttribute('height');
        row.style.height = '';
        for (let c = 0; c < row.cells.length; c++) {
          const td = row.cells[c];
          td.style.fontFamily = '';
          td.style.fontSize = '';
          td.style.lineHeight = '';
          td.style.height = '';
          td.removeAttribute('height');
          td.removeAttribute('width');
          td.querySelectorAll('*').forEach(child => {
            child.style.fontFamily = '';
            child.style.fontSize = '';
            child.style.lineHeight = '';
            child.style.height = '';
          });
        }
      }

      if (editorInstance) {
        try {
          const html = getEditorData();
          postToFlutter({ type: 'ckeditor_change', html: html });
        } catch(e) {}
      }
      showToastMsg('✨ Table typography & dimensions harmonized!');
    }

    function harmonizeSelectionStyles() {
      const cell = getActiveTableCell();
      if (cell) {
        harmonizeActiveTable();
        return;
      }
      const editable = document.querySelector('.ck-content, #fallback-content');
      if (editable) {
        editable.querySelectorAll('table, tr, td, th, p, span').forEach(el => {
          if (['tr', 'td', 'th', 'table'].includes(el.tagName.toLowerCase())) {
            el.removeAttribute('height');
            el.removeAttribute('width');
            el.style.height = '';
          }
          el.style.fontFamily = '';
          if (!['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'code', 'pre'].includes(el.tagName.toLowerCase())) {
            el.style.fontSize = '';
          }
          el.style.lineHeight = '';
        });
        if (editorInstance) {
          try {
            const html = getEditorData();
            postToFlutter({ type: 'ckeditor_change', html: html });
          } catch(e) {}
        }
        showToastMsg('✨ Document typography harmonized!');
      }
    }

    /* ====== VIDEO SIZING & RESIZE CONTROLS ====== */
    let currentVideoTab = 'url';
    let selectedVideoSize = '50%';
    let selectedVideoAlign = 'center';
    let activeMediaFigure = null;
    let videoResizeToolbar = null;

    function openVideoModal() {
      document.getElementById('video-modal').classList.add('show');
    }

    function closeVideoModal() {
      document.getElementById('video-modal').classList.remove('show');
    }

    function switchVideoTab(tab) {
      currentVideoTab = tab;
      document.getElementById('tab-video-url').classList.toggle('active', tab === 'url');
      document.getElementById('tab-video-file').classList.toggle('active', tab === 'file');
      document.getElementById('video-tab-url-content').style.display = tab === 'url' ? 'block' : 'none';
      document.getElementById('video-tab-file-content').style.display = tab === 'file' ? 'block' : 'none';
    }

    function selectVideoInitialSize(size) {
      selectedVideoSize = size;
      document.querySelectorAll('.video-size-opt').forEach(btn => {
        btn.classList.toggle('active', btn.getAttribute('data-size') === size);
      });
    }

    function selectVideoInitialAlign(align) {
      selectedVideoAlign = align;
      document.querySelectorAll('.video-align-opt').forEach(btn => {
        btn.classList.toggle('active', btn.getAttribute('data-align') === align);
      });
    }

    function insertConfiguredVideo() {
      let embedHtml = '';
      const size = selectedVideoSize || '50%';
      const align = selectedVideoAlign || 'center';
      const alignClass = 'media-align-' + align;
      const styleAttr = 'width:' + size + ';max-width:' + size + ';margin:16px auto;';

      if (currentVideoTab === 'url') {
        const url = document.getElementById('video-url-input').value.trim();
        if (!url) {
          showToastMsg('⚠️ Please enter a video URL');
          return;
        }

        function extractYouTubeId(urlStr) {
          try {
            var fullUrl = urlStr.indexOf('://') === -1 ? 'https://' + urlStr : urlStr;
            var u = new URL(fullUrl);
            if (u.hostname.indexOf('youtu.be') !== -1) {
              var p = u.pathname.charAt(0) === '/' ? u.pathname.substring(1) : u.pathname;
              return p.split('?')[0].split('&')[0];
            }
            if (u.hostname.indexOf('youtube.com') !== -1) {
              if (u.pathname.indexOf('/shorts/') !== -1) {
                return u.pathname.split('/shorts/')[1].split('/')[0];
              }
              if (u.pathname.indexOf('/embed/') !== -1) {
                return u.pathname.split('/embed/')[1].split('?')[0];
              }
              if (u.pathname.indexOf('/v/') !== -1) {
                return u.pathname.split('/v/')[1].split('?')[0];
              }
              return u.searchParams.get('v');
            }
          } catch (e) {}
          return null;
        }

        const ytId = extractYouTubeId(url);
        let vimeoId = '';
        if (!ytId && url.indexOf('vimeo.com/') !== -1) {
          vimeoId = url.split('vimeo.com/')[1].split('?')[0].split('#')[0].split('/').filter(Boolean).pop() || '';
        }
        /* YouTube/Vimeo go through CKEditor Media Embed (same as its toolbar button) so the player
           stays a real media widget: playable in Preview, resizable, and kept in the saved HTML */
        const embedUrl = ytId ? 'https://www.youtube.com/watch?v=' + ytId : (vimeoId ? 'https://vimeo.com/' + vimeoId : '');
        if (embedUrl && editorInstance && editorInstance.commands.get('mediaEmbed')) {
          closeVideoModal();
          insertVideoViaMediaEmbed(embedUrl, size, align);
          return;
        }
        if (ytId) {
          const videoSrc = 'https://www.youtube.com/embed/' + ytId;
          embedHtml = '<figure class="media ' + alignClass + '" style="' + styleAttr + '"><iframe src="' + videoSrc + '" style="width:100%;aspect-ratio:16/9;border:none;border-radius:8px;" allowfullscreen></iframe></figure><p>&nbsp;</p>';
        } else if (url.indexOf('vimeo.com/') !== -1) {
          const vimeoParts = url.split('vimeo.com/')[1].split('?')[0].split('#')[0].split('/');
          const vimeoId = vimeoParts.filter(Boolean).pop() || '';
          const videoSrc = 'https://player.vimeo.com/video/' + vimeoId;
          embedHtml = '<figure class="media ' + alignClass + '" style="' + styleAttr + '"><iframe src="' + videoSrc + '" style="width:100%;aspect-ratio:16/9;border:none;border-radius:8px;" allowfullscreen></iframe></figure><p>&nbsp;</p>';
        } else {
          embedHtml = '<figure class="media ' + alignClass + '" style="' + styleAttr + '"><video controls src="' + url + '" style="width:100%;aspect-ratio:16/9;border-radius:8px;"></video></figure><p>&nbsp;</p>';
        }
      } else {
        const fileInput = document.getElementById('video-file-input');
        if (!fileInput.files || !fileInput.files[0]) {
          showToastMsg('⚠️ Please select a video file to upload');
          return;
        }
        const file = fileInput.files[0];
        const videoBlobUrl = URL.createObjectURL(file);
        embedHtml = '<figure class="media ' + alignClass + '" style="' + styleAttr + '"><video controls src="' + videoBlobUrl + '" style="width:100%;aspect-ratio:16/9;border-radius:8px;"></video></figure><p>&nbsp;</p>';
      }

      closeVideoModal();
      if (editorInstance) {
        const viewFragment = editorInstance.data.processor.toView(embedHtml);
        const modelFragment = editorInstance.data.toModel(viewFragment);
        moveSelectionAfterSelectedWidget(editorInstance);
        editorInstance.model.insertContent(modelFragment);
        setTimeout(() => {
          attachMediaListeners();
          attachMediaDragHandles();
          const allMedia = document.querySelectorAll('.ck-content figure.media, .ck-content .media');
          const latest = allMedia[allMedia.length - 1];
          if (latest) {
            latest.style.width = size;
            latest.style.maxWidth = size;
            latest.classList.add(alignClass);
          }
        }, 120);
      }
      showToastMsg('🎬 Video attached (' + size + ' width)');
    }

    /* With a widget (e.g. another video) selected, inserting would replace it - insert after it instead */
    function moveSelectionAfterSelectedWidget(editor) {
      const selected = editor.model.document.selection.getSelectedElement();
      if (!selected || !editor.model.schema.isObject(selected)) return;
      editor.model.change(writer => {
        const paragraph = writer.createElement('paragraph');
        writer.insert(paragraph, selected, 'after');
        writer.setSelection(paragraph, 0);
      });
    }

    function insertVideoViaMediaEmbed(url, size, align) {
      const editor = editorInstance;
      const margin = align === 'left' ? '16px auto 16px 0' : (align === 'right' ? '16px 0 16px auto' : '16px auto');
      /* Size/alignment live in the media style registry, keyed by the figure's data-oembed-url */
      window._mediaStyleRegistry = window._mediaStyleRegistry || {};
      window._mediaStyleRegistry[url] = {
        width: size,
        maxWidth: size,
        margin: margin,
        style: 'width:' + size + ';max-width:' + size + ';margin:' + margin + ';'
      };
      moveSelectionAfterSelectedWidget(editor);
      editor.execute('mediaEmbed', url);
      editor.editing.view.focus();
      setTimeout(() => {
        reapplyAllMediaStyles();
        attachMediaListeners();
        attachMediaDragHandles();
        postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
      }, 120);
      showToastMsg('🎬 Video attached (' + size + ' width)');
    }

    function ensureVideoResizeToolbar() {
      if (videoResizeToolbar) return videoResizeToolbar;
      const tb = document.createElement('div');
      tb.className = 'video-resize-toolbar';
      tb.id = 'video-resize-toolbar';
      tb.innerHTML = '<span style="font-size:10px;color:#94a3b8;margin-right:2px;">Size:</span>' +
        '<button type="button" data-size="25%" onclick="resizeActiveMedia(&quot;25%&quot;)">25%</button>' +
        '<button type="button" data-size="50%" onclick="resizeActiveMedia(&quot;50%&quot;)">50%</button>' +
        '<button type="button" data-size="75%" onclick="resizeActiveMedia(&quot;75%&quot;)">75%</button>' +
        '<button type="button" data-size="100%" onclick="resizeActiveMedia(&quot;100%&quot;)">100%</button>' +
        '<span style="width:1px;height:14px;background:#475569;margin:0 2px;"></span>' +
        '<button type="button" onclick="alignActiveMedia(&quot;left&quot;)" title="Align Left">⬅️</button>' +
        '<button type="button" onclick="alignActiveMedia(&quot;center&quot;)" title="Center">⏺️</button>' +
        '<button type="button" onclick="alignActiveMedia(&quot;right&quot;)" title="Align Right">➡️</button>' +
        '<span style="width:1px;height:14px;background:#475569;margin:0 2px;"></span>' +
        '<input type="range" min="20" max="100" value="50" oninput="resizeActiveMedia(this.value + &quot;%&quot;)" title="Slide to adjust width">' +
        '<button type="button" onclick="removeActiveMedia()" title="Remove Video" style="color:#f87171;">🗑️</button>';
      document.body.appendChild(tb);
      tb.style.display = 'none';
      videoResizeToolbar = tb;
      return tb;
    }

    function getMediaUrlFromFigure(fig) {
      if (!fig) return null;
      try {
        const oembedDiv = fig.querySelector('[data-oembed-url]');
        if (oembedDiv && oembedDiv.getAttribute('data-oembed-url')) {
          return oembedDiv.getAttribute('data-oembed-url').trim();
        }
        const oembed = fig.querySelector('oembed');
        if (oembed && oembed.getAttribute('url')) {
          return oembed.getAttribute('url').trim();
        }
        const iframe = fig.querySelector('iframe');
        if (iframe && iframe.getAttribute('src')) {
          return iframe.getAttribute('src').trim();
        }
        const video = fig.querySelector('video');
        if (video && video.getAttribute('src')) {
          return video.getAttribute('src').trim();
        }
        if (fig.getAttribute('data-media-url')) {
          return fig.getAttribute('data-media-url').trim();
        }
      } catch(e) {}
      return fig.id || null;
    }

    function reapplyAllMediaStyles() {
      try {
        const figures = document.querySelectorAll('.ck-content figure.media, #fallback-content figure.media, .ck-content figure, #fallback-content figure');
        figures.forEach(fig => {
          const url = getMediaUrlFromFigure(fig);
          if (url && window._mediaStyleRegistry && window._mediaStyleRegistry[url]) {
            const reg = window._mediaStyleRegistry[url];
            if (reg.width && fig.style.width !== reg.width) {
              fig.style.width = reg.width;
              fig.style.maxWidth = reg.maxWidth || reg.width;
            }
            if (reg.margin && fig.style.margin !== reg.margin) {
              fig.style.margin = reg.margin;
            }
            if (fig.getAttribute('data-media-width') !== reg.width) {
              fig.setAttribute('data-media-width', reg.width);
            }
          } else if (fig.style && fig.style.width) {
            const u = getMediaUrlFromFigure(fig);
            if (u) {
              window._mediaStyleRegistry = window._mediaStyleRegistry || {};
              window._mediaStyleRegistry[u] = {
                width: fig.style.width,
                maxWidth: fig.style.maxWidth || fig.style.width,
                margin: fig.style.margin || '16px auto',
                style: fig.getAttribute('style') || ''
              };
            }
          }
        });
      } catch(e) {}
    }

    let _mediaListenersAttached = false;
    function attachMediaListeners() {
      const editable = document.querySelector('.ck-content, #fallback-content');
      if (!editable || _mediaListenersAttached) return;
      _mediaListenersAttached = true;

      editable.addEventListener('click', function(e) {
        const mediaFig = e.target.closest('figure.media, .media, [data-oembed-url], video, iframe');
        if (mediaFig) {
          const figure = mediaFig.tagName.toLowerCase() === 'figure' ? mediaFig : (mediaFig.closest('figure') || mediaFig);
          showVideoToolbar(figure);
        } else if (!e.target.closest('.video-resize-toolbar')) {
          hideVideoToolbar();
        }
        reapplyAllMediaStyles();
      });

      // Observe style attribute changes on editable figure elements
      try {
        const observer = new MutationObserver((mutations) => {
          for (let i = 0; i < mutations.length; i++) {
            const m = mutations[i];
            if (m.type === 'attributes' && m.attributeName === 'style' && m.target) {
              const fig = m.target.closest ? m.target.closest('figure.media, .media') : null;
              if (fig) {
                const url = getMediaUrlFromFigure(fig);
                if (url && window._mediaStyleRegistry && window._mediaStyleRegistry[url]) {
                  const reg = window._mediaStyleRegistry[url];
                  if (fig.style.width !== reg.width) {
                    fig.style.width = reg.width;
                    fig.style.maxWidth = reg.maxWidth || reg.width;
                  }
                  if (reg.margin && fig.style.margin !== reg.margin) {
                    fig.style.margin = reg.margin;
                  }
                }
              }
            }
          }
        });
        observer.observe(editable, { attributes: true, subtree: true, attributeFilter: ['style', 'class'] });
      } catch(e) {}
    }

    function showVideoToolbar(figure) {
      activeMediaFigure = figure;
      const tb = ensureVideoResizeToolbar();
      const rect = figure.getBoundingClientRect();
      
      tb.style.top = Math.max(10, rect.top - 46) + 'px';
      tb.style.left = (rect.left + rect.width / 2) + 'px';
      tb.style.display = 'flex';

      const currentW = figure.style.width || '100%';
      tb.querySelectorAll('button[data-size]').forEach(btn => {
        btn.classList.toggle('active', btn.getAttribute('data-size') === currentW);
      });
      const slider = tb.querySelector('input[type="range"]');
      if (slider) {
        const num = parseInt(currentW);
        if (!isNaN(num)) slider.value = num;
      }
    }

    function hideVideoToolbar() {
      if (videoResizeToolbar) {
        videoResizeToolbar.style.display = 'none';
      }
    }

    function resizeActiveMedia(size) {
      if (!activeMediaFigure) return;
      activeMediaFigure.style.width = size;
      activeMediaFigure.style.maxWidth = size;
      if (!activeMediaFigure.style.margin) {
        activeMediaFigure.style.margin = '16px auto';
      }
      activeMediaFigure.setAttribute('data-media-width', size);

      const url = getMediaUrlFromFigure(activeMediaFigure);
      if (url) {
        window._mediaStyleRegistry = window._mediaStyleRegistry || {};
        window._mediaStyleRegistry[url] = {
          width: size,
          maxWidth: size,
          margin: activeMediaFigure.style.margin,
          style: 'width:' + size + ';max-width:' + size + ';margin:' + activeMediaFigure.style.margin + ';'
        };
      }

      showVideoToolbar(activeMediaFigure);
      if (editorInstance) {
        try {
          const html = getEditorData();
          postToFlutter({ type: 'ckeditor_change', html: html });
        } catch(e) {}
      }
    }

    function alignActiveMedia(align) {
      if (!activeMediaFigure) return;
      if (align === 'left') {
        activeMediaFigure.style.marginLeft = '0';
        activeMediaFigure.style.marginRight = 'auto';
      } else if (align === 'center') {
        activeMediaFigure.style.marginLeft = 'auto';
        activeMediaFigure.style.marginRight = 'auto';
      } else if (align === 'right') {
        activeMediaFigure.style.marginLeft = 'auto';
        activeMediaFigure.style.marginRight = '0';
      }
      const margin = activeMediaFigure.style.margin ||
        ((activeMediaFigure.style.marginTop || '16px') + ' ' + (activeMediaFigure.style.marginRight || 'auto') + ' ' + (activeMediaFigure.style.marginBottom || '16px') + ' ' + (activeMediaFigure.style.marginLeft || 'auto'));
      activeMediaFigure.style.margin = margin;

      const url = getMediaUrlFromFigure(activeMediaFigure);
      if (url) {
        window._mediaStyleRegistry = window._mediaStyleRegistry || {};
        const entry = window._mediaStyleRegistry[url] || {
          width: activeMediaFigure.style.width || '100%',
          maxWidth: activeMediaFigure.style.maxWidth || '100%'
        };
        entry.margin = margin;
        entry.style = 'width:' + entry.width + ';max-width:' + entry.maxWidth + ';margin:' + margin + ';';
        window._mediaStyleRegistry[url] = entry;
      }

      showVideoToolbar(activeMediaFigure);
      if (editorInstance) {
        try {
          const html = getEditorData();
          postToFlutter({ type: 'ckeditor_change', html: html });
        } catch(e) {}
      }
    }

    function removeActiveMedia() {
      if (!activeMediaFigure) return;
      const url = getMediaUrlFromFigure(activeMediaFigure);
      if (url && window._mediaStyleRegistry) {
        delete window._mediaStyleRegistry[url];
      }
      activeMediaFigure.remove();
      hideVideoToolbar();
      activeMediaFigure = null;
      if (editorInstance) {
        try {
          const html = getEditorData();
          postToFlutter({ type: 'ckeditor_change', html: html });
        } catch(e) {}
      }
      showToastMsg('Video removed');
    }

    function attachMediaDragHandles() {
      // Safe no-op: Video sizing is handled by videoResizeToolbar without mutating CKEditor widget DOM
    }

    function showToastMsg(msg) {
      let toast = document.getElementById('toast-notification');
      if (!toast) {
        toast = document.createElement('div');
        toast.id = 'toast-notification';
        toast.style.cssText = 'position:fixed;bottom:40px;left:50%;transform:translateX(-50%);background:#0f172a;color:white;padding:10px 20px;border-radius:8px;font-size:13px;font-weight:500;box-shadow:0 6px 16px rgba(0,0,0,0.25);z-index:99999;transition:all 0.3s;display:flex;align-items:center;gap:8px;';
        document.body.appendChild(toast);
      }
      toast.textContent = msg;
      toast.style.display = 'flex';
      toast.style.opacity = '1';
      clearTimeout(window._toastTimer);
      window._toastTimer = setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => { toast.style.display = 'none'; }, 300);
      }, 3500);
    }

    /* ====== SLASH COMMANDS LOGIC ====== */
    const slashCommands = [
      { id: 'h1', name: 'Heading 1', desc: 'Large section heading', icon: 'H1', fn: () => execSlashCK('heading', { value: 'heading1' }) },
      { id: 'h2', name: 'Heading 2', desc: 'Medium section heading', icon: 'H2', fn: () => execSlashCK('heading', { value: 'heading2' }) },
      { id: 'h3', name: 'Heading 3', desc: 'Small section heading', icon: 'H3', fn: () => execSlashCK('heading', { value: 'heading3' }) },
      { id: 'bullet', name: 'Bulleted List', desc: 'Unordered list with bullet points', icon: '•', fn: () => execSlashCK('bulletedList') },
      { id: 'number', name: 'Numbered List', desc: 'Ordered numbered list', icon: '1.', fn: () => execSlashCK('numberedList') },
      { id: 'todo', name: 'To-Do Checklist', desc: 'Interactive task checklist', icon: '☑️', fn: () => execSlashCK('todoList') },
      { id: 'table2', name: 'Table (2x2)', desc: '2 rows x 2 columns data table', icon: '📊', fn: () => execSlashCK('insertTable', { rows: 2, columns: 2 }) },
      { id: 'table3', name: 'Table (3x3)', desc: '3 rows x 3 columns comparison table', icon: '▦', fn: () => execSlashCK('insertTable', { rows: 3, columns: 3 }) },
      { id: 'code', name: 'Code Block', desc: 'Syntax-highlighted code block', icon: '</>', fn: () => execSlashCK('codeBlock') },
      { id: 'quote', name: 'Block Quote', desc: 'Indented block quote callout', icon: '❝', fn: () => execSlashCK('blockQuote') },
      { id: 'divider', name: 'Horizontal Divider', desc: 'Thin line divider between sections', icon: '—', fn: () => execSlashCK('horizontalLine') },
      { id: 'pagebreak', name: 'Page Break', desc: 'Forced page break for print/PDF', icon: '📃', fn: () => { closeSlashModal(); insertPageBreak(); } },
      { id: 'math', name: 'Math Equation', desc: 'LaTeX mathematical formula', icon: '∑', fn: () => { closeSlashModal(); showMathModal(); } },
      { id: 'template', name: 'Document Template', desc: 'Insert pre-made structured layout', icon: '📋', fn: () => { closeSlashModal(); showTemplateModal(); } },
      { id: 'user_alex', name: 'Mention @Alex', desc: 'Insert team mention @alex', icon: '@', fn: () => insertSlashHtml('<span class="mention" data-mention="@alex">@alex</span>&nbsp;') },
      { id: 'tag_lims', name: 'Tag #LIMS', desc: 'Insert category tag #lims', icon: '#', fn: () => insertSlashHtml('<span class="mention" data-mention="#lims">#lims</span>&nbsp;') },
      { id: 'ref_cell', name: 'Reference Table Cell (\$)', desc: 'Link live cell value in text (e.g. \$A1)', icon: '\$', fn: () => { closeSlashModal(); showCellRefModal(); } },
      { id: 'formula', name: 'Table Formula (=)', desc: 'Insert live calculated formula (e.g. =SUM(A1+A2))', icon: '🧮', fn: () => { closeSlashModal(); showFormulaHelpModal(); } },
      { id: 'voice_to_text', name: 'Voice to Text (Dictation)', desc: 'Speak to type directly into document', icon: '🎙️', fn: () => { closeSlashModal(); toggleDirectVoiceInput(); } }
    ];

    function showSlashModal() {
      const modal = document.getElementById('slash-modal');
      modal.classList.add('show');
      const search = document.getElementById('slash-search');
      search.value = '';
      renderSlashCommands(slashCommands);
      setTimeout(() => { search.focus(); }, 100);
    }

    function closeSlashModal() {
      document.getElementById('slash-modal').classList.remove('show');
    }

    function renderSlashCommands(list) {
      const container = document.getElementById('slash-list');
      if (list.length === 0) {
        container.innerHTML = '<p style="color:#94a3b8;text-align:center;padding:20px;">No matching commands</p>';
        return;
      }
      let html = '';
      list.forEach((cmd, i) => {
        html += '<div class="slash-item" onclick="slashCommands[' + slashCommands.indexOf(cmd) + '].fn()">' +
          '<div class="slash-icon">' + cmd.icon + '</div>' +
          '<div><div class="slash-name">' + cmd.name + '</div><div class="slash-desc">' + cmd.desc + '</div></div></div>';
      });
      container.innerHTML = html;
    }

    function filterSlashCommands() {
      const q = document.getElementById('slash-search').value.toLowerCase().trim();
      const filtered = slashCommands.filter(c => c.name.toLowerCase().includes(q) || c.desc.toLowerCase().includes(q) || c.id.includes(q));
      renderSlashCommands(filtered);
    }

    function execSlashCK(command, params) {
      closeSlashModal();
      if (editorInstance) {
        try { editorInstance.execute(command, params); } catch(e) { console.warn(e); }
      } else if (isFallback) {
        if (command === 'bulletedList') formatDoc('insertUnorderedList');
        else if (command === 'numberedList') formatDoc('insertOrderedList');
        else if (command === 'insertTable') insertFallbackTable();
        else if (command === 'horizontalLine') insertFallbackHorizontalRule();
        else if (command === 'heading') formatDoc('formatBlock', (params && params.value === 'heading1') ? 'h1' : (params && params.value === 'heading2') ? 'h2' : 'h3');
        else if (command === 'blockQuote') formatDoc('formatBlock', 'blockquote');
        else if (command === 'codeBlock') formatDoc('formatBlock', 'pre');
      }
    }

    function insertSlashHtml(html) {
      closeSlashModal();
      if (editorInstance) {
        const viewFragment = editorInstance.data.processor.toView(html);
        const modelFragment = editorInstance.data.toModel(viewFragment);
        editorInstance.model.insertContent(modelFragment);
      } else if (isFallback) {
        document.execCommand('insertHTML', false, html);
        updateFallbackStats();
        postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
      }
    }

    /* Key listener for Cmd+/, Ctrl+/ (Slash Commands) */
    document.addEventListener('keydown', (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === '/') {
        e.preventDefault();
        showSlashModal();
        return;
      }
    });

    /* ====== SMART VIEWPORT CLAMPING FOR POPUPS & BALLOONS ====== */
    let _isClamping = false;
    function clampAllBalloons() {
      if (_isClamping) return;
      _isClamping = true;
      try {
        const balloons = document.querySelectorAll('.ck.ck-balloon-panel, .ck-balloon-panel');
        const statusBar = document.getElementById('status-bar');
        const statusBarHeight = (statusBar && statusBar.offsetHeight) ? statusBar.offsetHeight : 28;
        const maxBottom = window.innerHeight - statusBarHeight - 10;
        const minTop = 10;
        const minLeft = 10;
        const maxRight = window.innerWidth - 10;

        balloons.forEach(panel => {
          if (!panel.offsetParent && panel.style.display === 'none') return;
          // ONLY clamp dialog/form panels (Table Properties, Cell Properties, etc.)
          // Never clamp contextual toolbars! CKEditor's positioning engine manages toolbars naturally.
          const isFormPanel = panel.querySelector('.ck-form, .ck-table-properties-form, .ck-table-cell-properties-form');
          if (!isFormPanel) return;

          let rect = panel.getBoundingClientRect();
          if (rect.width === 0 || rect.height === 0) return;

          /* Never taller than the visible area: the form content scrolls instead */
          const available = Math.max(160, maxBottom - minTop);
          const maxH = available + 'px';
          if (panel.style.getPropertyValue('max-height') !== maxH) {
            /* 'important' to beat the stylesheet's !important viewport-based max-height */
            panel.style.setProperty('max-height', maxH, 'important');
            const content = panel.querySelector('.ck-balloon-panel__content');
            if (content) content.style.setProperty('max-height', maxH, 'important');
            rect = panel.getBoundingClientRect();
          }

          /* Keep the whole form on screen: push down if the top is cut off, up if the bottom is */
          let shiftY = 0;
          if (rect.top < minTop) shiftY = minTop - rect.top;
          else if (rect.bottom > maxBottom) shiftY = Math.max(minTop - rect.top, maxBottom - rect.bottom);
          if (Math.abs(shiftY) > 1) {
            const currentTop = parseFloat(panel.style.top);
            panel.style.top = (isNaN(currentTop) ? rect.top : currentTop) + shiftY + 'px';
            panel.dataset.clampedTop = panel.style.top;
          }
          /* Still where we moved it (CKEditor has not re-placed it): the arrow would point at the wrong spot */
          panel.classList.toggle('balloon-clamped', !!panel.dataset.clampedTop && panel.dataset.clampedTop === panel.style.top);

          // Adjust horizontal position if overflowing right or left
          if (rect.right > maxRight) {
            const overflowX = rect.right - maxRight;
            const currentLeft = parseFloat(panel.style.left) || rect.left;
            panel.style.left = Math.max(minLeft, currentLeft - overflowX) + 'px';
          } else if (rect.left < minLeft) {
            panel.style.left = minLeft + 'px';
          }
        });
      } finally {
        _isClamping = false;
      }
    }

    // Observe when balloon panels are added or opened (do NOT observe 'style' to avoid loops)
    const balloonObserver = new MutationObserver((mutations) => {
      if (_isClamping) return;
      /* CKEditor re-places balloons by rewriting their style; other style changes are irrelevant here */
      const relevant = mutations.some(m => m.type !== 'attributes' || m.attributeName !== 'style' ||
        (m.target.classList && m.target.classList.contains('ck-balloon-panel')));
      if (relevant) requestAnimationFrame(clampAllBalloons);
    });
    balloonObserver.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['class', 'style']
    });

    window.addEventListener('resize', () => { requestAnimationFrame(clampAllBalloons); });
    window.addEventListener('scroll', () => { requestAnimationFrame(clampAllBalloons); }, true);
    document.addEventListener('selectionchange', () => {
      requestAnimationFrame(clampAllBalloons);
      reapplyAllMediaStyles();
    });
    document.addEventListener('focusout', () => {
      reapplyAllMediaStyles();
    });
    window.addEventListener('blur', () => {
      reapplyAllMediaStyles();
    });

    /* ====== MESSAGE HANDLING (Flutter <-> JS) ====== */
    window.addEventListener('message', (event) => {
      let msg = event.data;
      if (typeof msg === 'string') { try { msg = JSON.parse(msg); } catch(_) { return; } }
      if (!msg) return;
      if (msg.type === 'setHtml') {
        initialContent = msg.html;
        setEditorData(msg.html);
      } else if (msg.type === 'setTheme') {
        document.body.className = msg.isDark ? 'dark' : 'light';
      } else if (msg.type === 'getHtml') {
        postToFlutter({ type: 'ckeditor_html', html: getEditorData() });
      } else if (msg.type === 'insertHtml') {
        if (editorInstance) {
          const viewFragment = editorInstance.data.processor.toView(msg.html);
          const modelFragment = editorInstance.data.toModel(viewFragment);
          editorInstance.model.insertContent(modelFragment);
        } else if (isFallback) {
          document.execCommand('insertHTML', false, msg.html);
          updateFallbackStats();
          postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
        }
      } else if (msg.type === 'insertVoiceHtml') {
        // Insert HTML returned by the Flutter/API voice/AI pipeline
        const html = msg.html || '';
        if (html && editorInstance) {
          const viewFragment = editorInstance.data.processor.toView(html);
          const modelFragment = editorInstance.data.toModel(viewFragment);
          editorInstance.model.insertContent(modelFragment);
          postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
        } else if (html && isFallback) {
          document.execCommand('insertHTML', false, html);
          updateFallbackStats();
          postToFlutter({ type: 'ckeditor_change', html: getEditorData() });
        }
        closeAiPromptModal();
        resetAiApiButton();
      } else if (msg.type === 'ai_generate_error') {
        const banner = document.getElementById('ai-error-banner');
        if (banner) {
          banner.textContent = msg.error || 'Failed to generate HTML content.';
          banner.style.display = 'block';
        }
        resetAiApiButton();
      } else if (msg.type === 'executeCommand') {
        if (editorInstance) {
          try { editorInstance.execute(msg.command, msg.params); } catch(e) {}
        } else if (isFallback) {
          try { formatDoc(msg.command, msg.params); } catch(e) {}
        }
      }
    });
  </script>
</body>
</html>''';
  }
}
