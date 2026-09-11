import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_rich_editor/src/core/command_bus/command_bus.dart';
import 'package:flutter_rich_editor/src/core/document_model/document_model.dart';

void main() {
  group('EditorCommandResult', () {
    test('success has success=true, document, and no error', () {
      final DocumentValue doc = DocumentValue.empty;
      final EditorCommandResult r =
          EditorCommandResult.success(document: doc);
      expect(r.success, isTrue);
      expect(r.document, doc);
      expect(r.errorCode, isNull);
      expect(r.errorMessage, isNull);
    });

    test('success carries optional selection', () {
      final DocumentValue doc = DocumentValue.empty;
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'n',
        offset: 1,
      );
      final EditorCommandResult r = EditorCommandResult.success(
        document: doc,
        selection: sel,
      );
      expect(r.selection, sel);
    });

    test('failure has success=false, no document/selection, error code', () {
      final EditorCommandResult r = EditorCommandResult.failure(
        errorCode: 'oops',
        errorMessage: 'something went wrong',
      );
      expect(r.success, isFalse);
      expect(r.document, isNull);
      expect(r.selection, isNull);
      expect(r.errorCode, 'oops');
      expect(r.errorMessage, 'something went wrong');
    });

    test('withDocument replaces document and keeps selection', () {
      final DocumentValue doc1 = DocumentValue.empty;
      final DocumentValue doc2 = DocumentValue(
        nodes: <EditorNode>[],
        version: 2,
      );
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'n',
        offset: 0,
      );
      final EditorCommandResult original =
          EditorCommandResult.success(document: doc1, selection: sel);
      final EditorCommandResult updated = original.withDocument(doc2);
      expect(updated.document, doc2);
      expect(updated.selection, sel);
      expect(updated.success, isTrue);
    });

    test('withDocument on a failure result still produces a success result',
        () {
      // withDocument always returns EditorCommandResult.success.
      final EditorCommandResult failure = EditorCommandResult.failure(
        errorCode: 'x',
      );
      final DocumentValue doc = DocumentValue.empty;
      final EditorCommandResult r = failure.withDocument(doc);
      expect(r.success, isTrue);
      expect(r.document, doc);
    });
  });

  group('EditorCommandException', () {
    test('toString contains command id, error code, and message', () {
      const EditorCommandException e = EditorCommandException(
        commandId: 'cmd1',
        errorCode: 'fail',
        message: 'something bad',
      );
      final String s = e.toString();
      expect(s, contains('cmd1'));
      expect(s, contains('fail'));
      expect(s, contains('something bad'));
    });

    test('message is optional', () {
      const EditorCommandException e = EditorCommandException(
        commandId: 'cmd1',
        errorCode: 'fail',
      );
      expect(e.message, isNull);
    });
  });
}