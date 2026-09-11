import 'package:flutter/foundation.dart';

/// Selection within the document.
///
/// [nodeId] identifies the selected node. For inline text selections
/// [startOffset] and [endOffset] are byte/code-unit offsets into the node text.
/// For block nodes, offsets are typically ignored.
@immutable
class EditorSelection {
  final String? nodeId;
  final int startOffset;
  final int endOffset;
  final bool isCollapsed;

  const EditorSelection.collapsed({
    required this.nodeId,
    required int offset,
  })  : startOffset = offset,
        endOffset = offset,
        isCollapsed = true;

  const EditorSelection.range({
    required this.nodeId,
    required this.startOffset,
    required this.endOffset,
  }) : isCollapsed = false;

  const EditorSelection.none()
      : nodeId = null,
        startOffset = 0,
        endOffset = 0,
        isCollapsed = true;

  bool get hasSelection => nodeId != null;

  EditorSelection copyWith({
    String? nodeId,
    int? startOffset,
    int? endOffset,
    bool? isCollapsed,
  }) =>
      EditorSelection.range(
        nodeId: nodeId ?? this.nodeId,
        startOffset: startOffset ?? this.startOffset,
        endOffset: endOffset ?? this.endOffset,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (nodeId != null) 'nodeId': nodeId,
        'startOffset': startOffset,
        'endOffset': endOffset,
        'isCollapsed': isCollapsed,
      };

  factory EditorSelection.fromJson(Map<String, dynamic> json) =>
      EditorSelection.range(
        nodeId: json['nodeId'] as String?,
        startOffset: json['startOffset'] as int? ?? 0,
        endOffset: json['endOffset'] as int? ?? 0,
      );
}
