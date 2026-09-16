import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import '../core/document_model/document_value.dart';
import '../core/document_model/editor_node.dart';

/// HTML serializer and deserializer for [DocumentValue].
class HtmlDocumentCodec {
  const HtmlDocumentCodec();

  /// Converts a [DocumentValue] into a semantic HTML string.
  String encode(DocumentValue document) {
    final StringBuffer buffer = StringBuffer();

    for (final EditorNode node in document.nodes) {
      buffer.write(_encodeNode(node));
    }

    return buffer.toString().trim();
  }

  String _encodeNode(EditorNode node) {
    switch (node.type) {
      case 'comment':
        return '<!--${node.text}-->\n';
      case 'heading':
        final int level = (node.metadata['level'] as num?)?.toInt() ?? 1;
        final String content = _encodeInline(node);
        final String align = node.attributes['align'] as String? ?? '';
        final String styleAttr = align.isNotEmpty ? ' style="text-align: $align;"' : '';
        return '<h$level$styleAttr>$content</h$level>\n';
      case 'blockquote':
        final String content = _encodeInline(node);
        final String align = node.attributes['align'] as String? ?? '';
        final String styleAttr = align.isNotEmpty ? ' style="text-align: $align;"' : '';
        if (content.startsWith('<p>') && content.endsWith('</p>')) {
          return '<blockquote$styleAttr>$content</blockquote>\n';
        }
        return '<blockquote$styleAttr><p>$content</p></blockquote>\n';
      case 'hr':
        return '<hr>\n';
      case 'code_block':
        final String lang = node.metadata['language'] as String? ?? '';
        final String classAttr = lang.isNotEmpty ? ' class="language-$lang"' : '';
        final String escaped = _escapeHtml(node.text);
        return '<pre><code$classAttr>$escaped</code></pre>\n';
      case 'image':
        final String url = node.metadata['url'] as String? ?? '';
        final String alt = node.metadata['alt'] as String? ?? '';
        final String caption = node.metadata['caption'] as String? ?? '';
        final String width = node.metadata['width'] != null ? ' width="${node.metadata['width']}"' : '';
        if (caption.isNotEmpty) {
          return '<figure><img src="$url" alt="$alt"$width><figcaption>$caption</figcaption></figure>\n';
        }
        return '<img src="$url" alt="$alt"$width>\n';
      case 'video':
        final String url = node.metadata['url'] as String? ?? '';
        final String poster = node.metadata['poster'] as String? ?? '';
        final String posterAttr = poster.isNotEmpty ? ' poster="$poster"' : '';
        return '<video src="$url"$posterAttr controls></video>\n';
      case 'table':
        return _encodeTable(node);
      case 'list':
        return _encodeList(node);
      case 'paragraph':
      default:
        final String content = _encodeInline(node);
        final String align = node.attributes['align'] as String? ?? '';
        final String styleAttr = align.isNotEmpty ? ' style="text-align: $align;"' : '';
        return '<p$styleAttr>$content</p>\n';
    }
  }

  String _encodeTable(EditorNode tableNode) {
    final StringBuffer buffer = StringBuffer();
    buffer.write('<table>\n');
    final String caption = tableNode.metadata['caption'] as String? ?? '';
    if (caption.isNotEmpty) {
      buffer.write('  <caption>$caption</caption>\n');
    }
    for (final EditorNode row in tableNode.children) {
      buffer.write('  <tr>\n');
      for (final EditorNode cell in row.children) {
        final bool isHeader = cell.metadata['isHeader'] == true;
        final String tag = isHeader ? 'th' : 'td';
        buffer.write('    <$tag>${cell.text}</$tag>\n');
      }
      buffer.write('  </tr>\n');
    }
    buffer.write('</table>\n');
    return buffer.toString();
  }

  String _encodeList(EditorNode listNode) {
    final String listType = listNode.metadata['listType'] as String? ?? 'bullet';
    final String tag = listType == 'numbered' ? 'ol' : 'ul';
    final StringBuffer buffer = StringBuffer();
    buffer.write('<$tag>\n');
    buffer.write('  <li>${_encodeInline(listNode)}');
    if (listNode.children.isNotEmpty) {
      for (final EditorNode child in listNode.children) {
        buffer.write('\n    ${_encodeNode(child)}');
      }
    }
    buffer.write('</li>\n');
    buffer.write('</$tag>\n');
    return buffer.toString();
  }

