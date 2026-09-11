import 'plugin.dart';

/// Predefined plugin presets.
///
/// Presets do not silently enable network, AI, collaboration, or raw HTML
/// capabilities. They only include features implemented by the registered
/// plugin list passed to the preset function.
abstract class PluginPresets {
  /// Basic text editing: formatting + structure.
  static List<EditorPlugin> basic(List<EditorPlugin> allPlugins) =>
      allPlugins
          .where((EditorPlugin p) =>
              p.id.startsWith('formatting/') || p.id.startsWith('structure/'))
          .toList();

  /// Basic + media features (images, video, links, embeds, tables, mentions,
  /// emoji).
  static List<EditorPlugin> media(List<EditorPlugin> allPlugins) =>
      allPlugins
          .where((EditorPlugin p) =>
              p.id.startsWith('formatting/') ||
              p.id.startsWith('structure/') ||
              p.id.startsWith('media/'))
          .toList();

  /// Full free-tier feature set. Does not include optional AI/collaboration
  /// providers.
  static List<EditorPlugin> full(List<EditorPlugin> allPlugins) =>
      allPlugins
          .where((EditorPlugin p) =>
              !p.id.startsWith('providers/') &&
              !p.id.startsWith('optional/'))
          .toList();

  /// Caller-supplied list, validated for dependency ordering.
  static List<EditorPlugin> custom(List<EditorPlugin> plugins) => plugins;
}
