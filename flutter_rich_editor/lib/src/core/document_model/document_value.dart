import 'package:flutter/foundation.dart';
import 'editor_node.dart';
import 'editor_selection.dart';

/// Represents an immutable snapshot of an editor document.
@immutable
class DocumentValue {
  const DocumentValue({
    required this.nodes,
    this.selection = const EditorSelection.collapsed(0),
    this.schemaVersion = 1,
    this.metadata = const <String, dynamic>{},
  });

  /// The root block nodes that form the document.
  final List<EditorNode> nodes;

  /// The active selection or cursor position.
  final EditorSelection selection;

  /// Schema version for forward/backward compatibility.
  final int schemaVersion;

  /// Document-level metadata (e.g. title, author, created timestamp).
  final Map<String, dynamic> metadata;

  /// Returns an empty document with a single empty paragraph.
  factory DocumentValue.empty() {
    return DocumentValue(
      nodes: <EditorNode>[
        EditorNode.paragraph(id: 'root_0', text: ''),
      ],
      selection: const EditorSelection.collapsed(0),
    );
  }

  /// Returns the combined plain text of all nodes.
  String get plainText {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < nodes.length; i++) {
      buffer.write(_extractText(nodes[i]));
      if (i < nodes.length - 1) {
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  /// Convenience method for plain text extraction.
  String toPlainText() => plainText;

  static String _extractText(EditorNode node) {
    if (node.text.isNotEmpty) {
      return node.text;
    }
    if (node.children.isNotEmpty) {
      return node.children.map(_extractText).join('\t');
    }
    return '';
  }

  bool get isEmpty =>
      nodes.isEmpty || (nodes.length == 1 && nodes.first.text.isEmpty && nodes.first.children.isEmpty);

  bool get isNotEmpty => !isEmpty;

  int get length => plainText.length;

  /// Creates a copy with optional property updates.
  DocumentValue copyWith({
    List<EditorNode>? nodes,
    EditorSelection? selection,
    int? schemaVersion,
    Map<String, dynamic>? metadata,
  }) {
    return DocumentValue(
      nodes: nodes != null
          ? List<EditorNode>.from(nodes)
          : List<EditorNode>.from(this.nodes),
      selection: selection ?? this.selection,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      metadata: metadata != null
          ? Map<String, dynamic>.from(metadata)
          : Map<String, dynamic>.from(this.metadata),
    );
  }

  /// Serializes to the versioned canonical JSON tree format.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'metadata': metadata,
      'selection': selection.toJson(),
      'nodes': nodes.map((EditorNode n) => n.toJson()).toList(),
    };
  }

  /// Deserializes from canonical JSON. Unknown nodes are preserved gracefully.
  factory DocumentValue.fromJson(Map<String, dynamic> json) {
    final int version = (json['schemaVersion'] as num?)?.toInt() ?? 1;
    final Map<String, dynamic> meta = json['metadata'] != null
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : const <String, dynamic>{};

    final EditorSelection sel = json['selection'] != null
        ? EditorSelection.fromJson(Map<String, dynamic>.from(json['selection'] as Map))
        : const EditorSelection.collapsed(0);

    final List<dynamic>? rawNodes = json['nodes'] as List<dynamic>?;
    final List<EditorNode> nodeList = rawNodes != null
        ? rawNodes
            .whereType<Map<dynamic, dynamic>>()
            .map((dynamic item) =>
                EditorNode.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList()
        : <EditorNode>[EditorNode.paragraph(id: 'node_0', text: '')];

    return DocumentValue(
      nodes: nodeList.isEmpty
          ? <EditorNode>[EditorNode.paragraph(id: 'node_0', text: '')]
          : nodeList,
      selection: sel,
      schemaVersion: version,
      metadata: meta,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentValue &&
          runtimeType == other.runtimeType &&
          schemaVersion == other.schemaVersion &&
          selection == other.selection &&
          mapEquals(metadata, other.metadata) &&
          listEquals(nodes, other.nodes);

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        selection,
        Object.hashAll(metadata.entries),
        Object.hashAll(nodes),
      );

  @override
  String toString() =>
      'DocumentValue(nodes: ${nodes.length}, selection: $selection, version: $schemaVersion)';
}
