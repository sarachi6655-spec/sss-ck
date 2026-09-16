import '../../core/command_bus/editor_command.dart';
import '../../core/document_model/document_value.dart';
import '../../core/document_model/editor_node.dart';
import '../../core/document_model/editor_selection.dart';
import '../../core/plugin_system/plugin.dart';

/// Command to change block type of the node under selection.
class SetBlockTypeCommand extends EditorCommand {
  const SetBlockTypeCommand({
    required this.type,
    this.metadata = const <String, dynamic>{},
  });

  final String type;
  final Map<String, dynamic> metadata;

  @override
  String get id => 'structure.setBlockType.$type';

  @override
  CommandResult execute(DocumentValue document) {
    final EditorSelection sel = document.selection;
    final int target = sel.nodeIndex;
    if (target < 0 || target >= document.nodes.length) {
      return CommandResult.ok(document);
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode current = updated[target];

    // Toggle back to paragraph if already active
    if (current.type == type &&
        (type != 'heading' || current.metadata['level'] == metadata['level'])) {
      updated[target] = current.copyWith(
        type: 'paragraph',
        metadata: const <String, dynamic>{},
      );
    } else {
      updated[target] = current.copyWith(
        type: type,
        metadata: metadata,
      );
    }

    return CommandResult.ok(document.copyWith(nodes: updated));
  }
}

/// Command to toggle a list item (bullet, numbered, todo).
class ToggleListCommand extends EditorCommand {
  const ToggleListCommand({
    this.listType = 'bullet',
  });

  final String listType;

  @override
  String get id => 'structure.list.$listType';

  @override
  CommandResult execute(DocumentValue document) {
    final EditorSelection sel = document.selection;
    final int target = sel.nodeIndex;
    if (target < 0 || target >= document.nodes.length) {
      return CommandResult.ok(document);
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode current = updated[target];

    if (current.type == 'list' && current.metadata['listType'] == listType) {
      // Toggle back to paragraph
      updated[target] = current.copyWith(
        type: 'paragraph',
        metadata: <String, dynamic>{},
      );
    } else {
      updated[target] = current.copyWith(
        type: 'list',
        metadata: <String, dynamic>{
          'listType': listType,
          'indent': current.metadata['indent'] ?? 0,
          if (listType == 'todo') 'checked': false,
        },
      );
    }

    return CommandResult.ok(document.copyWith(nodes: updated));
  }
}

/// Command to indent a list item.
class IndentListCommand extends EditorCommand {
  const IndentListCommand();

  @override
  String get id => 'structure.list.indent';

  @override
  CommandResult execute(DocumentValue document) {
    final EditorSelection sel = document.selection;
    final int target = sel.nodeIndex;
    if (target < 0 || target >= document.nodes.length) {
      return CommandResult.ok(document);
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode current = updated[target];

    if (current.type == 'list') {
      final int currentIndent = (current.metadata['indent'] as num?)?.toInt() ?? 0;
      final Map<String, dynamic> newMeta = Map<String, dynamic>.from(current.metadata);
      newMeta['indent'] = currentIndent + 1;
      updated[target] = current.copyWith(metadata: newMeta);
    }

    return CommandResult.ok(document.copyWith(nodes: updated));
  }
}

/// Command to outdent a list item.
class OutdentListCommand extends EditorCommand {
  const OutdentListCommand();

  @override
  String get id => 'structure.list.outdent';

  @override
  CommandResult execute(DocumentValue document) {
    final EditorSelection sel = document.selection;
    final int target = sel.nodeIndex;
    if (target < 0 || target >= document.nodes.length) {
      return CommandResult.ok(document);
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode current = updated[target];

    if (current.type == 'list') {
      final int currentIndent = (current.metadata['indent'] as num?)?.toInt() ?? 0;
      if (currentIndent > 0) {
        final Map<String, dynamic> newMeta = Map<String, dynamic>.from(current.metadata);
        newMeta['indent'] = currentIndent - 1;
        updated[target] = current.copyWith(metadata: newMeta);
      }
    }

    return CommandResult.ok(document.copyWith(nodes: updated));
  }
}

/// Command to insert a horizontal rule.
class InsertHorizontalRuleCommand extends EditorCommand {
  const InsertHorizontalRuleCommand();

  @override
  String get id => 'structure.insertHr';

  @override
  CommandResult execute(DocumentValue document) {
    final EditorSelection sel = document.selection;
    final int target = sel.nodeIndex;
    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);

    final EditorNode hrNode = EditorNode(
      id: 'hr_${DateTime.now().millisecondsSinceEpoch}',
      type: 'hr',
    );

    final int insertPos = (target >= 0 && target < updated.length) ? target + 1 : updated.length;
    updated.insert(insertPos, hrNode);

