import '../core/document_model/document_value.dart';
import '../core/document_model/editor_node.dart';

/// GitHub-flavored Markdown serializer and parser for [DocumentValue].
class MarkdownDocumentCodec {
  const MarkdownDocumentCodec();

  /// Encodes a [DocumentValue] to a GitHub Flavored Markdown string.
  String encode(DocumentValue document) {
    final StringBuffer buffer = StringBuffer();

    for (int i = 0; i < document.nodes.length; i++) {
      final EditorNode node = document.nodes[i];
      buffer.write(_encodeNode(node));
      if (i < document.nodes.length - 1) {
        buffer.write('\n\n');
      }
    }

    return buffer.toString().trim();
  }

  String _encodeNode(EditorNode node) {
    switch (node.type) {
      case 'heading':
        final int level = (node.metadata['level'] as num?)?.toInt() ?? 1;
        final String prefix = '#' * level;
        return '$prefix ${_encodeInline(node)}';

      case 'blockquote':
        return '> ${_encodeInline(node)}';

      case 'hr':
        return '---';

      case 'code_block':
        final String lang = node.metadata['language'] as String? ?? '';
        return '```$lang\n${node.text}\n```';

      case 'list':
        final String listType = node.metadata['listType'] as String? ?? 'bullet';
        final int indent = (node.metadata['indent'] as num?)?.toInt() ?? 0;
        final String indentStr = '  ' * indent;

        if (listType == 'todo') {
          final bool checked = node.metadata['checked'] == true;
          final String box = checked ? '[x]' : '[ ]';
          return '$indentStr- $box ${_encodeInline(node)}';
        } else if (listType == 'numbered') {
          return '${indentStr}1. ${_encodeInline(node)}';
        } else {
          return '$indentStr- ${_encodeInline(node)}';
        }

      case 'image':
        final String url = node.metadata['url'] as String? ?? '';
        final String alt = node.metadata['alt'] as String? ?? '';
        return '![$alt]($url)';

      case 'table':
        return _encodeTable(node);

      case 'paragraph':
      default:
        return _encodeInline(node);
    }
  }

  String _encodeTable(EditorNode tableNode) {
    if (tableNode.children.isEmpty) return '';
    final StringBuffer buffer = StringBuffer();
    final List<EditorNode> rows = tableNode.children;

    // Header row
    final EditorNode firstRow = rows.first;
    buffer.write('|');
    for (final EditorNode cell in firstRow.children) {
      buffer.write(' ${cell.text.trim()} |');
    }
    buffer.write('\n|');
    for (int i = 0; i < firstRow.children.length; i++) {
      buffer.write(' --- |');
    }

    // Subsequent rows
    for (int r = 1; r < rows.length; r++) {
      buffer.write('\n|');
      for (final EditorNode cell in rows[r].children) {
        buffer.write(' ${cell.text.trim()} |');
      }
    }

    return buffer.toString();
  }

  String _encodeInline(EditorNode node) {
    String text = node.text;
    final Map<String, dynamic> attrs = node.attributes;

    if (attrs['bold'] == true && !text.contains('**')) {
      text = '**$text**';
    }
    if (attrs['italic'] == true && !text.contains('*')) {
      text = '*$text*';
    }
    if (attrs['strikethrough'] == true && !text.contains('~~')) {
      text = '~~$text~~';
    }
    if (attrs['code'] == true && !text.contains('`')) {
      text = '`$text`';
    }
    if (attrs['link'] != null && !text.contains('](')) {
      text = '[$text](${attrs['link']})';
    }
    return text;
  }

