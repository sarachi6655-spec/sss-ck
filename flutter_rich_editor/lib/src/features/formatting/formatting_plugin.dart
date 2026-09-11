import 'package:flutter/material.dart';

import '../../core/document_model/document_model.dart';
import '../../core/plugin_system/plugin_system.dart';
import '../../theme/editor_theme.dart';

const String _kParagraph = 'paragraph';

/// Plugin that registers text formatting marks, paragraph attributes, and the
/// paragraph node type.
class FormattingPlugin extends EditorPlugin {
  @override
  String get id => 'formatting/core';

  @override
  String get name => 'Text Formatting';

  @override
  void register(PluginRegistry registry) {
    registry.registerNodeType(NodeTypeRegistration(
      nodeType: _kParagraph,
      fromJson: ParagraphNode.fromJson,
      toJson: (EditorNode n) => (n as ParagraphNode).toJson(),
      renderer: (BuildContext context, EditorNode node,
              NodeRenderContext renderContext) =>
          _ParagraphRenderer(node: node as ParagraphNode, context: renderContext),
    ));

    _registerMarkCommands(registry);
    _registerAttributeCommands(registry);
    _registerToolbarItems(registry);
  }

  void _registerMarkCommands(PluginRegistry registry) {
    for (final String mark in _marks) {
      registry.registerCommand('formatting/toggle_$mark',
          (Map<String, dynamic> args) => ToggleMarkCommand(mark: mark));
    }
    registry.registerCommand(
      'formatting/remove_format',
      (Map<String, dynamic> args) => const RemoveFormattingCommand(),
    );
  }

  void _registerAttributeCommands(PluginRegistry registry) {
    registry.registerCommand(
      'formatting/set_alignment',
      (Map<String, dynamic> args) => SetAlignmentCommand(
            alignment: args['alignment'] as String? ?? 'left',
          ),
    );
    registry.registerCommand(
      'formatting/set_indent',
      (Map<String, dynamic> args) => SetIndentCommand(
            delta: args['delta'] as int? ?? 1,
          ),
    );
    registry.registerCommand(
      'formatting/set_color',
      (Map<String, dynamic> args) => SetColorCommand(
            color: args['color'] as String?,
            background: args['background'] as bool? ?? false,
          ),
    );
    registry.registerCommand(
      'formatting/set_font',
      (Map<String, dynamic> args) => SetFontCommand(
            family: args['family'] as String?,
            size: args['size'] as double?,
          ),
    );
    registry.registerCommand(
      'formatting/set_line_height',
      (Map<String, dynamic> args) => SetLineHeightCommand(
            lineHeight: args['lineHeight'] as double? ?? 1.5,
          ),
    );
  }

  void _registerToolbarItems(PluginRegistry registry) {
    const List<Map<String, dynamic>> items = <Map<String, dynamic>>[
      <String, dynamic>{'id': 'formatting/toggle_bold', 'icon': Icons.format_bold, 'label': 'Bold', 'group': 'marks', 'order': 10},
      <String, dynamic>{'id': 'formatting/toggle_italic', 'icon': Icons.format_italic, 'label': 'Italic', 'group': 'marks', 'order': 20},
      <String, dynamic>{'id': 'formatting/toggle_underline', 'icon': Icons.format_underline, 'label': 'Underline', 'group': 'marks', 'order': 30},
      <String, dynamic>{'id': 'formatting/toggle_strikethrough', 'icon': Icons.format_strikethrough, 'label': 'Strikethrough', 'group': 'marks', 'order': 40},
      <String, dynamic>{'id': 'formatting/toggle_code', 'icon': Icons.code, 'label': 'Inline code', 'group': 'marks', 'order': 50},
      <String, dynamic>{'id': 'formatting/remove_format', 'icon': Icons.format_clear, 'label': 'Clear formatting', 'group': 'marks', 'order': 200},
      <String, dynamic>{'id': 'formatting/set_alignment', 'icon': Icons.format_align_left, 'label': 'Alignment', 'group': 'paragraph', 'order': 100},
      <String, dynamic>{'id': 'formatting/set_indent', 'icon': Icons.format_indent_increase, 'label': 'Indent', 'group': 'paragraph', 'order': 110},
      <String, dynamic>{'id': 'formatting/set_color', 'icon': Icons.format_color_text, 'label': 'Color', 'group': 'paragraph', 'order': 120},
      <String, dynamic>{'id': 'formatting/set_font', 'icon': Icons.font_download, 'label': 'Font', 'group': 'paragraph', 'order': 130},
    ];

    for (final Map<String, dynamic> item in items) {
      registry.registerToolbarItem(ToolbarItem(
        commandId: item['id'] as String,
        label: item['label'] as String,
        icon: item['icon'] as IconData?,
        group: item['group'] as String,
        order: item['order'] as int,
      ));
    }
  }
}

