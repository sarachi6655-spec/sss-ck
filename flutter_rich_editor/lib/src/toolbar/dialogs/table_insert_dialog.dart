import 'package:flutter/material.dart';

class TableInsertConfig {
  const TableInsertConfig({
    required this.rows,
    required this.columns,
    this.caption = '',
    this.hasHeader = true,
  });

  final int rows;
  final int columns;
  final String caption;
  final bool hasHeader;
}

class TableInsertDialog extends StatefulWidget {
  const TableInsertDialog({super.key});

  static Future<TableInsertConfig?> show(BuildContext context) {
    return showDialog<TableInsertConfig>(
      context: context,
      builder: (BuildContext ctx) => const TableInsertDialog(),
    );
  }

  @override
  State<TableInsertDialog> createState() => _TableInsertDialogState();
}

class _TableInsertDialogState extends State<TableInsertDialog> {
  int _selectedRows = 3;
  int _selectedCols = 3;
  bool _hasHeader = true;
  final TextEditingController _captionController = TextEditingController();

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: <Widget>[
          Icon(Icons.table_chart_outlined, color: Color(0xFF2563EB)),
          SizedBox(width: 8.0),
          Text('Insert Table', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Select Dimensions:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8.0),
            Center(
              child: Column(
                children: List<Widget>.generate(6, (int r) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List<Widget>.generate(6, (int c) {
                      final bool isHovered = (r + 1) <= _selectedRows && (c + 1) <= _selectedCols;
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedRows = r + 1;
                            _selectedCols = c + 1;
                          });
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          margin: const EdgeInsets.all(2.0),
                          decoration: BoxDecoration(
                            color: isHovered ? const Color(0xFF93C5FD) : Colors.grey.shade100,
                            border: Border.all(
                              color: isHovered ? const Color(0xFF2563EB) : Colors.grey.shade300,
                            ),
                            borderRadius: BorderRadius.circular(3.0),
                          ),
                        ),
                      );
                    }),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8.0),
            Center(
              child: Text(
                '$_selectedRows Rows × $_selectedCols Columns',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
              ),
            ),
            const Divider(height: 24.0),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include Header Row', style: TextStyle(fontSize: 14)),
              value: _hasHeader,
              onChanged: (bool? val) {
                setState(() {
                  _hasHeader = val ?? true;
                });
              },
            ),
            const SizedBox(height: 8.0),
            TextField(
              controller: _captionController,
              decoration: const InputDecoration(
                labelText: 'Table Caption (Optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(TableInsertConfig(
              rows: _selectedRows,
              columns: _selectedCols,
              hasHeader: _hasHeader,
              caption: _captionController.text.trim(),
            ));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
          ),
          child: const Text('Insert'),
        ),
      ],
    );
  }
}
