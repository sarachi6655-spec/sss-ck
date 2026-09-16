import 'toolbar_item.dart';

/// Configuration managing which toolbar items appear, their order, and groups.
class ToolbarConfig {
  const ToolbarConfig({
    this.hiddenItemIds = const <String>{},
    this.orderedItemIds = const <String>[],
    this.customItems = const <ToolbarItem>[],
  });

  final Set<String> hiddenItemIds;
  final List<String> orderedItemIds;
  final List<ToolbarItem> customItems;

  /// Filters and reorders items according to this configuration.
  List<ToolbarItem> apply(List<ToolbarItem> baseItems) {
    final Map<String, ToolbarItem> allItemsMap = <String, ToolbarItem>{};

    for (final ToolbarItem item in baseItems) {
      if (!hiddenItemIds.contains(item.id)) {
        allItemsMap[item.id] = item;
      }
    }

    for (final ToolbarItem item in customItems) {
      if (!hiddenItemIds.contains(item.id)) {
        allItemsMap[item.id] = item;
      }
    }

    if (orderedItemIds.isEmpty) {
      return allItemsMap.values.toList();
    }

    final List<ToolbarItem> result = <ToolbarItem>[];
    for (final String id in orderedItemIds) {
      if (allItemsMap.containsKey(id)) {
        result.add(allItemsMap.remove(id)!);
      }
    }

    // Append any remaining unmentioned items
    result.addAll(allItemsMap.values);
    return result;
  }
}