const List<String> _marks = <String>[
  'bold',
  'italic',
  'underline',
  'strikethrough',
  'subscript',
  'superscript',
  'code',
];

/// Toggle a text mark on the selected paragraph.
class ToggleMarkCommand extends EditorCommand {
  final String mark;

  const ToggleMarkCommand({required this.mark});

  @override
  String get id => 'formatting/toggle_$mark';

  @override
  EditorCommandResult execute(EditorCommandContext context) {
    final EditorSelection sel = context.selection;
    final DocumentValue doc = context.document;
    if (!sel.hasSelection || doc.nodes.isEmpty) {
      return const EditorCommandResult.failure(
        errorCode: 'selection.empty',
        errorMessage: 'No selection.',
      );
    }

    final int nodeIndex = _nodeIndex(doc, sel.nodeId!);
    if (nodeIndex < 0) {
      return const EditorCommandResult.failure(
        errorCode: 'node.missing',
        errorMessage: 'Selected node not found.',
      );
    }

    final EditorNode node = doc.nodes[nodeIndex];
    if (node is! ParagraphNode) {
      return const EditorCommandResult.failure(
        errorCode: 'node.invalid',
        errorMessage: 'Marks can only be applied to paragraph nodes.',
      );
    }

    final int start = sel.isCollapsed ? 0 : sel.startOffset;
    final int end = sel.isCollapsed ? node.plainText.length : sel.endOffset;
    final ParagraphNode updated = node.toggleMark(mark, start: start, end: end);

    final List<EditorNode> newNodes = List<EditorNode>.of(doc.nodes);
    newNodes[nodeIndex] = updated;

    return EditorCommandResult.success(
      document: DocumentValue(nodes: newNodes, version: doc.version + 1),
      selection: sel,
    );
  }

  @override
  EditorCommandResult undo(
    EditorCommandContext context,
    DocumentValue previousDocument,
  ) =>
      EditorCommandResult.success(document: previousDocument);

  static int _nodeIndex(DocumentValue doc, String nodeId) {
    for (int i = 0; i < doc.nodes.length; i++) {
      if (doc.nodes[i].id == nodeId) return i;
    }
    return -1;
  }
}

/// Remove all formatting marks from the selected range.
class RemoveFormattingCommand extends EditorCommand {
  const RemoveFormattingCommand();

  @override
  String get id => 'formatting/remove_format';

  @override
  EditorCommandResult execute(EditorCommandContext context) {
    final EditorSelection sel = context.selection;
    final DocumentValue doc = context.document;
    if (!sel.hasSelection || doc.nodes.isEmpty) {
      return const EditorCommandResult.failure(
        errorCode: 'selection.empty',
        errorMessage: 'No selection.',
      );
    }

    final int nodeIndex = ToggleMarkCommand._nodeIndex(doc, sel.nodeId!);
    if (nodeIndex < 0) {
      return const EditorCommandResult.failure(
        errorCode: 'node.missing',
        errorMessage: 'Selected node not found.',
      );
    }

    final EditorNode node = doc.nodes[nodeIndex];
    if (node is! ParagraphNode) {
      return const EditorCommandResult.success(document: doc);
    }

    final int start = sel.isCollapsed ? 0 : sel.startOffset;
    final int end = sel.isCollapsed ? node.plainText.length : sel.endOffset;

    ParagraphNode updated = node;
    for (final String mark in _marks) {
      updated = updated.toggleMark(mark, start: start, end: end);
      updated = updated.toggleMark(mark, start: start, end: end);
    }

    final List<EditorNode> newNodes = List<EditorNode>.of(doc.nodes);
    newNodes[nodeIndex] = updated;

    return EditorCommandResult.success(
      document: DocumentValue(nodes: newNodes, version: doc.version + 1),
      selection: sel,
    );
  }

