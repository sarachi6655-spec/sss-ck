import '../../core/command_bus/editor_command.dart';
import '../../core/document_model/document_value.dart';
import '../../core/document_model/editor_node.dart';
import '../../core/document_model/editor_selection.dart';
import '../../core/plugin_system/plugin.dart';

/// Command to apply or toggle an inline formatting mark.
class FormatMarkCommand extends EditorCommand {
  const FormatMarkCommand({
    required this.mark,
    this.value = true,
  });

  final String mark;
  final dynamic value;

  @override
  String get id => 'format.$mark';

  @override
  CommandResult execute(DocumentValue document) {
    final EditorSelection sel = document.selection;

    // Handle collapsed selection: store as pending mark in document metadata
    if (sel.isCollapsed) {
      final Map<String, dynamic> currentPending = document.metadata['pendingMarks'] != null
          ? Map<String, dynamic>.from(document.metadata['pendingMarks'] as Map)
          : <String, dynamic>{};

      // Toggle or set pending mark
      if (currentPending[mark] == value || (value == true && currentPending[mark] == true)) {
        currentPending.remove(mark);
      } else {
        currentPending[mark] = value;
      }

      // Also reflect on current node if it's empty
      final int targetIndex = sel.nodeIndex;
      final List<EditorNode> updatedNodes = List<EditorNode>.from(document.nodes);
      if (targetIndex >= 0 && targetIndex < updatedNodes.length) {
        final EditorNode node = updatedNodes[targetIndex];
        final Map<String, dynamic> newAttrs = Map<String, dynamic>.from(node.attributes);
        if (currentPending.containsKey(mark)) {
          newAttrs[mark] = value;
        } else {
          newAttrs.remove(mark);
        }
        updatedNodes[targetIndex] = node.copyWith(attributes: newAttrs);
      }

      final Map<String, dynamic> newMeta = Map<String, dynamic>.from(document.metadata);
      newMeta['pendingMarks'] = currentPending;

      return CommandResult.ok(document.copyWith(
        nodes: updatedNodes,
        metadata: newMeta,
      ));
    }

    // Handle expanded selection: apply or remove mark across selected range
    final int startNode = sel.startNodeIndex;
    final int endNode = sel.endNodeIndexNormalized;
    final List<EditorNode> updatedNodes = List<EditorNode>.from(document.nodes);

    // If selection is within a single node and partial sub-string
    if (startNode == endNode && startNode >= 0 && startNode < updatedNodes.length) {
      final EditorNode node = updatedNodes[startNode];
      final String text = node.text;
      final int start = sel.start.clamp(0, text.length);
      final int end = sel.end.clamp(0, text.length);

      // If whole node already had mark, remove it
      if (node.attributes[mark] == value) {
        final Map<String, dynamic> newAttrs = Map<String, dynamic>.from(node.attributes);
        newAttrs.remove(mark);
        updatedNodes[startNode] = node.copyWith(attributes: newAttrs);
        return CommandResult.ok(document.copyWith(nodes: updatedNodes));
      }

      // If partial selection within node, wrap with inline token
      if (start < end && (start > 0 || end < text.length)) {
        String token = '';
        if (mark == 'bold') {
          token = '**';
        } else if (mark == 'italic') {
          token = '*';
        } else if (mark == 'strikethrough') {
          token = '~~';
        } else if (mark == 'code') {
          token = '`';
        }

        if (token.isNotEmpty) {
          final String selectedText = text.substring(start, end);
          String newText;
          int newExtent = end;

          if (selectedText.startsWith(token) &&
              selectedText.endsWith(token) &&
              selectedText.length >= token.length * 2) {
            // Unwrap
            final String unwrapped = selectedText.substring(token.length, selectedText.length - token.length);
            newText = text.replaceRange(start, end, unwrapped);
            newExtent = start + unwrapped.length;
          } else {
            // Wrap
            final String wrapped = '$token$selectedText$token';
            newText = text.replaceRange(start, end, wrapped);
            newExtent = start + wrapped.length;
          }

          updatedNodes[startNode] = node.copyWith(text: newText);
          return CommandResult.ok(document.copyWith(
            nodes: updatedNodes,
            selection: EditorSelection(
              baseOffset: start,
              extentOffset: newExtent,
              nodeIndex: startNode,
            ),
          ));
        }
      }
    }

    // Determine if all nodes in selection already have this mark (to toggle off)
    bool allHaveMark = true;
    for (int i = startNode; i <= endNode && i < updatedNodes.length; i++) {
      if (updatedNodes[i].attributes[mark] != value) {
        allHaveMark = false;
        break;
      }
    }

    for (int i = startNode; i <= endNode && i < updatedNodes.length; i++) {
      final EditorNode node = updatedNodes[i];
      final Map<String, dynamic> newAttrs = Map<String, dynamic>.from(node.attributes);

      if (allHaveMark) {
        newAttrs.remove(mark);
      } else {
        newAttrs[mark] = value;
      }

      updatedNodes[i] = node.copyWith(attributes: newAttrs);
    }

    return CommandResult.ok(document.copyWith(nodes: updatedNodes));
  }
}

/// Command to clear all formatting marks from the selected range.
class ClearFormattingCommand extends EditorCommand {
  const ClearFormattingCommand();

  @override
  String get id => 'format.clear';

  @override
  CommandResult execute(DocumentValue document) {
    final EditorSelection sel = document.selection;
    final int startNode = sel.startNodeIndex;
    final int endNode = sel.endNodeIndexNormalized;
    final List<EditorNode> updatedNodes = List<EditorNode>.from(document.nodes);

    for (int i = startNode; i <= endNode && i < updatedNodes.length; i++) {
      updatedNodes[i] = updatedNodes[i].copyWith(attributes: const <String, dynamic>{});
    }

    final Map<String, dynamic> newMeta = Map<String, dynamic>.from(document.metadata);
    newMeta.remove('pendingMarks');

    return CommandResult.ok(document.copyWith(
      nodes: updatedNodes,
      metadata: newMeta,
    ));
  }
}

/// Plugin providing rich text formatting commands (bold, italic, underline, colors, etc.).
class FormattingPlugin extends EditorPlugin {
  const FormattingPlugin();

  @override
  String get id => 'formatting';

  @override
  String get name => 'Text Formatting';

  @override
  List<EditorCommand> get commands => const <EditorCommand>[
        FormatMarkCommand(mark: 'bold'),
        FormatMarkCommand(mark: 'italic'),
        FormatMarkCommand(mark: 'underline'),
        FormatMarkCommand(mark: 'strikethrough'),
        FormatMarkCommand(mark: 'code'),
        FormatMarkCommand(mark: 'subscript'),
        FormatMarkCommand(mark: 'superscript'),
        ClearFormattingCommand(),
      ];
}
