import 'dart:typed_data';

import '../features/voice_input/voice_insert_mode.dart';
import 'toolbar_item.dart';

/// Configuration managing which toolbar items appear, their order, and groups.
class ToolbarConfig {
  const ToolbarConfig({
    this.hiddenItemIds = const <String>{},
    this.orderedItemIds = const <String>[],
    this.customItems = const <ToolbarItem>[],
    this.onVoiceRecord,
    this.onVoiceTranscribe,
    this.onVoiceInput,
    this.onMicPressed,
    this.onVoiceError,
    this.voiceInsertMode = VoiceInsertMode.insertAtCursor,
  });

  final Set<String> hiddenItemIds;
  final List<String> orderedItemIds;
  final List<ToolbarItem> customItems;

  // ── Voice Input (optional) ────────────────────────────────────────────────

  /// Called when the user taps the mic button.
  ///
  /// Can use the platform's built-in speech recognition (e.g. `speech_to_text`),
  /// call your API with the recognized prompt, and return the resulting HTML string.
  /// The returned HTML is automatically inserted into the editor according to [voiceInsertMode].
  final Future<String?> Function()? onVoiceInput;

  /// Optional direct callback when the mic button is tapped.
  /// When provided, this is called immediately on tap, allowing the consuming app
  /// to perform custom speech flows and manually call [RichEditorController.insertHtml].
  final void Function()? onMicPressed;

  /// Called when the user taps the mic button to start recording.
  ///
  /// Must start the microphone and return the raw audio bytes when recording
  /// ends (i.e. when the user taps the button a second time).
  final Future<Uint8List> Function()? onVoiceRecord;

  /// Called with the recorded audio bytes after recording stops.
  ///
  /// Must call your voice-to-HTML API and return the HTML string that will
  /// be inserted into the editor.
  final Future<String> Function(Uint8List bytes)? onVoiceTranscribe;

  /// Optional error callback.  Receives a human-readable message when
  /// recording or transcription fails.  Defaults to showing a [SnackBar]
  /// when null.
  final void Function(String message)? onVoiceError;

  /// Controls where the transcribed HTML is inserted in the document.
  /// Defaults to [VoiceInsertMode.insertAtCursor].
  final VoiceInsertMode voiceInsertMode;

  /// Whether voice input callbacks are configured.
  bool get hasVoiceInput =>
      onVoiceInput != null ||
      onMicPressed != null ||
      (onVoiceRecord != null && onVoiceTranscribe != null);

  /// Filters and reorders items according to this configuration.
  List<ToolbarItem> apply(List<ToolbarItem> baseItems) {
    final Map<String, ToolbarItem> allItemsMap = <String, ToolbarItem>{};

    for (final ToolbarItem item in baseItems) {
      if (!hiddenItemIds.contains(item.id)) {
        allItemsMap[item.id] = item;
      }
    }

    for (final ToolbarItem item in customItems) {
      if (!hiddenItemIds.contains(item.id)) {
        allItemsMap[item.id] = item;
      }
    }

    if (orderedItemIds.isEmpty) {
      return allItemsMap.values.toList();
    }

    final List<ToolbarItem> result = <ToolbarItem>[];
    for (final String id in orderedItemIds) {
      if (allItemsMap.containsKey(id)) {
        result.add(allItemsMap.remove(id)!);
      }
    }

    // Append any remaining unmentioned items
    result.addAll(allItemsMap.values);
    return result;
  }
}
