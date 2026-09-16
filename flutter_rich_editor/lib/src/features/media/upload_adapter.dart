import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// The result returned by an [UploadAdapter].
class UploadResult {
  const UploadResult.success({
    required this.url,
    this.metadata = const <String, dynamic>{},
  })  : isSuccess = true,
        errorCode = null,
        errorMessage = null;

  const UploadResult.failure({
    required this.errorCode,
    this.errorMessage,
  })  : isSuccess = false,
        url = '',
        metadata = const <String, dynamic>{};

  final bool isSuccess;
  final String url;
  final Map<String, dynamic> metadata;
  final String? errorCode;
  final String? errorMessage;

  @override
  String toString() =>
      isSuccess ? 'UploadResult.success($url)' : 'UploadResult.failure($errorCode: $errorMessage)';
}

/// Abstract contract for uploading media assets (images, videos, attachments).
abstract class UploadAdapter {
  const UploadAdapter();

  /// List of accepted MIME types (e.g. ['image/png', 'image/jpeg', 'video/mp4']).
  List<String> get acceptedMimeTypes;

  /// Maximum file size allowed in bytes.
  int get maxFileSizeBytes => 50 * 1024 * 1024; // 50MB default

  /// Uploads binary data with progress and cancellation support.
  Future<UploadResult> uploadBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    void Function(double progress)? onProgress,
    Completer<void>? cancelToken,
  });
}

/// A default upload adapter converting assets directly to Base64 data URLs.
class Base64UploadAdapter extends UploadAdapter {
  const Base64UploadAdapter({
    this.allowedMimes = const <String>[
      'image/png',
      'image/jpeg',
      'image/webp',
      'image/gif',
      'video/mp4',
      'video/webm',
    ],
  });

  final List<String> allowedMimes;

  @override
  List<String> get acceptedMimeTypes => allowedMimes;

  @override
  Future<UploadResult> uploadBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    void Function(double progress)? onProgress,
    Completer<void>? cancelToken,
  }) async {
    // Check MIME
    if (!acceptedMimeTypes.contains(mimeType.toLowerCase())) {
      return UploadResult.failure(
        errorCode: 'upload.unsupported_mime',
        errorMessage: 'MIME type "$mimeType" is not supported.',
      );
    }

    // Check size
    if (bytes.lengthInBytes > maxFileSizeBytes) {
      return UploadResult.failure(
        errorCode: 'upload.file_too_large',
        errorMessage: 'File size exceeds limit of $maxFileSizeBytes bytes.',
      );
    }

    // Check cancellation
    if (cancelToken != null && cancelToken.isCompleted) {
      return const UploadResult.failure(
        errorCode: 'upload.cancelled',
        errorMessage: 'Upload operation was cancelled.',
      );
    }

    onProgress?.call(0.2);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    if (cancelToken != null && cancelToken.isCompleted) {
      return const UploadResult.failure(
        errorCode: 'upload.cancelled',
        errorMessage: 'Upload operation was cancelled.',
      );
    }

    onProgress?.call(0.7);
    final String base64Data = base64Encode(bytes);
    final String dataUrl = 'data:$mimeType;base64,$base64Data';

    onProgress?.call(1.0);
    return UploadResult.success(
      url: dataUrl,
      metadata: <String, dynamic>{
        'fileName': fileName,
        'size': bytes.lengthInBytes,
        'mimeType': mimeType,
      },
    );
  }
}