  /// Parses a Markdown string into a [DocumentValue].
  DocumentValue decode(String markdown) {
    final List<String> lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final List<EditorNode> nodes = <EditorNode>[];
    int counter = 0;

    int lineIndex = 0;
    while (lineIndex < lines.length) {
      final String line = lines[lineIndex];
      final String trimmed = line.trim();

      if (trimmed.isEmpty) {
        lineIndex++;
        continue;
      }

      // Code block
      if (trimmed.startsWith('```')) {
        final String lang = trimmed.substring(3).trim();
        final StringBuffer codeBuffer = StringBuffer();
        lineIndex++;
        while (lineIndex < lines.length && !lines[lineIndex].trim().startsWith('```')) {
          codeBuffer.writeln(lines[lineIndex]);
          lineIndex++;
        }
        if (lineIndex < lines.length) lineIndex++; // consume closing ```
        nodes.add(EditorNode.codeBlock(
          id: 'code_${counter++}',
          code: codeBuffer.toString().trimRight(),
          language: lang.isNotEmpty ? lang : 'plaintext',
        ));
        continue;
      }

      // Headings: # H1, ## H2, etc.
      if (trimmed.startsWith('#')) {
        int level = 0;
        while (level < trimmed.length && trimmed[level] == '#') {
          level++;
        }
        if (level <= 6 && level < trimmed.length && trimmed[level] == ' ') {
          final String content = trimmed.substring(level + 1).trim();
          nodes.add(EditorNode.heading(
            id: 'h_${counter++}',
            text: _stripInlineFormatting(content),
            level: level,
            attributes: _parseInlineAttributes(content),
          ));
          lineIndex++;
          continue;
        }
      }

      // Horizontal rule: --- or *** or ___
      if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
        nodes.add(EditorNode(
          id: 'hr_${counter++}',
          type: 'hr',
        ));
        lineIndex++;
        continue;
      }

      // Blockquote: > text
      if (trimmed.startsWith('>')) {
        final String content = trimmed.substring(1).trim();
        nodes.add(EditorNode(
          id: 'quote_${counter++}',
          type: 'blockquote',
          text: _stripInlineFormatting(content),
          attributes: _parseInlineAttributes(content),
        ));
        lineIndex++;
        continue;
      }

      // Table: starts with | and next line has | --- |
      if (trimmed.startsWith('|') &&
          lineIndex + 1 < lines.length &&
          lines[lineIndex + 1].trim().startsWith('|') &&
          lines[lineIndex + 1].contains('---')) {
        final List<EditorNode> rowNodes = <EditorNode>[];
        int tableRow = 0;

        // Parse header row
        final List<String> headerCells = _parseTableRow(trimmed);
        rowNodes.add(EditorNode(
          id: 'row_${tableRow++}',
          type: 'table_row',
          children: headerCells.map((String c) => EditorNode(
            id: 'cell_0_${headerCells.indexOf(c)}',
            type: 'table_cell',
            text: c,
            metadata: const <String, dynamic>{'isHeader': true},
          )).toList(),
        ));

        lineIndex += 2; // skip header and delimiter

        // Parse body rows
        while (lineIndex < lines.length && lines[lineIndex].trim().startsWith('|')) {
          final List<String> cells = _parseTableRow(lines[lineIndex].trim());
          rowNodes.add(EditorNode(
            id: 'row_${tableRow++}',
            type: 'table_row',
            children: cells.map((String c) => EditorNode(
              id: 'cell_${tableRow - 1}_${cells.indexOf(c)}',
              type: 'table_cell',
              text: c,
            )).toList(),
          ));
          lineIndex++;
        }

        nodes.add(EditorNode(
          id: 'table_${counter++}',
          type: 'table',
          metadata: <String, dynamic>{
            'rows': rowNodes.length,
            'columns': headerCells.length,
          },
          children: rowNodes,
        ));
        continue;
      }

      // Image: ![alt](url)
      final RegExp imgRegex = RegExp(r'^!\[(.*?)\]\((.*?)\)$');
      final Match? imgMatch = imgRegex.firstMatch(trimmed);
      if (imgMatch != null) {
        nodes.add(EditorNode.image(
          id: 'img_${counter++}',
          alt: imgMatch.group(1) ?? '',
          url: imgMatch.group(2) ?? '',
        ));
        lineIndex++;
        continue;
      }

      // List items: - [ ] todo, - bullet, * bullet, 1. numbered
      if (trimmed.startsWith('- [ ] ') || trimmed.startsWith('- [x] ')) {
        final bool checked = trimmed.startsWith('- [x] ');
        final String content = trimmed.substring(6).trim();
        nodes.add(EditorNode.listItem(
          id: 'li_${counter++}',
          text: _stripInlineFormatting(content),
          listType: 'todo',
          checked: checked,
          attributes: _parseInlineAttributes(content),
        ));
        lineIndex++;
        continue;
      }

      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        final String content = trimmed.substring(2).trim();
        nodes.add(EditorNode.listItem(
          id: 'li_${counter++}',
          text: _stripInlineFormatting(content),
          listType: 'bullet',
          attributes: _parseInlineAttributes(content),
        ));
        lineIndex++;
        continue;
      }

      final RegExp numberedRegex = RegExp(r'^\d+\.\s+(.*)$');
      final Match? numberedMatch = numberedRegex.firstMatch(trimmed);
      if (numberedMatch != null) {
        final String content = numberedMatch.group(1) ?? '';
        nodes.add(EditorNode.listItem(
          id: 'li_${counter++}',
          text: _stripInlineFormatting(content),
          listType: 'numbered',
          attributes: _parseInlineAttributes(content),
        ));
        lineIndex++;
        continue;
      }

      // Standard paragraph
      final bool hasInlineFormatting = trimmed.contains(RegExp(r'(\*\*|\*|~~|`|\[.*?\]\(.*?\))'));
      nodes.add(EditorNode.paragraph(
        id: 'p_${counter++}',
        text: hasInlineFormatting ? trimmed : _stripInlineFormatting(trimmed),
        attributes: _parseInlineAttributes(trimmed),
      ));
      lineIndex++;
    }

    if (nodes.isEmpty) {
      return DocumentValue.empty();
    }

    return DocumentValue(nodes: nodes);
  }

  List<String> _parseTableRow(String rowLine) {
    final List<String> rawCells = rowLine.split('|');
    if (rawCells.length > 2) {
      return rawCells
          .sublist(1, rawCells.length - 1)
          .map((String c) => c.trim())
          .toList();
    }
    return rawCells.map((String c) => c.trim()).where((String c) => c.isNotEmpty).toList();
  }

  String _stripInlineFormatting(String text) {
    String res = text;
    // Strip bold/italic
    res = res.replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1');
    res = res.replaceAll(RegExp(r'\*(.*?)\*'), r'$1');
    res = res.replaceAll(RegExp(r'~~(.*?)~~'), r'$1');
    res = res.replaceAll(RegExp(r'`(.*?)`'), r'$1');
    res = res.replaceAll(RegExp(r'\[(.*?)\]\(.*?\)'), r'$1');
    return res;
  }

  Map<String, dynamic> _parseInlineAttributes(String text) {
    final Map<String, dynamic> attrs = <String, dynamic>{};
    if (text.contains(RegExp(r'\*\*.*?\*\*'))) {
      attrs['bold'] = true;
    }
    if (text.contains(RegExp(r'(?<!\*)\*[^*]+?\*(?!\*)'))) {
      attrs['italic'] = true;
    }
    if (text.contains(RegExp(r'~~.*?~~'))) {
      attrs['strikethrough'] = true;
    }
    if (text.contains(RegExp(r'`.*?`'))) {
      attrs['code'] = true;
    }
    final Match? linkMatch = RegExp(r'\[.*?\]\((.*?)\)').firstMatch(text);
    if (linkMatch != null) {
      attrs['link'] = linkMatch.group(1);
    }
    return attrs;
  }
}
