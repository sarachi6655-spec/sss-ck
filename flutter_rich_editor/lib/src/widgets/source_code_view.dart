import 'package:flutter/material.dart';
import '../core/controller/rich_editor_controller.dart';
import '../theme/editor_theme.dart';

class SourceCodeView extends StatefulWidget {
  const SourceCodeView({
    super.key,
    required this.controller,
    required this.theme,
  });

  final RichEditorController controller;
  final EditorTheme theme;

  @override
  State<SourceCodeView> createState() => _SourceCodeViewState();
}

class _SourceCodeViewState extends State<SourceCodeView> {
  late final TextEditingController _htmlTextController;

  @override
  void initState() {
    super.initState();
    _htmlTextController = TextEditingController(text: widget.controller.toHtml());
    _htmlTextController.addListener(_syncHtmlBack);
  }

  void _syncHtmlBack() {
    final String newHtml = _htmlTextController.text;
    try {
      widget.controller.loadHtml(newHtml);
    } catch (_) {}
  }

  @override
  void dispose() {
    _htmlTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.theme.codeBlockBackgroundColor,
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: const Row(
              children: <Widget>[
                Icon(Icons.html, size: 18, color: Color(0xFF2563EB)),
                SizedBox(width: 6.0),
                Text(
                  'HTML Source Mode — Direct Semantic Markup Editing',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8.0),
          Expanded(
            child: TextField(
              controller: _htmlTextController,
              maxLines: null,
              expands: true,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13.0,
                height: 1.5,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
