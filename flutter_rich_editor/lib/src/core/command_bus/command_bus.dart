import 'dart:collection';
import '../document_model/document_value.dart';
import 'editor_command.dart';

export 'editor_command.dart';

/// Entry representing an applied command in the undo stack.
class _HistoryEntry {
  _HistoryEntry({
    required this.command,
    required this.beforeSnapshot,
    required this.afterSnapshot,
  });

  final EditorCommand command;
  final DocumentValue beforeSnapshot;
  final DocumentValue afterSnapshot;
}

/// The command bus orchestrates document mutations, transactions, and undo/redo stacks.
class CommandBus {
  CommandBus({
    int maxHistory = 100,
  }) : _maxHistory = maxHistory;

  final int _maxHistory;
  final Map<String, EditorCommand> _registeredCommands = <String, EditorCommand>{};
  final List<_HistoryEntry> _undoStack = <_HistoryEntry>[];
  final List<_HistoryEntry> _redoStack = <_HistoryEntry>[];

  final List<void Function(EditorCommand command, CommandResult result)> _listeners =
      <void Function(EditorCommand, CommandResult)>[];

  /// Registers a command into the bus.
  /// Throws [ArgumentError] if a command with the same ID is already registered.
  void registerCommand(EditorCommand command) {
    if (_registeredCommands.containsKey(command.id)) {
      throw ArgumentError('A command with id "${command.id}" is already registered.');
    }
    _registeredCommands[command.id] = command;
  }

  /// Unregisters a command by ID.
  void unregisterCommand(String commandId) {
    _registeredCommands.remove(commandId);
  }

  /// Returns the registered command with [commandId], or null if not registered.
  EditorCommand? getCommand(String commandId) => _registeredCommands[commandId];

  /// Returns an unmodifiable map of registered commands.
  Map<String, EditorCommand> get registeredCommands =>
      UnmodifiableMapView<String, EditorCommand>(_registeredCommands);

  /// Returns true if undo is possible.
  bool get canUndo => _undoStack.isNotEmpty;

  /// Returns true if redo is possible.
  bool get canRedo => _redoStack.isNotEmpty;

  /// Clears the undo and redo history.
  void clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
  }

  /// Adds a listener for command executions.
  void addListener(void Function(EditorCommand command, CommandResult result) listener) {
    _listeners.add(listener);
  }

  /// Removes a listener.
  void removeListener(void Function(EditorCommand command, CommandResult result) listener) {
    _listeners.remove(listener);
  }

  /// Dispatches an [EditorCommand] against the [currentDocument].
  /// On success, pushes to the undo stack and clears redo stack.
  CommandResult execute(EditorCommand command, DocumentValue currentDocument) {
    if (!command.canExecute(currentDocument)) {
      final CommandResult failure = CommandResult.failure(
        currentDocument: currentDocument,
        code: 'command.cannot_execute',
        message: 'Command "${command.id}" cannot execute on the current document.',
      );
      _notifyListeners(command, failure);
      return failure;
    }

    final CommandResult result = command.execute(currentDocument);
    if (result.success) {
      _undoStack.add(_HistoryEntry(
        command: command,
        beforeSnapshot: currentDocument,
        afterSnapshot: result.document,
      ));
      if (_undoStack.length > _maxHistory) {
        _undoStack.removeAt(0);
      }
      _redoStack.clear();
    }

    _notifyListeners(command, result);
    return result;
  }

  /// Undoes the last command and restores the document to its state before execution.
  CommandResult? undo(DocumentValue currentDocument) {
    if (!canUndo) {
      return null;
    }

    final _HistoryEntry entry = _undoStack.removeLast();
    final CommandResult undoResult = entry.command.undo(currentDocument, entry.beforeSnapshot);

    if (undoResult.success) {
      _redoStack.add(entry);
    } else {
      // Re-insert if undo failed
      _undoStack.add(entry);
    }

    return undoResult;
  }

  /// Redoes the last undone command.
  CommandResult? redo(DocumentValue currentDocument) {
    if (!canRedo) {
      return null;
    }

    final _HistoryEntry entry = _redoStack.removeLast();
    final CommandResult redoResult = entry.command.execute(entry.beforeSnapshot);

    if (redoResult.success) {
      _undoStack.add(entry);
    } else {
      _redoStack.add(entry);
    }

    return redoResult;
  }

  void _notifyListeners(EditorCommand command, CommandResult result) {
    for (final void Function(EditorCommand, CommandResult) listener in List<void Function(EditorCommand, CommandResult)>.from(_listeners)) {
      listener(command, result);
    }
  }

  /// Disposes resources and listeners.
  void dispose() {
    _registeredCommands.clear();
    _undoStack.clear();
    _redoStack.clear();
    _listeners.clear();
  }
}
