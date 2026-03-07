import '../models/chat_models.dart';
import 'llm_provider.dart';

class MockLlmProvider implements LlmProvider {
  @override
  String get defaultModel => 'mock/mobileclaw-v1';

  @override
  Future<LlmResponse> chat({
    required List<ChatMessage> messages,
    required String model,
    Map<String, Object?> options = const <String, Object?>{},
  }) async {
    final user = messages.where((m) => m.role == ChatRole.user).toList();
    final latest = user.isNotEmpty ? user.last.content : '...';
    return LlmResponse(
      content: 'Mock($model): 已收到「$latest」',
      reasoning: 'mock-provider',
    );
  }
}
