import 'package:flutter/material.dart';
import '../core/document_model/document_value.dart';
import '../core/document_model/editor_node.dart';
import '../theme/editor_theme.dart';
import 'rich_text_editing_controller.dart';

/// Tracks the character offset range for a single document node within
/// the flattened text.
class NodeSegment {
  const NodeSegment({
    required this.nodeIndex,
    required this.startOffset,
    required this.endOffset,
    required this.node,
    this.displayPrefix = '',
  });

  final int nodeIndex;
  final int startOffset;
  final int endOffset;
  final EditorNode node;

  /// Visual-only prefix (e.g. "• " for bullet lists) that is part of the text
  /// but not part of the document model text.
  final String displayPrefix;
}

/// A [TextEditingController] that manages the entire document as a single flat
/// text string. Each node's text is joined by `\n` separators. The controller
/// builds styled [TextSpan]s per node region so headings, lists, code blocks,
/// and blockquotes are rendered with appropriate styles.
///
/// This approach enables:
/// - Cross-line text selection via mouse drag
/// - Natural arrow-key navigation across nodes
/// - Standard Ctrl+A / Cmd+A select-all behavior
/// - Native delete/backspace for selected text across lines
class DocumentTextController extends TextEditingController {
  DocumentTextController({
    required this.theme,
  });

  EditorTheme theme;

  /// The mapping from node indices to character offset ranges.
  List<NodeSegment> _segments = <NodeSegment>[];

  /// Public access to current segments.
  List<NodeSegment> get segments => _segments;

  /// Whether we are currently syncing from the document model
  /// (prevents recursive updates).
  bool isSyncing = false;

  /// Builds the flat text from a [DocumentValue] and stores the segment map.
  void syncFromDocument(DocumentValue document) {
    isSyncing = true;
    final StringBuffer buffer = StringBuffer();
    final List<NodeSegment> newSegments = <NodeSegment>[];
    int offset = 0;

    for (int i = 0; i < document.nodes.length; i++) {
      final EditorNode node = document.nodes[i];
      if (i > 0) {
        buffer.write('\n');
        offset += 1;
      }

      // For non-text nodes, use a placeholder line
      String nodeText;
      String prefix = '';

      switch (node.type) {
        case 'table':
          nodeText = '[Table]';
          break;
        case 'image':
          nodeText = '[Image: ${node.metadata['alt'] ?? node.metadata['url'] ?? ''}]';
          break;
        case 'video':
          nodeText = '[Video]';
          break;
        case 'hr':
          nodeText = '───────────────────────────────────';
          break;
        case 'list':
          final String listType = node.metadata['listType'] as String? ?? 'bullet';
          final int indent = (node.metadata['indent'] as num?)?.toInt() ?? 0;
          final String indentStr = '  ' * indent;
          if (listType == 'numbered') {
            // Use a simple index for numbered lists
            prefix = '$indentStr${i + 1}. ';
          } else if (listType == 'todo') {
            final bool checked = node.metadata['checked'] == true;
            prefix = '$indentStr${checked ? '☑ ' : '☐ '}';
          } else {
            prefix = '$indentStr• ';
          }
          nodeText = prefix + node.text;
          break;
        default:
          nodeText = node.text;
          break;
      }

      final int segStart = offset;
      buffer.write(nodeText);
      offset += nodeText.length;

      newSegments.add(NodeSegment(
        nodeIndex: i,
        startOffset: segStart,
        endOffset: offset,
        node: node,
        displayPrefix: prefix,
      ));
    }

    _segments = newSegments;

    // Preserve selection if possible
    final TextSelection oldSel = selection;
    final String newText = buffer.toString();

    if (text != newText) {
      text = newText;
      // Restore selection clamped to new text length
      if (oldSel.isValid) {
        selection = TextSelection(
          baseOffset: oldSel.baseOffset.clamp(0, newText.length),
          extentOffset: oldSel.extentOffset.clamp(0, newText.length),
        );
      }
    }

    isSyncing = false;
  }

  /// Returns the node index at the given character offset.
  int nodeIndexAtOffset(int offset) {
    for (final NodeSegment seg in _segments) {
      if (offset >= seg.startOffset && offset <= seg.endOffset) {
        return seg.nodeIndex;
      }
    }
    return _segments.isNotEmpty ? _segments.last.nodeIndex : 0;
  }

  /// Returns the segment at the given character offset.
  NodeSegment? segmentAtOffset(int offset) {
    for (final NodeSegment seg in _segments) {
      if (offset >= seg.startOffset && offset <= seg.endOffset) {
        return seg;
      }
    }
    return _segments.isNotEmpty ? _segments.last : null;
  }

