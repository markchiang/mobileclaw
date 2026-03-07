import 'dart:convert';
import 'dart:io';

import '../models/chat_models.dart';
import '../services/llm_config_store.dart';
import 'llm_provider.dart';

class OpenAiCompatibleProvider implements LlmProvider {
  OpenAiCompatibleProvider({required this.configStore});

  final LlmConfigStore configStore;

  @override
  String get defaultModel => 'gpt-4o-mini';

  @override
  Future<LlmResponse> chat({
    required List<ChatMessage> messages,
    required String model,
    Map<String, Object?> options = const <String, Object?>{},
  }) async {
    final cfg = await configStore.load();
    final providerId = cfg.selectedProvider;
    final profile = cfg.selectedProfile;

    final baseUrl = profile.baseUrl.trim();
    if (baseUrl.isEmpty) {
      throw StateError('LLM 未設定：請到 Settings 填入 Base URL。');
    }

    final apiKey = profile.apiKey.trim();
    if (llmProviderRequiresApiKey(providerId) && apiKey.isEmpty) {
      throw StateError('LLM 未設定：請到 Settings 填入 API Key。');
    }

    final selectedModel =
        profile.model.trim().isEmpty ? model : profile.model.trim();

    final uri = Uri.parse(baseUrl);
    final reqBody = <String, Object?>{
      'model': selectedModel,
      'messages': messages.map(_toOpenAiMessage).toList(),
    };
    final tools = options['tools'];
    if (tools is List<LlmToolDefinition> && tools.isNotEmpty) {
      reqBody['tools'] = tools
          .map(
            (t) => <String, Object?>{
              'type': 'function',
              'function': <String, Object?>{
                'name': t.name,
                'description': t.description,
                'parameters': t.parameters,
              },
            },
          )
          .toList();
      reqBody['tool_choice'] = 'auto';
    }

    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      if (apiKey.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      }
      req.add(utf8.encode(jsonEncode(reqBody)));

      final resp = await req.close();
      final body = await utf8.decodeStream(resp);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw HttpException('LLM API error ${resp.statusCode}: $body',
            uri: uri);
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      final choices = (json['choices'] as List<dynamic>? ?? <dynamic>[]);
      if (choices.isEmpty) {
        throw const FormatException('LLM response has no choices');
      }

      final first = choices.first as Map<String, dynamic>;
      final message = first['message'] as Map<String, dynamic>?;
      final contentRaw = message?['content'];
      final toolCallsRaw =
          (message?['tool_calls'] as List<dynamic>? ?? <dynamic>[]);
      final toolCalls = <LlmToolCall>[];
      for (final toolCall in toolCallsRaw) {
        if (toolCall is! Map<String, dynamic>) {
          continue;
        }
        final id = '${toolCall['id'] ?? ''}'.trim();
        final fn = toolCall['function'];
        if (id.isEmpty || fn is! Map<String, dynamic>) {
          continue;
        }
        final name = '${fn['name'] ?? ''}'.trim();
        final args = '${fn['arguments'] ?? '{}'}';
        if (name.isEmpty) {
          continue;
        }
        toolCalls.add(LlmToolCall(id: id, name: name, argumentsJson: args));
      }

      final content = _normalizeContent(contentRaw);
      if (content.trim().isEmpty && toolCalls.isEmpty) {
        throw const FormatException('LLM response content is empty');
      }

      return LlmResponse(content: content, toolCalls: toolCalls);
    } finally {
      client.close(force: true);
    }
  }

  String _normalizeContent(Object? raw) {
    if (raw is String) {
      return raw;
    }
    if (raw is List) {
      final out = StringBuffer();
      for (final part in raw) {
        if (part is Map<String, dynamic> && part['type'] == 'text') {
          out.write(part['text'] ?? '');
        }
      }
      return out.toString();
    }
    return '';
  }

  Map<String, Object?> _toOpenAiMessage(ChatMessage m) {
    if (m.role == ChatRole.tool) {
      return <String, Object?>{
        'role': 'tool',
        'content': m.content,
        if (m.toolCallId != null && m.toolCallId!.trim().isNotEmpty)
          'tool_call_id': m.toolCallId,
      };
    }
    if (m.role == ChatRole.assistant && m.toolCalls.isNotEmpty) {
      return <String, Object?>{
        'role': 'assistant',
        'content': m.content.trim().isEmpty ? null : m.content,
        'tool_calls': m.toolCalls
            .map(
              (t) => <String, Object?>{
                'id': t.id,
                'type': 'function',
                'function': <String, Object?>{
                  'name': t.name,
                  'arguments': t.argumentsJson,
                },
              },
            )
            .toList(),
      };
    }
    return <String, Object?>{
      'role': m.role.name,
      'content': m.content,
    };
  }
}
