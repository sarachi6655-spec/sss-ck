import 'package:flutter/foundation.dart';

import 'editor_node.dart';

/// Paragraph node containing inline text spans with marks.
@immutable
class ParagraphNode extends EditorNode {
  @override
  final String id;
  @override
  final Map<String, dynamic> attributes;
  final List<TextSpanNode> spans;

  const ParagraphNode({
    required this.id,
    this.attributes = const <String, dynamic>{},
    this.spans = const <TextSpanNode>[],
  });

  factory ParagraphNode.empty({
    required String id,
    Map<String, dynamic> attributes = const <String, dynamic>{},
  }) =>
      ParagraphNode(id: id, attributes: attributes, spans: const <TextSpanNode>[]);

  factory ParagraphNode.fromText({
    required String id,
    required String text,
    Map<String, dynamic> attributes = const <String, dynamic>{},
    Set<String> marks = const <String>{},
  }) =>
      ParagraphNode(
        id: id,
        attributes: attributes,
        spans: <TextSpanNode>[TextSpanNode(text: text, marks: marks)],
      );

  @override
  String get type => 'paragraph';

  @override
  String get plainText => spans.map((TextSpanNode s) => s.text).join();

  bool get isEmpty => plainText.isEmpty;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        'id': id,
        if (attributes.isNotEmpty) 'attributes': attributes,
        'spans': spans.map((TextSpanNode s) => s.toJson()).toList(),
      };

  factory ParagraphNode.fromJson(Map<String, dynamic> json) => ParagraphNode(
        id: json['id'] as String,
        attributes: (json['attributes'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
        spans: (json['spans'] as List<dynamic>?)
                ?.map((dynamic s) =>
                    TextSpanNode.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const <TextSpanNode>[],
      );

  @override
  ParagraphNode copyWith({
    String? id,
    Map<String, dynamic>? attributes,
    List<TextSpanNode>? spans,
  }) =>
      ParagraphNode(
        id: id ?? this.id,
        attributes: attributes ?? this.attributes,
        spans: spans ?? this.spans,
      );

  /// Build a copy with [mark] toggled across all spans in [range].
  ParagraphNode toggleMark(String mark, {int? start, int? end}) {
    final int s = start ?? 0;
    final int e = end ?? plainText.length;
    if (s >= e || spans.isEmpty) return this;

    final List<TextSpanNode> newSpans = <TextSpanNode>[];
    int offset = 0;
    bool markExists = false;

    for (final TextSpanNode span in spans) {
      final int spanStart = offset;
      final int spanEnd = offset + span.text.length;
      offset = spanEnd;

      final int clampStart = s.clamp(spanStart, spanEnd);
      final int clampEnd = e.clamp(spanStart, spanEnd);

      if (clampStart >= clampEnd) {
        newSpans.add(span);
        continue;
      }

      if (span.marks.contains(mark)) {
        markExists = true;
      }

      final int localStart = clampStart - spanStart;
      final int localEnd = clampEnd - spanStart;

      if (localStart > 0) {
        newSpans.add(span.copyWith(text: span.text.substring(0, localStart)));
      }

      final String midText = span.text.substring(localStart, localEnd);
      final Set<String> newMarks = Set<String>.of(span.marks);
      if (markExists) {
        newMarks.remove(mark);
      } else {
        newMarks.add(mark);
      }
      newSpans.add(TextSpanNode(text: midText, marks: newMarks));

      if (localEnd < span.text.length) {
        newSpans
            .add(span.copyWith(text: span.text.substring(localEnd)));
      }
    }

    return copyWith(spans: _mergeSpans(newSpans));
  }

  /// Apply an attribute to the paragraph (alignment, indentation, line-height).
  ParagraphNode setAttribute(String key, dynamic value) {
    final Map<String, dynamic> newAttributes =
        Map<String, dynamic>.of(attributes);
    if (value == null) {
      newAttributes.remove(key);
    } else {
      newAttributes[key] = value;
    }
    return copyWith(attributes: newAttributes);
  }

  /// Insert text at [offset] with optional marks.
  ParagraphNode insertText(int offset, String text,
      {Set<String> marks = const <String>{}}) {
    if (text.isEmpty) return this;
    if (spans.isEmpty) {
      return copyWith(spans: <TextSpanNode>[TextSpanNode(text: text, marks: marks)]);
    }

    final List<TextSpanNode> newSpans = <TextSpanNode>[];
    int current = 0;
    bool inserted = false;
    for (final TextSpanNode span in spans) {
      final int spanStart = current;
      final int spanEnd = current + span.text.length;
      current = spanEnd;

      if (inserted || offset < spanStart || offset > spanEnd) {
        newSpans.add(span);
        continue;
      }

      final int localOffset = offset - spanStart;
      if (localOffset > 0) {
        newSpans.add(span.copyWith(text: span.text.substring(0, localOffset)));
      }
      newSpans.add(TextSpanNode(text: text, marks: span.marks));
      if (localOffset < span.text.length) {
        newSpans.add(
            span.copyWith(text: span.text.substring(localOffset)));
      }
      inserted = true;
    }

    return copyWith(spans: _mergeSpans(newSpans));
  }

  /// Delete text in [start,end).
  ParagraphNode deleteRange(int start, int end) {
    if (start >= end || spans.isEmpty) return this;
    final List<TextSpanNode> newSpans = <TextSpanNode>[];
    int offset = 0;
    for (final TextSpanNode span in spans) {
      final int spanStart = offset;
      final int spanEnd = offset + span.text.length;
      offset = spanEnd;

      final int clampStart = start.clamp(spanStart, spanEnd);
      final int clampEnd = end.clamp(spanStart, spanEnd);

      if (clampStart == spanStart && clampEnd == spanEnd) {
        continue;
      }

      final String before = clampStart > spanStart
          ? span.text.substring(0, clampStart - spanStart)
          : '';
      final String after = clampEnd < spanEnd
          ? span.text.substring(clampEnd - spanStart)
          : '';
      if (before.isNotEmpty || after.isNotEmpty) {
        newSpans.add(span.copyWith(text: before + after));
      }
    }
    return copyWith(spans: _mergeSpans(newSpans));
  }

  static List<TextSpanNode> _mergeSpans(List<TextSpanNode> spans) {
    if (spans.isEmpty) return spans;
    final List<TextSpanNode> merged = <TextSpanNode>[spans.first];
    for (int i = 1; i < spans.length; i++) {
      final TextSpanNode last = merged.last;
      final TextSpanNode current = spans[i];
      if (last.marks == current.marks && last.attributes == current.attributes) {
        merged[merged.length - 1] =
            last.copyWith(text: last.text + current.text);
      } else {
        merged.add(current);
      }
    }
    return merged;
  }
}
