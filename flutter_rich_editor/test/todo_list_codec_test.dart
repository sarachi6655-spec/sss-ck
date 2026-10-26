import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rich_editor/src/serialization/html_codec.dart';

void main() {
  const codec = HtmlDocumentCodec();

  test('To-do checked state is decoded from both CKEditor markup forms', () {
    // "with description" form, and the "without description" form CKEditor emits when the paragraph has attributes
    const html = '<ul class="todo-list">'
        '<li><label class="todo-list__label"><input type="checkbox" checked="checked" disabled="disabled">'
        '<span class="todo-list__label__description">done</span></label></li>'
        '<li><label class="todo-list__label"><input type="checkbox" disabled="disabled">'
        '<span class="todo-list__label__description">open</span></label></li>'
        '</ul>'
        '<ul class="todo-list" dir="ltr"><li><label class="todo-list__label todo-list__label_without-description">'
        '<input type="checkbox" checked="checked" disabled="disabled"></label><p dir="ltr">styled done</p></li></ul>';
    final nodes = codec.decode(html).nodes;

    expect(nodes.map((n) => n.metadata['listType']), everyElement('todo'));
    expect(nodes.map((n) => n.text), <String>['done', 'open', 'styled done']);
    expect(nodes.map((n) => n.metadata['checked']), <bool>[true, false, true]);
  });

  test('To-do items keep their checked state through decode/encode', () {
    const html = '<ul class="todo-list"><li><label class="todo-list__label">'
        '<input type="checkbox" checked="checked" disabled="disabled">'
        '<span class="todo-list__label__description">done</span></label></li></ul>';
    final encoded = codec.encode(codec.decode(html));

    expect(encoded, contains('class="todo-list"'));
    expect(encoded, contains('checked="checked"'));
    expect(encoded, contains('<span class="todo-list__label__description">done</span>'));
  });

  test('Plain bulleted lists are not treated as to-do lists', () {
    final nodes = codec.decode('<ul><li>a</li></ul>').nodes;
    expect(nodes.single.metadata['listType'], 'bullet');
    expect(nodes.single.metadata['checked'], false);
  });
}
