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
        if (node.metadata['oembed'] == true) {
          return '<figure class="media"><oembed url="$url"></oembed></figure>\n';
        }
        if (node.metadata['iframe'] == true) {
          return '<figure class="media"><iframe src="$url" style="width:100%;aspect-ratio:16/9;border:none;border-radius:8px;" allowfullscreen></iframe></figure>\n';
        }
        return '<figure class="media"><video src="$url"$posterAttr controls></video></figure>\n';
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
    final bool wrapInFigure = tableNode.metadata['wrapInFigure'] != false;
    final String figClass = tableNode.metadata['figureClass'] as String? ?? 'table';
    final String figStyle = tableNode.metadata['figureStyle'] as String? ?? '';

    if (wrapInFigure) {
      final String styleAttr = figStyle.isNotEmpty ? ' style="$figStyle"' : '';
      buffer.write('<figure class="$figClass"$styleAttr>\n');
    }

    final String tableClass = tableNode.metadata['class'] as String? ?? '';
    final String tableStyle = tableNode.metadata['style'] as String? ?? '';
    final String classAttr = tableClass.isNotEmpty ? ' class="$tableClass"' : '';
    final String styleAttr = tableStyle.isNotEmpty ? ' style="$tableStyle"' : '';

    buffer.write('  <table$classAttr$styleAttr>\n');
    final String caption = tableNode.metadata['caption'] as String? ?? '';
    if (caption.isNotEmpty) {
      buffer.write('    <caption>$caption</caption>\n');
    }
    buffer.write('    <tbody>\n');
    for (final EditorNode row in tableNode.children) {
      final String rowStyle = row.metadata['style'] as String? ?? '';
      final String rowClass = row.metadata['class'] as String? ?? '';
      final String rStyleAttr = rowStyle.isNotEmpty ? ' style="$rowStyle"' : '';
      final String rClassAttr = rowClass.isNotEmpty ? ' class="$rowClass"' : '';
      buffer.write('      <tr$rClassAttr$rStyleAttr>\n');
      for (final EditorNode cell in row.children) {
        final bool isHeader = cell.metadata['isHeader'] == true;
        final String tag = isHeader ? 'th' : 'td';
        final String? colspan = cell.metadata['colspan']?.toString();
        final String? rowspan = cell.metadata['rowspan']?.toString();
        final String colspanAttr = (colspan != null && colspan.isNotEmpty) ? ' colspan="$colspan"' : '';
        final String rowspanAttr = (rowspan != null && rowspan.isNotEmpty) ? ' rowspan="$rowspan"' : '';
        final String cellStyle = cell.metadata['style'] as String? ?? '';
        final String cellClass = cell.metadata['class'] as String? ?? '';
        final String? formula = cell.metadata['data-formula'] as String?;
        final String? title = cell.metadata['title'] as String?;
        final String cStyleAttr = cellStyle.isNotEmpty ? ' style="$cellStyle"' : '';
        final String cClassAttr = cellClass.isNotEmpty ? ' class="$cellClass"' : '';
        final String formulaAttr = (formula != null && formula.isNotEmpty) ? ' data-formula="$formula"' : '';
        final String titleAttr = (title != null && title.isNotEmpty) ? ' title="$title"' : '';

        String cellHtml = cell.metadata['html'] as String? ?? '';
        if (cellHtml.isNotEmpty) {
          cellHtml = cellHtml.replaceAll(RegExp(r'<span class="formula-badge"[^>]*>.*?</span>', caseSensitive: false), '');
          cellHtml = cellHtml.replaceAllMapped(RegExp(r'(\d+)\s*fx\b', caseSensitive: false), (m) => m[1]!);
        }
        final String rawText = cell.text.replaceAll(RegExp(r'\s*fx\b', caseSensitive: false), '').trim();
        final String cellContent = cellHtml.isNotEmpty
            ? cellHtml
            : (rawText.isNotEmpty ? _escapeHtml(rawText) : '&nbsp;');

        buffer.write('        <$tag$colspanAttr$rowspanAttr$formulaAttr$titleAttr$cClassAttr$cStyleAttr>$cellContent</$tag>\n');
      }
      buffer.write('      </tr>\n');
    }
    buffer.write('    </tbody>\n');
    buffer.write('  </table>\n');
    if (wrapInFigure) {
      buffer.write('</figure>\n');
    }
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
        _parseTable(element, nodes, nextId);
        break;

      case 'figure':
        final dom.Element? table = element.querySelector('table');
        if (table != null) {
          _parseTable(table, nodes, nextId, figureElement: element);
          break;
        }
        final dom.Element? img = element.querySelector('img');
        final String cap = element.querySelector('figcaption')?.text.trim() ?? '';
        if (img != null) {
          nodes.add(EditorNode.image(
            id: 'img_${nextId()}',
            url: img.attributes['src'] ?? '',
            alt: img.attributes['alt'] ?? '',
            caption: cap,
          ));
          break;
        }
        final dom.Element? oembed = element.querySelector('oembed');
        if (oembed != null) {
          nodes.add(EditorNode.video(
            id: 'vid_${nextId()}',
            url: oembed.attributes['url'] ?? '',
            metadata: <String, dynamic>{
              'oembed': true,
              if (element.attributes['class'] != null) 'class': element.attributes['class'],
              if (element.attributes['style'] != null) 'style': element.attributes['style'],
            },
          ));
          break;
        }
        final dom.Element? iframe = element.querySelector('iframe');
        if (iframe != null) {
          nodes.add(EditorNode.video(
            id: 'vid_${nextId()}',
            url: iframe.attributes['src'] ?? '',
            metadata: <String, dynamic>{
              'iframe': true,
              if (element.attributes['class'] != null) 'class': element.attributes['class'],
              if (element.attributes['style'] != null) 'style': element.attributes['style'],
            },
          ));
          break;
        }
        final dom.Element? vid = element.querySelector('video');
        if (vid != null) {
          nodes.add(EditorNode.video(
            id: 'vid_${nextId()}',
            url: vid.attributes['src'] ?? '',
            poster: vid.attributes['poster'] ?? '',
            metadata: <String, dynamic>{
              if (element.attributes['class'] != null) 'class': element.attributes['class'],
              if (element.attributes['style'] != null) 'style': element.attributes['style'],
            },
          ));
          break;
        }
        break;

      case 'oembed':
        nodes.add(EditorNode.video(
          id: 'vid_${nextId()}',
          url: element.attributes['url'] ?? '',
          metadata: const <String, dynamic>{'oembed': true},
        ));
        break;

      case 'iframe':
        nodes.add(EditorNode.video(
          id: 'vid_${nextId()}',
          url: element.attributes['src'] ?? '',
          metadata: const <String, dynamic>{'iframe': true},
        ));
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

  void _parseTable(
    dom.Element tableElement,
    List<EditorNode> nodes,
    int Function() nextId, {
    dom.Element? figureElement,
  }) {
    final String caption = tableElement.querySelector('caption')?.text.trim() ?? '';
    final List<EditorNode> rowNodes = <EditorNode>[];
    final List<dom.Element> trElements = tableElement.querySelectorAll('tr');
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
        final bool isHeader = cell.localName == 'th';
        String innerHtml = cell.innerHtml.trim();
        innerHtml = innerHtml.replaceAll(RegExp(r'<span class="formula-badge"[^>]*>.*?</span>', caseSensitive: false), '').trim();
        innerHtml = innerHtml.replaceAllMapped(RegExp(r'(\d+)\s*fx\b', caseSensitive: false), (m) => m[1]!);
        String cellText = cell.text.replaceAll(RegExp(r'\s*fx\b', caseSensitive: false), '').trim();
        final String? colspan = cell.attributes['colspan'];
        final String? rowspan = cell.attributes['rowspan'];
        final String? cellStyle = cell.attributes['style'];
        final String? cellClass = cell.attributes['class'];
        String? cellFormula = cell.attributes['data-formula'] ?? cell.querySelector('[data-formula]')?.attributes['data-formula'];
        final String? cellTitle = cell.attributes['title'] ?? cell.querySelector('[title*="Formula:"]')?.attributes['title'];
        if ((cellFormula == null || cellFormula.isEmpty) && cellTitle != null && cellTitle.contains('Formula:')) {
          final int idx = cellTitle.indexOf('Formula:');
          String cand = cellTitle.substring(idx + 8).trim();
          final int clickIdx = cand.toLowerCase().indexOf('(click');
          if (clickIdx != -1) {
            cand = cand.substring(0, clickIdx).trim();
          }
          if (cand.startsWith('=')) cellFormula = cand;
        }

        cellNodes.add(EditorNode(
          id: 'cell_${r}_$c',
          type: 'table_cell',
          text: cellText,
          metadata: <String, dynamic>{
            'isHeader': isHeader,
            'html': innerHtml.isNotEmpty ? innerHtml : cellText,
            if (colspan != null && colspan.isNotEmpty) 'colspan': colspan,
            if (rowspan != null && rowspan.isNotEmpty) 'rowspan': rowspan,
            if (cellStyle != null && cellStyle.isNotEmpty) 'style': cellStyle,
            if (cellClass != null && cellClass.isNotEmpty) 'class': cellClass,
            if (cellFormula != null && cellFormula.isNotEmpty) 'data-formula': cellFormula,
            if (cellTitle != null && cellTitle.isNotEmpty) 'title': cellTitle,
          },
        ));
      }

      final String? rowStyle = tr.attributes['style'];
      final String? rowClass = tr.attributes['class'];
      rowNodes.add(EditorNode(
        id: 'row_$r',
        type: 'table_row',
        metadata: <String, dynamic>{
          if (rowStyle != null && rowStyle.isNotEmpty) 'style': rowStyle,
          if (rowClass != null && rowClass.isNotEmpty) 'class': rowClass,
        },
        children: cellNodes,
      ));
    }

    final String? tableStyle = tableElement.attributes['style'];
    final String? tableClass = tableElement.attributes['class'];
    final String? figStyle = figureElement?.attributes['style'];
    final String? figClass = figureElement?.attributes['class'];

    nodes.add(EditorNode(
      id: 'table_${nextId()}',
      type: 'table',
      metadata: <String, dynamic>{
        'rows': rowNodes.length,
        'columns': colCount,
        'caption': caption,
        'wrapInFigure': figureElement != null,
        if (figStyle != null && figStyle.isNotEmpty) 'figureStyle': figStyle,
        if (figClass != null && figClass.isNotEmpty) 'figureClass': figClass,
        if (tableStyle != null && tableStyle.isNotEmpty) 'style': tableStyle,
        if (tableClass != null && tableClass.isNotEmpty) 'class': tableClass,
      },
      children: rowNodes,
    ));
  }

  Map<String, dynamic> _extractAttributes(dom.Element element) {
    final Map<String, dynamic> attrs = <String, dynamic>{};
    if (element.querySelector('strong, b') != null ||
        element.localName == 'strong' ||
        element.localName == 'b') {
      attrs['bold'] = true;
    }
    final String style = element.attributes['style'] ?? '';
    if (element.querySelector('em, i') != null ||
        element.localName == 'em' ||
        element.localName == 'i' ||
        style.contains('font-style: italic') ||
        style.contains('font-style:italic')) {
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
