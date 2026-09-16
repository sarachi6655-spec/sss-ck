import '../../core/command_bus/editor_command.dart';
import '../../core/document_model/document_value.dart';
import '../../core/document_model/editor_node.dart';
import '../../core/document_model/editor_selection.dart';
import '../../core/plugin_system/plugin.dart';

/// Sanitizer verifying Mermaid diagram syntax is secure from script injections.
class MermaidSanitizer {
  const MermaidSanitizer();

  static final List<RegExp> _unsafePatterns = <RegExp>[
    RegExp(r'<script\b', caseSensitive: false),
    RegExp(r'javascript:', caseSensitive: false),
    RegExp(r'onload\s*=', caseSensitive: false),
    RegExp(r'onerror\s*=', caseSensitive: false),
    RegExp(r'eval\s*\(', caseSensitive: false),
    RegExp(r'<iframe\b', caseSensitive: false),
  ];

  /// Returns true if the Mermaid source contains no prohibited injection payloads.
  bool isSafe(String mermaidSource) {
    for (final RegExp pattern in _unsafePatterns) {
      if (pattern.hasMatch(mermaidSource)) {
        return false;
      }
    }
    return true;
  }
}

/// Command to insert a sanitized Mermaid diagram block.
class InsertMermaidCommand extends EditorCommand {
  const InsertMermaidCommand({
    required this.diagramSource,
    this.sanitizer = const MermaidSanitizer(),
  });

  final String diagramSource;
  final MermaidSanitizer sanitizer;

  @override
  String get id => 'code.mermaid.insert';

  @override
  CommandResult execute(DocumentValue document) {
    if (!sanitizer.isSafe(diagramSource)) {
      return CommandResult.failure(
        currentDocument: document,
        code: 'mermaid.unsafe_input',
        message: 'The Mermaid diagram input contains prohibited or unsafe script constructs.',
      );
    }

    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorSelection sel = document.selection;
    final int insertPos = sel.nodeIndex >= 0 && sel.nodeIndex < updated.length
        ? sel.nodeIndex + 1
        : updated.length;

    final EditorNode mermaidNode = EditorNode(
      id: 'mermaid_${DateTime.now().millisecondsSinceEpoch}',
      type: 'mermaid',
      text: diagramSource,
    );

    updated.insert(insertPos, mermaidNode);

    return CommandResult.ok(document.copyWith(
      nodes: updated,
      selection: EditorSelection.collapsed(0, nodeIndex: insertPos),
    ));
  }
}

/// Plugin providing sanitized Mermaid diagram rendering.
class MermaidPlugin extends EditorPlugin {
  const MermaidPlugin({
    this.sanitizer = const MermaidSanitizer(),
  });

  final MermaidSanitizer sanitizer;

  @override
  String get id => 'code.mermaid';

  @override
  String get name => 'Mermaid Diagrams';

  @override
  List<EditorCommand> get commands => <EditorCommand>[
        InsertMermaidCommand(diagramSource: '', sanitizer: sanitizer),
      ];
}
