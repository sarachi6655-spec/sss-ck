import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/controller/rich_editor_controller.dart';
import '../core/document_model/document_value.dart';
import '../core/document_model/editor_node.dart';
import '../core/document_model/editor_selection.dart';
import '../features/formatting/formatting_plugin.dart';
import '../features/structure/structure_plugin.dart';
import '../theme/editor_theme.dart';
import '../toolbar/editor_toolbar.dart';
import '../toolbar/toolbar_config.dart';
import 'editor_config.dart';
import 'rich_text_editing_controller.dart';
import 'watchdog_boundary.dart';

/// Native Flutter implementation of the rich text editor widget.
class RichEditorNative extends StatefulWidget {
  const RichEditorNative({
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
  State<RichEditorNative> createState() => _RichEditorNativeState();
}

class _RichEditorNativeState extends State<RichEditorNative> {
  final Map<String, RichTextEditingController> _nodeControllers = <String, RichTextEditingController>{};
  final Map<String, FocusNode> _focusNodes = <String, FocusNode>{};

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    _syncNodeControllers();
  }

  @override
  void didUpdateWidget(covariant RichEditorNative oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _disposeNodeControllers();
      _syncNodeControllers();
    }
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    _syncNodeControllers();
    setState(() {});
    widget.onChanged?.call(widget.controller.document);
  }

  int _getNodeIndex(String nodeId) {
    return widget.controller.document.nodes.indexWhere((EditorNode n) => n.id == nodeId);
  }

  void _syncNodeControllers() {
    final Set<String> activeIds = <String>{};
    for (int i = 0; i < widget.controller.document.nodes.length; i++) {
      final EditorNode node = widget.controller.document.nodes[i];
      activeIds.add(node.id);

      // Handle table children cells as well
      if (node.type == 'table') {
        for (final EditorNode row in node.children) {
          for (final EditorNode cell in row.children) {
            activeIds.add(cell.id);
            _ensureControllerForNode(cell, cell.type);
          }
        }
      }

      _ensureControllerForNode(node, node.type);
    }

    // Clean up removed nodes
    _nodeControllers.removeWhere((String id, RichTextEditingController ctrl) {
      if (!activeIds.contains(id)) {
        ctrl.dispose();
        _focusNodes[id]?.dispose();
        _focusNodes.remove(id);
        return true;
      }
      return false;
    });
  }

  void _ensureControllerForNode(EditorNode node, String type) {
    if (!_nodeControllers.containsKey(node.id)) {
      final RichTextEditingController ctrl = RichTextEditingController(
        text: node.text,
        nodeAttributes: node.attributes,
        nodeType: type,
      );
      final FocusNode fn = FocusNode();

      // Listen for selection and cursor changes
      ctrl.addListener(() {
        if (fn.hasFocus) {
          _onFieldSelectionChanged(node.id);
        }
      });

      // Listen for focus changes
      fn.addListener(() {
        if (fn.hasFocus) {
          _onFieldSelectionChanged(node.id);
        }
      });

      _nodeControllers[node.id] = ctrl;
      _focusNodes[node.id] = fn;
    } else {
      final RichTextEditingController ctrl = _nodeControllers[node.id]!;
      ctrl.nodeAttributes = node.attributes;
      ctrl.nodeType = type;

      final FocusNode? fn = _focusNodes[node.id];
      final bool isFocused = fn?.hasFocus ?? false;

      // Only update text from external document if this field is not actively focused/edited
      if (!isFocused && ctrl.text != node.text) {
        final TextSelection oldSel = ctrl.selection;
        ctrl.text = node.text;
        if (oldSel.isValid) {
          ctrl.selection = TextSelection(
            baseOffset: oldSel.baseOffset.clamp(0, node.text.length),
            extentOffset: oldSel.extentOffset.clamp(0, node.text.length),
          );
        }
      }
    }
  }

  void _onFieldSelectionChanged(String nodeId) {
    final FocusNode? fn = _focusNodes[nodeId];
    final RichTextEditingController? ctrl = _nodeControllers[nodeId];
    if (fn != null && fn.hasFocus && ctrl != null) {
      final int nodeIndex = _getNodeIndex(nodeId);
      if (nodeIndex >= 0) {
        widget.controller.setSelection(EditorSelection(
          baseOffset: ctrl.selection.baseOffset,
          extentOffset: ctrl.selection.extentOffset,
          nodeIndex: nodeIndex,
        ));
      }
    }
  }

