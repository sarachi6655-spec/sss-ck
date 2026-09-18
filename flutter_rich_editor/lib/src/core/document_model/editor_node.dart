import 'package:flutter/foundation.dart';

/// Base model for any content node in the rich text document tree.
@immutable
class EditorNode {
  const EditorNode({
    required this.id,
    required this.type,
    this.text = '',
    this.attributes = const <String, dynamic>{},
    this.metadata = const <String, dynamic>{},
    this.children = const <EditorNode>[],
  });

  /// Stable unique identifier for the node.
  final String id;

  /// Node type: 'paragraph', 'heading', 'list', 'blockquote', 'hr',
  /// 'code_block', 'table', 'table_row', 'table_cell', 'image', 'video', 'embed', 'custom'
  final String type;

  /// Plain text content if this is a text-bearing node.
  final String text;

  /// Inline formatting marks or attributes (bold, italic, color, align, etc.).
  final Map<String, dynamic> attributes;

  /// Block-level metadata (e.g. heading level, list type, code language, alt text, url).
  final Map<String, dynamic> metadata;

  /// Child nodes for composite structures (e.g. table rows, nested list items).
  final List<EditorNode> children;

  /// Returns true if this node represents a block-level container.
  bool get isBlock =>
      type == 'paragraph' ||
      type == 'heading' ||
      type == 'list' ||
      type == 'blockquote' ||
      type == 'hr' ||
      type == 'code_block' ||
      type == 'table' ||
      type == 'image' ||
      type == 'video' ||
      type == 'embed';

  /// Returns true if this node contains nested children.
  bool get hasChildren => children.isNotEmpty;

  /// Creates a deep copy of this node with optional modifications.
  EditorNode copyWith({
    String? id,
    String? type,
    String? text,
    Map<String, dynamic>? attributes,
    Map<String, dynamic>? metadata,
    List<EditorNode>? children,
  }) {
    return EditorNode(
      id: id ?? this.id,
      type: type ?? this.type,
      text: text ?? this.text,
      attributes: attributes != null
          ? Map<String, dynamic>.from(attributes)
          : Map<String, dynamic>.from(this.attributes),
      metadata: metadata != null
          ? Map<String, dynamic>.from(metadata)
          : Map<String, dynamic>.from(this.metadata),
      children: children != null
          ? List<EditorNode>.from(children)
          : childrenCopy(this.children),
    );
  }

  static List<EditorNode> childrenCopy(List<EditorNode> list) {
    return list.map((EditorNode child) => child.copyWith()).toList();
  }

  /// Serializes the node into a canonical JSON representation.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type,
      if (text.isNotEmpty) 'text': text,
      if (attributes.isNotEmpty) 'attributes': attributes,
      if (metadata.isNotEmpty) 'metadata': metadata,
      if (children.isNotEmpty)
        'children': children.map((EditorNode c) => c.toJson()).toList(),
    };
  }

  /// Deserializes a node from canonical JSON. Unknown node types are preserved.
  factory EditorNode.fromJson(Map<String, dynamic> json) {
    return EditorNode(
      id: json['id'] as String? ?? UniqueKey().toString(),
      type: json['type'] as String? ?? 'paragraph',
      text: json['text'] as String? ?? '',
      attributes: json['attributes'] != null
          ? Map<String, dynamic>.from(json['attributes'] as Map)
          : const <String, dynamic>{},
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : const <String, dynamic>{},
      children: json['children'] != null
          ? (json['children'] as List)
              .whereType<Map<dynamic, dynamic>>()
              .map((dynamic item) => EditorNode.fromJson(
                  Map<String, dynamic>.from(item as Map)))
              .toList()
          : const <EditorNode>[],
    );
  }

  /// Helper factory for a paragraph node.
  factory EditorNode.paragraph({
    required String id,
    String text = '',
    Map<String, dynamic> attributes = const <String, dynamic>{},
  }) {
    return EditorNode(
      id: id,
      type: 'paragraph',
      text: text,
      attributes: attributes,
    );
  }

  /// Helper factory for a heading node.
  factory EditorNode.heading({
    required String id,
    String text = '',
    int level = 1,
    Map<String, dynamic> attributes = const <String, dynamic>{},
  }) {
    return EditorNode(
      id: id,
      type: 'heading',
      text: text,
      metadata: <String, dynamic>{'level': level},
      attributes: attributes,
    );
  }

  /// Helper factory for a list item node.
  factory EditorNode.listItem({
    required String id,
    String text = '',
    String listType = 'bullet', // 'bullet', 'numbered', 'todo'
    int indent = 0,
    bool checked = false,
    Map<String, dynamic> attributes = const <String, dynamic>{},
    List<EditorNode> children = const <EditorNode>[],
  }) {
    return EditorNode(
      id: id,
      type: 'list',
      text: text,
      metadata: <String, dynamic>{
        'listType': listType,
        'indent': indent,
        'checked': checked,
      },
      attributes: attributes,
      children: children,
    );
  }

  /// Helper factory for a code block node.
  factory EditorNode.codeBlock({
    required String id,
    String code = '',
    String language = 'plaintext',
  }) {
    return EditorNode(
      id: id,
      type: 'code_block',
      text: code,
      metadata: <String, dynamic>{'language': language},
    );
  }

  /// Helper factory for an image node.
  factory EditorNode.image({
    required String id,
    required String url,
    String alt = '',
    String caption = '',
    double? width,
    double? height,
  }) {
    return EditorNode(
      id: id,
      type: 'image',
      metadata: <String, dynamic>{
        'url': url,
        'alt': alt,
        'caption': caption,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      },
    );
  }

  /// Helper factory for a video node.
  factory EditorNode.video({
    required String id,
    required String url,
    String poster = '',
    double? width,
    double? height,
    String uploadState = 'ready', // 'ready', 'uploading', 'error'
    double progress = 1.0,
    Map<String, dynamic>? metadata,
  }) {
    return EditorNode(
      id: id,
      type: 'video',
      metadata: <String, dynamic>{
        'url': url,
        'poster': poster,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        'uploadState': uploadState,
        'progress': progress,
        if (metadata != null) ...metadata,
      },
    );
  }

  /// Helper factory for a table node.
  factory EditorNode.table({
    required String id,
    required int rows,
    required int columns,
    List<EditorNode>? rowNodes,
    String caption = '',
  }) {
    final List<EditorNode> builtRows = rowNodes ??
        List<EditorNode>.generate(rows, (int r) {
          return EditorNode(
            id: '${id}_row_$r',
            type: 'table_row',
            children: List<EditorNode>.generate(columns, (int c) {
              return EditorNode(
                id: '${id}_cell_${r}_$c',
                type: 'table_cell',
                text: '',
              );
            }),
          );
        });

    return EditorNode(
      id: id,
      type: 'table',
      metadata: <String, dynamic>{
        'rows': rows,
        'columns': columns,
        'caption': caption,
      },
      children: builtRows,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorNode &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          text == other.text &&
          mapEquals(attributes, other.attributes) &&
          mapEquals(metadata, other.metadata) &&
          listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(
        id,
        type,
        text,
        Object.hashAll(attributes.entries),
        Object.hashAll(metadata.entries),
        Object.hashAll(children),
      );

  @override
  String toString() =>
      'EditorNode(id: $id, type: $type, text: ${text.length > 20 ? '${text.substring(0, 20)}...' : text})';
}
