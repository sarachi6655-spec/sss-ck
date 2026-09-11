import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_rich_editor/src/core/document_model/paragraph_node.dart';

void main() {
  group('ParagraphNode', () {
    test('paragraph type is paragraph', () {
      final ParagraphNode p = ParagraphNode.fromText(id: 'a', text: 'hi');
      expect(p.type, 'paragraph');
      expect(p.id, 'a');
      expect(p.attributes, isEmpty);
      expect(p.plainText, 'hi');
    });

    test('empty paragraph has empty plainText and isEmpty true', () {
      final ParagraphNode p = ParagraphNode.empty(id: 'a');
      expect(p.plainText, '');
      expect(p.isEmpty, isTrue);
      expect(p.spans, isEmpty);
    });

    test('fromText wraps text in a single span with given marks', () {
      final ParagraphNode p = ParagraphNode.fromText(
        id: 'p',
        text: 'hello',
        marks: <String>{'bold'},
      );
      expect(p.spans, hasLength(1));
      expect(p.spans.first.text, 'hello');
      expect(p.spans.first.marks, <String>{'bold'});
    });

    test('toJson excludes attributes when empty', () {
      final ParagraphNode p = ParagraphNode.fromText(id: 'a', text: 'hi');
      final Map<String, dynamic> json = p.toJson();
      expect(json['type'], 'paragraph');
      expect(json['id'], 'a');
      expect(json.containsKey('attributes'), isFalse);
      expect(json['spans'], isA<List<dynamic>>());
    });

    test('toJson includes attributes when present', () {
      final ParagraphNode p = ParagraphNode(
        id: 'a',
        attributes: <String, dynamic>{'align': 'center'},
        spans: const <TextSpanNode>[],
      );
      final Map<String, dynamic> json = p.toJson();
      expect(json['attributes'], <String, dynamic>{'align': 'center'});
    });

    test('fromJson reads id, attributes, and spans', () {
      final ParagraphNode p = ParagraphNode.fromJson(<String, dynamic>{
        'id': 'p1',
        'attributes': <String, dynamic>{'align': 'right'},
        'spans': <Map<String, dynamic>>[
          <String, dynamic>{'text': 'hi'},
        ],
      });
      expect(p.id, 'p1');
      expect(p.attributes, <String, dynamic>{'align': 'right'});
      expect(p.spans, hasLength(1));
      expect(p.spans.first.text, 'hi');
    });

    test('fromJson defaults attributes and spans when missing', () {
      final ParagraphNode p = ParagraphNode.fromJson(<String, dynamic>{
        'id': 'p2',
      });
      expect(p.attributes, isEmpty);
      expect(p.spans, isEmpty);
    });

    test('copyWith overrides id, attributes, and spans', () {
      final ParagraphNode original = ParagraphNode.fromText(id: 'a', text: 'x');
      final ParagraphNode copy = original.copyWith(id: 'b');
      expect(copy.id, 'b');
      expect(copy.spans, original.spans);
    });

    test('setAttribute adds and removes attribute when null', () {
      final ParagraphNode original = ParagraphNode.fromText(id: 'a', text: 'x');
      final ParagraphNode added = original.setAttribute('align', 'center');
      expect(added.attributes['align'], 'center');
      final ParagraphNode removed = added.setAttribute('align', null);
      expect(removed.attributes.containsKey('align'), isFalse);
    });

    test('toggleMark adds mark to range when not present', () {
      final ParagraphNode original = ParagraphNode.fromText(
        id: 'a',
        text: 'hello world',
      );
      final ParagraphNode updated =
          original.toggleMark('bold', start: 0, end: 5);
      // First span (0..5) should be bold; second span (6..11) should not.
      final List<TextSpanNode> newSpans = updated.spans;
      expect(newSpans.first.text, 'hello');
      expect(newSpans.first.marks.contains('bold'), isTrue);
      expect(newSpans.last.text, ' world');
      expect(newSpans.last.marks.contains('bold'), isFalse);
    });

    test('toggleMark removes mark when present', () {
      final ParagraphNode original = ParagraphNode(
        id: 'a',
        spans: const <TextSpanNode>[
          TextSpanNode(text: 'hi', marks: <String>{'bold'}),
        ],
      );
      final ParagraphNode updated =
          original.toggleMark('bold', start: 0, end: 2);
      // Both spans should have no bold after merge (since both contain it).
      for (final TextSpanNode s in updated.spans) {
        expect(s.marks.contains('bold'), isFalse);
      }
    });

    test('toggleMark is a no-op when range is empty or spans empty', () {
      final ParagraphNode empty = ParagraphNode.empty(id: 'a');
      expect(empty.toggleMark('bold'), same(empty));

      final ParagraphNode p = ParagraphNode.fromText(id: 'a', text: 'hi');
      // start == end -> no-op
      expect(p.toggleMark('bold', start: 2, end: 2), same(p));
    });

    test('insertText inserts at start of existing spans', () {
      final ParagraphNode original = ParagraphNode.fromText(
        id: 'a',
        text: 'world',
        marks: <String>{'bold'},
      );
      final ParagraphNode updated = original.insertText(0, 'hello ');
      expect(updated.plainText, 'hello world');
    });

    test('insertText inserts in the middle', () {
      final ParagraphNode original = ParagraphNode.fromText(
        id: 'a',
        text: 'hello world',
      );
      final ParagraphNode updated = original.insertText(5, ' cool');
      expect(updated.plainText, 'hello cool world');
    });

    test('insertText into empty paragraph initializes a span', () {
      final ParagraphNode original = ParagraphNode.empty(id: 'a');
      final ParagraphNode updated = original.insertText(0, 'hi');
      expect(updated.spans, hasLength(1));
      expect(updated.plainText, 'hi');
    });

    test('insertText with empty text is a no-op', () {
      final ParagraphNode original = ParagraphNode.fromText(id: 'a', text: 'hi');
      expect(original.insertText(0, ''), same(original));
    });

    test('deleteRange removes text in the middle', () {
      final ParagraphNode original = ParagraphNode.fromText(
        id: 'a',
        text: 'hello world',
      );
      final ParagraphNode updated = original.deleteRange(5, 6);
      expect(updated.plainText, 'helloworld');
    });

    test('deleteRange with full span removes it entirely', () {
      final ParagraphNode original = ParagraphNode.fromText(
        id: 'a',
        text: 'hi',
      );
      final ParagraphNode updated = original.deleteRange(0, 2);
      expect(updated.spans, isEmpty);
    });

    test('deleteRange is a no-op when start >= end', () {
      final ParagraphNode original = ParagraphNode.fromText(id: 'a', text: 'hi');
      expect(original.deleteRange(1, 1), same(original));
      expect(original.deleteRange(2, 1), same(original));
    });

    test('deleteRange with empty spans returns same', () {
      final ParagraphNode original = ParagraphNode.empty(id: 'a');
      expect(original.deleteRange(0, 1), same(original));
    });

    test('multiple operations merge adjacent spans with same marks', () {
      // After toggling, identical adjacent spans should merge.
      final ParagraphNode original = ParagraphNode.fromText(id: 'a', text: 'hi');
      final ParagraphNode updated = original.toggleMark('bold');
      // Without splits, both halves should have bold and merge.
      // The text is 'hi' (length 2), so start=0 end=2 -> single span with bold.
      expect(updated.spans, hasLength(1));
      expect(updated.spans.first.marks.contains('bold'), isTrue);
    });
  });
}