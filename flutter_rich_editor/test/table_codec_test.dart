
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
  });
}
