import 'dart:convert';

import '../models/chat_models.dart';
import '../providers/llm_provider.dart';
import 'jsonl_memory_store.dart';
import 'openclaw_bridge.dart';

class AiRuntime {
  AiRuntime({
    required this.provider,
    required this.memoryStore,
    required this.bridge,
    this.model,
  });

  final LlmProvider provider;
  final JsonlMemoryStore memoryStore;
  final OpenclawBridge bridge;
  final String? model;

  Future<ChatMessage> handleUserMessage({
    required String sessionKey,
    required String input,
  }) async {
    await memoryStore.addMessage(sessionKey, ChatRole.user, input);

    final history = await memoryStore.getHistory(sessionKey);
    final context = await bridge.buildRuntimeContext();

    final promptMessages = <ChatMessage>[
      ChatMessage(
        role: ChatRole.system,
        content: context,
        sessionKey: sessionKey,
        createdAt: DateTime.now(),
      ),
      ...history,
    ];

    final assistant = await _runWithWorkspaceTools(
      promptMessages: promptMessages,
      sessionKey: sessionKey,
    );

    await memoryStore.addFullMessage(assistant);
    await _refreshSummary(sessionKey);
    return assistant;
  }

  Future<ChatMessage> _runWithWorkspaceTools({
    required List<ChatMessage> promptMessages,
    required String sessionKey,
  }) async {
    final convo = <ChatMessage>[...promptMessages];
    final tools = bridge.workspaceTools();

    for (var i = 0; i < 6; i += 1) {
      final resp = await provider.chat(
        messages: convo,
        model: model ?? provider.defaultModel,
        options: <String, Object?>{
          'tools': tools,
        },
      );

      if (resp.toolCalls.isEmpty) {
        return ChatMessage(
          role: ChatRole.assistant,
          content: resp.content,
          sessionKey: sessionKey,
          createdAt: DateTime.now(),
        );
      }

      convo.add(
        ChatMessage(
          role: ChatRole.assistant,
          content: resp.content,
          sessionKey: sessionKey,
          createdAt: DateTime.now(),
          toolCalls: resp.toolCalls
              .map(
                (t) => ToolCallRecord(
                  id: t.id,
                  name: t.name,
                  argumentsJson: t.argumentsJson,
                ),
              )
              .toList(),
        ),
      );

      for (final call in resp.toolCalls) {
        Map<String, dynamic> args;
        try {
          args =
              (jsonDecode(call.argumentsJson) as Map).cast<String, dynamic>();
        } catch (_) {
          args = <String, dynamic>{};
        }
        final output = await bridge.executeWorkspaceTool(call.name, args);
        convo.add(
          ChatMessage(
            role: ChatRole.tool,
            content: output,
            toolCallId: call.id,
            sessionKey: sessionKey,
            createdAt: DateTime.now(),
          ),
        );
      }
    }

    return ChatMessage(
      role: ChatRole.assistant,
      content: '工具迭代次數過多，已中止。請再試一次。',
      sessionKey: sessionKey,
      createdAt: DateTime.now(),
    );
  }

  Future<void> _refreshSummary(String sessionKey) async {
    final history = await memoryStore.getHistory(sessionKey);
    if (history.isEmpty) {
      return;
    }
    final start = history.length > 6 ? history.length - 6 : 0;
    final latest = history
        .sublist(start)
        .map((m) => '${m.role.name}: ${m.content}')
        .join(' | ');
    final summary = latest.length > 240 ? latest.substring(0, 240) : latest;
    await memoryStore.setSummary(sessionKey, summary);
  }
}