  void _disposeNodeControllers() {
    for (final RichTextEditingController ctrl in _nodeControllers.values) {
      ctrl.dispose();
    }
    for (final FocusNode fn in _focusNodes.values) {
      fn.dispose();
    }
    _nodeControllers.clear();
    _focusNodes.clear();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _disposeNodeControllers();
    super.dispose();
  }

  void _updateNodeText(int index, String newText) {
    final List<EditorNode> nodes = List<EditorNode>.from(widget.controller.document.nodes);
    if (index >= 0 && index < nodes.length) {
      String resolvedText = newText;
      // Auto-resolve table cell references like $A1 when followed by space or punctuation
      if (newText.contains(r'$') && (newText.endsWith(' ') || newText.endsWith('\n') || newText.endsWith('.') || newText.endsWith(','))) {
        resolvedText = widget.controller.resolveCellReferences(newText);
        if (resolvedText != newText) {
          final RichTextEditingController? ctrl = _nodeControllers[nodes[index].id];
          if (ctrl != null) {
            final int diff = resolvedText.length - newText.length;
            final TextSelection currentSel = ctrl.selection;
            ctrl.text = resolvedText;
            ctrl.selection = TextSelection.collapsed(offset: (currentSel.baseOffset + diff).clamp(0, resolvedText.length));
          }
        }
      }

      nodes[index] = nodes[index].copyWith(text: resolvedText);
      final int offset = _nodeControllers[nodes[index].id]?.selection.baseOffset ?? resolvedText.length;
      widget.controller.updateDocumentDirect(
        widget.controller.document.copyWith(
          nodes: nodes,
          selection: EditorSelection.collapsed(offset, nodeIndex: index),
        ),
        notify: false,
      );
      widget.onChanged?.call(widget.controller.document);
    }
  }

  void _updateTableCell(EditorNode tableNode, int rowIdx, int cellIdx, String newText) {
    final int tableIndex = _getNodeIndex(tableNode.id);
    if (tableIndex < 0) return;

    final List<EditorNode> updatedRows = List<EditorNode>.from(tableNode.children);
    if (rowIdx < 0 || rowIdx >= updatedRows.length) return;

    final EditorNode targetRow = updatedRows[rowIdx];
    final List<EditorNode> updatedCells = List<EditorNode>.from(targetRow.children);
    if (cellIdx < 0 || cellIdx >= updatedCells.length) return;

    updatedCells[cellIdx] = updatedCells[cellIdx].copyWith(text: newText);
    updatedRows[rowIdx] = targetRow.copyWith(children: updatedCells);

    final List<EditorNode> docNodes = List<EditorNode>.from(widget.controller.document.nodes);
    docNodes[tableIndex] = tableNode.copyWith(children: updatedRows);

    final String cellCoord = RichEditorController.formatCellCoord(cellIdx, rowIdx);

    // Sync any text nodes that reference this table cell via <span class="table-cell-ref" data-cell-coord="..."> or $Coord
    for (int i = 0; i < docNodes.length; i++) {
      if (i == tableIndex) continue;
      final EditorNode n = docNodes[i];
      if (n.text.contains(cellCoord)) {
        final String updatedHtml = n.text.replaceAllMapped(
          RegExp('<span[^>]*data-cell-coord="$cellCoord"[^>]*>.*?</span>', caseSensitive: false),
          (Match m) => '<span class="mention table-cell-ref" data-mention="\$$cellCoord" data-cell-coord="$cellCoord" title="Table cell $cellCoord: $newText (Live Link)">$newText</span>',
        );
        if (updatedHtml != n.text) {
          docNodes[i] = n.copyWith(text: updatedHtml);
          final RichTextEditingController? c = _nodeControllers[n.id];
          if (c != null && c.text != updatedHtml) {
            c.text = updatedHtml;
          }
        }
      }
    }

    widget.controller.updateDocumentDirect(
      widget.controller.document.copyWith(nodes: docNodes),
      notify: false,
    );
    widget.onChanged?.call(widget.controller.document);
  }

