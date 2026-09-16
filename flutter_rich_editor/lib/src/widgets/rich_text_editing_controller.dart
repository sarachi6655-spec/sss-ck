import 'package:flutter/material.dart';

/// Custom [TextEditingController] that dynamically renders inline marks and block styling
/// while preserving exact character counts for seamless IME / web input and cursor positioning.
class RichTextEditingController extends TextEditingController {
  RichTextEditingController({
    super.text,
    this.nodeAttributes = const <String, dynamic>{},
    this.nodeType = 'paragraph',
  });

  Map<String, dynamic> nodeAttributes;
  String nodeType;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final TextStyle effectiveStyle = applyAttributes(style ?? const TextStyle(), nodeAttributes);
    final String fullText = text;
    if (fullText.isEmpty) {
      return TextSpan(text: '', style: effectiveStyle);
    }

    // Match inline formatting: **bold**, *italic*, ~~strikethrough~~, `code`, [label](url)
    final RegExp tokenRegex = RegExp(
      r'(\*\*(.*?)\*\*)|(\*(.*?)\*)|(~~(.*?)~~)|(`(.*?)`)|(\[(.*?)\]\((.*?)\))',
    );

    final List<InlineSpan> spans = <InlineSpan>[];
    int lastMatchEnd = 0;

    for (final Match match in tokenRegex.allMatches(fullText)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: fullText.substring(lastMatchEnd, match.start),
          style: effectiveStyle,
        ));
      }

      final String matchedText = match.group(0)!;
      final Color markerColor = (effectiveStyle.color ?? Colors.black).withValues(alpha: 0.35);
      final TextStyle markerStyle = effectiveStyle.copyWith(
        color: markerColor,
        fontWeight: FontWeight.normal,
        fontStyle: FontStyle.normal,
        decoration: TextDecoration.none,
      );

      if (matchedText.startsWith('**') && matchedText.endsWith('**') && matchedText.length >= 4) {
        final String inner = match.group(2) ?? '';
        spans.add(TextSpan(text: '**', style: markerStyle));
        spans.add(TextSpan(
          text: inner,
          style: effectiveStyle.copyWith(fontWeight: FontWeight.bold),
        ));
        spans.add(TextSpan(text: '**', style: markerStyle));
      } else if (matchedText.startsWith('*') && matchedText.endsWith('*') && matchedText.length >= 2) {
        final String inner = match.group(4) ?? '';
        spans.add(TextSpan(text: '*', style: markerStyle));
        spans.add(TextSpan(
          text: inner,
          style: effectiveStyle.copyWith(fontStyle: FontStyle.italic),
        ));
        spans.add(TextSpan(text: '*', style: markerStyle));
      } else if (matchedText.startsWith('~~') && matchedText.endsWith('~~') && matchedText.length >= 4) {
        final String inner = match.group(6) ?? '';
        spans.add(TextSpan(text: '~~', style: markerStyle));
        spans.add(TextSpan(
          text: inner,
          style: effectiveStyle.copyWith(decoration: TextDecoration.lineThrough),
        ));
        spans.add(TextSpan(text: '~~', style: markerStyle));
      } else if (matchedText.startsWith('`') && matchedText.endsWith('`') && matchedText.length >= 2) {
        final String inner = match.group(8) ?? '';
        spans.add(TextSpan(text: '`', style: markerStyle));
        spans.add(TextSpan(
          text: inner,
          style: effectiveStyle.copyWith(
            fontFamily: 'monospace',
            backgroundColor: (effectiveStyle.color ?? Colors.black).withValues(alpha: 0.08),
          ),
        ));
        spans.add(TextSpan(text: '`', style: markerStyle));
      } else if (matchedText.startsWith('[') && matchedText.contains('](')) {
        final String label = match.group(10) ?? '';
        final String url = match.group(11) ?? '';
        spans.add(TextSpan(text: '[', style: markerStyle));
        spans.add(TextSpan(
          text: label,
          style: effectiveStyle.copyWith(
            color: const Color(0xFF2563EB),
            decoration: TextDecoration.underline,
          ),
        ));
        spans.add(TextSpan(text: ']($url)', style: markerStyle));
      } else {
        spans.add(TextSpan(text: matchedText, style: effectiveStyle));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < fullText.length) {
      spans.add(TextSpan(
        text: fullText.substring(lastMatchEnd),
        style: effectiveStyle,
      ));
    }

    return TextSpan(style: effectiveStyle, children: spans);
  }

  static TextStyle applyAttributes(TextStyle style, Map<String, dynamic> attrs) {
    TextStyle res = style;
    if (attrs['bold'] == true) {
      res = res.copyWith(fontWeight: FontWeight.bold);
    }
    if (attrs['italic'] == true) {
      res = res.copyWith(fontStyle: FontStyle.italic);
    }
    if (attrs['underline'] == true) {
      res = res.copyWith(decoration: TextDecoration.underline);
    }
    if (attrs['strikethrough'] == true) {
      res = res.copyWith(decoration: TextDecoration.lineThrough);
    }
    if (attrs['code'] == true) {
      res = res.copyWith(fontFamily: 'monospace');
    }
    if (attrs['color'] != null) {
      try {
        final String hex = attrs['color'].toString().replaceAll('#', '');
        res = res.copyWith(color: Color(int.parse('FF$hex', radix: 16)));
      } catch (_) {}
    }
    if (attrs['highlight'] != null || attrs['backgroundColor'] != null) {
      try {
        final String raw = (attrs['highlight'] ?? attrs['backgroundColor']).toString().replaceAll('#', '');
        res = res.copyWith(backgroundColor: Color(int.parse('FF$raw', radix: 16)));
      } catch (_) {}
    }
    if (attrs['fontFamily'] != null && attrs['fontFamily'] != 'Default') {
      res = res.copyWith(fontFamily: attrs['fontFamily'].toString());
    }
    if (attrs['fontSize'] != null) {
      final double? sz = (attrs['fontSize'] as num?)?.toDouble();
      if (sz != null && sz > 0) {
        res = res.copyWith(fontSize: sz);
      }
    }
    return res;
  }
}
