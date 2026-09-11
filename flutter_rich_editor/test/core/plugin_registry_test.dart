import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_rich_editor/src/core/plugin_system/plugin_system.dart';
import 'package:flutter_rich_editor/src/core/document_model/document_model.dart';

EditorPlugin _makePlugin({
  required String id,
  String name = 'p',
  List<String> dependencies = const <String>[],
  bool registerInBody = true,
}) {
  return _StubPlugin(
    id: id,
    name: name,
    dependencies: dependencies,
    registerInBody: registerInBody,
  );
}

class _StubPlugin extends EditorPlugin {
  @override
  final String id;
  @override
  final String name;
  @override
  final List<String> dependencies;
  final bool registerInBody;
  final List<String> registerCalls = <String>[];
  final List<String> disposeCalls = <String>[];

  _StubPlugin({
    required this.id,
    required this.name,
    required this.dependencies,
    required this.registerInBody,
  });

  @override
  void register(PluginRegistry registry) {
    registerCalls.add(id);
    if (registerInBody) {
      registry.registerNodeType(
        NodeTypeRegistration(
          nodeType: 'paragraph',
          fromJson: (Map<String, dynamic> json) => ParagraphNode.fromJson(json),
          toJson: (EditorNode n) =>
              (n as ParagraphNode).toJson(),
          renderer: (
            BuildContext context,
            EditorNode node,
            NodeRenderContext renderContext,
          ) =>
              const SizedBox.shrink(),
        ),
      );
    }
  }

  @override
  void dispose(PluginRegistry registry) {
    disposeCalls.add(id);
  }
}

