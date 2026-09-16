
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
}
