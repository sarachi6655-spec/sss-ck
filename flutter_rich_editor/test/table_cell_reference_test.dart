import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rich_editor/flutter_rich_editor.dart';

void main() {
  group('Table Cell Reference Tests', () {
    test('parseCellCoord parses coordinates accurately', () {
      expect(RichEditorController.parseCellCoord('A1'), (col: 0, row: 0));
      expect(RichEditorController.parseCellCoord('B1'), (col: 1, row: 0));
      expect(RichEditorController.parseCellCoord('A2'), (col: 0, row: 1));
      expect(RichEditorController.parseCellCoord('C5'), (col: 2, row: 4));
      expect(RichEditorController.parseCellCoord('Z1'), (col: 25, row: 0));
      expect(RichEditorController.parseCellCoord('AA1'), (col: 26, row: 0));
      expect(RichEditorController.parseCellCoord('invalid'), isNull);
      expect(RichEditorController.parseCellCoord(''), isNull);
    });

    test('formatCellCoord formats 0-based row and col correctly', () {
      expect(RichEditorController.formatCellCoord(0, 0), 'A1');
      expect(RichEditorController.formatCellCoord(1, 0), 'B1');
      expect(RichEditorController.formatCellCoord(0, 1), 'A2');
      expect(RichEditorController.formatCellCoord(2, 4), 'C5');
      expect(RichEditorController.formatCellCoord(25, 0), 'Z1');
      expect(RichEditorController.formatCellCoord(26, 0), 'AA1');
    });

    test('getTableCellValue and resolveCellReferences work with document tables', () {
      final controller = RichEditorController();

      // Create a document with a table (team members and marks) and a paragraph
      const tableHtml = '''
<figure class="table">
  <table>
    <thead>
      <tr><th>Team</th><th>Marks</th></tr>
    </thead>
    <tbody>
      <tr><td>Team A</td><td>95</td></tr>
      <tr><td>Team B</td><td>88</td></tr>
    </tbody>
  </table>
</figure>
<p>The team a performed well and their mark is </p>
''';

      controller.loadHtml(tableHtml);

      // Verify table cell value extraction
      // Row 0 is header: A1=Team, B1=Marks
      // Row 1 is data: A2=Team A, B2=95
      // Row 2 is data: A3=Team B, B3=88
      expect(controller.getTableCellValue('A1'), 'Team');
      expect(controller.getTableCellValue('B1'), 'Marks');
      expect(controller.getTableCellValue('A2'), 'Team A');
      expect(controller.getTableCellValue('B2'), '95');
      expect(controller.getTableCellValue('A3'), 'Team B');
      expect(controller.getTableCellValue('B3'), '88');

      // Test resolveCellReferences
      final resolved = controller.resolveCellReferences('The winner is \$A2 with score \$B2');
      expect(resolved, 'The winner is Team A with score 95');

      // Test toCleanReportHtml
      const htmlWithPill = '<p>The mark is <span class="mention table-cell-ref" data-mention="\$B2" data-cell-coord="B2">95</span> in test.</p>';
      controller.loadHtml(htmlWithPill);
      final clean = controller.toCleanReportHtml();
      expect(clean.contains('The mark is 95 in test.'), isTrue);
      expect(clean.contains('table-cell-ref'), isFalse);
    });

    test('InsertTableCellReferenceCommand inserts reference into document', () {
      final controller = RichEditorController();
      const initialHtml = '''
<figure class="table">
  <table>
    <tbody>
      <tr><td>Team Alpha</td><td>99</td></tr>
    </tbody>
  </table>
</figure>
<p>Score: </p>
''';
      controller.loadHtml(initialHtml);
      // Select inside the paragraph (nodeIndex 1, offset 7)
      controller.setSelection(const EditorSelection(baseOffset: 7, extentOffset: 7, nodeIndex: 1));

      // Execute InsertTableCellReferenceCommand for B1
      controller.execute(const InsertTableCellReferenceCommand(coord: 'B1'));

      final html = controller.toHtml();
      expect(html.contains('data-cell-coord="B1"'), isTrue);
      expect(html.contains('99'), isTrue);
    });

    test('Updating cell value updates cell extraction and references', () {
      final controller = RichEditorController();
      const initialHtml = '''
<figure class="table">
  <table>
    <tbody>
      <tr><td>34</td></tr>
      <tr><td>32</td></tr>
      <tr><td data-formula="=SUM(A1+A2)" data-formula-val="66"><p><strong>66</strong></p></td></tr>
    </tbody>
  </table>
</figure>
<p>Total is \$A3</p>
''';
      controller.loadHtml(initialHtml);
      expect(controller.getTableCellValue('A1'), '34');
      expect(controller.getTableCellValue('A2'), '32');
      expect(controller.getTableCellValue('A3'), '66');
      expect(controller.resolveCellReferences('Total is \$A3'), 'Total is 66');

      // Now update A1 to 40 and A3 formula val to 72
      const updatedHtml = '''
<figure class="table">
  <table>
    <tbody>
      <tr><td>40</td></tr>
      <tr><td>32</td></tr>
      <tr><td data-formula="=SUM(A1+A2)" data-formula-val="72"><p><strong>72</strong></p></td></tr>
    </tbody>
  </table>
</figure>
<p>Total is \$A3</p>
''';
      controller.loadHtml(updatedHtml);
      expect(controller.getTableCellValue('A1'), '40');
      expect(controller.getTableCellValue('A2'), '32');
      expect(controller.getTableCellValue('A3'), '72');
      expect(controller.resolveCellReferences('Total is \$A3'), 'Total is 72');
    });

    test('Preserves reference pill attributes data-cell-coord and data-mention in paragraphs', () {
      final controller = RichEditorController();
      const htmlWithPill = '<p>The values are <span class="mention table-cell-ref" data-mention="\$A1" data-cell-coord="A1">200</span> and <span class="mention table-cell-ref" data-mention="\$A2" data-cell-coord="A2">30</span>, sum is <span class="mention table-cell-ref" data-mention="\$A3" data-cell-coord="A3">230</span>.</p>';
      controller.loadHtml(htmlWithPill);
      final exported = controller.toHtml();
      expect(exported.contains('data-cell-coord="A1"'), isTrue);
      expect(exported.contains('data-cell-coord="A2"'), isTrue);
      expect(exported.contains('data-cell-coord="A3"'), isTrue);
      expect(exported.contains('table-cell-ref'), isTrue);
      expect(exported.contains('200'), isTrue);
      expect(exported.contains('30'), isTrue);
      expect(exported.contains('230'), isTrue);
    });

    test('Inline formula pills outside tables evaluate and export cleanly in toCleanReportHtml', () {
      final controller = RichEditorController();
      const htmlWithFormulaPill = '<p>Total is <span class="inline-formula-pill" data-formula="=SUM(A1+A2)">230</span> for this report.</p>';
      controller.loadHtml(htmlWithFormulaPill);
      final clean = controller.toCleanReportHtml();
      expect(clean, contains('Total is 230 for this report.'));
      expect(clean.contains('inline-formula-pill'), isFalse);
    });
  });
}
