import 'dart:async';
import '../core/document_model/document_value.dart';
import '../features/collaboration_basic/collaboration_plugin.dart';

/// Abstract contract for an AI assistant provider without embedding credentials.
abstract class AiAssistantProvider {
  const AiAssistantProvider();

  /// Requests a trackable suggestion to improve, complete, or rephrase content.
  Future<ContentSuggestion> generateSuggestion({
    required DocumentValue document,
    required String selectedText,
    required String prompt,
    required EditorUser user,
  });
}

/// A mock/reference AI assistant provider that operates without network credentials.
class MockAiAssistantProvider extends AiAssistantProvider {
  const MockAiAssistantProvider();

  @override
  Future<ContentSuggestion> generateSuggestion({
    required DocumentValue document,
    required String selectedText,
    required String prompt,
    required EditorUser user,
  }) async {
    final String improved = selectedText.isNotEmpty
        ? 'Improved: $selectedText'
        : 'Suggested content for "$prompt"';

    final String targetNodeId = document.nodes.isNotEmpty
        ? document.nodes[document.selection.nodeIndex.clamp(0, document.nodes.length - 1)].id
        : 'root_0';

    return ContentSuggestion(
      id: 'sug_${DateTime.now().millisecondsSinceEpoch}',
      nodeId: targetNodeId,
      author: user,
      originalText: selectedText,
      suggestedText: improved,
    );
  }
}
