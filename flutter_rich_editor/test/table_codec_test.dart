
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rich_editor/src/serialization/html_codec.dart';

void main() {
  test('Table codec test', () {
    const codec = HtmlDocumentCodec();
    const inputHtml = '<figure class="table"><table><tbody><tr><td>Cell 1</td><td>Cell 2</td></tr></tbody></table></figure>';
    final doc = codec.decode(inputHtml);
    print('Decoded nodes count: ${doc.nodes.length}');
    for (final n in doc.nodes) {
      print('Node type: ${n.type}');
    }
    final outputHtml = codec.encode(doc);
    print('Encoded output HTML: "$outputHtml"');
    expect(outputHtml.contains('Cell 1'), isTrue);
  });

  test('Table formula attribute preservation test', () {
    const codec = HtmlDocumentCodec();
    const inputHtml = '<figure class="table"><table><tbody><tr><td>23</td><td>1</td></tr><tr><td data-formula="=A1+B1" title="Formula: =A1+B1"><strong>24</strong></td><td>Result</td></tr></tbody></table></figure>';
    final doc = codec.decode(inputHtml);
    expect(doc.nodes.length, 1);
    final tableNode = doc.nodes.first;
    expect(tableNode.type, 'table');
    final row2 = tableNode.children[1];
    final formulaCell = row2.children[0];
    expect(formulaCell.metadata['data-formula'], '=A1+B1');
    expect(formulaCell.metadata['title'], 'Formula: =A1+B1');

    final encoded = codec.encode(doc);
    expect(encoded.contains('data-formula="=A1+B1"'), isTrue);
    expect(encoded.contains('title="Formula: =A1+B1"'), isTrue);
  });

  test('Table formula roundtrip reload from saved database HTML test', () {
    const codec = HtmlDocumentCodec();
    // Simulate HTML saved to database with formula and fx badge
    const savedHtmlFromDb = '<figure class="table"><table><tbody><tr><td>23</td></tr><tr><td>1</td></tr><tr><td data-formula="=SUM(A1+A2)" title="Formula: =SUM(A1+A2) (Click fx to edit)" class="has-formula"><p><strong data-formula="=SUM(A1+A2)">24</strong> <span class="formula-badge" data-formula="=SUM(A1+A2)" title="Formula: =SUM(A1+A2)">fx</span></p></td></tr></tbody></table></figure>';

    // 1. App fetches from database and loads into codec/controller
    final doc = codec.decode(savedHtmlFromDb);
    final tableNode = doc.nodes.first;
    final row3 = tableNode.children[2];
    final formulaCell = row3.children[0];

    // Verify formula is perfectly decoded
    expect(formulaCell.metadata['data-formula'], '=SUM(A1+A2)');
    expect(formulaCell.metadata['title'], 'Formula: =SUM(A1+A2) (Click fx to edit)');

    // 2. Controller encodes HTML for CKEditor iframe initialContent
    final reloadedHtml = codec.encode(doc);
    expect(reloadedHtml.contains('data-formula="=SUM(A1+A2)"'), isTrue);
    expect(reloadedHtml.contains('title="Formula: =SUM(A1+A2) (Click fx to edit)"'), isTrue);

    // 3. Fallback test: even if data-formula attribute was missing but child badge has it
    const htmlWithChildBadgeOnly = '<figure class="table"><table><tbody><tr><td>23</td></tr><tr><td>1</td></tr><tr><td><p><strong>24</strong> <span class="formula-badge" data-formula="=SUM(A1+A2)" title="Formula: =SUM(A1+A2)">fx</span></p></td></tr></tbody></table></figure>';
    final docFallback = codec.decode(htmlWithChildBadgeOnly);
    final fallbackCell = docFallback.nodes.first.children[2].children[0];
    expect(fallbackCell.metadata['data-formula'], '=SUM(A1+A2)');

    // 4. Fallback test: even if only title has Formula:
    const htmlWithTitleOnly = '<figure class="table"><table><tbody><tr><td>23</td></tr><tr><td>1</td></tr><tr><td title="Formula: =SUM(A1+A2) (Click fx to edit)"><p><strong>24</strong></p></td></tr></tbody></table></figure>';
    final docTitleFallback = codec.decode(htmlWithTitleOnly);
    final titleCell = docTitleFallback.nodes.first.children[2].children[0];
    expect(titleCell.metadata['data-formula'], '=SUM(A1+A2)');
  });

  test('Table formula A1+A2 SUM with cell references in description roundtrip test', () {
    const codec = HtmlDocumentCodec();
    const html = '''
<figure class="table"><table><tbody>
<tr><td>34</td></tr>
<tr><td>32</td></tr>
<tr><td data-formula="=SUM(A1+A2)" data-formula-val="66" title="Formula: =SUM(A1+A2)" class="has-formula"><p><strong>66</strong></p></td></tr>
</tbody></table></figure>
<p>The values are <span class="mention table-cell-ref" data-mention="\$A1" data-cell-coord="A1">34</span> and <span class="mention table-cell-ref" data-mention="\$A2" data-cell-coord="A2">32</span>, sum is <span class="mention table-cell-ref" data-mention="\$A3" data-cell-coord="A3">66</span>.</p>
''';
    final doc = codec.decode(html);
    final encoded = codec.encode(doc);

    // Verify formula, formula-val, and cell references are fully preserved
    expect(encoded.contains('data-formula="=SUM(A1+A2)"'), isTrue);
    expect(encoded.contains('data-formula-val="66"'), isTrue);
    expect(encoded.contains('data-cell-coord="A1"'), isTrue);
    expect(encoded.contains('data-cell-coord="A2"'), isTrue);
    expect(encoded.contains('data-cell-coord="A3"'), isTrue);
  });

  test('Table column widths (colgroup) survive a decode/encode round-trip', () {
    const codec = HtmlDocumentCodec();
    const inputHtml = '<figure class="table"><table class="ck-table-resized"><colgroup><col style="width:20%;"><col style="width:30%;"><col style="width:50%;"></colgroup><tbody><tr><td>A1</td><td>B1</td><td>C1</td></tr></tbody></table></figure>';
    final encoded = codec.encode(codec.decode(inputHtml));
    expect(encoded.contains('<colgroup><col style="width:20%;"><col style="width:30%;"><col style="width:50%;"></colgroup>'), isTrue);
    expect(encoded.indexOf('<colgroup>') < encoded.indexOf('<tbody>'), isTrue);
  });
}
