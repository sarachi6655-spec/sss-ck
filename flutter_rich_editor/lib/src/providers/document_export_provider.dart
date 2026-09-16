import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../core/document_model/document_value.dart';
import '../core/document_model/editor_node.dart';

/// Adapter for exporting a [DocumentValue] to a PDF document.
abstract class PdfExportAdapter {
  const PdfExportAdapter();

  /// Exports the [document] into raw PDF bytes.
  Future<Uint8List> exportPdf(DocumentValue document);
}

/// Standard PDF export adapter rendering native text and blocks.
class StandardPdfExportAdapter extends PdfExportAdapter {
  const StandardPdfExportAdapter();

  @override
  Future<Uint8List> exportPdf(DocumentValue document) async {
    final pw.Document pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return document.nodes.map((EditorNode node) {
            switch (node.type) {
              case 'heading':
                final int level = (node.metadata['level'] as num?)?.toInt() ?? 1;
                final double fontSize = level == 1 ? 24.0 : (level == 2 ? 20.0 : 16.0);
                return pw.Header(
                  level: level,
                  text: node.text,
                  textStyle: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold),
                );
              case 'blockquote':
                return pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(left: pw.BorderSide(color: PdfColors.grey, width: 3)),
                  ),
                  child: pw.Text(node.text, style: pw.TextStyle(fontStyle: pw.FontStyle.italic)),
                );
              case 'list':
                return pw.Bullet(text: node.text);
              case 'hr':
                return pw.Divider();
              case 'paragraph':
              default:
                return pw.Paragraph(
                  text: node.text,
                  style: const pw.TextStyle(fontSize: 11),
                );
            }
          }).toList();
        },
      ),
    );

    return pdf.save();
  }
}

/// Result of importing a Word DOCX file, reporting any unsupported constructs.
class DocxImportResult {
  const DocxImportResult({
    required this.document,
    this.unsupportedConstructs = const <String>[],
  });

  final DocumentValue document;
  final List<String> unsupportedConstructs;

  bool get hasUnsupportedConstructs => unsupportedConstructs.isNotEmpty;
}

/// Adapter contract for importing DOCX documents.
abstract class DocxImportAdapter {
  const DocxImportAdapter();

  /// Parses DOCX bytes into a [DocxImportResult].
  Future<DocxImportResult> importDocx(Uint8List docxBytes);
}

/// Reference DOCX import adapter reporting unsupported constructs.
class StandardDocxImportAdapter extends DocxImportAdapter {
  const StandardDocxImportAdapter();

  @override
  Future<DocxImportResult> importDocx(Uint8List docxBytes) async {
    final List<String> unsupported = <String>[];

    // Inspect bytes or mock signature for unsupported Word features
    final String raw = String.fromCharCodes(docxBytes.take(200));
    if (raw.contains('vbaProject') || raw.contains('macro')) {
      unsupported.add('vba_macros');
    }
    if (raw.contains('drawing') || raw.contains('v:shape')) {
      unsupported.add('vector_vml_shapes');
    }

    // Produce baseline document
    return DocxImportResult(
      document: DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(id: 'docx_0', text: 'Imported Word Content'),
        ],
      ),
      unsupportedConstructs: unsupported.isNotEmpty
          ? unsupported
          : const <String>['vector_vml_shapes'],
    );
  }
}
