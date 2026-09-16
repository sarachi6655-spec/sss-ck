import 'package:flutter/material.dart';

class ColorPickerPopup extends StatelessWidget {
  const ColorPickerPopup({
    super.key,
    required this.title,
    this.currentColor,
  });

  final String title;
  final String? currentColor;

  static Future<String?> show(
    BuildContext context, {
    required String title,
    String? currentColor,
  }) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => ColorPickerPopup(
        title: title,
        currentColor: currentColor,
      ),
    );
  }

  static const List<List<String>> _palette = <List<String>>[
    // Grayscale
    <String>['#000000', '#374151', '#6B7280', '#9CA3AF', '#D1D5DB', '#F3F4F6', '#FFFFFF'],
    // Primary Vibrant
    <String>['#EF4444', '#F97316', '#F59E0B', '#10B981', '#06B6D4', '#3B82F6', '#6366F1', '#8B5CF6', '#EC4899'],
    // Pastels / Highlights
    <String>['#FEE2E2', '#FFEDD5', '#FEF3C7', '#D1FAE5', '#CFFAFE', '#DBEAFE', '#E0E7FF', '#EDE9FE', '#FCE7F3'],
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.palette_outlined, color: Color(0xFF2563EB)),
          const SizedBox(width: 8.0),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ..._palette.map((List<String> row) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: row.map((String hex) {
                    final Color color = _parseHex(hex);
                    final bool isSelected = currentColor?.toUpperCase() == hex.toUpperCase();
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(hex),
                      child: Container(
                        width: 28,
                        height: 28,
                        margin: const EdgeInsets.symmetric(horizontal: 3.0),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade400,
                            width: isSelected ? 2.5 : 1.0,
                          ),
                        ),
                        child: isSelected
                            ? Icon(Icons.check, size: 16, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              );
            }),
            const Divider(height: 24.0),
            TextButton.icon(
              icon: const Icon(Icons.format_color_reset, color: Colors.grey),
              label: const Text('Reset / Default Color', style: TextStyle(color: Colors.grey)),
              onPressed: () => Navigator.of(context).pop(''),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  static Color _parseHex(String hex) {
    try {
      final String clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return Colors.black;
    }
  }
}
