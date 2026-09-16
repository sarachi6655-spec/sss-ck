import 'package:flutter_rich_editor/flutter_rich_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RichEditorController Tests', () {
    test('test_controller_rejectsCommandsAfterDispose', () {
      final RichEditorController controller = RichEditorController();
      controller.dispose();

      expect(controller.isDisposed, true);

      expect(
        () => controller.execute(const FormatMarkCommand(mark: 'bold')),
        throwsA(isA<StateError>()),
      );

      expect(
        () => controller.undo(),
        throwsA(isA<StateError>()),
      );

      expect(
        () => controller.document,
        throwsA(isA<StateError>()),
      );
    });
  });
}
