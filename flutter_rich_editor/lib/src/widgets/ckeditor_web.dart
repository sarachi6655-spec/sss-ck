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
  });

  final String initialHtml;
  final bool isDark;
  final String placeholder;
  final void Function(String html) onContentChanged;
  final void Function(void Function(String html) setHtml)? onEditorReady;

  @override
  State<CKEditorWebView> createState() => _CKEditorWebViewState();
}

class _CKEditorWebViewState extends State<CKEditorWebView> {
  late final String _viewType;
  late final String _editorId;
  web.HTMLIFrameElement? _iframe;
  JSFunction? _messageListener;

  @override
  void initState() {
    super.initState();
    final int uniqueId = DateTime.now().microsecondsSinceEpoch;
    _editorId = 'ckeditor_$uniqueId';
    _viewType = 'ckeditor-view-$uniqueId';

    _registerViewFactory();
    _setupMessageListener();

    widget.onEditorReady?.call(setHtml);
  }

  @override
  void didUpdateWidget(covariant CKEditorWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      iframe.setAttribute('allow', 'clipboard-read; clipboard-write; fullscreen');
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
                widget.onContentChanged(html);
              }
            }
          } catch (_) {}
        }
      }
    }).toJS;
    _messageListener = listener;
    web.window.addEventListener('message', listener);
  }

  void setHtml(String html) {
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
    final String initialJson = jsonEncode(widget.initialHtml);
    final String placeholderJson = jsonEncode(widget.placeholder);
    final String editorIdJson = jsonEncode(_editorId);

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="format-detection" content="telephone=no">
  <title>CKEditor 5 — Full Featured</title>
  <!-- CKEditor 5 Super Build loaded dynamically in body script -->
  <!-- jsPDF for Export to PDF -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.2/jspdf.umd.min.js"></script>
  <!-- html2canvas for PDF rendering -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
  <!-- KaTeX for math equations -->
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
  <script src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
  <!-- Google Fonts for rich typography (Calibri fallbacks, Inter, Roboto, Lato, Poppins, etc.) -->
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Fira+Code:wght@400;500;600&family=Inter:wght@400;500;600;700&family=Lato:wght@400;700&family=Montserrat:wght@400;600;700&family=Open+Sans:wght@400;600;700&family=Poppins:wght@400;500;600;700&family=Roboto:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    /* ====== RESET & BASE ====== */
    * { box-sizing: border-box; margin: 0; padding: 0; }
    html, body {
      width: 100%; height: 100%; height: 100dvh; overflow: hidden;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, Cantarell, "Helvetica Neue", sans-serif;
      font-size: 14px;
      background: #ffffff; color: #1e293b;
      touch-action: manipulation;
      -webkit-tap-highlight-color: transparent;
      transition: background 0.2s, color 0.2s;
    }
    /* ====== MAIN LAYOUT ====== */
    #app-container {
      display: flex; flex-direction: column; width: 100%; height: 100%; height: 100dvh;
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
      display: flex; flex: 1 1 auto; overflow: hidden; position: relative;
    }
    #editor-main {
      flex: 1 1 auto; display: flex; flex-direction: column;
      overflow: hidden; min-width: 0;
    }
    /* ====== CKEDITOR CUSTOMIZATION ====== */
    .ck.ck-editor { display: flex !important; flex-direction: column !important; height: 100% !important; width: 100% !important; border: none !important; border-radius: 0 !important; }
    .ck.ck-editor__top { flex-shrink: 0 !important; }
    .ck.ck-toolbar { border: none !important; border-bottom: 1px solid #e2e8f0 !important; background: #f8fafc !important; padding: 2px 6px !important; flex-wrap: wrap !important; }
    .ck.ck-toolbar .ck-toolbar__separator { background: #e2e8f0 !important; }
    .ck.ck-editor__main { flex: 1 1 auto !important; overflow-y: auto !important; height: 0 !important; }
    .ck-content { min-height: 100% !important; padding: 14px 20px !important; font-size: 15px !important; line-height: 1.7 !important; cursor: text !important; }
    .ck-content:focus { outline: none !important; }
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
    .ck-content table { border-collapse: collapse; width: 100%; margin: 16px 0; }
    .ck-content table td, .ck-content table th { border: 1px solid #cbd5e1; padding: 8px 12px; text-align: left; vertical-align: top; }
    .ck-content table th { background: #f1f5f9; font-weight: 600; color: #0f172a; }
    .ck-content table tr:nth-child(even) td { background: #f8fafc; }
    /* Highlight */
    .ck-content mark, .ck-content .marker-yellow { background: #fef08a; }
    .ck-content .marker-green { background: #bbf7d0; }
    .ck-content .marker-pink { background: #fbcfe8; }
    .ck-content .marker-blue { background: #bfdbfe; }
    .ck-content .pen-red { color: #dc2626; background: transparent; }
    .ck-content .pen-green { color: #16a34a; background: transparent; }
    /* Todo list */
    .ck-content .todo-list { list-style: none; padding-left: 0; }
    .ck-content .todo-list li { display: flex; align-items: flex-start; gap: 8px; margin: 4px 0; }
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
      margin: 16px auto !important;
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
      justify-content: center; z-index: 9999;
    }
    .modal-overlay.show { display: flex; }
    .modal-box {
      background: white; border-radius: 12px; padding: 24px; width: 90%;
      max-width: 600px; max-height: 80vh; overflow-y: auto;
      box-shadow: 0 20px 60px rgba(0,0,0,0.3);
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
    body.dark #fallback-container { border-color: #45475a; }
    body.dark #fallback-toolbar { background: #313244; border-color: #45475a; }
    body.dark #fallback-toolbar button, body.dark #fallback-toolbar select { background: #45475a; color: #cdd6f4; border-color: #585b70; }
    body.dark #fallback-content { background: #181825; color: #cdd6f4; }


    /* ====== DROPDOWN OVERFLOW & MAX-HEIGHT FIX ====== */
    .ck.ck-dropdown__panel,
    .ck-dropdown__panel {
      max-height: min(280px, calc(100vh - 120px)) !important;
      overflow-y: auto !important;
      overflow-x: hidden !important;
      -webkit-overflow-scrolling: touch !important;
      box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.2), 0 8px 10px -6px rgba(0, 0, 0, 0.1) !important;
      border-radius: 8px !important;
      scrollbar-width: thin !important;
    }
    .ck.ck-dropdown__panel .ck-list,
    .ck-dropdown__panel .ck-list {
      max-height: inherit !important;
      overflow-y: auto !important;
      overflow-x: hidden !important;
      -webkit-overflow-scrolling: touch !important;
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

    /* Balloon Panels (Table Toolbar, Link Balloon, etc.) */
    .ck.ck-balloon-panel,
    .ck-balloon-panel {
      max-width: min(520px, 95vw) !important;
      box-shadow: 0 10px 25px rgba(0, 0, 0, 0.18) !important;
      border-radius: 8px !important;
      z-index: 1000 !important;
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
      .ck-content .table,
      .ck-content table {
        margin: 10px 0 !important;
        max-width: 100% !important;
        overflow-x: auto !important;
        -webkit-overflow-scrolling: touch !important;
        display: block !important;
      }
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

    /* ====== PRINT STYLES ====== */
    @media print {
      #action-bar, #status-bar, #side-panel, .ck-toolbar { display: none !important; }
      .ck-content { padding: 0 !important; }
    }
  </style>
</head>
<body class="$darkClass">
  <div id="app-container">
    <!-- ==== ACTION BAR (Premium-like features) ==== -->
    <div id="action-bar">
      <button onclick="toggleFullscreen()" id="btn-fullscreen" title="Toggle Fullscreen (Maximize Editor)" style="background:#eff6ff;color:#1d4ed8;font-weight:600;border-color:#bfdbfe;">⛶ Fullscreen</button>
      <div class="separator"></div>
      <button onclick="exportToPDF()" title="Export to PDF">📄 PDF</button>
      <button onclick="exportToWord()" title="Export to Word">📝 Word</button>
      <button onclick="importFromWord()" title="Import from Word">📂 Import</button>
      <button onclick="printEditor()" title="Print">🖨️ Print</button>
      <div class="separator"></div>
      <button onclick="toggleTrackChanges()" id="btn-track-changes" title="Track Changes">📋 Track</button>
      <button onclick="openPanel('comments')" title="Comments">💬 Comments</button>
      <button onclick="openPanel('revisions')" title="Revision History">🕐 History</button>
      <button onclick="openPanel('outline')" title="Document Outline">📑 Outline</button>
      <div class="separator"></div>
      <button onclick="showFormulaHelpModal()" title="Table Formulas (100% Auto-Calculating on keystroke)">⚡ Formulas (Auto)</button>
      <button onclick="openTableColorModal()" id="btn-table-color" title="Color Table Cells, Columns, Rows or Entire Table" style="background:#fef3c7;color:#92400e;font-weight:600;border-color:#fcd34d;">🎨 Table Color</button>
      <div class="separator"></div>
      <button onclick="showTemplateModal()" title="Insert Template">📋 Templates</button>
      <button onclick="showMathModal()" title="Insert Math Equation">∑ Math</button>
      <button onclick="insertPageBreak()" title="Insert Page Break">📃 Page Break</button>
      <button onclick="openVideoModal()" id="btn-video" title="Insert & Resize Video (YouTube, Vimeo, MP4)" style="background:#ede9fe;color:#5b21b6;border-color:#ddd6fe;font-weight:600;">🎬 Video</button>
      <button onclick="showSlashModal()" title="Slash Commands & Quick Insert (Cmd+/)">⚡ / Slash</button>
      <button onclick="toggleShowBlocks()" id="btn-show-blocks" title="Show Blocks">¶ Blocks</button>
      <div class="separator"></div>
      <button onclick="formatPainter()" id="btn-format-painter" title="Format Painter">🖌️ Painter</button>
      <button onclick="harmonizeSelectionStyles()" id="btn-harmonize" title="Match Document Style (Normalize fonts/sizes in pasted content)" style="background:#f0fdf4;color:#166534;border-color:#bbf7d0;font-weight:600;">🧹 Harmonize</button>
      <button onclick="toggleReadonly()" id="btn-readonly" title="Toggle Read Only">🔒 ReadOnly</button>
      <select onchange="changeLanguage(this.value)" title="Text Direction">
        <option value="ltr">LTR</option>
        <option value="rtl">RTL</option>
      </select>
    </div>

    <!-- ==== EDITOR + SIDE PANEL ==== -->
    <div id="editor-wrapper">
      <div id="editor-main">
        <div id="editor"></div>
        <div id="fallback-container">
          <div id="fallback-toolbar">
            <select onchange="formatDoc('formatBlock', this.value)">
              <option value="p">Paragraph</option><option value="h1">H1</option>
              <option value="h2">H2</option><option value="h3">H3</option>
            </select>
            <button onclick="formatDoc('bold')"><b>B</b></button>
            <button onclick="formatDoc('italic')"><i>I</i></button>
            <button onclick="formatDoc('underline')"><u>U</u></button>
            <button onclick="formatDoc('strikeThrough')"><s>S</s></button>
            <button onclick="formatDoc('insertUnorderedList')">• List</button>
            <button onclick="formatDoc('insertOrderedList')">1. List</button>
            <button onclick="insertFallbackTable()">📊 Table</button>
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

  <!-- ==== FORMULA HELP MODAL ==== -->
  <div class="modal-overlay" id="formula-modal">
    <div class="modal-box" style="max-width:580px;">
      <button class="close-modal" onclick="closeFormulaHelpModal()">&times;</button>
      <h2>🧮 Table Formulas & Calculations</h2>
      <p style="margin-bottom:12px;color:#475569;font-size:13px;">Type any formula starting with <code>=</code> into a table cell. It <strong>automatically calculates and updates on every keystroke in real time</strong> — no buttons needed!</p>
      
      <div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;padding:12px;margin-bottom:14px;font-size:13px;">
        <div style="font-weight:600;margin-bottom:6px;color:#1e293b;">📍 How Cell Coordinates Work</div>
        <p style="margin:0 0 6px 0;color:#64748b;font-size:12px;">Columns are letters (<strong>A, B, C...</strong>) and rows are numbers (<strong>1, 2, 3...</strong>):</p>
        <table style="width:100%;border-collapse:collapse;margin:4px 0;background:white;font-size:12px;" border="1">
          <tr style="background:#f1f5f9;"><th style="padding:5px;"></th><th style="padding:5px;">Column A</th><th style="padding:5px;">Column B</th></tr>
          <tr><td style="background:#f1f5f9;font-weight:600;padding:5px;text-align:center;">Row 1</td><td style="padding:5px;">Cell <strong>A1</strong> (e.g. 120)</td><td style="padding:5px;">Cell <strong>B1</strong></td></tr>
          <tr><td style="background:#f1f5f9;font-weight:600;padding:5px;text-align:center;">Row 2</td><td style="padding:5px;">Cell <strong>A2</strong> (e.g. 230)</td><td style="padding:5px;">Cell <strong>B2</strong></td></tr>
          <tr><td style="background:#f1f5f9;font-weight:600;padding:5px;text-align:center;">Row 3</td><td style="padding:5px;background:#eff6ff;">Cell <strong>A3</strong> (e.g. <code>=SUM(A1+A2)</code>)</td><td style="padding:5px;">Cell <strong>B3</strong></td></tr>
        </table>
      </div>

      <div style="display:flex;flex-direction:column;gap:8px;font-size:13px;margin-bottom:16px;">
        <div style="padding:8px 12px;background:#eff6ff;border-radius:6px;border-left:3px solid #3b82f6;">
          <strong>Addition & Sum:</strong> <code>=SUM(A1+A2)</code> or <code>=A1+A2</code> or <code>=SUM(A1:A2)</code><br>
          <span style="color:#64748b;font-size:12px;">Calculates: <strong>350</strong> (120 + 230)</span>
        </div>
        <div style="padding:8px 12px;background:#f0fdf4;border-radius:6px;border-left:3px solid #22c55e;">
          <strong>Average:</strong> <code>=AVG(A1:A2)</code> or <code>=AVERAGE(A1:A2)</code><br>
          <span style="color:#64748b;font-size:12px;">Calculates: <strong>175</strong></span>
        </div>
        <div style="padding:8px 12px;background:#fefce8;border-radius:6px;border-left:3px solid #eab308;">
          <strong>Arithmetic:</strong> <code>=A1 * B1</code> &nbsp;|&nbsp; <code>=A1 - A2</code> &nbsp;|&nbsp; <code>=A1 / 2</code> &nbsp;|&nbsp; <code>=(A1+A2)*1.1</code>
        </div>
        <div style="padding:8px 12px;background:#faf5ff;border-radius:6px;border-left:3px solid #a855f7;">
          <strong>Min, Max, Count:</strong> <code>=MIN(A1:A5)</code> &nbsp;|&nbsp; <code>=MAX(A1:A5)</code> &nbsp;|&nbsp; <code>=COUNT(A1:A5)</code>
        </div>
      </div>

      <div class="modal-actions">
        <button class="primary-btn" onclick="closeFormulaHelpModal();">✓ Auto-Calculate is Active</button>
      </div>
    </div>
  </div>

  <!-- ==== TABLE COLOR & STYLING MODAL ==== -->
  <div class="modal-overlay" id="table-color-modal">
    <div class="modal-box" style="max-width:540px;">
      <button class="close-modal" onclick="closeTableColorModal()">&times;</button>
      <h2>🎨 Table Styling & Color</h2>
      <p style="margin-bottom:12px;color:#64748b;font-size:12px;">Apply background colors, text colors, and borders to table cells, columns, rows, or the entire table.</p>

      <!-- Target Selection -->
      <div style="margin-bottom:14px;">
        <label style="font-weight:600;font-size:12px;display:block;margin-bottom:6px;color:#334155;">1. Choose Target:</label>
        <div style="display:flex;gap:6px;flex-wrap:wrap;">
          <button type="button" class="tbl-target-btn active" data-target="cell" onclick="setTableColorTarget('cell')">🔲 Current Cell</button>
          <button type="button" class="tbl-target-btn" data-target="col" onclick="setTableColorTarget('col')">🏛️ Entire Column</button>
          <button type="button" class="tbl-target-btn" data-target="row" onclick="setTableColorTarget('row')">➖ Entire Row</button>
          <button type="button" class="tbl-target-btn" data-target="table" onclick="setTableColorTarget('table')">📊 Entire Table</button>
          <button type="button" class="tbl-target-btn" data-target="header" onclick="setTableColorTarget('header')">🏷️ Header Row</button>
          <button type="button" class="tbl-target-btn" data-target="zebra" onclick="setTableColorTarget('zebra')">🦓 Zebra Stripes</button>
        </div>
      </div>

      <!-- Color Presets -->
      <div style="margin-bottom:14px;">
        <label style="font-weight:600;font-size:12px;display:block;margin-bottom:6px;color:#334155;">2. Select Background Color:</label>
        <div class="color-swatch-grid" style="display:grid;grid-template-columns:repeat(auto-fill, minmax(42px, 1fr));gap:6px;">
          <button type="button" class="color-swatch" style="background:#ffffff;border:1px solid #cbd5e1;" title="Clear / White" onclick="applyPresetBg('#ffffff', '#1e293b')"></button>
          <button type="button" class="color-swatch" style="background:#eff6ff;border:1px solid #bfdbfe;" title="Soft Blue" onclick="applyPresetBg('#eff6ff', '#1e40af')"></button>
          <button type="button" class="color-swatch" style="background:#f0fdf4;border:1px solid #bbf7d0;" title="Soft Green" onclick="applyPresetBg('#f0fdf4', '#166534')"></button>
          <button type="button" class="color-swatch" style="background:#fefce8;border:1px solid #fef08a;" title="Soft Yellow" onclick="applyPresetBg('#fefce8', '#854d0e')"></button>
          <button type="button" class="color-swatch" style="background:#faf5ff;border:1px solid #e9d5ff;" title="Soft Purple" onclick="applyPresetBg('#faf5ff', '#6b21a8')"></button>
          <button type="button" class="color-swatch" style="background:#fef2f2;border:1px solid #fecaca;" title="Soft Red" onclick="applyPresetBg('#fef2f2', '#991b1b')"></button>
          <button type="button" class="color-swatch" style="background:#f1f5f9;border:1px solid #cbd5e1;" title="Slate Gray" onclick="applyPresetBg('#f1f5f9', '#0f172a')"></button>
          <button type="button" class="color-swatch" style="background:#e0e7ff;border:1px solid #c7d2fe;" title="Indigo Light" onclick="applyPresetBg('#e0e7ff', '#3730a3')"></button>
          <button type="button" class="color-swatch" style="background:#ccfbf1;border:1px solid #99f6e4;" title="Teal Light" onclick="applyPresetBg('#ccfbf1', '#115e59')"></button>
          <button type="button" class="color-swatch" style="background:#ffedd5;border:1px solid #fed7aa;" title="Orange Light" onclick="applyPresetBg('#ffedd5', '#9a3412')"></button>
          <button type="button" class="color-swatch" style="background:#2563eb;border:1px solid #1d4ed8;" title="Royal Blue" onclick="applyPresetBg('#2563eb', '#ffffff')"></button>
          <button type="button" class="color-swatch" style="background:#1e293b;border:1px solid #0f172a;" title="Dark Slate" onclick="applyPresetBg('#1e293b', '#ffffff')"></button>
        </div>
        <div style="display:flex;align-items:center;gap:10px;margin-top:10px;">
          <label style="font-size:12px;color:#475569;">Custom Color:</label>
          <input type="color" id="tbl-custom-bg" value="#3b82f6" style="width:36px;height:30px;padding:1px;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;" onchange="applyCustomBg(this.value)">
          <button type="button" onclick="clearTableBg()" style="padding:4px 10px;font-size:11px;border:1px solid #cbd5e1;background:#fff;border-radius:4px;cursor:pointer;">Clear Background</button>
        </div>
      </div>

      <!-- Border Color & Text Color Options -->
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:16px;">
        <div>
          <label style="font-weight:600;font-size:12px;display:block;margin-bottom:4px;color:#334155;">Border Color:</label>
          <div style="display:flex;align-items:center;gap:6px;">
            <input type="color" id="tbl-border-color" value="#cbd5e1" style="width:36px;height:30px;padding:1px;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;" onchange="applyBorderColor(this.value)">
            <button type="button" onclick="applyBorderColor('#cbd5e1')" style="padding:4px 8px;font-size:11px;border:1px solid #cbd5e1;background:#fff;border-radius:4px;cursor:pointer;">Default</button>
            <button type="button" onclick="applyBorderColor('#3b82f6')" style="padding:4px 8px;font-size:11px;border:1px solid #93c5fd;background:#eff6ff;color:#1d4ed8;border-radius:4px;cursor:pointer;">Blue</button>
          </div>
        </div>
        <div>
          <label style="font-weight:600;font-size:12px;display:block;margin-bottom:4px;color:#334155;">Text Color:</label>
          <div style="display:flex;align-items:center;gap:6px;">
            <input type="color" id="tbl-text-color" value="#0f172a" style="width:36px;height:30px;padding:1px;border:1px solid #cbd5e1;border-radius:4px;cursor:pointer;" onchange="applyTextColor(this.value)">
            <button type="button" onclick="applyTextColor('#0f172a')" style="padding:4px 8px;font-size:11px;border:1px solid #cbd5e1;background:#fff;border-radius:4px;cursor:pointer;">Dark</button>
            <button type="button" onclick="applyTextColor('#ffffff')" style="padding:4px 8px;font-size:11px;border:1px solid #475569;background:#1e293b;color:#fff;border-radius:4px;cursor:pointer;">White</button>
          </div>
        </div>
      </div>

      <div class="modal-actions" style="justify-content:space-between;align-items:center;">
        <button type="button" onclick="harmonizeActiveTable()" style="padding:6px 12px;background:#f0fdf4;color:#166534;border:1px solid #86efac;border-radius:6px;font-size:12px;cursor:pointer;font-weight:600;display:flex;align-items:center;gap:4px;">🧹 Harmonize Table (Match Document Style)</button>
        <button class="primary-btn" onclick="closeTableColorModal()">Done</button>
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

  <script>
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

    function postToFlutter(msg) {
      msg.editorId = EDITOR_ID;
      window.parent.postMessage(JSON.stringify(msg), '*');
    }

    /* ====== CKEDITOR 5 INIT ====== */
    function onScriptLoaded() {
      scriptLoaded = true;
      initCKEditor();
    }

    /* Dynamically load CKEditor script so onScriptLoaded is always defined first */
    (function loadCKEditorScript() {
      var s = document.createElement('script');
      s.src = 'https://cdn.ckeditor.com/ckeditor5/41.4.2/super-build/ckeditor.js';
      s.onload = function() { onScriptLoaded(); };
      s.onerror = function() { initFallback(); };
      document.head.appendChild(s);
    })();

    setTimeout(() => {
      if (!scriptLoaded && !editorInstance && !isFallback) initFallback();
    }, 8000);

    function initCKEditor() {
      if (typeof CKEDITOR === 'undefined') { initFallback(); return; }

      CKEDITOR.ClassicEditor
        .create(document.querySelector('#editor'), {
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
              'sourceEditing', 'showBlocks', '|',
              'textPartLanguage', 'accessibilityHelp'
            ],
            shouldNotGroupWhenFull: false
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
        })
        .then(editor => {
          editorInstance = editor;
          window.editorInstance = editor;
          if (initialContent) editor.setData(initialContent);

          /* Set up Base64 image upload adapter */
          editor.plugins.get('FileRepository').createUploadAdapter = (loader) => {
            return new Base64UploadAdapter(loader);
          };

          /* Content change listener */
          editor.model.document.on('change:data', () => {
            const data = editor.getData();
            postToFlutter({ type: 'ckeditor_change', html: data });
            updateParaCount();
            updatePageIndicator();
            if (trackChangesEnabled) recordChange();
            autoSaveRevision();
            scheduleLiveFormulaRecalc();
          });

          /* Attach live input/keyup/keydown listeners + MutationObserver on editable DOM */
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
              // MutationObserver: catches CKEditor's model→view DOM writes that events may miss
              const formulaObserver = new MutationObserver(() => {
                if (!window._isUpdatingFormula) scheduleLiveFormulaRecalc();
                attachMediaListeners();
                attachMediaDragHandles();
              });
              formulaObserver.observe(el, { childList: true, subtree: true, characterData: true });

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

          /* Initial revision */
          saveRevision('Initial version');

          postToFlutter({ type: 'ckeditor_ready' });
        })
        .catch(err => {
          console.warn('CKEditor init failed, falling back:', err);
          initFallback();
        });
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
      if (isFallback || editorInstance) return;
      isFallback = true;
      document.getElementById('editor').style.display = 'none';
      const container = document.getElementById('fallback-container');
      container.style.display = 'flex';
      const content = document.getElementById('fallback-content');
      if (initialContent) content.innerHTML = initialContent;
      content.addEventListener('input', () => {
        postToFlutter({ type: 'ckeditor_change', html: content.innerHTML });
      });
      postToFlutter({ type: 'ckeditor_ready' });
    }

    function formatDoc(cmd, value = null) {
      document.execCommand(cmd, false, value);
      const content = document.getElementById('fallback-content');
      postToFlutter({ type: 'ckeditor_change', html: content.innerHTML });
    }

    function insertFallbackTable() {
      const html = '<table border="1" style="border-collapse:collapse;width:100%;margin:10px 0;">' +
        '<tr><th style="padding:8px;background:#e2e8f0;">Header 1</th><th style="padding:8px;background:#e2e8f0;">Header 2</th></tr>' +
        '<tr><td style="padding:8px;">Cell 1</td><td style="padding:8px;">Cell 2</td></tr></table>';
      document.execCommand('insertHTML', false, html);
    }

    /* ====== EXPORT TO PDF ====== */
    function exportToPDF() {
      const data = getEditorData();
      if (!data) return;

      /* Build a temporary printable div */
      const printDiv = document.createElement('div');
      printDiv.style.cssText = 'position:fixed;left:-9999px;top:0;width:794px;padding:40px;background:white;color:black;font-family:serif;font-size:12pt;line-height:1.6;';
      printDiv.innerHTML = data;
      document.body.appendChild(printDiv);

      if (typeof html2canvas !== 'undefined' && typeof jspdf !== 'undefined') {
        html2canvas(printDiv, { scale: 2, useCORS: true }).then(canvas => {
          const { jsPDF } = jspdf;
          const pdf = new jsPDF('p', 'mm', 'a4');
          const imgData = canvas.toDataURL('image/png');
          const pdfWidth = pdf.internal.pageSize.getWidth();
          const pdfHeight = (canvas.height * pdfWidth) / canvas.width;
          let position = 0;
          const pageHeight = pdf.internal.pageSize.getHeight();

          /* Multi-page support */
          while (position < pdfHeight) {
            if (position > 0) pdf.addPage();
            pdf.addImage(imgData, 'PNG', 0, -position, pdfWidth, pdfHeight);
            position += pageHeight;
          }
          pdf.save('document.pdf');
          document.body.removeChild(printDiv);
        });
      } else {
        /* Fallback: use browser print */
        document.body.removeChild(printDiv);
        window.print();
      }
    }

    /* ====== EXPORT TO WORD ====== */
    function exportToWord() {
      const data = getEditorData();
      if (!data) return;
      const html = '<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word" xmlns="http://www.w3.org/TR/REC-html40">' +
        '<head><meta charset="utf-8"><style>body{font-family:Calibri,sans-serif;font-size:11pt;line-height:1.6;} table{border-collapse:collapse;width:100%;} td,th{border:1px solid #000;padding:6px 8px;} pre{background:#f5f5f5;padding:10px;font-family:Consolas,monospace;} blockquote{border-left:3px solid #999;padding-left:12px;color:#555;font-style:italic;}</style></head>' +
        '<body>' + data + '</body></html>';
      const blob = new Blob([html], { type: 'application/msword' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url; a.download = 'document.doc'; a.click();
      URL.revokeObjectURL(url);
    }

    /* ====== IMPORT FROM WORD ====== */
    function importFromWord() {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = '.doc,.docx,.html,.htm,.rtf,.txt';
      input.onchange = (e) => {
        const file = e.target.files[0];
        if (!file) return;
        const reader = new FileReader();
        if (file.name.endsWith('.txt')) {
          reader.onload = (ev) => {
            const text = ev.target.result;
            const html = '<p>' + text.replace(/\\n\\n/g, '</p><p>').replace(/\\n/g, '<br>') + '</p>';
            setEditorData(html);
          };
          reader.readAsText(file);
        } else if (file.name.endsWith('.html') || file.name.endsWith('.htm')) {
          reader.onload = (ev) => setEditorData(ev.target.result);
          reader.readAsText(file);
        } else {
          /* For .doc/.docx, read as HTML (basic) */
          reader.onload = (ev) => {
            const content = ev.target.result;
            /* Try to extract readable content */
            const text = new TextDecoder('utf-8', {fatal: false}).decode(new Uint8Array(content));
            const cleaned = text.replace(/[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]/g, '');
            setEditorData('<p>' + cleaned.substring(0, 50000) + '</p>');
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
      btn.classList.toggle('active', trackChangesEnabled);
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
    function autoSaveRevision() {
      clearTimeout(autoSaveTimer);
      autoSaveTimer = setTimeout(() => {
        saveRevision('Auto-save');
      }, 30000); /* Auto-save every 30 seconds of inactivity */
    }

    function saveRevision(label) {
      const data = getEditorData();
      if (!data) return;
      const lastRev = revisions.length > 0 ? revisions[0] : null;
      if (lastRev && lastRev.content === data) return;

      revisions.unshift({
        id: Date.now(),
        label: label || 'Revision ' + (revisions.length + 1),
        time: new Date().toLocaleString(),
        content: data,
        preview: getTextPreview(data, 80)
      });
      if (revisions.length > 50) revisions.pop();
      if (currentPanel === 'revisions') renderRevisionsPanel();
    }

    function restoreRevision(id) {
      const rev = revisions.find(r => r.id === id);
      if (rev) {
        saveRevision('Before restore');
        setEditorData(rev.content);
      }
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
      revisions.forEach((rev, i) => {
        html += '<div class="revision-item' + (i === 0 ? ' active' : '') + '" onclick="restoreRevision(' + rev.id + ')">' +
          '<div class="rev-title">' + escapeHtml(rev.label) + '</div>' +
          '<div class="rev-time">' + rev.time + '</div>' +
          '<div class="rev-preview">' + escapeHtml(rev.preview) + '</div></div>';
      });
      container.innerHTML = html;
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
      showBlocksEnabled = !showBlocksEnabled;
      document.getElementById('btn-show-blocks').classList.toggle('active', showBlocksEnabled);
      if (editorInstance) {
        try { editorInstance.execute('showBlocks'); } catch(e) {}
      }
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

    /* ====== READ ONLY ====== */
    function toggleReadonly() {
      isReadonly = !isReadonly;
      document.getElementById('btn-readonly').classList.toggle('active', isReadonly);
      if (editorInstance) {
        editorInstance.enableReadOnlyMode('custom-lock');
        if (!isReadonly) editorInstance.disableReadOnlyMode('custom-lock');
      }
    }

    /* ====== TEXT DIRECTION ====== */
    function changeLanguage(dir) {
      const editable = document.querySelector('.ck-content');
      if (editable) editable.style.direction = dir;
    }

    /* ====== HELPERS ====== */
    function getEditorData() {
      if (editorInstance) return editorInstance.getData();
      if (isFallback) return document.getElementById('fallback-content').innerHTML;
      return '';
    }

    function setEditorData(html) {
      if (editorInstance) {
        editorInstance.setData(html);
      } else if (isFallback) {
        document.getElementById('fallback-content').innerHTML = html;
        postToFlutter({ type: 'ckeditor_change', html: html });
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

    function updatePageIndicator() {
      const editable = document.querySelector('.ck-content, #fallback-content');
      if (!editable) return;
      /* Estimate page based on content height (A4 ≈ 1120px at 96dpi) */
      const contentHeight = editable.scrollHeight;
      const pageHeight = 1120;
      const pages = Math.max(1, Math.ceil(contentHeight / pageHeight));
      const currentScroll = editable.scrollTop || 0;
      const currentPage = Math.max(1, Math.ceil((currentScroll + 1) / pageHeight));
      document.getElementById('page-indicator').textContent = 'Page ' + currentPage + ' of ' + pages;
    }

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
      const idx = clean.indexOf('=');
      if (idx !== -1) {
        const before = clean.substring(0, idx).trim();
        if (before === '') {
          return clean.substring(idx).trim();
        }
      }
      return clean;
    }

    function extractNumber(raw) {
      if (!raw) return 0;
      let s = String(raw).trim();
      if (s.indexOf('fx') !== -1) {
        s = s.split('fx').join('').trim();
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

      let expr = rawExpr;

      // Normalize spaces around parentheses: e.g. SUM ( ABOVE ) -> SUM(ABOVE)
      expr = expr.split('(').map(function(s) { return s.trimEnd(); }).join('(').split(')').map(function(s) { return s.trimStart(); }).join(')');

      // 1. SUM(ABOVE), SUM(UP), SUM()
      expr = expr.replace(/SUM\\((?:ABOVE|UP)?\\)/gi, () => {
        const vals = getAboveValues();
        return vals.reduce((a, b) => a + b, 0);
      });

      // 2. AVG(ABOVE), AVERAGE(ABOVE)
      expr = expr.replace(/(?:AVG|AVERAGE)\\((?:ABOVE|UP)?\\)/gi, () => {
        const vals = getAboveValues();
        return vals.length > 0 ? (vals.reduce((a, b) => a + b, 0) / vals.length) : 0;
      });

      // 3. MIN(ABOVE)
      expr = expr.replace(/MIN\\((?:ABOVE|UP)?\\)/gi, () => {
        const vals = getAboveValues();
        return vals.length > 0 ? Math.min.apply(null, vals) : 0;
      });

      // 4. MAX(ABOVE)
      expr = expr.replace(/MAX\\((?:ABOVE|UP)?\\)/gi, () => {
        const vals = getAboveValues();
        return vals.length > 0 ? Math.max.apply(null, vals) : 0;
      });

      // 5. COUNT(ABOVE)
      expr = expr.replace(/COUNT\\((?:ABOVE|UP)?\\)/gi, () => {
        return getAboveValues().length;
      });

      // 6. SUM(LEFT)
      expr = expr.replace(/SUM\\(LEFT\\)/gi, () => {
        const vals = getLeftValues();
        return vals.reduce((a, b) => a + b, 0);
      });

      // 7. SUM(A1:A2) or SUM(A1..A2)
      expr = expr.replace(/SUM\\(([A-Za-z]+[0-9]+)(?::|\\.\\.)([A-Za-z]+[0-9]+)\\)/gi, (m, c1, c2) => {
        const vals = getRangeValues(c1, c2);
        return vals.reduce((a, b) => a + b, 0);
      });

      // 8. AVG(A1:A2)
      expr = expr.replace(/(?:AVG|AVERAGE)\\(([A-Za-z]+[0-9]+)(?::|\\.\\.)([A-Za-z]+[0-9]+)\\)/gi, (m, c1, c2) => {
        const vals = getRangeValues(c1, c2);
        return vals.length > 0 ? (vals.reduce((a, b) => a + b, 0) / vals.length) : 0;
      });

      // 9. MIN(A1:A2)
      expr = expr.replace(/MIN\\(([A-Za-z]+[0-9]+)(?::|\\.\\.)([A-Za-z]+[0-9]+)\\)/gi, (m, c1, c2) => {
        const vals = getRangeValues(c1, c2);
        return vals.length > 0 ? Math.min.apply(null, vals) : 0;
      });

      // 10. MAX(A1:A2)
      expr = expr.replace(/MAX\\(([A-Za-z]+[0-9]+)(?::|\\.\\.)([A-Za-z]+[0-9]+)\\)/gi, (m, c1, c2) => {
        const vals = getRangeValues(c1, c2);
        return vals.length > 0 ? Math.max.apply(null, vals) : 0;
      });

      // 11. COUNT(A1:A2)
      expr = expr.replace(/COUNT\\(([A-Za-z]+[0-9]+)(?::|\\.\\.)([A-Za-z]+[0-9]+)\\)/gi, (m, c1, c2) => {
        return getRangeValues(c1, c2).length;
      });

      // 12. SUM(A1, A2) or SUM(A1 + A2)
      expr = expr.replace(/SUM\\(([^)]+)\\)/gi, (m, inner) => {
        if (inner.indexOf(',') !== -1) {
          const parts = inner.split(',');
          let sum = 0;
          for (let i = 0; i < parts.length; i++) {
            const p = parts[i].trim();
            const coord = parseCellCoord(p);
            if (coord) sum += getCellValue(p);
            else { const n = parseFloat(p); if (!isNaN(n)) sum += n; }
          }
          return sum;
        }
        return '(' + inner + ')';
      });

      // 13. Replace individual coordinates like A1, A2, B3 with cell values
      expr = expr.replace(/([A-Za-z]+[0-9]+)/g, (match) => {
        const coord = parseCellCoord(match);
        if (coord) {
          return getCellValue(match);
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
        if (ch === '+' || ch === '-' || ch === '*' || ch === '/' || ch === '(' || ch === ')') {
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

      function parseFactor() {
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

    function scanAndRegisterTableFormulas() {
      const liveTables = document.querySelectorAll('.ck-content table, .ck-editor__editable table, #fallback-content table, table');
      liveTables.forEach((table, tableIdx) => {
        const rows = table.rows;
        if (!rows) return;
        for (let r = 0; r < rows.length; r++) {
          for (let c = 0; c < rows[r].cells.length; c++) {
            const cell = rows[r].cells[c];
            const regKey = tableIdx + '_' + r + '_' + c;
            const txt = cleanFormulaText(cell.innerText || cell.textContent || '');
            if (txt.startsWith('=')) {
              window._tableFormulaRegistry[regKey] = txt;
              cell.setAttribute('data-formula', txt);
            } else if (cell.getAttribute && cell.getAttribute('data-formula')) {
              const f = cleanFormulaText(cell.getAttribute('data-formula'));
              if (f.startsWith('=')) {
                window._tableFormulaRegistry[regKey] = f;
              }
            } else if (cell.querySelector) {
              const elF = cell.querySelector('[data-formula]');
              if (elF) {
                const f = cleanFormulaText(elF.getAttribute('data-formula'));
                if (f.startsWith('=')) {
                  window._tableFormulaRegistry[regKey] = f;
                }
              }
            }
          }
        }
      });
    }

    function getCellFormula(cell, tableIdx, r, c) {
      const regKey = (tableIdx !== undefined && r !== undefined && c !== undefined) ? (tableIdx + '_' + r + '_' + c) : null;
      if (cell) {
        const directText = cleanFormulaText(cell.innerText || cell.textContent || '');
        if (directText.startsWith('=')) {
          if (regKey) window._tableFormulaRegistry[regKey] = directText;
          return directText;
        }
        if (cell.getAttribute && cell.getAttribute('data-formula')) {
          const f = cleanFormulaText(cell.getAttribute('data-formula'));
          if (f.startsWith('=')) {
            if (regKey) window._tableFormulaRegistry[regKey] = f;
            return f;
          }
        }
        if (cell.querySelector) {
          const withFormula = cell.querySelectorAll('[data-formula]');
          for (let i = 0; i < withFormula.length; i++) {
            const f = cleanFormulaText(withFormula[i].getAttribute('data-formula'));
            if (f.startsWith('=')) {
              if (regKey) window._tableFormulaRegistry[regKey] = f;
              return f;
            }
          }
          const withTitle = cell.querySelectorAll('[title*="Formula:"]');
          for (let i = 0; i < withTitle.length; i++) {
            const title = withTitle[i].getAttribute('title') || '';
            const idx = title.indexOf('Formula:');
            if (idx !== -1) {
              const cand = cleanFormulaText(title.substring(idx + 8));
              if (cand.startsWith('=')) {
                if (regKey) window._tableFormulaRegistry[regKey] = cand;
                return cand;
              }
            }
          }
        }
      }
      if (regKey && window._tableFormulaRegistry[regKey]) {
        return window._tableFormulaRegistry[regKey];
      }
      return null;
    }

    function evaluateAllTableFormulas(showToast = false) {
      autoUpdateTableFormulasDOM();
      if (showToast) {
        showToastMsg('⚡ Table formulas are 100% auto-calculated in real time');
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
                  editor.model.change(writer => {
                    const range = writer.createRangeIn(targetCell);
                    writer.remove(range);
                    const p = writer.createElement('paragraph');
                    writer.insert(p, targetCell, 0);
                    writer.insertText(resStr, { bold: true }, p, 0);
                  });
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

    function autoUpdateTableFormulasDOM() {
      const liveTables = document.querySelectorAll('.ck-content table, .ck-editor__editable table, #fallback-content table, table');
      if (liveTables.length === 0) return;

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

        // 3. Recalculate formula cells and update LIVE DOM
        for (let r = 0; r < liveRows.length; r++) {
          for (let c = 0; c < liveRows[r].cells.length; c++) {
            const liveCell = liveRows[r].cells[c];
            const formula = getCellFormula(liveCell, tableIdx, r, c);
            if (formula && formula.startsWith('=')) {
              const res = evaluateFormulaString(formula, grid, r, c);
              if (res !== null) {
                const resStr = String(res);
                liveCell.setAttribute('data-formula', formula);

                const strong = liveCell.querySelector('strong');
                if (strong) {
                  if (strong.textContent !== resStr) {
                    strong.textContent = resStr;
                    strong.setAttribute('data-formula', formula);
                    anyUpdated = true;
                  }
                } else {
                  liveCell.innerHTML = '<p><strong data-formula="' + formula + '">' + resStr + '</strong> <span class="formula-badge" style="font-size:10px;padding:1px 5px;background:#dbeafe;color:#1e40af;border-radius:3px;font-weight:normal;cursor:help;margin-left:4px;" data-formula="' + formula + '" title="Formula: ' + formula + '">fx</span></p>';
                  anyUpdated = true;
                }

                let badge = liveCell.querySelector('.formula-badge');
                if (!badge) {
                  const p = liveCell.querySelector('p') || liveCell;
                  p.insertAdjacentHTML('beforeend', ' <span class="formula-badge" style="font-size:10px;padding:1px 5px;background:#dbeafe;color:#1e40af;border-radius:3px;font-weight:normal;cursor:help;margin-left:4px;" data-formula="' + formula + '" title="Formula: ' + formula + '">fx</span>');
                } else {
                  badge.setAttribute('data-formula', formula);
                  badge.setAttribute('title', 'Formula: ' + formula);
                }

                // Update grid so chained formulas work instantly
                grid[r][c] = resStr;
              }
            }
          }
        }
      });

      if (anyUpdated) {
        if (editorInstance) {
          try {
            const editableEl = editorInstance.ui && editorInstance.ui.view && editorInstance.ui.view.editable
              ? editorInstance.ui.view.editable.element : null;
            if (editableEl) {
              postToFlutter({ type: 'ckeditor_change', html: editableEl.innerHTML });
            }
          } catch(e) {}
        }
      }
    }
    window.autoUpdateTableFormulasDOM = autoUpdateTableFormulasDOM;

    function evaluateTableFormulas() {
      autoUpdateTableFormulasDOM();
    }

    // Live formula recalculation on any input/keyup at document level
    document.addEventListener('input', function() { scheduleLiveFormulaRecalc(); }, true);
    document.addEventListener('keyup', function() { scheduleLiveFormulaRecalc(); }, true);

    // Also recalculate when cell loses focus
    document.addEventListener('focusout', function(e) {
      setTimeout(() => {
        autoUpdateTableFormulasDOM();
        if (editorInstance && editorInstance.model) {
          syncAllModelFormulaCells();
        }
      }, 40);
    }, true);

    function syncAllModelFormulaCells() {
      if (!editorInstance || !editorInstance.model) return;
      try {
        const liveTables = document.querySelectorAll('.ck-content table, .ck-editor__editable table');
        liveTables.forEach((table, tableIdx) => {
          for (let r = 0; r < table.rows.length; r++) {
            for (let c = 0; c < table.rows[r].cells.length; c++) {
              const regKey = tableIdx + '_' + r + '_' + c;
              if (window._tableFormulaRegistry && window._tableFormulaRegistry[regKey]) {
                const strong = table.rows[r].cells[c].querySelector('strong');
                if (strong) {
                  _syncModelFormulaCell(editorInstance, tableIdx, r, c, strong.textContent, window._tableFormulaRegistry[regKey]);
                }
              }
            }
          }
        });
      } catch (e) {}
    }

    // Recalculate on Enter/Tab in table cell
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Enter' || e.key === 'Tab') {
        setTimeout(() => {
          autoUpdateTableFormulasDOM();
        }, 30);
      }
    }, true);

    function showFormulaHelpModal() {
      document.getElementById('formula-modal').classList.add('show');
    }

    function closeFormulaHelpModal() {
      document.getElementById('formula-modal').classList.remove('show');
    }

    /* ====== TABLE COLOR & STYLING LOGIC ====== */
    let lastActiveTableCell = null;
    let currentTableTarget = 'cell';

    document.addEventListener('click', function(e) {
      const cell = e.target.closest('td, th');
      if (cell) lastActiveTableCell = cell;
    }, true);

    document.addEventListener('selectionchange', function() {
      const sel = window.getSelection();
      if (sel && sel.anchorNode) {
        const node = sel.anchorNode.nodeType === Node.ELEMENT_NODE ? sel.anchorNode : sel.anchorNode.parentElement;
        const cell = node ? node.closest('td, th') : null;
        if (cell) lastActiveTableCell = cell;
      }
    });

    function getActiveTableCell() {
      if (lastActiveTableCell && document.contains(lastActiveTableCell)) return lastActiveTableCell;
      const sel = window.getSelection();
      if (sel && sel.anchorNode) {
        const node = sel.anchorNode.nodeType === Node.ELEMENT_NODE ? sel.anchorNode : sel.anchorNode.parentElement;
        const cell = node ? node.closest('td, th') : null;
        if (cell) {
          lastActiveTableCell = cell;
          return cell;
        }
      }
      const anyCell = document.querySelector('.ck-content table td, .ck-content table th, #fallback-content table td, #fallback-content table th');
      if (anyCell) {
        lastActiveTableCell = anyCell;
        return anyCell;
      }
      return null;
    }

    function openTableColorModal() {
      const cell = getActiveTableCell();
      if (!cell) {
        showToastMsg('⚠️ Click inside a table cell first!');
        return;
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

    function applyPresetBg(bg, text) {
      applyTableFormatting(bg, text, null);
    }

    function applyCustomBg(bg) {
      applyTableFormatting(bg, null, null);
    }

    function clearTableBg() {
      applyTableFormatting('', '#1e293b', null);
    }

    function applyBorderColor(borderColor) {
      applyTableFormatting(null, null, borderColor);
    }

    function applyTextColor(txtColor) {
      applyTableFormatting(null, txtColor, null);
    }

    function applyTableFormatting(bgColor, txtColor, borderColor) {
      const cell = getActiveTableCell();
      if (!cell) {
        showToastMsg('⚠️ Click inside a table cell first!');
        return;
      }
      const table = cell.closest('table');
      if (!table) return;

      const colIdx = cell.cellIndex;
      const row = cell.closest('tr');

      const applyToCell = (c) => {
        if (!c) return;
        if (bgColor !== null && bgColor !== undefined) c.style.backgroundColor = bgColor;
        if (txtColor !== null && txtColor !== undefined) c.style.color = txtColor;
        if (borderColor !== null && borderColor !== undefined) {
          c.style.borderColor = borderColor;
          c.style.borderWidth = '1px';
          c.style.borderStyle = 'solid';
        }
      };

      if (currentTableTarget === 'cell') {
        applyToCell(cell);
      } else if (currentTableTarget === 'col') {
        for (let i = 0; i < table.rows.length; i++) {
          const r = table.rows[i];
          if (r.cells && r.cells[colIdx]) {
            applyToCell(r.cells[colIdx]);
          }
        }
      } else if (currentTableTarget === 'row') {
        if (row && row.cells) {
          for (let j = 0; j < row.cells.length; j++) {
            applyToCell(row.cells[j]);
          }
        }
      } else if (currentTableTarget === 'table') {
        for (let i = 0; i < table.rows.length; i++) {
          const r = table.rows[i];
          for (let j = 0; j < r.cells.length; j++) {
            applyToCell(r.cells[j]);
          }
        }
      } else if (currentTableTarget === 'header') {
        if (table.rows.length > 0) {
          const r = table.rows[0];
          for (let j = 0; j < r.cells.length; j++) {
            const c = r.cells[j];
            c.style.backgroundColor = bgColor || '#1e293b';
            c.style.color = txtColor || '#ffffff';
            c.style.fontWeight = '700';
            if (borderColor) c.style.borderColor = borderColor;
          }
        }
      } else if (currentTableTarget === 'zebra') {
        const color1 = bgColor || '#f8fafc';
        const color2 = '#ffffff';
        for (let i = 0; i < table.rows.length; i++) {
          const bg = (i % 2 === 0) ? color1 : color2;
          const r = table.rows[i];
          for (let j = 0; j < r.cells.length; j++) {
            r.cells[j].style.backgroundColor = bg;
            if (txtColor) r.cells[j].style.color = txtColor;
            if (borderColor) r.cells[j].style.borderColor = borderColor;
          }
        }
      }

      // Sync with CKEditor model and Flutter
      if (editorInstance) {
        try {
          const html = editorInstance.getData();
          postToFlutter({ type: 'ckeditor_change', html: html });
        } catch(e) {}
      }
      showToastMsg('🎨 Table formatting updated!');
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
          const html = editorInstance.getData();
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
            const html = editorInstance.getData();
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

    function attachMediaListeners() {
      const editable = document.querySelector('.ck-content, #fallback-content');
      if (!editable) return;

      editable.addEventListener('click', function(e) {
        const mediaFig = e.target.closest('figure.media, .media, [data-oembed-url], video, iframe');
        if (mediaFig) {
          const figure = mediaFig.tagName.toLowerCase() === 'figure' ? mediaFig : (mediaFig.closest('figure') || mediaFig);
          showVideoToolbar(figure);
        } else if (!e.target.closest('.video-resize-toolbar')) {
          hideVideoToolbar();
        }
      });
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
      showVideoToolbar(activeMediaFigure);
      if (editorInstance) {
        try {
          const html = editorInstance.getData();
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
      showVideoToolbar(activeMediaFigure);
      if (editorInstance) {
        try {
          const html = editorInstance.getData();
          postToFlutter({ type: 'ckeditor_change', html: html });
        } catch(e) {}
      }
    }

    function removeActiveMedia() {
      if (!activeMediaFigure) return;
      activeMediaFigure.remove();
      hideVideoToolbar();
      activeMediaFigure = null;
      if (editorInstance) {
        try {
          const html = editorInstance.getData();
          postToFlutter({ type: 'ckeditor_change', html: html });
        } catch(e) {}
      }
      showToastMsg('Video removed');
    }

    function attachMediaDragHandles() {
      const editable = document.querySelector('.ck-content, #fallback-content');
      if (!editable) return;

      editable.querySelectorAll('figure.media, .media').forEach(media => {
        if (!media.querySelector('.video-resize-handle')) {
          const handle = document.createElement('div');
          handle.className = 'video-resize-handle';
          handle.title = 'Drag to resize video';
          media.appendChild(handle);

          let startX, startW, parentW;
          handle.addEventListener('mousedown', function(e) {
            e.preventDefault();
            e.stopPropagation();
            startX = e.clientX;
            startW = media.offsetWidth;
            parentW = media.parentElement ? media.parentElement.offsetWidth : 800;

            function onMouseMove(ev) {
              const dx = ev.clientX - startX;
              const newW = Math.max(160, Math.min(parentW, startW + dx));
              const pct = Math.round((newW / parentW) * 100);
              media.style.width = pct + '%';
              media.style.maxWidth = pct + '%';
              showVideoToolbar(media);
            }
            function onMouseUp() {
              document.removeEventListener('mousemove', onMouseMove);
              document.removeEventListener('mouseup', onMouseUp);
              if (editorInstance) {
                try {
                  const html = editorInstance.getData();
                  postToFlutter({ type: 'ckeditor_change', html: html });
                } catch(e) {}
              }
            }
            document.addEventListener('mousemove', onMouseMove);
            document.addEventListener('mouseup', onMouseUp);
          });
        }
      });
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
      { id: 'tag_lims', name: 'Tag #LIMS', desc: 'Insert category tag #lims', icon: '#', fn: () => insertSlashHtml('<span class="mention" data-mention="#lims">#lims</span>&nbsp;') }
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
      }
    }

    function insertSlashHtml(html) {
      closeSlashModal();
      if (editorInstance) {
        const viewFragment = editorInstance.data.processor.toView(html);
        const modelFragment = editorInstance.data.toModel(viewFragment);
        editorInstance.model.insertContent(modelFragment);
      }
    }

    /* Key listener for Cmd+/, Ctrl+/, and Enter/Tab in table cells */
    document.addEventListener('keydown', (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === '/') {
        e.preventDefault();
        showSlashModal();
        return;
      }
      if (e.key === 'Enter' || e.key === 'Tab') {
        const sel = window.getSelection ? window.getSelection() : null;
        if (sel && sel.anchorNode) {
          const el = sel.anchorNode.nodeType === 3 ? sel.anchorNode.parentElement : sel.anchorNode;
          const td = el ? el.closest('td, th') : null;
          if (td) {
            const raw = cleanFormulaText(td.innerText || td.textContent || '');
            if (raw.startsWith('=')) {
              if (e.key === 'Enter') {
                e.preventDefault();
                e.stopPropagation();
              }
              setTimeout(() => { evaluateAllTableFormulas(true); }, 50);
            }
          }
        }
      }
    });

    /* Auto-evaluate when user leaves table cell */
    document.addEventListener('focusout', (e) => {
      if (e.target && e.target.closest && e.target.closest('table')) {
        const td = e.target.closest('td, th');
        if (td) {
          const raw = cleanFormulaText(td.innerText || td.textContent || '');
          if (raw.startsWith('=')) {
            setTimeout(() => { evaluateAllTableFormulas(false); }, 80);
          }
        }
      }
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
        }
      } else if (msg.type === 'executeCommand') {
        if (editorInstance) {
          try { editorInstance.execute(msg.command, msg.params); } catch(e) {}
        }
      }
    });
  </script>
</body>
</html>''';
  }
}
