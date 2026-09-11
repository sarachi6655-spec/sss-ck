import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_rich_editor/src/core/plugin_system/plugin_system.dart';

EditorPlugin _plugin(String id) => _Stub(id: id);

class _Stub extends EditorPlugin {
  @override
  final String id;
  @override
  final String name;
  _Stub({required this.id, String? name}) : name = name ?? id;

  @override
  List<String> get dependencies => const <String>[];

  @override
  void register(PluginRegistry registry) {}
}

void main() {
  group('PluginPresets', () {
    test('basic includes formatting and structure plugins only', () {
      final List<EditorPlugin> all = <EditorPlugin>[
        _plugin('formatting/bold'),
        _plugin('formatting/italic'),
        _plugin('structure/heading'),
        _plugin('structure/list'),
        _plugin('media/image'),
        _plugin('media/video'),
        _plugin('code/block'),
        _plugin('paste/text'),
        _plugin('providers/ai'),
        _plugin('optional/collab'),
      ];
      final List<EditorPlugin> basic = PluginPresets.basic(all);
      expect(basic.map((EditorPlugin p) => p.id), <String>[
        'formatting/bold',
        'formatting/italic',
        'structure/heading',
        'structure/list',
      ]);
    });

    test('media includes formatting, structure, and media plugins', () {
      final List<EditorPlugin> all = <EditorPlugin>[
        _plugin('formatting/bold'),
        _plugin('structure/heading'),
        _plugin('media/image'),
        _plugin('media/video'),
        _plugin('code/block'),
        _plugin('providers/ai'),
        _plugin('optional/collab'),
      ];
      final List<EditorPlugin> media = PluginPresets.media(all);
      expect(media.map((EditorPlugin p) => p.id), <String>[
        'formatting/bold',
        'structure/heading',
        'media/image',
        'media/video',
      ]);
    });

    test('full excludes providers and optional namespaces', () {
      final List<EditorPlugin> all = <EditorPlugin>[
        _plugin('formatting/bold'),
        _plugin('structure/heading'),
        _plugin('media/image'),
        _plugin('code/block'),
        _plugin('providers/ai'),
        _plugin('providers/storage'),
        _plugin('optional/collab'),
      ];
      final List<EditorPlugin> full = PluginPresets.full(all);
      expect(full.map((EditorPlugin p) => p.id), <String>[
        'formatting/bold',
        'structure/heading',
        'media/image',
        'code/block',
      ]);
    });

    test('custom returns the same list reference', () {
      final List<EditorPlugin> input = <EditorPlugin>[
        _plugin('a'),
        _plugin('b'),
      ];
      final List<EditorPlugin> out = PluginPresets.custom(input);
      expect(identical(input, out), isTrue);
    });

    test('basic returns empty when no plugins match', () {
      final List<EditorPlugin> all = <EditorPlugin>[
        _plugin('media/image'),
        _plugin('providers/ai'),
      ];
      expect(PluginPresets.basic(all), isEmpty);
    });

    test('media returns empty when no plugins match', () {
      final List<EditorPlugin> all = <EditorPlugin>[
        _plugin('code/block'),
        _plugin('providers/ai'),
      ];
      expect(PluginPresets.media(all), isEmpty);
    });

    test('full returns empty when everything is providers or optional', () {
      final List<EditorPlugin> all = <EditorPlugin>[
        _plugin('providers/ai'),
        _plugin('optional/collab'),
      ];
      expect(PluginPresets.full(all), isEmpty);
    });
  });
}