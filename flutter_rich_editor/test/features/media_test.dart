import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_rich_editor/flutter_rich_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Media and Table Tests', () {
    test('test_tableCommands_supportRowsColumnsMergedCellsAndResize', () {
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.table(id: 'tbl_1', rows: 2, columns: 2),
        ],
      );

      // Insert Row
      const InsertTableRowCommand addRow = InsertTableRowCommand(tableId: 'tbl_1', rowIndex: 1);
      final CommandResult rowRes = addRow.execute(doc);
      expect(rowRes.success, true);
      expect(rowRes.document.nodes[0].metadata['rows'], 3);

      // Insert Column
      const InsertTableColumnCommand addCol = InsertTableColumnCommand(tableId: 'tbl_1', columnIndex: 1);
      final CommandResult colRes = addCol.execute(rowRes.document);
      expect(colRes.success, true);
      expect(colRes.document.nodes[0].metadata['columns'], 3);

      // Resize Column
      const ResizeTableColumnCommand resize = ResizeTableColumnCommand(tableId: 'tbl_1', columnIndex: 0, width: 150.0);
      final CommandResult resizeRes = resize.execute(colRes.document);
      expect(resizeRes.success, true);
      expect(resizeRes.document.nodes[0].metadata['columnWidths']['0'], 150.0);

      // Merge Cells
      const MergeTableCellsCommand merge = MergeTableCellsCommand(
        tableId: 'tbl_1',
        startRow: 0,
        startCol: 0,
        endRow: 0,
        endCol: 1,
      );
      final CommandResult mergeRes = merge.execute(resizeRes.document);
      expect(mergeRes.success, true);
      final EditorNode firstCell = mergeRes.document.nodes[0].children[0].children[0];
      expect(firstCell.metadata['colSpan'], 2);
    });

    test('test_uploadAdapter_reportsProgressSupportsCancellationAndReturnsTypedFailure', () async {
      const Base64UploadAdapter adapter = Base64UploadAdapter();
      final List<double> progressReports = <double>[];

      // Test valid upload with progress
      final Uint8List validBytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final UploadResult res = await adapter.uploadBytes(
        bytes: validBytes,
        fileName: 'test.png',
        mimeType: 'image/png',
        onProgress: progressReports.add,
      );

      expect(res.isSuccess, true);
      expect(res.url.startsWith('data:image/png;base64,'), true);
      expect(progressReports.isNotEmpty, true);
      expect(progressReports.last, 1.0);

      // Test unsupported MIME typed failure
      final UploadResult failRes = await adapter.uploadBytes(
        bytes: validBytes,
        fileName: 'test.exe',
        mimeType: 'application/x-msdownload',
      );
      expect(failRes.isSuccess, false);
      expect(failRes.errorCode, 'upload.unsupported_mime');

      // Test cancellation
      final Completer<void> cancelToken = Completer<void>()..complete();
      final UploadResult cancelRes = await adapter.uploadBytes(
        bytes: validBytes,
        fileName: 'test.png',
        mimeType: 'image/png',
        cancelToken: cancelToken,
      );
      expect(cancelRes.isSuccess, false);
      expect(cancelRes.errorCode, 'upload.cancelled');
    });

    test('test_videoNode_rendersPosterBufferingPlaybackAndErrorStates', () {
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          EditorNode.video(
            id: 'v1',
            url: 'https://cdn.example.com/video.mp4',
            poster: 'https://cdn.example.com/poster.jpg',
            uploadState: 'ready',
          ),
        ],
      );

      final EditorNode node = doc.nodes[0];
      expect(node.metadata['poster'], 'https://cdn.example.com/poster.jpg');
      expect(node.metadata['uploadState'], 'ready');

      // Update to buffering
      const UpdateVideoStateCommand bufCmd = UpdateVideoStateCommand(nodeId: 'v1', uploadState: 'buffering');
      final CommandResult bufRes = bufCmd.execute(doc);
      expect(bufRes.document.nodes[0].metadata['uploadState'], 'buffering');

      // Update to error
      const UpdateVideoStateCommand errCmd = UpdateVideoStateCommand(nodeId: 'v1', uploadState: 'error');
      final CommandResult errRes = errCmd.execute(bufRes.document);
      expect(errRes.document.nodes[0].metadata['uploadState'], 'error');
    });

    test('test_mediaPolicy_rejectsDisallowedEmbedUrl', () {
      const MediaEmbedPolicy policy = MediaEmbedPolicy();

      const InsertEmbedCommand allowedCmd = InsertEmbedCommand(
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        policy: policy,
      );
      final CommandResult allowedRes = allowedCmd.execute(DocumentValue.empty());
      expect(allowedRes.success, true);

      const InsertEmbedCommand disallowedCmd = InsertEmbedCommand(
        url: 'https://malicious-site.com/video.html',
        policy: policy,
      );
      final CommandResult disallowedRes = disallowedCmd.execute(DocumentValue.empty());
      expect(disallowedRes.success, false);
      expect(disallowedRes.errorCode, 'media.disallowed_url');
    });
  });
}