void main() {
  group('PluginRegistry', () {
    test('register stores plugin in order', () {
      final PluginRegistry r = PluginRegistry();
      final EditorPlugin p1 = _makePlugin(id: 'a');
      final EditorPlugin p2 = _makePlugin(id: 'b');
      r.register(p1);
      r.register(p2);
      expect(r.plugins.toList(), <EditorPlugin>[p1, p2]);
    });

    test('register rejects duplicate plugin id', () {
      final PluginRegistry r = PluginRegistry();
      r.register(_makePlugin(id: 'dup'));
      expect(
        () => r.register(_makePlugin(id: 'dup')),
        throwsA(isA<PluginRegistryException>()),
      );
    });

    test('register rejects when dependency is missing', () {
      final PluginRegistry r = PluginRegistry();
      expect(
        () => r.register(_makePlugin(id: 'b', dependencies: <String>['a'])),
        throwsA(isA<PluginRegistryException>()),
      );
    });

    test('register accepts when dependency is present', () {
      final PluginRegistry r = PluginRegistry();
      r.register(_makePlugin(id: 'a'));
      r.register(_makePlugin(id: 'b', dependencies: <String>['a']));
      expect(r.plugins.toList(), hasLength(2));
    });

    test('registerNodeType rejects duplicate node type', () {
      final PluginRegistry r = PluginRegistry();
      r.registerNodeType(
        NodeTypeRegistration(
          nodeType: 'para',
          fromJson: (Map<String, dynamic> j) => ParagraphNode.fromJson(j),
          toJson: (EditorNode n) => n.toJson(),
          renderer: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
      expect(
        () => r.registerNodeType(
          NodeTypeRegistration(
            nodeType: 'para',
            fromJson: (Map<String, dynamic> j) => ParagraphNode.fromJson(j),
            toJson: (EditorNode n) => n.toJson(),
            renderer: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        throwsA(isA<PluginRegistryException>()),
      );
    });

    test('registerCommand rejects duplicate command id', () {
      final PluginRegistry r = PluginRegistry();
      r.registerCommand('c1', (Map<String, dynamic> a) => _NoopCommand());
      expect(
        () => r.registerCommand(
          'c1',
          (Map<String, dynamic> a) => _NoopCommand(),
        ),
        throwsA(isA<PluginRegistryException>()),
      );
    });

    test('createCommand throws for unknown command id', () {
      final PluginRegistry r = PluginRegistry();
      expect(
        () => r.createCommand('missing'),
        throwsA(isA<PluginRegistryException>()),
      );
    });

    test('createCommand invokes the registered factory', () {
      final PluginRegistry r = PluginRegistry();
      r.registerCommand('c1', (Map<String, dynamic> a) => _NoopCommand());
      final EditorCommand cmd = r.createCommand('c1');
      expect(cmd, isA<EditorCommand>());
      expect(cmd.id, 'noop');
    });

    test('registerToolbarItem accumulates items and exposes them sorted', () {
      final PluginRegistry r = PluginRegistry();
      r.registerToolbarItem(
        const ToolbarItem(
          commandId: 'b',
          label: 'B',
          group: 'g',
          order: 20,
        ),
      );
      r.registerToolbarItem(
        const ToolbarItem(
          commandId: 'a',
          label: 'A',
          group: 'g',
          order: 10,
        ),
      );
      final List<ToolbarItem> items = r.toolbarItems;
      expect(items[0].commandId, 'a');
      expect(items[1].commandId, 'b');
    });

    test('registerShortcut accumulates shortcuts', () {
      final PluginRegistry r = PluginRegistry();
      r.registerShortcut(
        const ShortcutRegistration(
          activator: SingleActivator(LogicalKeyboardKey.keyB),
          commandId: 'bold',
        ),
      );
      r.registerShortcut(
        const ShortcutRegistration(
          activator: SingleActivator(LogicalKeyboardKey.keyI),
          commandId: 'italic',
        ),
      );
      expect(r.shortcuts, hasLength(2));
    });

    test('dispose clears all collections', () {
      final PluginRegistry r = PluginRegistry();
      r.register(_makePlugin(id: 'a'));
      r.registerNodeType(
        NodeTypeRegistration(
          nodeType: 't',
          fromJson: (Map<String, dynamic> j) => ParagraphNode.fromJson(j),
          toJson: (EditorNode n) => n.toJson(),
          renderer: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
      r.registerCommand('c1', (Map<String, dynamic> a) => _NoopCommand());
      r.registerToolbarItem(
        const ToolbarItem(commandId: 'x', label: 'X', group: 'g'),
      );
      r.registerShortcut(
        const ShortcutRegistration(
          activator: SingleActivator(LogicalKeyboardKey.keyA),
          commandId: 'x',
        ),
      );
      r.dispose();
      expect(r.plugins, isEmpty);
      expect(r.nodeTypes, isEmpty);
      expect(r.commandIds, isEmpty);
      expect(r.toolbarItems, isEmpty);
      expect(r.shortcuts, isEmpty);
    });

    test('dispose calls plugin dispose in reverse order', () {
      final PluginRegistry r = PluginRegistry();
      final _StubPlugin p1 = _StubPlugin(
        id: 'a',
        name: 'A',
        dependencies: const <String>[],
        registerInBody: false,
      );
      final _StubPlugin p2 = _StubPlugin(
        id: 'b',
        name: 'B',
        dependencies: const <String>[],
        registerInBody: false,
      );
      r.register(p1);
      r.register(p2);
      r.dispose();
      expect(p1.disposeCalls, <String>['a']);
      expect(p2.disposeCalls, <String>['b']);
      expect(p2.disposeCalls.first, 'b');
      expect(p1.disposeCalls.first, 'a');
    });

    test('dispose swallows exceptions thrown by plugins', () {
      final PluginRegistry r = PluginRegistry();
      r.register(_ThrowingPlugin());
      expect(() => r.dispose(), returnsNormally);
    });

    test('nodeFromJson returns UnsupportedNode for unknown type', () {
      final PluginRegistry r = PluginRegistry();
      final EditorNode n = r.nodeFromJson(<String, dynamic>{
        'type': 'mystery',
        'id': 'x',
      });
      expect(n, isA<UnsupportedNode>());
      expect((n as UnsupportedNode).originalType, 'mystery');
    });

    test('nodeFromJson returns UnsupportedNode when type key missing', () {
      final PluginRegistry r = PluginRegistry();
      final EditorNode n = r.nodeFromJson(<String, dynamic>{'id': 'x'});
      expect(n, isA<UnsupportedNode>());
      expect(n.type, 'unsupported');
    });

    test('nodeFromJson invokes registered factory for known type', () {
      final PluginRegistry r = PluginRegistry();
      r.registerNodeType(
        NodeTypeRegistration(
          nodeType: 'paragraph',
          fromJson: (Map<String, dynamic> j) => ParagraphNode.fromJson(j),
          toJson: (EditorNode n) => (n as ParagraphNode).toJson(),
          renderer: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
      final EditorNode n = r.nodeFromJson(<String, dynamic>{
        'type': 'paragraph',
        'id': 'p1',
        'spans': <Map<String, dynamic>>[<String, dynamic>{'text': 'x'}],
      });
      expect(n, isA<ParagraphNode>());
      expect((n as ParagraphNode).plainText, 'x');
    });

    test('nodeToJson serializes via registered serializer', () {
      final PluginRegistry r = PluginRegistry();
      r.registerNodeType(
        NodeTypeRegistration(
          nodeType: 'paragraph',
          fromJson: (Map<String, dynamic> j) => ParagraphNode.fromJson(j),
          toJson: (EditorNode n) => <String, dynamic>{
            'wrapped': true,
            'id': n.id,
          },
          renderer: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
      final EditorNode p = ParagraphNode.fromText(id: 'p1', text: 'x');
      final Map<String, dynamic> json = r.nodeToJson(p);
      expect(json['wrapped'], isTrue);
      expect(json['id'], 'p1');
    });

    test('nodeToJson falls back for unregistered types', () {
      final PluginRegistry r = PluginRegistry();
      final EditorNode p = ParagraphNode.fromText(id: 'p1', text: 'x');
      final Map<String, dynamic> json = r.nodeToJson(p);
      // No serializer registered, so falls back to a minimal map.
      expect(json['type'], 'paragraph');
      expect(json['id'], 'p1');
    });

    test('nodeToJson preserves UnsupportedNode JSON', () {
      final PluginRegistry r = PluginRegistry();
      final EditorNode u = UnsupportedNode(
        id: 'u1',
        originalType: 'foo',
        json: <String, dynamic>{'type': 'foo', 'data': 'raw'},
      );
      final Map<String, dynamic> json = r.nodeToJson(u);
      expect(json['type'], 'foo');
      expect(json['data'], 'raw');
    });

    test('toolbarItems getter returns unmodifiable list', () {
      final PluginRegistry r = PluginRegistry();
      r.registerToolbarItem(
        const ToolbarItem(commandId: 'x', label: 'X', group: 'g'),
      );
      expect(() => r.toolbarItems.add(
            const ToolbarItem(commandId: 'y', label: 'Y', group: 'g'),
          ), throwsUnsupportedError);
    });

    test('shortcuts getter returns unmodifiable list', () {
      final PluginRegistry r = PluginRegistry();
      r.registerShortcut(
        const ShortcutRegistration(
          activator: SingleActivator(LogicalKeyboardKey.keyA),
          commandId: 'x',
        ),
      );
      expect(
        () => r.shortcuts.add(
          const ShortcutRegistration(
            activator: SingleActivator(LogicalKeyboardKey.keyB),
            commandId: 'y',
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('PluginRegistryException', () {
    test('toString includes message', () {
      final PluginRegistryException e =
          PluginRegistryException('boom');
      expect(e.toString(), contains('boom'));
      expect(e.toString(), contains('PluginRegistryException'));
    });
  });

  group('UnsupportedNode', () {
    test('type is unsupported and plainText is empty', () {
      final UnsupportedNode u = UnsupportedNode(
        id: 'u',
        originalType: 'foo',
        json: <String, dynamic>{},
      );
      expect(u.type, 'unsupported');
      expect(u.plainText, '');
      expect(u.attributes, isEmpty);
    });

    test('toJson returns the original json', () {
      final UnsupportedNode u = UnsupportedNode(
        id: 'u',
        originalType: 'foo',
        json: <String, dynamic>{'raw': 1},
      );
      expect(u.toJson(), <String, dynamic>{'raw': 1});
    });

    test('copyWith preserves originalType and json', () {
      final UnsupportedNode u = UnsupportedNode(
        id: 'u',
        originalType: 'foo',
        json: <String, dynamic>{'raw': 1},
      );
      final UnsupportedNode copy = u.copyWith(id: 'u2') as UnsupportedNode;
      expect(copy.id, 'u2');
      expect(copy.originalType, 'foo');
      expect(copy.json, <String, dynamic>{'raw': 1});
    });
  });
}

class _NoopCommand extends EditorCommand {
  const _NoopCommand();
  @override
  String get id => 'noop';
  @override
  EditorCommandResult execute(EditorCommandContext context) =>
      EditorCommandResult.success(document: context.document);
  @override
  EditorCommandResult undo(
    EditorCommandContext context,
    DocumentValue previousDocument,
  ) =>
      EditorCommandResult.success(document: previousDocument);
}

class _ThrowingPlugin extends EditorPlugin {
  @override
  String get id => 'throwing';
  @override
  String get name => 'Throwing';
  @override
  void register(PluginRegistry registry) {}
  @override
  void dispose(PluginRegistry registry) {
    throw StateError('plugin boom');
  }
}