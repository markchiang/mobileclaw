import '../models/chat_models.dart';

class LlmToolDefinition {
  const LlmToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, Object?> parameters;
}

class LlmToolCall {
  const LlmToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  final String id;
  final String name;
  final String argumentsJson;
}

class LlmResponse {
  LlmResponse({
    required this.content,
    this.reasoning = '',
    this.toolCalls = const <LlmToolCall>[],
  });

  final String content;
  final String reasoning;
  final List<LlmToolCall> toolCalls;
}

abstract class LlmProvider {
  Future<LlmResponse> chat({
    required List<ChatMessage> messages,
    required String model,
    Map<String, Object?> options = const <String, Object?>{},
  });

  String get defaultModel;
}