  KeyEventResult _handleKeyEvent(int index, EditorNode node, FocusNode fn, KeyEvent event) {
    if (event is KeyDownEvent) {
      // Enter key -> split block or add next item
      if (event.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
        if (node.type == 'code_block') {
          // Allow multiline code block editing
          return KeyEventResult.ignored;
        }

        final RichTextEditingController? ctrl = _nodeControllers[node.id];
        final int cursorOffset = ctrl?.selection.baseOffset ?? node.text.length;

        widget.controller.execute(SplitBlockCommand(
          nodeIndex: index,
          splitOffset: cursorOffset,
        ));

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (index + 1 < widget.controller.document.nodes.length) {
            final String nextId = widget.controller.document.nodes[index + 1].id;
            _focusNodes[nextId]?.requestFocus();
            _nodeControllers[nextId]?.selection = const TextSelection.collapsed(offset: 0);
          }
        });
        return KeyEventResult.handled;
      }

      // Backspace at offset 0 -> merge backward or unwrap block
      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        final RichTextEditingController? ctrl = _nodeControllers[node.id];
        if (ctrl != null && ctrl.selection.isCollapsed && ctrl.selection.baseOffset == 0) {
          widget.controller.execute(MergeBlockBackwardCommand(nodeIndex: index));

          WidgetsBinding.instance.addPostFrameCallback((_) {
            final int targetIdx = (index - 1).clamp(0, widget.controller.document.nodes.length - 1);
            if (widget.controller.document.nodes.isNotEmpty) {
              final String targetId = widget.controller.document.nodes[targetIdx].id;
              _focusNodes[targetId]?.requestFocus();
            }
          });
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  void _handleCanvasTap() {
    if (widget.config.readOnly) return;

    if (widget.controller.document.isEmpty) {
      final EditorNode emptyNode = EditorNode.paragraph(
        id: 'node_${DateTime.now().microsecondsSinceEpoch}',
        text: '',
      );
      widget.controller.import(DocumentValue(nodes: <EditorNode>[emptyNode]));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.controller.document.nodes.isNotEmpty) {
        final int lastIndex = widget.controller.document.nodes.length - 1;
        final EditorNode lastNode = widget.controller.document.nodes[lastIndex];
        _focusNodes[lastNode.id]?.requestFocus();
        if (_nodeControllers.containsKey(lastNode.id)) {
          final RichTextEditingController ctrl = _nodeControllers[lastNode.id]!;
          ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
        }
      }
    });
  }

  void _toggleMark(String mark) {
    widget.controller.execute(FormatMarkCommand(mark: mark));
  }

  @override
  Widget build(BuildContext context) {
    final EditorTheme theme = widget.theme;
    final EditorConfig config = widget.config;

    final Widget canvasContent = widget.controller.document.isEmpty && config.placeholder.isNotEmpty && !config.readOnly
        ? Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  config.placeholder,
                  style: theme.bodyStyle.copyWith(color: theme.placeholderColor),
                ),
              ),
              _buildNodeList(theme, config),
            ],
          )
        : _buildNodeList(theme, config);

    Widget canvas = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _handleCanvasTap,
      child: Container(
        decoration: BoxDecoration(
          color: config.readOnly ? theme.readOnlyBackgroundColor : theme.backgroundColor,
          border: Border.all(color: theme.borderColor),
          borderRadius: BorderRadius.circular(theme.borderRadius),
        ),
        padding: theme.contentPadding,
        child: canvasContent,
      ),
    );

    if (config.enableWatchdog) {
      canvas = WatchdogBoundary(
        controller: widget.controller,
        child: canvas,
      );
    }

    // Keyboard shortcuts: Cmd/Ctrl + B, I, U, Z, Y
    if (!config.readOnly) {
      canvas = CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _toggleMark('bold'),
          const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () => _toggleMark('bold'),
          const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _toggleMark('italic'),
          const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () => _toggleMark('italic'),
          const SingleActivator(LogicalKeyboardKey.keyU, control: true): () => _toggleMark('underline'),
          const SingleActivator(LogicalKeyboardKey.keyU, meta: true): () => _toggleMark('underline'),
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () => widget.controller.undo(),
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () => widget.controller.undo(),
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): () => widget.controller.redo(),
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): () => widget.controller.redo(),
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): () => widget.controller.redo(),
        },
        child: canvas,
      );
    }

    final List<Widget> children = <Widget>[];

    if (config.showToolbar && config.toolbarPosition == ToolbarPosition.top && !config.readOnly) {
      children.add(EditorToolbar(
        controller: widget.controller,
        theme: theme,
        config: widget.toolbarConfig,
      ));
      children.add(const SizedBox(height: 8.0));
    }

    children.add(Expanded(child: canvas));

    if (config.showToolbar && config.toolbarPosition == ToolbarPosition.bottom && !config.readOnly) {
      children.add(const SizedBox(height: 8.0));
      children.add(EditorToolbar(
        controller: widget.controller,
        theme: theme,
        config: widget.toolbarConfig,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildNodeList(EditorTheme theme, EditorConfig config) {
    final List<EditorNode> nodes = widget.controller.document.nodes;

    return ListView.builder(
      itemCount: nodes.length,
      itemBuilder: (BuildContext context, int index) {
        final EditorNode node = nodes[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: _buildNodeWidget(node, index, theme, config),
        );
      },
    );
  }

  Widget _buildNodeWidget(
    EditorNode node,
    int index,
    EditorTheme theme,
    EditorConfig config,
  ) {
    switch (node.type) {
      case 'heading':
        return _buildHeading(node, index, theme, config);
      case 'blockquote':
        return _buildBlockquote(node, index, theme, config);
      case 'code_block':
        return _buildCodeBlock(node, index, theme, config);
      case 'hr':
        return Divider(color: theme.hrColor, thickness: theme.hrHeight);
      case 'list':
        return _buildListItem(node, index, theme, config);
      case 'image':
        return _buildImage(node, theme);
      case 'video':
        return _buildVideo(node, theme);
      case 'table':
        return _buildTable(node, theme, config);
      case 'paragraph':
      default:
        return _buildParagraph(node, index, theme, config);
    }
  }

  Widget _buildHeading(
    EditorNode node,
    int index,
    EditorTheme theme,
    EditorConfig config,
  ) {
    final int level = (node.metadata['level'] as num?)?.toInt() ?? 1;
    TextStyle style;
    switch (level) {
      case 1:
        style = theme.heading1Style;
        break;
      case 2:
        style = theme.heading2Style;
        break;
      case 3:
        style = theme.heading3Style;
        break;
      case 4:
        style = theme.heading4Style;
        break;
      case 5:
        style = theme.heading5Style;
        break;
      case 6:
      default:
        style = theme.heading6Style;
        break;
    }

    if (config.readOnly) {
      return Text(node.text, style: RichTextEditingController.applyAttributes(style, node.attributes));
    }

    final FocusNode fn = _focusNodes[node.id]!;
    return Focus(
      onKeyEvent: (FocusNode f, KeyEvent event) => _handleKeyEvent(index, node, f, event),
      child: TextField(
        controller: _nodeControllers[node.id],
        focusNode: fn,
        style: style,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        cursorColor: theme.cursorColor,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onTap: () => _onFieldSelectionChanged(node.id),
        onChanged: (String val) => _updateNodeText(index, val),
      ),
    );
  }

  Widget _buildParagraph(
    EditorNode node,
    int index,
    EditorTheme theme,
    EditorConfig config,
  ) {
    final TextStyle baseStyle = theme.bodyStyle;

    if (config.readOnly) {
      return Text(node.text, style: RichTextEditingController.applyAttributes(baseStyle, node.attributes));
    }

    final FocusNode fn = _focusNodes[node.id]!;
    return Focus(
      onKeyEvent: (FocusNode f, KeyEvent event) => _handleKeyEvent(index, node, f, event),
      child: TextField(
        controller: _nodeControllers[node.id],
        focusNode: fn,
        style: baseStyle,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        cursorColor: theme.cursorColor,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onTap: () => _onFieldSelectionChanged(node.id),
        onChanged: (String val) => _updateNodeText(index, val),
      ),
    );
  }

  Widget _buildBlockquote(
    EditorNode node,
    int index,
    EditorTheme theme,
    EditorConfig config,
  ) {
    if (config.readOnly) {
      return Container(
        padding: theme.blockquotePadding,
        decoration: BoxDecoration(
          color: theme.blockquoteBackgroundColor,
          border: Border(left: BorderSide(color: theme.blockquoteBorderColor, width: 4.0)),
        ),
        child: Text(node.text, style: RichTextEditingController.applyAttributes(theme.blockquoteTextStyle, node.attributes)),
      );
    }

    final FocusNode fn = _focusNodes[node.id]!;
    return Container(
      padding: theme.blockquotePadding,
      decoration: BoxDecoration(
        color: theme.blockquoteBackgroundColor,
        border: Border(left: BorderSide(color: theme.blockquoteBorderColor, width: 4.0)),
      ),
      child: Focus(
        onKeyEvent: (FocusNode f, KeyEvent event) => _handleKeyEvent(index, node, f, event),
        child: TextField(
          controller: _nodeControllers[node.id],
          focusNode: fn,
          style: theme.blockquoteTextStyle,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          cursorColor: theme.cursorColor,
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onTap: () => _onFieldSelectionChanged(node.id),
          onChanged: (String val) => _updateNodeText(index, val),
        ),
      ),
    );
  }

  Widget _buildCodeBlock(
    EditorNode node,
    int index,
    EditorTheme theme,
    EditorConfig config,
  ) {
    if (config.readOnly) {
      return Container(
        padding: theme.codeBlockPadding,
        decoration: BoxDecoration(
          color: theme.codeBlockBackgroundColor,
          border: Border.all(color: theme.codeBlockBorderColor),
          borderRadius: BorderRadius.circular(theme.codeBlockBorderRadius),
        ),
        child: Text(node.text, style: theme.codeBlockTextStyle),
      );
    }

    final FocusNode fn = _focusNodes[node.id]!;
    return Container(
      padding: theme.codeBlockPadding,
      decoration: BoxDecoration(
        color: theme.codeBlockBackgroundColor,
        border: Border.all(color: theme.codeBlockBorderColor),
        borderRadius: BorderRadius.circular(theme.codeBlockBorderRadius),
      ),
      child: Focus(
        onKeyEvent: (FocusNode f, KeyEvent event) => _handleKeyEvent(index, node, f, event),
        child: TextField(
          controller: _nodeControllers[node.id],
          focusNode: fn,
          style: theme.codeBlockTextStyle,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          cursorColor: theme.cursorColor,
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onTap: () => _onFieldSelectionChanged(node.id),
          onChanged: (String val) => _updateNodeText(index, val),
        ),
      ),
    );
  }

  Widget _buildListItem(
    EditorNode node,
    int index,
    EditorTheme theme,
    EditorConfig config,
  ) {
    final String listType = node.metadata['listType'] as String? ?? 'bullet';
    final int indent = (node.metadata['indent'] as num?)?.toInt() ?? 0;
    final double indentPadding = indent * 20.0;

    Widget leading;
    if (listType == 'todo') {
      final bool checked = node.metadata['checked'] == true;
      leading = Checkbox(
        value: checked,
        onChanged: config.readOnly
            ? null
            : (bool? val) {
                final List<EditorNode> nodes = List<EditorNode>.from(widget.controller.document.nodes);
                final Map<String, dynamic> meta = Map<String, dynamic>.from(node.metadata);
                meta['checked'] = val ?? false;
                nodes[index] = node.copyWith(metadata: meta);
                widget.controller.import(widget.controller.document.copyWith(nodes: nodes));
              },
      );
    } else if (listType == 'numbered') {
      leading = Text('${index + 1}. ', style: theme.bodyStyle.copyWith(fontWeight: FontWeight.bold));
    } else {
      leading = const Text('• ', style: TextStyle(fontSize: 18.0));
    }

    Widget contentWidget;
    if (config.readOnly) {
      contentWidget = Text(node.text, style: RichTextEditingController.applyAttributes(theme.bodyStyle, node.attributes));
    } else {
      final FocusNode fn = _focusNodes[node.id]!;
      contentWidget = Focus(
        onKeyEvent: (FocusNode f, KeyEvent event) => _handleKeyEvent(index, node, f, event),
        child: TextField(
          controller: _nodeControllers[node.id],
          focusNode: fn,
          style: theme.bodyStyle,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          cursorColor: theme.cursorColor,
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onTap: () => _onFieldSelectionChanged(node.id),
          onChanged: (String val) => _updateNodeText(index, val),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(left: indentPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          leading,
          Expanded(child: contentWidget),
        ],
      ),
    );
  }

  Widget _buildImage(EditorNode node, EditorTheme theme) {
    final String url = node.metadata['url'] as String? ?? '';
    final String caption = node.metadata['caption'] as String? ?? '';
    final double? width = (node.metadata['width'] as num?)?.toDouble();

    Widget imageWidget;
    if (url.startsWith('data:image/')) {
      final String base64Content = url.split(',').last;
      imageWidget = Image.memory(base64Decode(base64Content), width: width);
    } else if (url.isNotEmpty) {
      imageWidget = Image.network(
        url,
        width: width,
        errorBuilder: (context, error, stack) => Container(
          height: 120,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    } else {
      imageWidget = const SizedBox();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(theme.imageBorderRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          imageWidget,
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(caption, style: theme.captionStyle),
            ),
        ],
      ),
    );
  }

  Widget _buildVideo(EditorNode node, EditorTheme theme) {
    final String poster = node.metadata['poster'] as String? ?? '';
    final String uploadState = node.metadata['uploadState'] as String? ?? 'ready';
    final double progress = (node.metadata['progress'] as num?)?.toDouble() ?? 1.0;

    return Semantics(
      label: 'Video player',
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: theme.videoControlsBackgroundColor,
          borderRadius: BorderRadius.circular(theme.videoBorderRadius),
          image: poster.isNotEmpty
              ? DecorationImage(image: NetworkImage(poster), fit: BoxFit.cover)
              : null,
        ),
        alignment: Alignment.center,
        child: uploadState == 'uploading'
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CircularProgressIndicator(
                    value: progress,
                    valueColor: AlwaysStoppedAnimation<Color>(theme.uploadProgressColor),
                  ),
                  const SizedBox(height: 8),
                  Text('Uploading ${(progress * 100).toInt()}%', style: const TextStyle(color: Colors.white)),
                ],
              )
            : uploadState == 'buffering'
                ? const CircularProgressIndicator(color: Colors.white)
                : uploadState == 'error'
                    ? Icon(Icons.error_outline, color: theme.uploadErrorColor, size: 48)
                    : const Icon(Icons.play_circle_fill, color: Colors.white, size: 56),
      ),
    );
  }

  Widget _buildTable(EditorNode node, EditorTheme theme, EditorConfig config) {
    final String caption = node.metadata['caption'] as String? ?? '';

    return Semantics(
      label: 'Data table',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Text(caption, style: theme.captionStyle),
            ),
          Table(
            border: TableBorder.all(color: theme.tableBorderColor),
            children: List<TableRow>.generate(node.children.length, (int rowIdx) {
              final EditorNode row = node.children[rowIdx];
              return TableRow(
                children: List<Widget>.generate(row.children.length, (int cellIdx) {
                  final EditorNode cell = row.children[cellIdx];
                  final bool isHeader = cell.metadata['isHeader'] == true;
                  final TextStyle cellStyle = theme.bodyStyle.copyWith(
                    fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                  );

                  Widget cellWidget;
                  if (config.readOnly) {
                    cellWidget = Text(
                      cell.text.isNotEmpty ? cell.text : ' ',
                      style: cellStyle,
                    );
                  } else {
                    cellWidget = TextField(
                      controller: _nodeControllers[cell.id],
                      focusNode: _focusNodes[cell.id],
                      style: cellStyle,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (String val) => _updateTableCell(node, rowIdx, cellIdx, val),
                    );
                  }

                  return Container(
                    color: isHeader ? theme.tableHeaderBackgroundColor : null,
                    padding: theme.tableCellPadding,
                    child: cellWidget,
                  );
                }),
              );
            }),
          ),
        ],
      ),
    );
  }
}
