import 'package:flutter/material.dart';
import '../../core/command_bus/editor_command.dart';
import '../../core/document_model/document_value.dart';
import '../../core/document_model/editor_node.dart';
import '../../core/document_model/editor_selection.dart';
import '../../core/plugin_system/plugin.dart';

/// Syntax highlighter interface for code blocks with fallback.
abstract class SyntaxHighlighter {
  const SyntaxHighlighter();

  /// Highlights [code] for [language]. Returns a [TextSpan] or null if language is unsupported.
  TextSpan? highlight(String code, String language);
}

/// A default syntax highlighter that provides basic keyword styling and falls back to plain text.
class DefaultSyntaxHighlighter extends SyntaxHighlighter {
  const DefaultSyntaxHighlighter();

  static const Set<String> _supportedLanguages = <String>{
    'dart',
    'javascript',
    'python',
    'json',
    'html',
    'css',
    'sql',
  };

  @override
  TextSpan? highlight(String code, String language) {
    if (!_supportedLanguages.contains(language.toLowerCase())) {
      // Fallback to plain text styling
      return null;
    }

    // Basic keyword highlighter for supported languages
    final List<TextSpan> spans = <TextSpan>[];
    final List<String> lines = code.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      if (line.trim().startsWith('//') || line.trim().startsWith('#')) {
        spans.add(TextSpan(
          text: line,
          style: const TextStyle(color: Color(0xFF6A9955), fontStyle: FontStyle.italic),
        ));
      } else {
        spans.add(TextSpan(text: line));
      }
      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return TextSpan(children: spans);
  }
}

/// Command to insert a code block.
class InsertCodeBlockCommand extends EditorCommand {
  const InsertCodeBlockCommand({
    this.code = '',
    this.language = 'plaintext',
  });

  final String code;
  final String language;

  @override
  String get id => 'code.insert';

  @override
  CommandResult execute(DocumentValue document) {
    final List<EditorNode> updated = List<EditorNode>.from(document.nodes);
    final EditorSelection sel = document.selection;
    final int insertPos = sel.nodeIndex >= 0 && sel.nodeIndex < updated.length
        ? sel.nodeIndex + 1
        : updated.length;

    final EditorNode codeNode = EditorNode.codeBlock(
      id: 'code_${DateTime.now().millisecondsSinceEpoch}',
      code: code,
      language: language,
    );

    updated.insert(insertPos, codeNode);

    return CommandResult.ok(document.copyWith(
      nodes: updated,
      selection: EditorSelection.collapsed(0, nodeIndex: insertPos),
    ));
  }
}

/// Plugin providing syntax-highlighted code blocks with editable fallback.
class CodeBlockPlugin extends EditorPlugin {
  const CodeBlockPlugin({
    this.highlighter = const DefaultSyntaxHighlighter(),
  });

  final SyntaxHighlighter highlighter;

  @override
  String get id => 'code.block';

  @override
  String get name => 'Code Block';

  @override
  List<EditorCommand> get commands => const <EditorCommand>[
        InsertCodeBlockCommand(),
      ];
}
