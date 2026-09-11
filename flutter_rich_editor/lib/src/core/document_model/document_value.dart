import 'package:flutter/foundation.dart';

import 'editor_node.dart';

/// Immutable snapshot of the editor document.
@immutable
class DocumentValue {
  final List<EditorNode> nodes;
  final int version;

  const DocumentValue({required this.nodes, this.version = 1});

  static const DocumentValue empty = DocumentValue(nodes: <EditorNode>[]);

  DocumentValue copyWith({List<EditorNode>? nodes, int? version}) =>
      DocumentValue(
        nodes: nodes ?? this.nodes,
        version: version ?? this.version,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'nodes': nodes.map((EditorNode n) => n.toJson()).toList(),
      };

  factory DocumentValue.fromJson(
    Map<String, dynamic> json,
    EditorNode Function(Map<String, dynamic>) nodeResolver,
  ) {
    final List<dynamic> rawNodes = json['nodes'] as List<dynamic>? ??
        const <dynamic>[];
    return DocumentValue(
      version: json['version'] as int? ?? 1,
      nodes: rawNodes
          .map((dynamic n) => nodeResolver(n as Map<String, dynamic>))
          .toList(),
    );
  }

  String get plainText => nodes.map((EditorNode n) => n.plainText).join('\n');
}
