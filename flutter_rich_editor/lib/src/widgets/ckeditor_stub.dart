import 'package:flutter/material.dart';

/// Fallback / stub for non-web platforms.
class CKEditorWebView extends StatelessWidget {
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
  final Future<String?> Function(String text)? onVoiceInput;

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('CKEditor Web view is not supported on this platform.'),
    );
  }
}
