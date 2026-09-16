import 'package:flutter/material.dart';

class LinkDialogResult {
  const LinkDialogResult({
    required this.url,
    this.displayText = '',
    this.isUnlink = false,
  });

  final String url;
  final String displayText;
  final bool isUnlink;
}

class LinkDialog extends StatefulWidget {
  const LinkDialog({
    super.key,
    this.initialUrl = '',
    this.initialText = '',
  });

  final String initialUrl;
  final String initialText;

  static Future<LinkDialogResult?> show(
    BuildContext context, {
    String initialUrl = '',
    String initialText = '',
  }) {
    return showDialog<LinkDialogResult>(
      context: context,
      builder: (BuildContext ctx) => LinkDialog(
        initialUrl: initialUrl,
        initialText: initialText,
      ),
    );
  }

  @override
  State<LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<LinkDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
    _textController = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.initialUrl.isNotEmpty;

    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(Icons.link, color: Color(0xFF2563EB)),
          const SizedBox(width: 8.0),
          Text(isEditing ? 'Edit Link' : 'Insert Link', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _urlController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'URL',
              hintText: 'https://example.com',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12.0),
          TextField(
            controller: _textController,
            decoration: const InputDecoration(
              labelText: 'Display Text (Optional)',
              hintText: 'Click here',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        if (isEditing)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(const LinkDialogResult(url: '', isUnlink: true));
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove Link'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            String url = _urlController.text.trim();
            if (url.isNotEmpty && !url.startsWith('http://') && !url.startsWith('https://') && !url.startsWith('mailto:')) {
              url = 'https://$url';
            }
            if (url.isNotEmpty) {
              Navigator.of(context).pop(LinkDialogResult(
                url: url,
                displayText: _textController.text.trim(),
              ));
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
