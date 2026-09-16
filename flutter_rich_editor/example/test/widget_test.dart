import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rich_editor/flutter_rich_editor.dart';
import 'package:flutter_rich_editor_example/main.dart';

void main() {
  testWidgets('RichEditorDemoApp loads and renders editor showcase', (WidgetTester tester) async {
    await tester.pumpWidget(const RichEditorDemoApp());
    await tester.pumpAndSettle();

    expect(find.text('Flutter Rich Editor Showcase'), findsOneWidget);
    expect(find.byType(RichEditor), findsOneWidget);
    expect(find.byType(EditorToolbar), findsOneWidget);
  });
}

