import 'package:flutter/material.dart';
import '../core/controller/rich_editor_controller.dart';
import '../theme/editor_theme.dart';
import '../toolbar/toolbar_config.dart';
import 'editor_config.dart';
import 'rich_editor.dart';

/// Fullscreen modal dialog hosting a [RichEditor].
class FullscreenEditor extends StatelessWidget {
  const FullscreenEditor({
    super.key,
    required this.controller,
    this.theme = const EditorTheme(),
    this.config = const EditorConfig(),
    this.toolbarConfig = const ToolbarConfig(),
    this.title = 'Document Editor',
    this.onClose,
  });

  final RichEditorController controller;
  final EditorTheme theme;
  final EditorConfig config;
  final ToolbarConfig toolbarConfig;
  final String title;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(title, style: theme.heading3Style),
        backgroundColor: theme.toolbarBackgroundColor,
        elevation: theme.toolbarElevation,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close Fullscreen',
            onPressed: onClose ?? () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: RichEditor(
            controller: controller,
            theme: theme,
            config: config,
            toolbarConfig: toolbarConfig,
          ),
        ),
      ),
    );
  }
}
