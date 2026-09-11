import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Base class for every node in the canonical document tree.
///
/// Nodes are immutable value objects. All mutations happen through commands
/// which replace nodes in the document tree.
@immutable
abstract class EditorNode {
  const EditorNode();

  /// Stable node type string used for serialization and plugin registration.
  String get type;

  /// Stable node identifier. Preserved across undo/redo and serialization
  /// round-trips when possible.
  String get id;

  /// Arbitrary node-level metadata (alignment, language, level, etc.).
  Map<String, dynamic> get attributes;

  /// Inline text content used by paragraph-like nodes.
  /// Nodes that do not contain inline text return an empty string.
  String get plainText;

  /// Serialize to the canonical JSON representation.
  Map<String, dynamic> toJson();

  /// Create a copy with optional overrides.
  EditorNode copyWith({String? id, Map<String, dynamic>? attributes});
}

/// Inline span describing text and its marks (bold, italic, etc.).
@immutable
class TextSpanNode {
  final String text;
  final Set<String> marks;
  final Map<String, dynamic> attributes;

  const TextSpanNode({
    required this.text,
    this.marks = const <String>{},
    this.attributes = const <String, dynamic>{},
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        if (marks.isNotEmpty) 'marks': marks.toList(),
        if (attributes.isNotEmpty) 'attributes': attributes,
      };

  factory TextSpanNode.fromJson(Map<String, dynamic> json) => TextSpanNode(
        text: json['text'] as String? ?? '',
        marks: (json['marks'] as List<dynamic>?)
                ?.map((dynamic e) => e.toString())
                .toSet() ??
            const <String>{},
        attributes: (json['attributes'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
      );

  TextSpanNode copyWith({
    String? text,
    Set<String>? marks,
    Map<String, dynamic>? attributes,
  }) =>
      TextSpanNode(
        text: text ?? this.text,
        marks: marks ?? this.marks,
        attributes: attributes ?? this.attributes,
      );
}
