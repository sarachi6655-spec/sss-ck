import '../core/document_model/document_value.dart';
import '../core/document_model/editor_node.dart';

/// Interoperability codec for migrating content from Quill Delta format to [DocumentValue].
class DeltaDocumentCodec {
  const DeltaDocumentCodec();

  /// Converts Quill Delta operations to a [DocumentValue].
  DocumentValue decode(List<dynamic> deltaOps) {
    final List<EditorNode> nodes = <EditorNode>[];
    StringBuffer currentLine = StringBuffer();
    Map<String, dynamic> currentAttributes = <String, dynamic>{};
    int nodeCounter = 0;

    for (final dynamic op in deltaOps) {
      if (op is! Map) continue;
      final dynamic insert = op['insert'];
      final Map<String, dynamic> attrs = op['attributes'] != null
          ? Map<String, dynamic>.from(op['attributes'] as Map)
          : <String, dynamic>{};

      if (insert is String) {
        final List<String> parts = insert.split('\n');
        for (int i = 0; i < parts.length; i++) {
          final String part = parts[i];
          currentLine.write(part);
          if (part.isNotEmpty && attrs.isNotEmpty) {
            currentAttributes.addAll(attrs);
          }

          // If there is a newline, commit the line as a node
          if (i < parts.length - 1) {
            if (attrs.isNotEmpty) {
              currentAttributes.addAll(attrs);
            }
            final String lineText = currentLine.toString();
            final String nodeType = _resolveNodeType(currentAttributes);

            if (nodeType == 'heading') {
              final int level = (currentAttributes['header'] as num?)?.toInt() ?? 1;
              nodes.add(EditorNode.heading(
                id: 'migrated_${nodeCounter++}',
                text: lineText,
                level: level,
                attributes: _cleanInlineAttributes(currentAttributes),
              ));
            } else if (nodeType == 'list') {
              final String listType = currentAttributes['list'] == 'ordered' ? 'numbered' : 'bullet';
              nodes.add(EditorNode.listItem(
                id: 'migrated_${nodeCounter++}',
                text: lineText,
                listType: listType,
                attributes: _cleanInlineAttributes(currentAttributes),
              ));
            } else if (nodeType == 'blockquote') {
              nodes.add(EditorNode(
                id: 'migrated_${nodeCounter++}',
                type: 'blockquote',
                text: lineText,
                attributes: _cleanInlineAttributes(currentAttributes),
              ));
            } else if (nodeType == 'code_block') {
              nodes.add(EditorNode.codeBlock(
                id: 'migrated_${nodeCounter++}',
                code: lineText,
              ));
            } else {
              nodes.add(EditorNode.paragraph(
                id: 'migrated_${nodeCounter++}',
                text: lineText,
                attributes: _cleanInlineAttributes(currentAttributes),
              ));
            }

            currentLine = StringBuffer();
            currentAttributes = <String, dynamic>{};
          }
        }
      } else if (insert is Map) {
        // Embeds: image, video, etc.
        if (insert.containsKey('image')) {
          nodes.add(EditorNode.image(
            id: 'migrated_${nodeCounter++}',
            url: insert['image'].toString(),
          ));
        } else if (insert.containsKey('video')) {
          nodes.add(EditorNode.video(
            id: 'migrated_${nodeCounter++}',
            url: insert['video'].toString(),
          ));
        }
      }
    }

    if (currentLine.isNotEmpty) {
      nodes.add(EditorNode.paragraph(
        id: 'migrated_${nodeCounter++}',
        text: currentLine.toString(),
        attributes: _cleanInlineAttributes(currentAttributes),
      ));
    }

    if (nodes.isEmpty) {
      return DocumentValue.empty();
    }

    return DocumentValue(nodes: nodes);
  }

  /// Converts a [DocumentValue] back to Quill Delta operations.
  List<Map<String, dynamic>> encode(DocumentValue document) {
    final List<Map<String, dynamic>> ops = <Map<String, dynamic>>[];

    for (final EditorNode node in document.nodes) {
      switch (node.type) {
        case 'heading':
          final int level = (node.metadata['level'] as num?)?.toInt() ?? 1;
          if (node.text.isNotEmpty) {
            ops.add(<String, dynamic>{
              'insert': node.text,
              if (node.attributes.isNotEmpty) 'attributes': node.attributes,
            });
          }
          ops.add(<String, dynamic>{
            'insert': '\n',
            'attributes': <String, dynamic>{'header': level},
          });
          break;

        case 'list':
          final String listType = node.metadata['listType'] as String? ?? 'bullet';
          if (node.text.isNotEmpty) {
            ops.add(<String, dynamic>{
              'insert': node.text,
              if (node.attributes.isNotEmpty) 'attributes': node.attributes,
            });
          }
          ops.add(<String, dynamic>{
            'insert': '\n',
            'attributes': <String, dynamic>{
              'list': listType == 'numbered' ? 'ordered' : 'bullet',
            },
          });
          break;

        case 'blockquote':
          if (node.text.isNotEmpty) {
            ops.add(<String, dynamic>{
              'insert': node.text,
              if (node.attributes.isNotEmpty) 'attributes': node.attributes,
            });
          }
          ops.add(<String, dynamic>{
            'insert': '\n',
            'attributes': <String, dynamic>{'blockquote': true},
          });
          break;

        case 'code_block':
          ops.add(<String, dynamic>{
            'insert': node.text,
          });
          ops.add(<String, dynamic>{
            'insert': '\n',
            'attributes': <String, dynamic>{'code-block': true},
          });
          break;

        case 'image':
          ops.add(<String, dynamic>{
            'insert': <String, dynamic>{'image': node.metadata['url'] ?? ''},
          });
          ops.add(<String, dynamic>{'insert': '\n'});
          break;

        case 'video':
          ops.add(<String, dynamic>{
            'insert': <String, dynamic>{'video': node.metadata['url'] ?? ''},
          });
          ops.add(<String, dynamic>{'insert': '\n'});
          break;

        case 'paragraph':
        default:
          if (node.text.isNotEmpty) {
            ops.add(<String, dynamic>{
              'insert': node.text,
              if (node.attributes.isNotEmpty) 'attributes': node.attributes,
            });
          }
          ops.add(<String, dynamic>{'insert': '\n'});
          break;
      }
    }

    return ops;
  }

  String _resolveNodeType(Map<String, dynamic> attrs) {
    if (attrs.containsKey('header')) return 'heading';
    if (attrs.containsKey('list')) return 'list';
    if (attrs.containsKey('blockquote')) return 'blockquote';
    if (attrs.containsKey('code-block')) return 'code_block';
    return 'paragraph';
  }

  Map<String, dynamic> _cleanInlineAttributes(Map<String, dynamic> attrs) {
    final Map<String, dynamic> clean = Map<String, dynamic>.from(attrs);
    clean.remove('header');
    clean.remove('list');
    clean.remove('blockquote');
    clean.remove('code-block');
    return clean;
  }
}
