import 'editor_node.dart';

/// Concrete node representing a standard paragraph block.
class ParagraphNode extends EditorNode {
  const ParagraphNode({
    required super.id,
    super.text = '',
    super.attributes = const <String, dynamic>{},
    super.metadata = const <String, dynamic>{},
    super.children = const <EditorNode>[],
  }) : super(type: 'paragraph');

  @override
  ParagraphNode copyWith({
    String? id,
    String? type,
    String? text,
    Map<String, dynamic>? attributes,
    Map<String, dynamic>? metadata,
    List<EditorNode>? children,
  }) {
    return ParagraphNode(
      id: id ?? this.id,
      text: text ?? this.text,
      attributes: attributes != null
          ? Map<String, dynamic>.from(attributes)
          : Map<String, dynamic>.from(this.attributes),
      metadata: metadata != null
          ? Map<String, dynamic>.from(metadata)
          : Map<String, dynamic>.from(this.metadata),
      children: children != null
          ? List<EditorNode>.from(children)
          : EditorNode.childrenCopy(this.children),
    );
  }
}
