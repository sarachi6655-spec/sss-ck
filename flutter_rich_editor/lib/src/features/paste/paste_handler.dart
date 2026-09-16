import '../../core/command_bus/editor_command.dart';
import '../../core/document_model/document_value.dart';
import '../../core/document_model/editor_node.dart';
import '../../core/document_model/editor_selection.dart';
import '../../serialization/html_codec.dart';
import '../../serialization/markdown_codec.dart';

/// Sanitizes external HTML and inserts paste content as an undoable command.
class PasteContentCommand extends EditorCommand {
  const PasteContentCommand({
    required this.rawContent,
    this.isHtml = false,
    this.isMarkdown = false,
  });

  final String rawContent;
  final bool isHtml;
  final bool isMarkdown;

  @override
  String get id => 'paste.content';

  @override
  CommandResult execute(DocumentValue document) {
    List<EditorNode> insertedNodes;

    if (isHtml) {
      final String sanitized = sanitizeHtml(rawContent);
      final DocumentValue parsed = const HtmlDocumentCodec().decode(sanitized);
      insertedNodes = parsed.nodes;
    } else if (isMarkdown) {
      final DocumentValue parsed = const MarkdownDocumentCodec().decode(rawContent);
      insertedNodes = parsed.nodes;
    } else {
      // Plain text
      final List<String> lines = rawContent.split('\n');
      insertedNodes = lines.map((String l) {
        return EditorNode.paragraph(
          id: 'pasted_${DateTime.now().millisecondsSinceEpoch}_${lines.indexOf(l)}',
          text: l,
        );
      }).toList();
    }

    if (insertedNodes.isEmpty) {
      return CommandResult.ok(document);
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorSelection sel = document.selection;
    final int insertIndex = sel.nodeIndex.clamp(0, updated.length);

    // If current node is empty paragraph, replace it
    if (insertIndex < updated.length &&
        updated[insertIndex].type == 'paragraph' &&
        updated[insertIndex].text.isEmpty) {
      updated.removeAt(insertIndex);
    }

    updated.insertAll(insertIndex, insertedNodes);

    final int newSelectionNode = (insertIndex + insertedNodes.length - 1).clamp(0, updated.length - 1);
    final int newSelectionOffset = updated[newSelectionNode].text.length;

    return CommandResult.ok(document.copyWith(
      nodes: updated,
      selection: EditorSelection.collapsed(newSelectionOffset, nodeIndex: newSelectionNode),
    ));
  }

  /// Strips dangerous tags, event handlers, and Word XML clutter.
  static String sanitizeHtml(String html) {
    String cleaned = html;

    // Remove Word conditional comments <!--[if ...]>...<![endif]-->
    cleaned = cleaned.replaceAll(RegExp(r'<!--\[if[\s\S]*?<!\[endif\]-->', caseSensitive: false), '');

    // Remove script tags and contents
    cleaned = cleaned.replaceAll(RegExp(r'<script\b[\s\S]*?</script>', caseSensitive: false), '');

    // Remove iframe, object, embed
    cleaned = cleaned.replaceAll(RegExp(r'<(iframe|object|embed)\b[\s\S]*?</\1>', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'<(iframe|object|embed)\b[^>]*?>', caseSensitive: false), '');

    // Remove inline event handlers (onclick=, onerror=, etc.)
    cleaned = cleaned.replaceAll(RegExp(r'''\son[a-zA-Z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)''', caseSensitive: false), '');

    // Remove javascript: URLs
    cleaned = cleaned.replaceAll(RegExp(r'href\s*=\s*["\x27]javascript:[\s\S]*?["\x27]', caseSensitive: false), 'href="#"');

    // Remove Word specific namespace tags (<o:p>, </o:p>, <w:...>)
    cleaned = cleaned.replaceAll(RegExp(r'</?[a-zA-Z]+:[^>]*>', caseSensitive: false), '');

    return cleaned;
  }
}
