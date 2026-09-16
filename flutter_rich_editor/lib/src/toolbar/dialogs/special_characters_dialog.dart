import 'package:flutter/material.dart';

class SpecialCharactersDialog extends StatelessWidget {
  const SpecialCharactersDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => const SpecialCharactersDialog(),
    );
  }

  static const Map<String, List<String>> _categories = <String, List<String>>{
    'Currency': <String>['€', '£', '¥', '₹', '\$', '¢', '₩', '₿', '₽'],
    'Math': <String>['±', '×', '÷', '≠', '≤', '≥', '≈', '√', '∞', '∑', '∫', '‰', '½', '¼', '¾', '°'],
    'Greek / Science': <String>['α', 'β', 'γ', 'δ', 'ε', 'θ', 'λ', 'µ', 'π', 'σ', 'φ', 'ω', 'Ω', 'Δ'],
    'Symbols & Legal': <String>['©', '®', '™', '§', '¶', '•', '—', '–', '†', '‡', '✓', '✕', '★'],
    'Arrows': <String>['←', '→', '↑', '↓', '↔', '↵', '⇐', '⇒', '▲', '▼'],
  };

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _categories.keys.length,
      child: AlertDialog(
        title: const Row(
          children: <Widget>[
            Icon(Icons.emoji_symbols, color: Color(0xFF2563EB)),
            SizedBox(width: 8.0),
            Text('Special Characters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 380,
          height: 280,
          child: Column(
            children: <Widget>[
              TabBar(
                isScrollable: true,
                labelColor: const Color(0xFF2563EB),
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: const Color(0xFF2563EB),
                tabs: _categories.keys.map((String cat) => Tab(text: cat)).toList(),
              ),
              const SizedBox(height: 12.0),
              Expanded(
                child: TabBarView(
                  children: _categories.values.map((List<String> symbols) {
                    return GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 6,
                        crossAxisSpacing: 6.0,
                        mainAxisSpacing: 6.0,
                      ),
                      itemCount: symbols.length,
                      itemBuilder: (BuildContext ctx, int i) {
                        final String char = symbols[i];
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(char),
                          borderRadius: BorderRadius.circular(4.0),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(4.0),
                              color: Colors.grey.shade50,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              char,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                            ),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