    return CommandResult.ok(document.copyWith(
      nodes: updated,
      selection: EditorSelection.collapsed(0, nodeIndex: insertPos),
    ));
  }
}

/// Command to split a block at a given character offset (e.g. when Enter is pressed).
class SplitBlockCommand extends EditorCommand {
  const SplitBlockCommand({
    required this.nodeIndex,
    required this.splitOffset,
  });

  final int nodeIndex;
  final int splitOffset;

  @override
  String get id => 'structure.splitBlock';

  @override
  CommandResult execute(DocumentValue document) {
    if (nodeIndex < 0 || nodeIndex >= document.nodes.length) {
      return CommandResult.ok(document);
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode current = updated[nodeIndex];
    final String currentText = current.text;
    final int safeOffset = splitOffset.clamp(0, currentText.length);

    final String firstPart = currentText.substring(0, safeOffset);
    final String secondPart = currentText.substring(safeOffset);

    // If it's a list item and it's empty, convert to regular paragraph
    if (current.type == 'list' && currentText.trim().isEmpty) {
      updated[nodeIndex] = current.copyWith(type: 'paragraph', metadata: const <String, dynamic>{});
      return CommandResult.ok(document.copyWith(
        nodes: updated,
        selection: EditorSelection.collapsed(0, nodeIndex: nodeIndex),
      ));
    }

    // First part stays in current node
    updated[nodeIndex] = current.copyWith(text: firstPart);

    // Second part goes to next node
    final String nextType = current.type == 'list' ? 'list' : 'paragraph';
    final Map<String, dynamic> nextMeta = current.type == 'list'
        ? Map<String, dynamic>.from(current.metadata)
        : const <String, dynamic>{};

    final String newId = 'node_${DateTime.now().microsecondsSinceEpoch}';
    final EditorNode newNode = EditorNode(
      id: newId,
      type: nextType,
      text: secondPart,
      metadata: nextMeta,
    );

    updated.insert(nodeIndex + 1, newNode);

    return CommandResult.ok(document.copyWith(
      nodes: updated,
      selection: EditorSelection.collapsed(0, nodeIndex: nodeIndex + 1),
    ));
  }
}

/// Command to merge a block with the previous block (e.g. when Backspace is pressed at start of line).
class MergeBlockBackwardCommand extends EditorCommand {
  const MergeBlockBackwardCommand({
    required this.nodeIndex,
  });

  final int nodeIndex;

  @override
  String get id => 'structure.mergeBlockBackward';

  @override
  CommandResult execute(DocumentValue document) {
    if (nodeIndex <= 0 || nodeIndex >= document.nodes.length) {
      // If at node 0 and it's not a paragraph, convert to paragraph
      if (nodeIndex == 0 && document.nodes.isNotEmpty) {
        final EditorNode node = document.nodes[0];
        if (node.type != 'paragraph') {
          final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
          updated[0] = node.copyWith(type: 'paragraph', metadata: const <String, dynamic>{});
          return CommandResult.ok(document.copyWith(
            nodes: updated,
            selection: const EditorSelection.collapsed(0, nodeIndex: 0),
          ));
        }
      }
      return CommandResult.ok(document);
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode current = updated[nodeIndex];
    final EditorNode prev = updated[nodeIndex - 1];

    // If current is heading, list, or quote, first unwrap to paragraph
    if (current.type != 'paragraph') {
      updated[nodeIndex] = current.copyWith(type: 'paragraph', metadata: const <String, dynamic>{});
      return CommandResult.ok(document.copyWith(
        nodes: updated,
        selection: EditorSelection.collapsed(0, nodeIndex: nodeIndex),
      ));
    }

    // Merge current into prev
    final int prevLen = prev.text.length;
    final String mergedText = prev.text + current.text;
    updated[nodeIndex - 1] = prev.copyWith(text: mergedText);
    updated.removeAt(nodeIndex);

    return CommandResult.ok(document.copyWith(
      nodes: updated,
      selection: EditorSelection.collapsed(prevLen, nodeIndex: nodeIndex - 1),
    ));
  }
}

/// Command to set text alignment on the selected block.
class SetTextAlignmentCommand extends EditorCommand {
  const SetTextAlignmentCommand({required this.align});

  final String align;

  @override
  String get id => 'structure.align.$align';

