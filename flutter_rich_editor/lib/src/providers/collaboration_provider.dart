import '../core/document_model/document_value.dart';

/// Abstract contract for real-time collaboration connection.
abstract class RealtimeCollaborationProvider {
  const RealtimeCollaborationProvider();

  Stream<DocumentValue> get documentStream;

  void sendDocumentUpdate(DocumentValue update);

  void disconnect();
}
