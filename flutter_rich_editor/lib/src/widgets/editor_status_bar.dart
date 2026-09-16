import 'package:flutter/material.dart';
import '../core/controller/rich_editor_controller.dart';
import '../core/document_model/editor_node.dart';
import '../theme/editor_theme.dart';

class EditorStatusBar extends StatelessWidget {
  const EditorStatusBar({
    super.key,
    required this.controller,
    required this.theme,
  });

  final RichEditorController controller;
  final EditorTheme theme;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        final int words = _calculateWords(controller.document.plainText);
        final int chars = controller.document.plainText.length;
        final String breadcrumbs = _calculateBreadcrumbs();

        return Container(
          height: 28.0,
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          decoration: BoxDecoration(
            color: theme.toolbarBackgroundColor,
            border: Border(top: BorderSide(color: theme.toolbarBorderColor)),
          ),
          child: Row(
            children: <Widget>[
              // Breadcrumbs
              Expanded(
                child: Text(
                  breadcrumbs,
                  style: TextStyle(
                    fontSize: 11.0,
                    color: theme.toolbarItemColor.withValues(alpha: 0.7),
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Word & Character count
              Text(
                'Words: $words  |  Characters: $chars',
                style: TextStyle(
                  fontSize: 11.0,
                  color: theme.toolbarItemColor.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  int _calculateWords(String text) {
    if (text.trim().isEmpty) return 0;
    return text.trim().split(RegExp(r'\s+')).length;
  }

  String _calculateBreadcrumbs() {
    final int index = controller.selection.nodeIndex;
    if (index < 0 || index >= controller.document.nodes.length) {
      return 'body';
    }
    final EditorNode node = controller.document.nodes[index];
    switch (node.type) {
      case 'heading':
        final int level = (node.metadata['level'] as num?)?.toInt() ?? 1;
        return 'body > h$level';
      case 'blockquote':
        return 'body > blockquote > p';
      case 'code_block':
        return 'body > pre > code';
      case 'list':
        final String tag = node.metadata['listType'] == 'numbered' ? 'ol' : 'ul';
        return 'body > $tag > li';
      case 'table':
        return 'body > table > tr > td';
      case 'image':
        return 'body > figure > img';
      case 'video':
        return 'body > video';
      case 'paragraph':
      default:
        return 'body > p';
    }
  }
}