  @override
  EditorCommandResult undo(
    EditorCommandContext context,
    DocumentValue previousDocument,
  ) =>
      EditorCommandResult.success(document: previousDocument);
}

/// Set paragraph alignment.
class SetAlignmentCommand extends EditorCommand {
  final String alignment;

  const SetAlignmentCommand({required this.alignment});

  @override
  String get id => 'formatting/set_alignment';

  @override
  EditorCommandResult execute(EditorCommandContext context) {
    return _applyToSelectedParagraph(
      context,
      (ParagraphNode node) => node.setAttribute('align', alignment),
    );
  }

  @override
  EditorCommandResult undo(
    EditorCommandContext context,
    DocumentValue previousDocument,
  ) =>
      EditorCommandResult.success(document: previousDocument);
}

/// Adjust paragraph indentation.
class SetIndentCommand extends EditorCommand {
  final int delta;

  const SetIndentCommand({required this.delta});

  @override
  String get id => 'formatting/set_indent';

  @override
  EditorCommandResult execute(EditorCommandContext context) {
    return _applyToSelectedParagraph(
      context,
      (ParagraphNode node) {
        final int current = (node.attributes['indent'] as int?) ?? 0;
        final int next = (current + delta).clamp(0, 8);
        return node.setAttribute('indent', next);
      },
    );
  }

  @override
  EditorCommandResult undo(
    EditorCommandContext context,
    DocumentValue previousDocument,
  ) =>
      EditorCommandResult.success(document: previousDocument);
}

/// Set text color or background/highlight color.
class SetColorCommand extends EditorCommand {
  final String? color;
  final bool background;

  const SetColorCommand({this.color, this.background = false});

  @override
  String get id => 'formatting/set_color';

  @override
  EditorCommandResult execute(EditorCommandContext context) {
    if (color == null) {
      return _applyToSelectedParagraph(
        context,
        (ParagraphNode node) => node.setAttribute(
            background ? 'background' : 'color', null),
      );
    }
    final String? validated = _validateColor(color!);
    if (validated == null) {
      return const EditorCommandResult.failure(
        errorCode: 'format.invalidColor',
        errorMessage: 'Invalid color value.',
      );
    }
    return _applyToSelectedParagraph(
      context,
      (ParagraphNode node) =>
          node.setAttribute(background ? 'background' : 'color', validated),
    );
  }

  @override
  EditorCommandResult undo(
    EditorCommandContext context,
    DocumentValue previousDocument,
  ) =>
      EditorCommandResult.success(document: previousDocument);

  static String? _validateColor(String value) {
    final String v = value.trim();
    if (v.isEmpty) return null;
    if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(v)) return v;
    if (RegExp(r'^#[0-9A-Fa-f]{8}$').hasMatch(v)) return v;
    if (RegExp(r'^rgb\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*\)$').hasMatch(v)) {
      return v;
    }
    return null;
  }
}

/// Set font family and/or size.
class SetFontCommand extends EditorCommand {
  final String? family;
  final double? size;

  const SetFontCommand({this.family, this.size});

  @override
  String get id => 'formatting/set_font';

  @override
  EditorCommandResult execute(EditorCommandContext context) {
    return _applyToSelectedParagraph(
      context,
      (ParagraphNode node) {
        ParagraphNode updated = node;
        if (family != null) {
          updated = updated.setAttribute('fontFamily', family);
        }
        if (size != null) {
          updated = updated.setAttribute('fontSize', size);
        }
        return updated;
      },
    );
  }

  @override
  EditorCommandResult undo(
    EditorCommandContext context,
    DocumentValue previousDocument,
  ) =>
      EditorCommandResult.success(document: previousDocument);
}

/// Set paragraph line height.
class SetLineHeightCommand extends EditorCommand {
  final double lineHeight;

  const SetLineHeightCommand({required this.lineHeight});

  @override
  String get id => 'formatting/set_line_height';

  @override
  EditorCommandResult execute(EditorCommandContext context) {
    return _applyToSelectedParagraph(
      context,
      (ParagraphNode node) => node.setAttribute('lineHeight', lineHeight),
    );
  }

  @override
  EditorCommandResult undo(
    EditorCommandContext context,
    DocumentValue previousDocument,
  ) =>
      EditorCommandResult.success(document: previousDocument);
}