  @override
  CommandResult execute(DocumentValue document) {
    final EditorSelection sel = document.selection;
    final int target = sel.nodeIndex;
    if (target < 0 || target >= document.nodes.length) {
      return CommandResult.ok(document);
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode current = updated[target];
    final Map<String, dynamic> newAttrs = Map<String, dynamic>.from(current.attributes);

    if (newAttrs['align'] == align) {
      newAttrs.remove('align');
    } else {
      newAttrs['align'] = align;
    }

    updated[target] = current.copyWith(attributes: newAttrs);
    return CommandResult.ok(document.copyWith(nodes: updated));
  }
}

/// Command to set font family on the selected block.
class SetFontFamilyCommand extends EditorCommand {
  const SetFontFamilyCommand({required this.fontFamily});

  final String fontFamily;

  @override
  String get id => 'structure.fontFamily.$fontFamily';

  @override
  CommandResult execute(DocumentValue document) {
    final EditorSelection sel = document.selection;
    final int target = sel.nodeIndex;
    if (target < 0 || target >= document.nodes.length) {
      return CommandResult.ok(document);
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode current = updated[target];
    final Map<String, dynamic> newAttrs = Map<String, dynamic>.from(current.attributes);

    if (fontFamily.isEmpty || fontFamily == 'Default') {
      newAttrs.remove('fontFamily');
    } else {
      newAttrs['fontFamily'] = fontFamily;
    }

    updated[target] = current.copyWith(attributes: newAttrs);
    return CommandResult.ok(document.copyWith(nodes: updated));
  }
}

/// Command to set font size on the selected block.
class SetFontSizeCommand extends EditorCommand {
  const SetFontSizeCommand({required this.fontSize});

  final double fontSize;

  @override
  String get id => 'structure.fontSize.$fontSize';

  @override
  CommandResult execute(DocumentValue document) {
    final EditorSelection sel = document.selection;
    final int target = sel.nodeIndex;
    if (target < 0 || target >= document.nodes.length) {
      return CommandResult.ok(document);
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode current = updated[target];
    final Map<String, dynamic> newAttrs = Map<String, dynamic>.from(current.attributes);

    if (fontSize <= 0) {
      newAttrs.remove('fontSize');
    } else {
      newAttrs['fontSize'] = fontSize;
    }

    updated[target] = current.copyWith(attributes: newAttrs);
    return CommandResult.ok(document.copyWith(nodes: updated));
  }
}

/// Command to insert a special character or symbol at the current cursor position.
class InsertSpecialCharacterCommand extends EditorCommand {
  const InsertSpecialCharacterCommand({required this.character});

  final String character;

  @override
  String get id => 'structure.specialChar';

  @override
  CommandResult execute(DocumentValue document) {
    final EditorSelection sel = document.selection;
    final int target = sel.nodeIndex;
    if (target < 0 || target >= document.nodes.length) {
      return CommandResult.ok(document);
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode current = updated[target];
    final String text = current.text;
    final int offset = sel.start.clamp(0, text.length);

    final String newText = text.replaceRange(offset, offset, character);
    updated[target] = current.copyWith(text: newText);

    return CommandResult.ok(document.copyWith(
      nodes: updated,
      selection: EditorSelection.collapsed(offset + character.length, nodeIndex: target),
    ));
  }
}

/// Command to merge the next block into the current block (Delete key at end of line).
class MergeBlockForwardCommand extends EditorCommand {
  const MergeBlockForwardCommand({
    required this.nodeIndex,
  });

  final int nodeIndex;

  @override
  String get id => 'structure.mergeBlockForward';

  @override
  CommandResult execute(DocumentValue document) {
    if (nodeIndex < 0 || nodeIndex >= document.nodes.length) {
      return CommandResult.ok(document);
    }

    final int nextIndex = nodeIndex + 1;
    if (nextIndex >= document.nodes.length) {
      // Nothing to merge forward into
      return CommandResult.ok(document);
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorNode current = updated[nodeIndex];
    final EditorNode next = updated[nextIndex];

    // Skip merging into non-text nodes (tables, images, etc.)
    if (next.type == 'table' || next.type == 'image' || next.type == 'video' || next.type == 'hr') {
      // Delete the next non-text node instead
      updated.removeAt(nextIndex);
      return CommandResult.ok(document.copyWith(
        nodes: updated,
        selection: EditorSelection.collapsed(current.text.length, nodeIndex: nodeIndex),
      ));
    }

    // Merge next node's text into current node
    final int cursorPos = current.text.length;
    final String mergedText = current.text + next.text;
    updated[nodeIndex] = current.copyWith(text: mergedText);
    updated.removeAt(nextIndex);

    return CommandResult.ok(document.copyWith(
      nodes: updated,
      selection: EditorSelection.collapsed(cursorPos, nodeIndex: nodeIndex),
    ));
  }
}

/// Command to delete all selected content, including across multiple nodes.
/// Handles the "select all + delete" scenario.
class DeleteSelectedNodesCommand extends EditorCommand {
  const DeleteSelectedNodesCommand({
    required this.startNodeIndex,
    required this.endNodeIndex,
    required this.startOffset,
    required this.endOffset,
  });

