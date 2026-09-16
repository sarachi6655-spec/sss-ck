import 'package:flutter/foundation.dart';
import '../document_model/document_value.dart';

/// The result of executing or undoing an [EditorCommand].
@immutable
class CommandResult {
  const CommandResult({
    required this.success,
    required this.document,
    this.errorCode,
    this.errorMessage,
  });

  const CommandResult.ok(DocumentValue doc)
      : success = true,
        document = doc,
        errorCode = null,
        errorMessage = null;

  const CommandResult.failure({
    required DocumentValue currentDocument,
    required String code,
    String? message,
  })  : success = false,
        document = currentDocument,
        errorCode = code,
        errorMessage = message;

  final bool success;
  final DocumentValue document;
  final String? errorCode;
  final String? errorMessage;

  @override
  String toString() =>
      'CommandResult(success: $success, errorCode: $errorCode, error: $errorMessage)';
}

/// Abstract contract for any operation that mutates an editor document.
abstract class EditorCommand {
  const EditorCommand();

  /// Unique identifier of this command.
  String get id;

  /// Returns whether this command can execute against the given document state.
  bool canExecute(DocumentValue document) => true;

  /// Executes the mutation and returns the new document value.
  CommandResult execute(DocumentValue document);

  /// Reverses the mutation given the current document state and pre-execution snapshot.
  CommandResult undo(DocumentValue document, DocumentValue previousSnapshot) {
    return CommandResult.ok(previousSnapshot);
  }
}

/// A generic command wrapping an execution lambda.
class FunctionalCommand extends EditorCommand {
  FunctionalCommand({
    required this.id,
    required CommandResult Function(DocumentValue) onExecute,
    bool Function(DocumentValue)? onCanExecute,
    CommandResult Function(DocumentValue, DocumentValue)? onUndo,
  })  : _onExecute = onExecute,
        _onCanExecute = onCanExecute,
        _onUndo = onUndo;

  @override
  final String id;

  final CommandResult Function(DocumentValue) _onExecute;
  final bool Function(DocumentValue)? _onCanExecute;
  final CommandResult Function(DocumentValue, DocumentValue)? _onUndo;

  @override
  bool canExecute(DocumentValue document) =>
      _onCanExecute != null ? _onCanExecute(document) : true;

  @override
  CommandResult execute(DocumentValue document) => _onExecute(document);

  @override
  CommandResult undo(DocumentValue document, DocumentValue previousSnapshot) {
    if (_onUndo != null) {
      return _onUndo(document, previousSnapshot);
    }
    return super.undo(document, previousSnapshot);
  }
}
