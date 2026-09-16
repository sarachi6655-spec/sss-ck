import 'plugin.dart';

/// Predefined plugin bundles matching common use cases.
enum PluginPresetKind {
  basic,
  media,
  full,
  custom,
}

/// A bundle configuration for activating editor features.
class PluginPreset {
  const PluginPreset({
    required this.kind,
    this.customPlugins = const <EditorPlugin>[],
  });

  const PluginPreset.basic() : this(kind: PluginPresetKind.basic);
  const PluginPreset.media() : this(kind: PluginPresetKind.media);
  const PluginPreset.full() : this(kind: PluginPresetKind.full);
  const PluginPreset.custom(List<EditorPlugin> plugins)
      : this(kind: PluginPresetKind.custom, customPlugins: plugins);

  final PluginPresetKind kind;
  final List<EditorPlugin> customPlugins;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PluginPreset &&
          runtimeType == other.runtimeType &&
          kind == other.kind;

  @override
  int get hashCode => kind.hashCode;

  @override
  String toString() => 'PluginPreset($kind)';
}