  /// Parses the current text back into a list of node text updates.
  /// Returns a map of nodeIndex -> new text (without display prefix).
  List<String> parseTextToNodeTexts() {
    final String currentText = text;
    final List<String> lines = <String>[];

    // Split the text by counting segments
    // Each segment boundary is at the `\n` between nodes
    if (_segments.isEmpty) {
      return <String>[currentText];
    }

    // Simple approach: split by \n and map back
    // This works because each node is on its own line(s)
    // Code blocks may have internal \n, but we handle that below
    int textPos = 0;
    for (int s = 0; s < _segments.length; s++) {
      final NodeSegment seg = _segments[s];
      final int nextSegStart = s + 1 < _segments.length
          ? _segments[s + 1].startOffset - 1 // -1 for the \n separator
          : currentText.length;

      // Find the end of this segment in the current text
      // The text may have changed (user typing), so boundaries may have shifted
      String segText;
      if (textPos <= currentText.length) {
        if (s + 1 < _segments.length) {
          // Find the \n that separates this segment from the next
          // But this is complex when text has been edited...
          segText = ''; // Will be computed below
        } else {
          segText = currentText.substring(textPos.clamp(0, currentText.length));
        }
      } else {
        segText = '';
      }

      // Strip display prefix for list items
      if (seg.displayPrefix.isNotEmpty && segText.startsWith(seg.displayPrefix)) {
        segText = segText.substring(seg.displayPrefix.length);
      }

      lines.add(segText);
      textPos = nextSegStart + 1; // +1 for the \n
    }

    return lines;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final String fullText = text;
    if (fullText.isEmpty) {
      return TextSpan(text: '', style: style ?? theme.bodyStyle);
    }

    if (_segments.isEmpty) {
      return TextSpan(text: fullText, style: style ?? theme.bodyStyle);
    }

    final List<InlineSpan> children = <InlineSpan>[];

    for (int s = 0; s < _segments.length; s++) {
      final NodeSegment seg = _segments[s];

      // Add \n separator between segments (except first)
      if (s > 0) {
        // The \n is already in the text at the boundary
        // We just need to make sure our spans cover it
      }

      // Compute actual offsets in the current text
      // (text may have grown/shrunk from user edits)
      final int segStart = seg.startOffset.clamp(0, fullText.length);
      final int segEnd = seg.endOffset.clamp(segStart, fullText.length);

      if (segStart >= fullText.length) continue;

      // Include the \n separator before this segment
      if (s > 0 && segStart > 0) {
        final int sepStart = (seg.startOffset - 1).clamp(0, fullText.length);
        if (sepStart < segStart && sepStart < fullText.length) {
          children.add(TextSpan(
            text: fullText.substring(sepStart, segStart),
            style: style ?? theme.bodyStyle,
          ));
        }
      }

      final String segText = fullText.substring(segStart, segEnd);
      final TextStyle segStyle = _styleForNode(seg.node, style ?? theme.bodyStyle);

      children.add(TextSpan(
        text: segText,
        style: segStyle,
      ));
    }

    // Handle any trailing text not covered by segments
    final int lastSegEnd = _segments.isNotEmpty ? _segments.last.endOffset : 0;
    if (lastSegEnd < fullText.length) {
      children.add(TextSpan(
        text: fullText.substring(lastSegEnd),
        style: style ?? theme.bodyStyle,
      ));
    }

    if (children.isEmpty) {
      return TextSpan(text: fullText, style: style ?? theme.bodyStyle);
    }

    return TextSpan(style: style ?? theme.bodyStyle, children: children);
  }

  TextStyle _styleForNode(EditorNode node, TextStyle baseStyle) {
    TextStyle nodeStyle;

    switch (node.type) {
      case 'heading':
        final int level = (node.metadata['level'] as num?)?.toInt() ?? 1;
        switch (level) {
          case 1:
            nodeStyle = theme.heading1Style;
            break;
          case 2:
            nodeStyle = theme.heading2Style;
            break;
          case 3:
            nodeStyle = theme.heading3Style;
            break;
          case 4:
            nodeStyle = theme.heading4Style;
            break;
          case 5:
            nodeStyle = theme.heading5Style;
            break;
          case 6:
          default:
            nodeStyle = theme.heading6Style;
            break;
        }
        break;

      case 'blockquote':
        nodeStyle = theme.blockquoteTextStyle;
        break;

      case 'code_block':
        nodeStyle = theme.codeBlockTextStyle.copyWith(
          backgroundColor: theme.codeBlockBackgroundColor,
        );
        break;

      case 'hr':
        nodeStyle = baseStyle.copyWith(
          color: theme.hrColor,
          letterSpacing: 2.0,
        );
        break;

      case 'list':
        nodeStyle = baseStyle;
        break;

      case 'table':
      case 'image':
      case 'video':
        nodeStyle = baseStyle.copyWith(
          color: theme.placeholderColor,
          fontStyle: FontStyle.italic,
        );
        break;

      case 'paragraph':
      default:
        nodeStyle = baseStyle;
        break;
    }

    // Apply inline attributes (bold, italic, color, etc.)
    nodeStyle = RichTextEditingController.applyAttributes(nodeStyle, node.attributes);

    return nodeStyle;
  }
}
