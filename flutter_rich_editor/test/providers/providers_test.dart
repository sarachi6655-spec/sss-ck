import 'dart:typed_data';
import 'package:flutter_rich_editor/flutter_rich_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Optional Providers Tests', () {
    test('test_aiProvider_returnsTrackableSuggestionWithoutEmbeddingCredentials', () async {
      const MockAiAssistantProvider aiProvider = MockAiAssistantProvider();
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.paragraph(id: 'p1', text: 'Drafting medical report details'),
        ],
      );

      final ContentSuggestion suggestion = await aiProvider.generateSuggestion(
        document: doc,
        selectedText: 'Drafting medical report details',
        prompt: 'Improve tone and formalize',
        user: const EditorUser(id: 'usr_ai', name: 'AI Co-pilot'),
      );

      expect(suggestion.id.isNotEmpty, true);
      expect(suggestion.nodeId, 'p1');
      expect(suggestion.originalText, 'Drafting medical report details');
      expect(suggestion.suggestedText.contains('Improved:'), true);
      expect(suggestion.author.name, 'AI Co-pilot');
    });

    test('test_pdfExport_usesConfiguredAdapter', () async {
      const StandardPdfExportAdapter adapter = StandardPdfExportAdapter();
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.heading(id: 'h1', text: 'LIMS Analysis Report', level: 1),
          EditorNode.paragraph(id: 'p1', text: 'All sample parameters verified within normal range.'),
        ],
      );

      final Uint8List pdfBytes = await adapter.exportPdf(doc);

      expect(pdfBytes.isNotEmpty, true);
      // Verify PDF header magic bytes %PDF-
      final String header = String.fromCharCodes(pdfBytes.take(5));
      expect(header, '%PDF-');
    });

    test('test_docxImportReportsUnsupportedConstructs', () async {
      const StandardDocxImportAdapter adapter = StandardDocxImportAdapter();
      final Uint8List sampleDocxBytes = Uint8List.fromList('vbaProject macro content drawing'.codeUnits);

      final DocxImportResult result = await adapter.importDocx(sampleDocxBytes);

      expect(result.document.nodes.isNotEmpty, true);
      expect(result.hasUnsupportedConstructs, true);
      expect(result.unsupportedConstructs.contains('vba_macros'), true);
      expect(result.unsupportedConstructs.contains('vector_vml_shapes'), true);
    });
  });
}