  String _encodeInline(EditorNode node) {
    if (node.text.contains('<') && node.text.contains('>')) {
      return node.text;
    }
    String content = _escapeHtml(node.text);
    final Map<String, dynamic> attrs = node.attributes;

    if (attrs['bold'] == true) {
      content = '<strong>$content</strong>';
    }
    if (attrs['italic'] == true) {
      content = '<em>$content</em>';
    }
    if (attrs['underline'] == true) {
      content = '<u>$content</u>';
    }
    if (attrs['strikethrough'] == true) {
      content = '<s>$content</s>';
    }
    if (attrs['code'] == true) {
      content = '<code>$content</code>';
    }
    if (attrs['subscript'] == true) {
      content = '<sub>$content</sub>';
    }
    if (attrs['superscript'] == true) {
      content = '<sup>$content</sup>';
    }
    if (attrs['link'] != null) {
      content = '<a href="${attrs['link']}">$content</a>';
    }
    if (attrs['color'] != null) {
      content = '<span style="color: ${attrs['color']};">$content</span>';
    }
    if (attrs['highlight'] != null) {
      content = '<span style="background-color: ${attrs['highlight']};">$content</span>';
    } else if (attrs['backgroundColor'] != null) {
      content = '<span style="background-color: ${attrs['backgroundColor']};">$content</span>';
    }
    if (attrs['fontFamily'] != null && attrs['fontFamily'] != 'Default') {
      content = '<span style="font-family: ${attrs['fontFamily']};">$content</span>';
    }
    if (attrs['fontSize'] != null) {
      content = '<span style="font-size: ${attrs['fontSize']}px;">$content</span>';
    }
    return content;
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// Parses an HTML string into a [DocumentValue].
  DocumentValue decode(String html) {
    if (html.trim().isEmpty) {
      return DocumentValue.empty();
    }

    final dom.DocumentFragment fragment = html_parser.parseFragment(html);
    final List<EditorNode> nodes = <EditorNode>[];
    int counter = 0;

    for (final dom.Node node in fragment.nodes) {
      if (node is dom.Comment) {
        nodes.add(EditorNode(
          id: 'comment_${counter++}',
          type: 'comment',
          text: node.data?.trim() ?? '',
        ));
      } else if (node is dom.Element) {
        _parseElement(node, nodes, () => counter++);
      } else if (node is dom.Text && node.text.trim().isNotEmpty) {
        nodes.add(EditorNode.paragraph(
          id: 'node_${counter++}',
          text: node.text.trim(),
        ));
      }
    }

    if (nodes.isEmpty) {
      return DocumentValue.empty();
    }

    return DocumentValue(nodes: nodes);
  }

  void _parseElement(
    dom.Element element,
    List<EditorNode> nodes,
    int Function() nextId,
  ) {
    final String tag = element.localName?.toLowerCase() ?? '';

    switch (tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final int level = int.tryParse(tag.substring(1)) ?? 1;
        final String inner = element.innerHtml.trim();
        final String text = inner.contains('<') ? inner : element.text.trim();
        nodes.add(EditorNode.heading(
          id: 'h_${nextId()}',
          text: text,
          level: level,
          attributes: _extractAttributes(element),
        ));
        break;

      case 'blockquote':
        final dom.Element? p = element.querySelector('p');
        final String inner = p != null ? p.innerHtml.trim() : element.innerHtml.trim();
        final String text = inner.contains('<') ? inner : (p?.text.trim() ?? element.text.trim());
        nodes.add(EditorNode(
          id: 'quote_${nextId()}',
          type: 'blockquote',
          text: text,
          attributes: _extractAttributes(element),
        ));
        break;

      case 'hr':
        nodes.add(EditorNode(
          id: 'hr_${nextId()}',
          type: 'hr',
        ));
        break;

      case 'pre':
        final dom.Element? codeElem = element.querySelector('code');
        final String codeText = codeElem != null ? codeElem.text : element.text;
        String lang = '';
        if (codeElem != null) {
          final String cls = codeElem.className;
          if (cls.contains('language-')) {
            lang = cls.split('language-').last.split(' ').first;
          }
        }
        nodes.add(EditorNode.codeBlock(
          id: 'code_${nextId()}',
          code: codeText,
          language: lang.isNotEmpty ? lang : 'plaintext',
        ));
        break;

      case 'ul':
      case 'ol':
        final String listType = tag == 'ol' ? 'numbered' : 'bullet';
        for (final dom.Element li in element.children.where((dom.Element c) => c.localName == 'li')) {
          nodes.add(EditorNode.listItem(
            id: 'li_${nextId()}',
            text: li.nodes.whereType<dom.Text>().map((dom.Text t) => t.text).join(' ').trim().isNotEmpty
                ? li.nodes.whereType<dom.Text>().map((dom.Text t) => t.text).join(' ').trim()
                : li.text.trim(),
            listType: listType,
            attributes: _extractAttributes(li),
          ));
        }
        break;

      case 'table':
        final String caption = element.querySelector('caption')?.text.trim() ?? '';
        final List<EditorNode> rowNodes = <EditorNode>[];
        final List<dom.Element> trElements = element.querySelectorAll('tr');
        int colCount = 0;

        for (int r = 0; r < trElements.length; r++) {
          final dom.Element tr = trElements[r];
          final List<EditorNode> cellNodes = <EditorNode>[];
          final List<dom.Element> cells = tr.querySelectorAll('th, td');
          if (cells.length > colCount) {
            colCount = cells.length;
          }

          for (int c = 0; c < cells.length; c++) {
            final dom.Element cell = cells[c];
            cellNodes.add(EditorNode(
              id: 'cell_${r}_$c',
              type: 'table_cell',
              text: cell.text.trim(),
              metadata: <String, dynamic>{
                'isHeader': cell.localName == 'th',
              },
            ));
          }

          rowNodes.add(EditorNode(
            id: 'row_$r',
            type: 'table_row',
            children: cellNodes,
          ));
        }

        nodes.add(EditorNode(
          id: 'table_${nextId()}',
          type: 'table',
          metadata: <String, dynamic>{
            'rows': rowNodes.length,
            'columns': colCount,
            'caption': caption,
          },
          children: rowNodes,
        ));
        break;

      case 'figure':
        final dom.Element? img = element.querySelector('img');
        final String cap = element.querySelector('figcaption')?.text.trim() ?? '';
        if (img != null) {
          nodes.add(EditorNode.image(
            id: 'img_${nextId()}',
            url: img.attributes['src'] ?? '',
            alt: img.attributes['alt'] ?? '',
            caption: cap,
          ));
        }
        break;

      case 'img':
        nodes.add(EditorNode.image(
          id: 'img_${nextId()}',
          url: element.attributes['src'] ?? '',
          alt: element.attributes['alt'] ?? '',
        ));
        break;

      case 'video':
        nodes.add(EditorNode.video(
          id: 'vid_${nextId()}',
          url: element.attributes['src'] ?? '',
          poster: element.attributes['poster'] ?? '',
        ));
        break;

      case 'p':
      default:
        final String inner = element.innerHtml.trim();
        final String text = inner.contains('<') ? inner : element.text.trim();
        nodes.add(EditorNode.paragraph(
          id: 'p_${nextId()}',
          text: text,
          attributes: _extractAttributes(element),
        ));
        break;
    }
  }

  Map<String, dynamic> _extractAttributes(dom.Element element) {
    final Map<String, dynamic> attrs = <String, dynamic>{};
    if (element.querySelector('strong, b') != null ||
        element.localName == 'strong' ||
        element.localName == 'b') {
      attrs['bold'] = true;
    }
    if (element.querySelector('em, i') != null ||
        element.localName == 'em' ||
        element.localName == 'i') {
      attrs['italic'] = true;
    }
    if (element.querySelector('u') != null || element.localName == 'u') {
      attrs['underline'] = true;
    }
    if (element.querySelector('s, del') != null ||
        element.localName == 's' ||
        element.localName == 'del') {
      attrs['strikethrough'] = true;
    }
    if (element.querySelector('code') != null || element.localName == 'code') {
      attrs['code'] = true;
    }
    final dom.Element? a = element.querySelector('a') ?? (element.localName == 'a' ? element : null);
    if (a != null && a.attributes.containsKey('href')) {
      attrs['link'] = a.attributes['href'];
    }
    final String style = element.attributes['style'] ?? '';
    if (style.isNotEmpty) {
      if (style.contains('text-align:')) {
        final RegExp alignRegex = RegExp(r'text-align:\s*([a-zA-Z]+)');
        final Match? match = alignRegex.firstMatch(style);
        if (match != null) {
          attrs['align'] = match.group(1);
        }
      }
      if (style.contains('color:')) {
        final RegExp colorRegex = RegExp(r'(?<!background-)color:\s*([^;]+)');
        final Match? match = colorRegex.firstMatch(style);
        if (match != null) {
          attrs['color'] = match.group(1)?.trim();
        }
      }
      if (style.contains('background-color:')) {
        final RegExp bgRegex = RegExp(r'background-color:\s*([^;]+)');
        final Match? match = bgRegex.firstMatch(style);
        if (match != null) {
          attrs['backgroundColor'] = match.group(1)?.trim();
        }
      }
      if (style.contains('font-family:')) {
        final RegExp fontRegex = RegExp(r'font-family:\s*([^;]+)');
        final Match? match = fontRegex.firstMatch(style);
        if (match != null) {
          attrs['fontFamily'] = match.group(1)?.trim();
        }
      }
      if (style.contains('font-size:')) {
        final RegExp sizeRegex = RegExp(r'font-size:\s*([0-9.]+)(?:px)?');
        final Match? match = sizeRegex.firstMatch(style);
        if (match != null) {
          attrs['fontSize'] = double.tryParse(match.group(1) ?? '');
        }
      }
    }
    return attrs;
  }
}