  final int startNodeIndex;
  final int endNodeIndex;
  final int startOffset;
  final int endOffset;

  @override
  String get id => 'structure.deleteSelected';

  @override
  CommandResult execute(DocumentValue document) {
    if (document.nodes.isEmpty) return CommandResult.ok(document);

    final int sNode = startNodeIndex.clamp(0, document.nodes.length - 1);
    final int eNode = endNodeIndex.clamp(0, document.nodes.length - 1);

    // If same node, just trim the text
    if (sNode == eNode) {
      final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
      final EditorNode node = updated[sNode];
      final int sOff = startOffset.clamp(0, node.text.length);
      final int eOff = endOffset.clamp(0, node.text.length);
      final String newText = node.text.substring(0, sOff) + node.text.substring(eOff);
      updated[sNode] = node.copyWith(text: newText);
      return CommandResult.ok(document.copyWith(
        nodes: updated,
        selection: EditorSelection.collapsed(sOff, nodeIndex: sNode),
      ));
    }

    // Multi-node deletion
    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);

    // Keep start of first node and end of last node
    final EditorNode firstNode = updated[sNode];
    final EditorNode lastNode = updated[eNode];
    final int sOff = startOffset.clamp(0, firstNode.text.length);
    final int eOff = endOffset.clamp(0, lastNode.text.length);
    final String remainingText = firstNode.text.substring(0, sOff) + lastNode.text.substring(eOff);

    // Replace first node with merged content
    updated[sNode] = firstNode.copyWith(text: remainingText);

    // Remove all nodes between first and last (inclusive of nodes after first)
    if (eNode > sNode) {
      updated.removeRange(sNode + 1, eNode + 1);
    }

    // Ensure document is never empty
    if (updated.isEmpty) {
      updated.add(EditorNode.paragraph(
        id: 'p_${DateTime.now().microsecondsSinceEpoch}',
        text: '',
      ));
    }

    return CommandResult.ok(document.copyWith(
      nodes: updated,
      selection: EditorSelection.collapsed(sOff, nodeIndex: sNode.clamp(0, updated.length - 1)),
    ));
  }
}

/// Command to clear the entire document (select all + delete).
class ClearDocumentCommand extends EditorCommand {
  const ClearDocumentCommand();

  @override
  String get id => 'structure.clearDocument';

  @override
  CommandResult execute(DocumentValue document) {
    return CommandResult.ok(DocumentValue(
      nodes: <EditorNode>[
        EditorNode.paragraph(
          id: 'p_${DateTime.now().microsecondsSinceEpoch}',
          text: '',
        ),
      ],
      selection: const EditorSelection.collapsed(0, nodeIndex: 0),
    ));
  }
}

/// Plugin providing document structure operations (headings, lists, blockquote, hr).
class StructurePlugin extends EditorPlugin {
  const StructurePlugin();

  @override
  String get id => 'structure';

  @override
  String get name => 'Document Structure';

  @override
  List<EditorCommand> get commands => const <EditorCommand>[
        SetBlockTypeCommand(type: 'paragraph'),
        SetBlockTypeCommand(type: 'heading', metadata: <String, dynamic>{'level': 1}),
        SetBlockTypeCommand(type: 'heading', metadata: <String, dynamic>{'level': 2}),
        SetBlockTypeCommand(type: 'heading', metadata: <String, dynamic>{'level': 3}),
        SetBlockTypeCommand(type: 'heading', metadata: <String, dynamic>{'level': 4}),
        SetBlockTypeCommand(type: 'heading', metadata: <String, dynamic>{'level': 5}),
        SetBlockTypeCommand(type: 'heading', metadata: <String, dynamic>{'level': 6}),
        SetBlockTypeCommand(type: 'blockquote'),
        ToggleListCommand(listType: 'bullet'),
        ToggleListCommand(listType: 'numbered'),
        ToggleListCommand(listType: 'todo'),
        IndentListCommand(),
        OutdentListCommand(),
        InsertHorizontalRuleCommand(),
        SplitBlockCommand(nodeIndex: 0, splitOffset: 0),
        MergeBlockBackwardCommand(nodeIndex: 0),
        MergeBlockForwardCommand(nodeIndex: 0),
        DeleteSelectedNodesCommand(startNodeIndex: 0, endNodeIndex: 0, startOffset: 0, endOffset: 0),
        ClearDocumentCommand(),
        SetTextAlignmentCommand(align: 'left'),
        SetFontFamilyCommand(fontFamily: 'Default'),
        SetFontSizeCommand(fontSize: 14.0),
        InsertSpecialCharacterCommand(character: ''),
      ];
}
