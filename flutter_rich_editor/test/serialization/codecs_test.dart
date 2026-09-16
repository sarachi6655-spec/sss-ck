import 'package:flutter_rich_editor/flutter_rich_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Serialization Codecs Tests', () {
    test('test_jsonCodec_roundTripsAllSupportedNodesAndAttributes', () {
      final DocumentValue original = DocumentValue(
        metadata: const <String, dynamic>{'title': 'Test Doc'},
        selection: const EditorSelection(baseOffset: 2, extentOffset: 5, nodeIndex: 1),
        nodes: <EditorNode>[
          EditorNode.heading(id: 'h1', text: 'Main Title', level: 1, attributes: const {'bold': true}),
          EditorNode.paragraph(id: 'p1', text: 'Paragraph with formatting', attributes: const {'italic': true, 'color': '#FF0000'}),
          EditorNode.listItem(id: 'l1', text: 'Task 1', listType: 'todo', checked: true),
          EditorNode.codeBlock(id: 'c1', code: 'void main() {}', language: 'dart'),
          EditorNode.image(id: 'i1', url: 'https://img.png', alt: 'Alt image'),
          EditorNode.table(id: 't1', rows: 2, columns: 2, caption: 'Sample Table'),
        ],
      );

      const JsonDocumentCodec codec = JsonDocumentCodec();
      final Map<String, dynamic> jsonMap = codec.encodeToMap(original);
      final DocumentValue decoded = codec.decodeFromMap(jsonMap);

      expect(decoded.nodes.length, original.nodes.length);
      expect(decoded.selection, original.selection);
      expect(decoded.nodes[0].type, 'heading');
      expect(decoded.nodes[0].attributes['bold'], true);
      expect(decoded.nodes[1].attributes['color'], '#FF0000');
      expect(decoded.nodes[2].metadata['checked'], true);
      expect(decoded.nodes[3].text, 'void main() {}');
      expect(decoded.nodes[5].type, 'table');
      expect(decoded.nodes[5].metadata['caption'], 'Sample Table');
    });

    test('test_htmlCodec_preservesSupportedStructureAndComments', () {
      const String inputHtml = '<!--Important Header Comment-->\n'
          '<h1>Title with <strong>Bold</strong></h1>\n'
          '<p>Paragraph with <em>italic</em> and <a href="https://flutter.dev">link</a></p>\n'
          '<blockquote><p>Quote text</p></blockquote>\n'
          '<!--Footer Note-->';

      const HtmlDocumentCodec codec = HtmlDocumentCodec();
      final DocumentValue doc = codec.decode(inputHtml);

      // Verify comment preservation
      final List<EditorNode> comments = doc.nodes.where((EditorNode n) => n.type == 'comment').toList();
      expect(comments.length, 2);
      expect(comments[0].text, 'Important Header Comment');
      expect(comments[1].text, 'Footer Note');

      // Verify structure
      expect(doc.nodes.any((EditorNode n) => n.type == 'heading'), true);
      expect(doc.nodes.any((EditorNode n) => n.type == 'paragraph'), true);
      expect(doc.nodes.any((EditorNode n) => n.type == 'blockquote'), true);

      // Re-encode to HTML and verify round trip
      final String reEncoded = codec.encode(doc);
      expect(reEncoded.contains('<!--Important Header Comment-->'), true);
      expect(reEncoded.contains('<!--Footer Note-->'), true);
      expect(reEncoded.contains('<strong>Bold</strong>'), true);
      expect(reEncoded.contains('<blockquote>'), true);
    });

    test('test_markdownCodec_roundTripsSupportedGitHubMarkdown', () {
      const String originalMarkdown = '# Document Heading\n\n'
          'This is a **bold** paragraph.\n\n'
          '- [ ] Incomplete task\n\n'
          '- [x] Completed task\n\n'
          '> Blockquote quote\n\n'
          '---\n\n'
          '```dart\nvoid main() {}\n```';

      const MarkdownDocumentCodec codec = MarkdownDocumentCodec();
      final DocumentValue doc = codec.decode(originalMarkdown);

      expect(doc.nodes.length, 7);
      expect(doc.nodes[0].type, 'heading');
      expect(doc.nodes[0].text, 'Document Heading');
      expect(doc.nodes[1].attributes['bold'], true);
      expect(doc.nodes[2].metadata['listType'], 'todo');
      expect(doc.nodes[2].metadata['checked'], false);
      expect(doc.nodes[3].metadata['checked'], true);
      expect(doc.nodes[4].type, 'blockquote');
      expect(doc.nodes[5].type, 'hr');
      expect(doc.nodes[6].type, 'code_block');

      final String reEncoded = codec.encode(doc);
      expect(reEncoded.contains('# Document Heading'), true);
      expect(reEncoded.contains('**bold**'), true);
      expect(reEncoded.contains('- [ ]'), true);
      expect(reEncoded.contains('- [x]'), true);
      expect(reEncoded.contains('> Blockquote quote'), true);
      expect(reEncoded.contains('---'), true);
      expect(reEncoded.contains('```dart'), true);
    });

    test('test_deltaMigration_preservesExistingQuillContent', () {
      final List<Map<String, dynamic>> quillOps = <Map<String, dynamic>>[
        <String, dynamic>{'insert': 'Heading Title'},
        <String, dynamic>{'insert': '\n', 'attributes': <String, dynamic>{'header': 1}},
        <String, dynamic>{'insert': 'Hello '},
        <String, dynamic>{'insert': 'World', 'attributes': <String, dynamic>{'bold': true}},
        <String, dynamic>{'insert': '!\n'},
        <String, dynamic>{'insert': 'Item 1\n', 'attributes': <String, dynamic>{'list': 'bullet'}},
      ];

      const DeltaDocumentCodec codec = DeltaDocumentCodec();
      final DocumentValue doc = codec.decode(quillOps);

      expect(doc.nodes.length, 3);
      expect(doc.nodes[0].type, 'heading');
      expect(doc.nodes[0].text, 'Heading Title');
      expect(doc.nodes[0].metadata['level'], 1);

      expect(doc.nodes[1].type, 'paragraph');
      expect(doc.nodes[1].text, 'Hello World!');
      expect(doc.nodes[1].attributes['bold'], true);

      expect(doc.nodes[2].type, 'list');
      expect(doc.nodes[2].text, 'Item 1');
      expect(doc.nodes[2].metadata['listType'], 'bullet');

      // Re-encode back to Delta ops
      final List<Map<String, dynamic>> encodedOps = codec.encode(doc);
      expect(encodedOps.any((Map<String, dynamic> op) => op['insert'] == 'Heading Title'), true);
      expect(encodedOps.any((Map<String, dynamic> op) => op['attributes']?['header'] == 1), true);
    });
  });
}
