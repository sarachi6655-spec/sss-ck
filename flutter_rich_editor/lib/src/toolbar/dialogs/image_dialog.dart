import 'package:flutter/material.dart';

class ImageDialogResult {
  const ImageDialogResult({
    required this.url,
    this.alt = '',
    this.caption = '',
    this.width,
  });

  final String url;
  final String alt;
  final String caption;
  final double? width;
}

class ImageDialog extends StatefulWidget {
  const ImageDialog({
    super.key,
    this.initialUrl = '',
    this.initialAlt = '',
    this.initialCaption = '',
    this.initialWidth,
  });

  final String initialUrl;
  final String initialAlt;
  final String initialCaption;
  final double? initialWidth;

  static Future<ImageDialogResult?> show(
    BuildContext context, {
    String initialUrl = '',
    String initialAlt = '',
    String initialCaption = '',
    double? initialWidth,
  }) {
    return showDialog<ImageDialogResult>(
      context: context,
      builder: (BuildContext ctx) => ImageDialog(
        initialUrl: initialUrl,
        initialAlt: initialAlt,
        initialCaption: initialCaption,
        initialWidth: initialWidth,
      ),
    );
  }

  @override
  State<ImageDialog> createState() => _ImageDialogState();
}

class _ImageDialogState extends State<ImageDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _altController;
  late final TextEditingController _captionController;
  double? _width;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
    _altController = TextEditingController(text: widget.initialAlt);
    _captionController = TextEditingController(text: widget.initialCaption);
    _width = widget.initialWidth;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _altController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: <Widget>[
          Icon(Icons.image_outlined, color: Color(0xFF2563EB)),
          SizedBox(width: 8.0),
          Text('Insert Image', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _urlController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Image URL or Data URL',
                hintText: 'https://images.unsplash.com/... or data:image/...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12.0),
            TextField(
              controller: _altController,
              decoration: const InputDecoration(
                labelText: 'Alt Text (Accessibility)',
                hintText: 'Clinical lab sample #102',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12.0),
            TextField(
              controller: _captionController,
              decoration: const InputDecoration(
                labelText: 'Caption (Optional)',
                hintText: 'Figure 1: Morphology',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12.0),
            const Text('Display Size:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4.0),
            Wrap(
              spacing: 8.0,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('Auto'),
                  selected: _width == null,
                  onSelected: (bool selected) {
                    setState(() => _width = null);
                  },
                ),
                ChoiceChip(
                  label: const Text('Small (200px)'),
                  selected: _width == 200,
                  onSelected: (bool selected) {
                    setState(() => _width = 200);
                  },
                ),
                ChoiceChip(
                  label: const Text('Medium (400px)'),
                  selected: _width == 400,
                  onSelected: (bool selected) {
                    setState(() => _width = 400);
                  },
                ),
                ChoiceChip(
                  label: const Text('Full Width'),
                  selected: _width == 600,
                  onSelected: (bool selected) {
                    setState(() => _width = 600);
                  },
                ),
              ],
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
            final String url = _urlController.text.trim();
            if (url.isNotEmpty) {
              Navigator.of(context).pop(ImageDialogResult(
                url: url,
                alt: _altController.text.trim(),
                caption: _captionController.text.trim(),
                width: _width,
              ));
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
          ),
          child: const Text('Insert Image'),
        ),
      ],
    );
  }
}
