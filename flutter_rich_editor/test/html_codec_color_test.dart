import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rich_editor/src/serialization/html_codec.dart';

void main() {
  test('border-color is not read as text color', () {
    const codec = HtmlDocumentCodec();
    final doc = codec.decode('<p style="border-color: #00ff00; color: #0000ff;">Hi</p><p style="border-color: #ff0000;">Yo</p>');
    final nodes = doc.nodes;
    expect(nodes[0].attributes['color'], '#0000ff');
    expect(nodes[1].attributes['color'], isNull);
  });
}
