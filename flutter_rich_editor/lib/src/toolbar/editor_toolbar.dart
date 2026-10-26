import 'package:flutter/material.dart';
import '../core/controller/rich_editor_controller.dart';
import '../core/document_model/editor_node.dart';
import '../features/formatting/formatting_plugin.dart';
import '../features/media/image_plugin.dart';
import '../features/media/link_plugin.dart';
import '../features/media/table_plugin.dart';
import '../features/media/video_plugin.dart';
import '../features/structure/structure_plugin.dart';
import '../features/voice_input/voice_input_button.dart';
import '../theme/editor_theme.dart';
import 'dialogs/color_picker_popup.dart';
import 'dialogs/image_dialog.dart';
import 'dialogs/link_dialog.dart';
import 'dialogs/special_characters_dialog.dart';
import 'dialogs/table_insert_dialog.dart';
import 'toolbar_config.dart';
import 'toolbar_item.dart';

/// Interactive toolbar widget dynamically styled by [EditorTheme].
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.controller,
    required this.theme,
    this.config = const ToolbarConfig(),
    this.onToggleSourceMode,
    this.onToggleFindReplace,
    this.isSourceMode = false,
  });

  final RichEditorController controller;
  final EditorTheme theme;
  final ToolbarConfig config;
  final VoidCallback? onToggleSourceMode;
  final VoidCallback? onToggleFindReplace;
  final bool isSourceMode;

  List<ToolbarItem> _buildDefaultItems(BuildContext context) => <ToolbarItem>[
        // History
        ToolbarItem(
          id: 'undo',
          icon: Icons.undo,
          label: 'Undo',
          tooltip: 'Undo (Ctrl+Z)',
          isEnabled: (doc) => controller.canUndo,
          onTap: (ctrl) => ctrl.undo(),
        ),
        ToolbarItem(
          id: 'redo',
          icon: Icons.redo,
          label: 'Redo',
          tooltip: 'Redo (Ctrl+Y)',
          isEnabled: (doc) => controller.canRedo,
          onTap: (ctrl) => ctrl.redo(),
        ),

        // Block Type Dropdown
        ToolbarItem(
          id: 'format',
          icon: Icons.format_shapes,
          label: 'Paragraph Format',
          tooltip: 'Block Type',
          customWidget: (BuildContext ctx, RichEditorController ctrl, EditorTheme th) {
            return _buildFormatDropdown(ctrl, th);
          },
        ),

        // Font Family Dropdown
        ToolbarItem(
          id: 'font_family',
          icon: Icons.font_download,
          label: 'Font Family',
          tooltip: 'Font Family',
          customWidget: (BuildContext ctx, RichEditorController ctrl, EditorTheme th) {
            return _buildFontFamilyDropdown(ctrl, th);
          },
        ),

        // Font Size Dropdown
        ToolbarItem(
          id: 'font_size',
          icon: Icons.format_size,
          label: 'Font Size',
          tooltip: 'Font Size',
          customWidget: (BuildContext ctx, RichEditorController ctrl, EditorTheme th) {
            return _buildFontSizeDropdown(ctrl, th);
          },
        ),

        // Inline formatting
        ToolbarItem(
          id: 'bold',
          icon: Icons.format_bold,
          label: 'Bold',
          tooltip: 'Bold (Ctrl+B)',
          isActive: (doc) =>
              doc.selection.isCollapsed
                  ? (doc.metadata['pendingMarks']?['bold'] == true)
                  : (doc.nodes.isNotEmpty &&
                      doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].attributes['bold'] == true),
          onTap: (ctrl) => ctrl.execute(const FormatMarkCommand(mark: 'bold')),
        ),
        ToolbarItem(
          id: 'italic',
          icon: Icons.format_italic,
          label: 'Italic',
          tooltip: 'Italic (Ctrl+I)',
          isActive: (doc) =>
              doc.selection.isCollapsed
                  ? (doc.metadata['pendingMarks']?['italic'] == true)
                  : (doc.nodes.isNotEmpty &&
                      doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].attributes['italic'] == true),
          onTap: (ctrl) => ctrl.execute(const FormatMarkCommand(mark: 'italic')),
        ),
        ToolbarItem(
          id: 'underline',
          icon: Icons.format_underlined,
          label: 'Underline',
          tooltip: 'Underline (Ctrl+U)',
          isActive: (doc) =>
              doc.nodes.isNotEmpty &&
              doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].attributes['underline'] == true,
          onTap: (ctrl) => ctrl.execute(const FormatMarkCommand(mark: 'underline')),
        ),
        ToolbarItem(
          id: 'strikethrough',
          icon: Icons.format_strikethrough,
          label: 'Strikethrough',
          tooltip: 'Strikethrough',
          isActive: (doc) =>
              doc.nodes.isNotEmpty &&
              doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].attributes['strikethrough'] == true,
          onTap: (ctrl) => ctrl.execute(const FormatMarkCommand(mark: 'strikethrough')),
        ),
        ToolbarItem(
          id: 'subscript',
          icon: Icons.subscript,
          label: 'Subscript',
          tooltip: 'Subscript',
          isActive: (doc) =>
              doc.nodes.isNotEmpty &&
              doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].attributes['subscript'] == true,
          onTap: (ctrl) => ctrl.execute(const FormatMarkCommand(mark: 'subscript')),
        ),
        ToolbarItem(
          id: 'superscript',
          icon: Icons.superscript,
          label: 'Superscript',
          tooltip: 'Superscript',
          isActive: (doc) =>
              doc.nodes.isNotEmpty &&
              doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].attributes['superscript'] == true,
          onTap: (ctrl) => ctrl.execute(const FormatMarkCommand(mark: 'superscript')),
        ),
        ToolbarItem(
          id: 'code',
          icon: Icons.code,
          label: 'Code',
          tooltip: 'Inline Code',
          isActive: (doc) =>
              doc.nodes.isNotEmpty &&
              doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].attributes['code'] == true,
          onTap: (ctrl) => ctrl.execute(const FormatMarkCommand(mark: 'code')),
        ),

        // Color pickers
        ToolbarItem(
          id: 'color',
          icon: Icons.format_color_text,
          label: 'Font Color',
          tooltip: 'Font Color',
          onTap: (ctrl) async {
            final String? hex = await ColorPickerPopup.show(context, title: 'Font Color');
            if (hex != null) {
              ctrl.execute(FormatMarkCommand(mark: 'color', value: hex.isNotEmpty ? hex : null));
            }
          },
        ),
        ToolbarItem(
          id: 'highlight',
          icon: Icons.border_color,
          label: 'Highlight Color',
          tooltip: 'Highlight Color',
          onTap: (ctrl) async {
            final String? hex = await ColorPickerPopup.show(context, title: 'Highlight Color');
            if (hex != null) {
              ctrl.execute(FormatMarkCommand(mark: 'backgroundColor', value: hex.isNotEmpty ? hex : null));
            }
          },
        ),

        // Text Alignment
        ToolbarItem(
          id: 'align_left',
          icon: Icons.format_align_left,
          label: 'Align Left',
          tooltip: 'Align Left',
          isActive: (doc) =>
              doc.nodes.isNotEmpty &&
              doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].attributes['align'] == 'left',
          onTap: (ctrl) => ctrl.execute(const SetTextAlignmentCommand(align: 'left')),
        ),
        ToolbarItem(
          id: 'align_center',
          icon: Icons.format_align_center,
          label: 'Align Center',
          tooltip: 'Align Center',
          isActive: (doc) =>
              doc.nodes.isNotEmpty &&
              doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].attributes['align'] == 'center',
          onTap: (ctrl) => ctrl.execute(const SetTextAlignmentCommand(align: 'center')),
        ),
        ToolbarItem(
          id: 'align_right',
          icon: Icons.format_align_right,
          label: 'Align Right',
          tooltip: 'Align Right',
          isActive: (doc) =>
              doc.nodes.isNotEmpty &&
              doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].attributes['align'] == 'right',
          onTap: (ctrl) => ctrl.execute(const SetTextAlignmentCommand(align: 'right')),
        ),
        ToolbarItem(
          id: 'align_justify',
          icon: Icons.format_align_justify,
          label: 'Justify',
          tooltip: 'Justify',
          isActive: (doc) =>
              doc.nodes.isNotEmpty &&
              doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].attributes['align'] == 'justify',
          onTap: (ctrl) => ctrl.execute(const SetTextAlignmentCommand(align: 'justify')),
        ),

        // Lists & Indent
        ToolbarItem(
          id: 'bullet_list',
          icon: Icons.format_list_bulleted,
          label: 'Bullet List',
          tooltip: 'Bullet List',
          isActive: (doc) =>
              doc.nodes.isNotEmpty &&
              doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].type == 'list' &&
              doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].metadata['listType'] == 'bullet',
          onTap: (ctrl) => ctrl.execute(const ToggleListCommand(listType: 'bullet')),
        ),
        ToolbarItem(
          id: 'numbered_list',
          icon: Icons.format_list_numbered,
          label: 'Numbered List',
          tooltip: 'Numbered List',
          isActive: (doc) =>
              doc.nodes.isNotEmpty &&
              doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].type == 'list' &&
              doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].metadata['listType'] == 'numbered',
          onTap: (ctrl) => ctrl.execute(const ToggleListCommand(listType: 'numbered')),
        ),
        ToolbarItem(
          id: 'todo_list',
          icon: Icons.checklist,
          label: 'To-do List',
          tooltip: 'To-do Checklist',
          isActive: (doc) =>
              doc.nodes.isNotEmpty &&
              doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].type == 'list' &&
              doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].metadata['listType'] == 'todo',
          onTap: (ctrl) => ctrl.execute(const ToggleListCommand(listType: 'todo')),
        ),
        ToolbarItem(
          id: 'indent',
          icon: Icons.format_indent_increase,
          label: 'Indent',
          tooltip: 'Increase Indent',
          onTap: (ctrl) => ctrl.execute(const IndentListCommand()),
        ),
        ToolbarItem(
          id: 'outdent',
          icon: Icons.format_indent_decrease,
          label: 'Outdent',
          tooltip: 'Decrease Indent',
          onTap: (ctrl) => ctrl.execute(const OutdentListCommand()),
        ),
        ToolbarItem(
          id: 'blockquote',
          icon: Icons.format_quote,
          label: 'Quote',
          tooltip: 'Blockquote',
          isActive: (doc) =>
              doc.nodes.isNotEmpty &&
              doc.nodes[doc.selection.nodeIndex.clamp(0, doc.nodes.length - 1)].type == 'blockquote',
          onTap: (ctrl) => ctrl.execute(const SetBlockTypeCommand(type: 'blockquote')),
        ),

        // Inserts
        ToolbarItem(
          id: 'table',
          icon: Icons.table_chart,
          label: 'Table',
          tooltip: 'Insert Table',
          onTap: (ctrl) async {
            final TableInsertConfig? res = await TableInsertDialog.show(context);
            if (res != null) {
              ctrl.execute(InsertTableCommand(
                rows: res.rows,
                columns: res.columns,
                caption: res.caption,
              ));
            }
          },
        ),
        ToolbarItem(
          id: 'image',
          icon: Icons.image,
          label: 'Image',
          tooltip: 'Insert Image',
          onTap: (ctrl) async {
            final ImageDialogResult? res = await ImageDialog.show(context);
            if (res != null) {
              ctrl.execute(InsertImageCommand(
                url: res.url,
                alt: res.alt,
                caption: res.caption,
                width: res.width,
              ));
            }
          },
        ),
        ToolbarItem(
          id: 'video',
          icon: Icons.videocam,
          label: 'Video',
          tooltip: 'Insert Video',
          onTap: (ctrl) => ctrl.execute(const InsertVideoCommand(url: 'https://sample.mp4')),
        ),
        ToolbarItem(
          id: 'link',
          icon: Icons.link,
          label: 'Link',
          tooltip: 'Insert / Edit Link',
          onTap: (ctrl) async {
            final LinkDialogResult? res = await LinkDialog.show(context);
            if (res != null) {
              if (res.isUnlink) {
                ctrl.execute(const FormatMarkCommand(mark: 'link', value: null));
              } else {
                ctrl.execute(SetLinkCommand(url: res.url));
              }
            }
          },
        ),
        ToolbarItem(
          id: 'special_char',
          icon: Icons.emoji_symbols,
          label: 'Special Characters',
          tooltip: 'Special Characters & Symbols',
          onTap: (ctrl) async {
            final String? char = await SpecialCharactersDialog.show(context);
            if (char != null && char.isNotEmpty) {
              ctrl.execute(InsertSpecialCharacterCommand(character: char));
            }
          },
        ),
        ToolbarItem(
          id: 'hr',
          icon: Icons.horizontal_rule,
          label: 'Horizontal Line',
          tooltip: 'Horizontal Line',
          onTap: (ctrl) => ctrl.execute(const InsertHorizontalRuleCommand()),
        ),
        ToolbarItem(
          id: 'clear_format',
          icon: Icons.format_clear,
          label: 'Clear Formatting',
          tooltip: 'Remove Formatting',
          onTap: (ctrl) => ctrl.execute(const ClearFormattingCommand()),
        ),

        // Tools
        if (onToggleFindReplace != null)
          ToolbarItem(
            id: 'find_replace',
            icon: Icons.search,
            label: 'Find and Replace',
            tooltip: 'Find & Replace',
            onTap: (_) => onToggleFindReplace?.call(),
          ),
        if (onToggleSourceMode != null)
          ToolbarItem(
            id: 'source',
            icon: Icons.html,
            label: 'Source',
            tooltip: 'Source Editing (HTML)',
            isActive: (_) => isSourceMode,
            onTap: (_) => onToggleSourceMode?.call(),
          ),

        // AI Generate / Voice Input — auto-injected when voice/AI callbacks are set
        if (config.hasVoiceInput)
          ToolbarItem(
            id: 'voice.input',
            icon: Icons.auto_awesome,
            label: 'Generate',
            tooltip: 'Generate with AI (Voice or Text)',
            customWidget: (BuildContext ctx, RichEditorController ctrl, EditorTheme th) =>
                VoiceInputButton(
              controller: ctrl,
              theme: th,
              insertMode: config.voiceInsertMode,
              onRecord: config.onVoiceRecord,
              onTranscribe: config.onVoiceTranscribe,
              onVoiceInput: config.onVoiceInput,
              onMicPressed: config.onMicPressed,
              onError: config.onVoiceError,
            ),
          ),
      ];

  Widget _buildFormatDropdown(RichEditorController ctrl, EditorTheme th) {
    final int idx = ctrl.selection.nodeIndex;
    String currentType = 'paragraph';
    if (idx >= 0 && idx < ctrl.document.nodes.length) {
      final EditorNode node = ctrl.document.nodes[idx];
      if (node.type == 'heading') {
        final int level = (node.metadata['level'] as num?)?.toInt() ?? 1;
        currentType = 'h$level';
      } else if (node.type == 'blockquote') {
        currentType = 'blockquote';
      } else if (node.type == 'code_block') {
        currentType = 'code_block';
      }
    }

    return Container(
      height: 32.0,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      decoration: BoxDecoration(
        color: th.toolbarItemActiveBackgroundColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentType,
          isDense: true,
          dropdownColor: th.toolbarBackgroundColor,
          style: TextStyle(color: th.textColor, fontSize: 13.0),
          icon: Icon(Icons.arrow_drop_down, color: th.toolbarItemColor, size: 20),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(value: 'paragraph', child: Text('Paragraph')),
            DropdownMenuItem<String>(value: 'h1', child: Text('Heading 1', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            DropdownMenuItem<String>(value: 'h2', child: Text('Heading 2', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            DropdownMenuItem<String>(value: 'h3', child: Text('Heading 3', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
            DropdownMenuItem<String>(value: 'h4', child: Text('Heading 4', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            DropdownMenuItem<String>(value: 'blockquote', child: Text('Blockquote', style: TextStyle(fontStyle: FontStyle.italic))),
            DropdownMenuItem<String>(value: 'code_block', child: Text('Code Block', style: TextStyle(fontFamily: 'monospace'))),
          ],
          onChanged: (String? val) {
            if (val == null) return;
            if (val == 'paragraph') {
              ctrl.execute(const SetBlockTypeCommand(type: 'paragraph'));
            } else if (val.startsWith('h')) {
              final int level = int.tryParse(val.substring(1)) ?? 1;
              ctrl.execute(SetBlockTypeCommand(type: 'heading', metadata: <String, dynamic>{'level': level}));
            } else if (val == 'blockquote') {
              ctrl.execute(const SetBlockTypeCommand(type: 'blockquote'));
            } else if (val == 'code_block') {
              ctrl.execute(const SetBlockTypeCommand(type: 'code_block'));
            }
          },
        ),
      ),
    );
  }

  Widget _buildFontFamilyDropdown(RichEditorController ctrl, EditorTheme th) {
    final int idx = ctrl.selection.nodeIndex;
    String currentFont = 'Default';
    if (idx >= 0 && idx < ctrl.document.nodes.length) {
      final String? font = ctrl.document.nodes[idx].attributes['fontFamily'] as String?;
      if (font != null && font.isNotEmpty) currentFont = font;
    }

    const List<String> fonts = <String>['Default', 'Arial', 'Courier New', 'Georgia', 'Times New Roman', 'Verdana'];

    return Container(
      height: 32.0,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      decoration: BoxDecoration(
        color: th.toolbarItemActiveBackgroundColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: fonts.contains(currentFont) ? currentFont : 'Default',
          isDense: true,
          dropdownColor: th.toolbarBackgroundColor,
          style: TextStyle(color: th.textColor, fontSize: 13.0),
          icon: Icon(Icons.arrow_drop_down, color: th.toolbarItemColor, size: 20),
          items: fonts.map((String f) {
            return DropdownMenuItem<String>(
              value: f,
              child: Text(f, style: TextStyle(fontFamily: f == 'Default' ? null : f)),
            );
          }).toList(),
          onChanged: (String? val) {
            ctrl.execute(SetFontFamilyCommand(fontFamily: val ?? 'Default'));
          },
        ),
      ),
    );
  }

  Widget _buildFontSizeDropdown(RichEditorController ctrl, EditorTheme th) {
    final int idx = ctrl.selection.nodeIndex;
    String currentSize = '14';
    if (idx >= 0 && idx < ctrl.document.nodes.length) {
      final num? size = ctrl.document.nodes[idx].attributes['fontSize'] as num?;
      if (size != null) currentSize = size.toInt().toString();
    }

    const List<Map<String, String>> sizes = <Map<String, String>>[
      <String, String>{'val': '10', 'label': 'Tiny (10)'},
      <String, String>{'val': '12', 'label': 'Small (12)'},
      <String, String>{'val': '14', 'label': 'Normal (14)'},
      <String, String>{'val': '18', 'label': 'Big (18)'},
      <String, String>{'val': '24', 'label': 'Huge (24)'},
    ];

    return Container(
      height: 32.0,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      decoration: BoxDecoration(
        color: th.toolbarItemActiveBackgroundColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: sizes.any((Map<String, String> s) => s['val'] == currentSize) ? currentSize : '14',
          isDense: true,
          dropdownColor: th.toolbarBackgroundColor,
          style: TextStyle(color: th.textColor, fontSize: 13.0),
          icon: Icon(Icons.arrow_drop_down, color: th.toolbarItemColor, size: 20),
          items: sizes.map((Map<String, String> s) {
            return DropdownMenuItem<String>(
              value: s['val'],
              child: Text(s['label']!),
            );
          }).toList(),
          onChanged: (String? val) {
            if (val != null) {
              ctrl.execute(SetFontSizeCommand(fontSize: double.tryParse(val) ?? 14.0));
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<ToolbarItem> defaultItems = _buildDefaultItems(context);
    final List<ToolbarItem> items = config.apply(defaultItems);

    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        return Material(
          elevation: theme.toolbarElevation,
          color: theme.toolbarBackgroundColor,
          borderRadius: BorderRadius.circular(theme.toolbarBorderRadius),
          child: Container(
            height: theme.toolbarHeight,
            padding: theme.toolbarPadding,
            decoration: BoxDecoration(
              border: Border.all(color: theme.toolbarBorderColor),
              borderRadius: BorderRadius.circular(theme.toolbarBorderRadius),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: items.map((ToolbarItem item) {
                  if (item.customWidget != null) {
                    return item.customWidget!(context, controller, theme);
                  }

                  final bool active = item.isActive?.call(controller.document) ?? false;
                  final bool enabled = item.isEnabled?.call(controller.document) ?? true;

                  return Semantics(
                    label: item.label,
                    button: true,
                    enabled: enabled,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: Focus(
                        canRequestFocus: false,
                        child: IconButton(
                          icon: Icon(item.icon, size: 20),
                          tooltip: item.tooltip ?? item.label,
                          color: active
                              ? theme.toolbarItemActiveColor
                              : (enabled ? theme.toolbarItemColor : theme.toolbarItemColor.withValues(alpha: theme.disabledOpacity)),
                          style: active
                              ? IconButton.styleFrom(
                                  backgroundColor: theme.toolbarItemActiveBackgroundColor,
                                )
                              : null,
                          onPressed: enabled ? () => item.onTap?.call(controller) : null,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}
