import 'dart:convert';
import '../core/document_model/document_value.dart';

/// Canonical JSON codec for lossless persistence of [DocumentValue].
class JsonDocumentCodec {
  const JsonDocumentCodec();

  /// Serializes a [DocumentValue] to a canonical JSON-compatible Map.
  Map<String, dynamic> encodeToMap(DocumentValue document) {
    return document.toJson();
  }

  /// Serializes a [DocumentValue] to a JSON String.
  String encode(DocumentValue document) {
    return jsonEncode(encodeToMap(document));
  }

  /// Deserializes a [DocumentValue] from a JSON-compatible Map.
  DocumentValue decodeFromMap(Map<String, dynamic> map) {
    return DocumentValue.fromJson(map);
  }

  /// Deserializes a [DocumentValue] from a JSON String.
  DocumentValue decode(String jsonString) {
    final dynamic parsed = jsonDecode(jsonString);
    if (parsed is Map<String, dynamic>) {
      return decodeFromMap(parsed);
    } else if (parsed is Map) {
      return decodeFromMap(Map<String, dynamic>.from(parsed));
    }
    throw FormatException('Invalid JSON payload for DocumentValue: $jsonString');
  }
}
