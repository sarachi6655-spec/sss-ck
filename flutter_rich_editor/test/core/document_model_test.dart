import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_rich_editor/src/core/document_model/document_model.dart';

void main() {
  group('DocumentValue', () {
    test('empty document has no nodes and version 1', () {
      const DocumentValue doc = DocumentValue.empty;
      expect(doc.nodes, isEmpty);
      expect(doc.version, 1);
    });

    test('copyWith overrides fields and preserves unspecified ones', () {
      const DocumentValue original = DocumentValue(
        nodes: <EditorNode>[],
        version: 2,
      );
      final DocumentValue copy = original.copyWith(version: 5);
      expect(copy.version, 5);
      expect(copy.nodes, original.nodes);
    });

    test('plainText joins node text with newline separator', () {
      final ParagraphNode p1 = ParagraphNode.fromText(
        id: 'a',
        text: 'hello',
      );
      final ParagraphNode p2 = ParagraphNode.fromText(
        id: 'b',
        text: 'world',
      );
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[p1, p2],
      );
      expect(doc.plainText, 'hello\nworld');
    });

    test('toJson encodes version and nodes', () {
      final ParagraphNode p1 = ParagraphNode.fromText(id: 'a', text: 'hi');
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[p1],
        version: 7,
      );
      final Map<String, dynamic> json = doc.toJson();
      expect(json['version'], 7);
      expect(json['nodes'], isA<List<dynamic>>());
      expect((json['nodes'] as List<dynamic>).length, 1);
    });

    test('fromJson decodes version and nodes with resolver', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'version': 3,
        'nodes': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'paragraph',
            'id': 'p1',
            'spans': <Map<String, dynamic>>[
              <String, dynamic>{'text': 'abc'},
            ],
          },
        ],
      };
      final DocumentValue doc = DocumentValue.fromJson(
        json,
        (Map<String, dynamic> n) => ParagraphNode.fromJson(n),
      );
      expect(doc.version, 3);
      expect(doc.nodes, hasLength(1));
      expect((doc.nodes.first as ParagraphNode).spans.first.text, 'abc');
    });

    test('fromJson defaults version to 1 when missing', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'nodes': <Map<String, dynamic>>[],
      };
      final DocumentValue doc = DocumentValue.fromJson(
        json,
        (Map<String, dynamic> n) => ParagraphNode.fromJson(n),
      );
      expect(doc.version, 1);
    });

    test('fromJson defaults nodes list to empty when missing', () {
      final DocumentValue doc = DocumentValue.fromJson(
        <String, dynamic>{'version': 2},
        (Map<String, dynamic> n) => ParagraphNode.fromJson(n),
      );
      expect(doc.nodes, isEmpty);
      expect(doc.version, 2);
    });
  });

  group('EditorSelection', () {
    test('collapsed selection has matching offsets and isCollapsed true', () {
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'n1',
        offset: 4,
      );
      expect(sel.startOffset, 4);
      expect(sel.endOffset, 4);
      expect(sel.isCollapsed, isTrue);
      expect(sel.hasSelection, isTrue);
      expect(sel.nodeId, 'n1');
    });

    test('range selection exposes start/end offsets', () {
      const EditorSelection sel = EditorSelection.range(
        nodeId: 'n2',
        startOffset: 2,
        endOffset: 8,
      );
      expect(sel.startOffset, 2);
      expect(sel.endOffset, 8);
      expect(sel.isCollapsed, isFalse);
      expect(sel.hasSelection, isTrue);
    });

    test('none selection has no node and no selection flag', () {
      const EditorSelection sel = EditorSelection.none();
      expect(sel.nodeId, isNull);
      expect(sel.hasSelection, isFalse);
      expect(sel.isCollapsed, isTrue);
    });

    test('copyWith overrides fields', () {
      const EditorSelection original = EditorSelection.collapsed(
        nodeId: 'n1',
        offset: 0,
      );
      final EditorSelection updated = original.copyWith(endOffset: 9);
      expect(updated.startOffset, 0);
      expect(updated.endOffset, 9);
    });

    test('toJson omits nodeId when null and includes offsets', () {
      const EditorSelection sel = EditorSelection.none();
      final Map<String, dynamic> json = sel.toJson();
      expect(json.containsKey('nodeId'), isFalse);
      expect(json['startOffset'], 0);
      expect(json['endOffset'], 0);
      expect(json['isCollapsed'], isTrue);
    });

    test('toJson includes nodeId when present', () {
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'n42',
        offset: 3,
      );
      final Map<String, dynamic> json = sel.toJson();
      expect(json['nodeId'], 'n42');
      expect(json['startOffset'], 3);
    });

    test('fromJson handles missing nodeId', () {
      final EditorSelection sel = EditorSelection.fromJson(
        <String, dynamic>{
          'startOffset': 0,
          'endOffset': 5,
        },
      );
      expect(sel.nodeId, isNull);
      expect(sel.endOffset, 5);
    });
  });

  group('TextSpanNode', () {
    test('toJson encodes text and omits empty marks/attributes', () {
      const TextSpanNode span = TextSpanNode(text: 'hi');
      final Map<String, dynamic> json = span.toJson();
      expect(json['text'], 'hi');
      expect(json.containsKey('marks'), isFalse);
      expect(json.containsKey('attributes'), isFalse);
    });

    test('toJson includes marks and attributes when present', () {
      const TextSpanNode span = TextSpanNode(
        text: 'x',
        marks: <String>{'bold'},
        attributes: <String, dynamic>{'color': 'red'},
      );
      final Map<String, dynamic> json = span.toJson();
      expect(json['marks'], <String>['bold']);
      expect(json['attributes'], <String, dynamic>{'color': 'red'});
    });

    test('fromJson defaults text to empty string when missing', () {
      final TextSpanNode span = TextSpanNode.fromJson(<String, dynamic>{});
      expect(span.text, '');
      expect(span.marks, isEmpty);
      expect(span.attributes, isEmpty);
    });

    test('fromJson parses marks and attributes correctly', () {
      final TextSpanNode span = TextSpanNode.fromJson(<String, dynamic>{
        'text': 't',
        'marks': <dynamic>['a', 'b'],
        'attributes': <String, dynamic>{'k': 'v'},
      });
      expect(span.text, 't');
      expect(span.marks, <String>{'a', 'b'});
      expect(span.attributes, <String, dynamic>{'k': 'v'});
    });

    test('copyWith overrides fields and preserves defaults', () {
      const TextSpanNode span = TextSpanNode(text: 'a', marks: <String>{'m'});
      final TextSpanNode copy = span.copyWith(text: 'b');
      expect(copy.text, 'b');
      expect(copy.marks, <String>{'m'});
    });
  });
}