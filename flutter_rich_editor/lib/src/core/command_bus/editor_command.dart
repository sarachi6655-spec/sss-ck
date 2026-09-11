import 'package:flutter/foundation.dart';

import '../document_model/document_model.dart';
import '../plugin_system/plugin.dart';

/// Base class for all editor commands.
///
/// Commands are the sole mutation path for the document. Every toolbar action,
/// keyboard shortcut, paste handler, provider, and programmatic API call must
/// create and execute a command through the command bus.
abstract class EditorCommand {
  const EditorCommand();

  /// Stable command identifier. Must match the id registered in the plugin
  /// registry.
  String get id;

  /// Execute the command and return the new document state.
  EditorCommandResult execute(EditorCommandContext context);

  /// Undo the command given the previous document snapshot.
  EditorCommandResult undo(
    EditorCommandContext context,
    DocumentValue previousDocument,
  );
}

/// Result of command execution.
@immutable
class EditorCommandResult {
  final bool success;
  final DocumentValue? document;
  final EditorSelection? selection;
  final String? errorCode;
  final String? errorMessage;

  const EditorCommandResult.success({
    required this.document,
    this.selection,
  })  : success = true,
        errorCode = null,
        errorMessage = null;

  const EditorCommandResult.failure({
    required this.errorCode,
    this.errorMessage,
  })  : success = false,
        document = null,
        selection = null;

  /// Convenience copy with a replaced document.
  EditorCommandResult withDocument(DocumentValue document) =>
      EditorCommandResult.success(document: document, selection: selection);
}

/// Factory that builds a command from its arguments.
typedef EditorCommandFactory = EditorCommand Function(
    Map<String, dynamic> arguments);

/// Exception thrown by the command bus when execution fails.
class EditorCommandException implements Exception {
  final String commandId;
  final String errorCode;
  final String? message;

  const EditorCommandException({
    required this.commandId,
    required this.errorCode,
    this.message,
  });

  @override
  String toString() =>
      'EditorCommandException($commandId, $errorCode): $message';
}