EditorCommandResult _applyToSelectedParagraph(
  EditorCommandContext context,
  ParagraphNode Function(ParagraphNode) transform,
) {
  final EditorSelection sel = context.selection;
  final DocumentValue doc = context.document;
  if (!sel.hasSelection || doc.nodes.isEmpty) {
    return const EditorCommandResult.failure(
      errorCode: 'selection.empty',
      errorMessage: 'No selection.',
    );
  }

  final int nodeIndex = ToggleMarkCommand._nodeIndex(doc, sel.nodeId!);
  if (nodeIndex < 0) {
    return const EditorCommandResult.failure(
      errorCode: 'node.missing',
      errorMessage: 'Selected node not found.',
    );
  }

  final EditorNode node = doc.nodes[nodeIndex];
  if (node is! ParagraphNode) {
    return const EditorCommandResult.failure(
      errorCode: 'node.invalid',
      errorMessage: 'Operation requires a paragraph node.',
    );
  }

  final List<EditorNode> newNodes = List<EditorNode>.of(doc.nodes);
  newNodes[nodeIndex] = transform(node);

  return EditorCommandResult.success(
    document: DocumentValue(nodes: newNodes, version: doc.version + 1),
    selection: sel,
  );
}

/// Widget renderer for paragraph nodes.
class _ParagraphRenderer extends StatelessWidget {
  final ParagraphNode node;
  final NodeRenderContext context;

  const _ParagraphRenderer({required this.node, required this.context});

  @override
  Widget build(BuildContext context) {
    final EditorTheme theme = this.context.theme as EditorTheme;
    final TextAlign align = _parseAlign(node.attributes['align'] as String?);
    final double? lineHeight = node.attributes['lineHeight'] as double?;
    final int indent = (node.attributes['indent'] as int?) ?? 0;

    return Padding(
      padding: EdgeInsets.only(
        left: theme.spacingUnit * 2 * indent,
        bottom: theme.paragraphSpacing,
      ),
      child: Text.rich(
        TextSpan(
          children: node.spans.map((TextSpanNode span) {
            return TextSpan(
              text: span.text,
              style: _spanStyle(span, theme),
            );
          }).toList(),
        ),
        textAlign: align,
        textDirection: this.context.direction,
      ),
    );
  }

  TextStyle _spanStyle(TextSpanNode span, EditorThemeData theme) {
    TextStyle style = theme.paragraphStyle;
    final String? color = node.attributes['color'] as String?;
    final String? background = node.attributes['background'] as String?;
    final String? family = node.attributes['fontFamily'] as String?;
    final double? size = node.attributes['fontSize'] as double?;

    if (color != null) {
      style = style.copyWith(color: _parseColor(color));
    }
    if (background != null) {
      style = style.copyWith(backgroundColor: _parseColor(background));
    }
    if (family != null) {
      style = style.copyWith(fontFamily: family);
    }
    if (size != null) {
      style = style.copyWith(fontSize: size);
    }

    for (final String mark in span.marks) {
      switch (mark) {
        case 'bold':
          style = style.copyWith(fontWeight: FontWeight.bold);
        case 'italic':
          style = style.copyWith(fontStyle: FontStyle.italic);
        case 'underline':
          style = style.copyWith(decoration: TextDecoration.underline);
        case 'strikethrough':
          style = style.copyWith(
            decoration: TextDecoration.lineThrough,
            decorationThickness: 1.5,
          );
        case 'subscript':
          style = style.copyWith(
            fontSize: (style.fontSize ?? 16) * 0.75,
            baselineShift: -2,
          );
        case 'superscript':
          style = style.copyWith(
            fontSize: (style.fontSize ?? 16) * 0.75,
            baselineShift: 4,
          );
        case 'code':
          style = style.copyWith(
            fontFamily: 'monospace',
            backgroundColor: theme.foregroundColor.withOpacity(0.1),
          );
      }
    }

    if (lineHeight != null) {
      style = style.copyWith(height: lineHeight);
    }

    return style;
  }

  static TextAlign _parseAlign(String? value) {
    switch (value) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      case 'justify':
        return TextAlign.justify;
      case 'left':
      default:
        return TextAlign.left;
    }
  }

  static Color? _parseColor(String value) {
    try {
      return Color(int.parse(value.replaceFirst('#', '0xFF')));
    } on Object {
      return null;
    }
  }
}
