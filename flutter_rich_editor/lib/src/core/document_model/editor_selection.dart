import 'package:flutter/foundation.dart';

/// Represents a selection within an editor document or within a node.
@immutable
class EditorSelection {
  const EditorSelection({
    required this.baseOffset,
    required this.extentOffset,
    this.nodeIndex = 0,
    this.endNodeIndex,
  });

  const EditorSelection.collapsed(int offset, {int nodeIndex = 0})
      : this(
          baseOffset: offset,
          extentOffset: offset,
          nodeIndex: nodeIndex,
          endNodeIndex: nodeIndex,
        );

  final int baseOffset;
  final int extentOffset;
  final int nodeIndex;
  final int? endNodeIndex;

  int get actualEndNodeIndex => endNodeIndex ?? nodeIndex;

  bool get isCollapsed =>
      baseOffset == extentOffset && nodeIndex == actualEndNodeIndex;

  int get start => baseOffset <= extentOffset ? baseOffset : extentOffset;
  int get end => baseOffset <= extentOffset ? extentOffset : baseOffset;

  int get startNodeIndex =>
      nodeIndex <= actualEndNodeIndex ? nodeIndex : actualEndNodeIndex;
  int get endNodeIndexNormalized =>
      nodeIndex <= actualEndNodeIndex ? actualEndNodeIndex : nodeIndex;

  EditorSelection normalized() {
    if (baseOffset <= extentOffset && nodeIndex <= actualEndNodeIndex) {
      return this;
    }
    return EditorSelection(
      baseOffset: start,
      extentOffset: end,
      nodeIndex: startNodeIndex,
      endNodeIndex: endNodeIndexNormalized,
    );
  }

  EditorSelection copyWith({
    int? baseOffset,
    int? extentOffset,
    int? nodeIndex,
    int? endNodeIndex,
  }) {
    return EditorSelection(
      baseOffset: baseOffset ?? this.baseOffset,
      extentOffset: extentOffset ?? this.extentOffset,
      nodeIndex: nodeIndex ?? this.nodeIndex,
      endNodeIndex: endNodeIndex ?? this.endNodeIndex,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'baseOffset': baseOffset,
      'extentOffset': extentOffset,
      'nodeIndex': nodeIndex,
      'endNodeIndex': actualEndNodeIndex,
    };
  }

  factory EditorSelection.fromJson(Map<String, dynamic> json) {
    return EditorSelection(
      baseOffset: (json['baseOffset'] as num?)?.toInt() ?? 0,
      extentOffset: (json['extentOffset'] as num?)?.toInt() ?? 0,
      nodeIndex: (json['nodeIndex'] as num?)?.toInt() ?? 0,
      endNodeIndex: (json['endNodeIndex'] as num?)?.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorSelection &&
          runtimeType == other.runtimeType &&
          baseOffset == other.baseOffset &&
          extentOffset == other.extentOffset &&
          nodeIndex == other.nodeIndex &&
          actualEndNodeIndex == other.actualEndNodeIndex;

  @override
  int get hashCode => Object.hash(
        baseOffset,
        extentOffset,
        nodeIndex,
        actualEndNodeIndex,
      );

  @override
  String toString() =>
      'EditorSelection(node: $nodeIndex->$actualEndNodeIndex, offset: $baseOffset->$extentOffset)';
}
