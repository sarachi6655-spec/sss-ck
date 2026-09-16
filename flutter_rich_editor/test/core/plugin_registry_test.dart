import 'package:flutter_rich_editor/flutter_rich_editor.dart';
import 'package:flutter_test/flutter_test.dart';

class _SamplePluginA extends EditorPlugin {
  _SamplePluginA(this.onDisposed);
  final void Function(String) onDisposed;

  @override
  String get id => 'plugin.a';

  @override
  List<EditorCommand> get commands => <EditorCommand>[
        FunctionalCommand(
          id: 'cmd.sample',
          onExecute: (doc) => CommandResult.ok(doc),
        ),
      ];

  @override
  void dispose() {
    onDisposed(id);
    super.dispose();
  }
}

class _SamplePluginB extends EditorPlugin {
  _SamplePluginB(this.onDisposed);
  final void Function(String) onDisposed;

  @override
  String get id => 'plugin.b';

  @override
  List<EditorCommand> get commands => <EditorCommand>[
        FunctionalCommand(
          id: 'cmd.sample', // duplicate!
          onExecute: (doc) => CommandResult.ok(doc),
        ),
      ];

  @override
  void dispose() {
    onDisposed(id);
    super.dispose();
  }
}

class _SamplePluginC extends EditorPlugin {
  _SamplePluginC(this.onDisposed);
  final void Function(String) onDisposed;

  @override
  String get id => 'plugin.c';

  @override
  void dispose() {
    onDisposed(id);
    super.dispose();
  }
}

void main() {
  group('PluginRegistry Tests', () {
    test('test_pluginRegistry_rejectsDuplicateCommandIds', () {
      final CommandBus bus = CommandBus();
      final PluginRegistry registry = PluginRegistry(commandBus: bus);

      registry.registerPlugin(_SamplePluginA((_) {}));

      expect(
        () => registry.registerPlugin(_SamplePluginB((_) {})),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('test_pluginRegistry_registersAndDisposesPluginsInOrder', () {
      final CommandBus bus = CommandBus();
      final PluginRegistry registry = PluginRegistry(commandBus: bus);
      final List<String> disposedOrder = <String>[];

      final _SamplePluginA pA = _SamplePluginA(disposedOrder.add);
      final _SamplePluginC pC = _SamplePluginC(disposedOrder.add);

      registry.registerPlugin(pA);
      registry.registerPlugin(pC);

      expect(registry.plugins.length, 2);
      expect(registry.plugins[0].id, 'plugin.a');
      expect(registry.plugins[1].id, 'plugin.c');

      registry.dispose();

      // Deterministic reverse registration order
      expect(disposedOrder, <String>['plugin.c', 'plugin.a']);
      expect(registry.plugins.isEmpty, true);
    });
  });
}
