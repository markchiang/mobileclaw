import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileclaw_app/core/models/chat_models.dart';
import 'package:mobileclaw_app/core/providers/llm_provider.dart';
import 'package:mobileclaw_app/core/services/ai_runtime.dart';
import 'package:mobileclaw_app/core/services/jsonl_memory_store.dart';
import 'package:mobileclaw_app/core/services/openclaw_bridge.dart';
import 'package:mobileclaw_app/core/services/web_config_store.dart';

class _StaticProvider implements LlmProvider {
  List<ChatMessage> lastMessages = const <ChatMessage>[];

  @override
  String get defaultModel => 'test/model';

  @override
  Future<LlmResponse> chat({
    required List<ChatMessage> messages,
    required String model,
    Map<String, Object?> options = const <String, Object?>{},
  }) async {
    lastMessages = List<ChatMessage>.from(messages);
    return LlmResponse(content: 'assistant-reply');
  }
}

class _ToolCallingProvider implements LlmProvider {
  var _step = 0;

  @override
  String get defaultModel => 'test/model';

  @override
  Future<LlmResponse> chat({
    required List<ChatMessage> messages,
    required String model,
    Map<String, Object?> options = const <String, Object?>{},
  }) async {
    if (_step == 0) {
      _step += 1;
      return LlmResponse(
        content: '',
        toolCalls: const <LlmToolCall>[
          LlmToolCall(
            id: 'call_1',
            name: 'write_workspace_doc',
            argumentsJson:
                '{"path":"memory/MEMORY.md","content":"# MEMORY\\n- user likes tea"}',
          ),
        ],
      );
    }
    return LlmResponse(content: 'memory updated');
  }
}

void main() {
  test('summary is generated from most recent messages', () async {
    final root = await Directory.systemTemp.createTemp('mobileclaw-runtime-');
    try {
      final memory = JsonlMemoryStore(root);
      await memory.init();
      final workspace = Directory('${root.path}/workspace')
        ..createSync(recursive: true);
      await File('${workspace.path}/AGENTS.md').writeAsString('# Agent rules');
      await File('${workspace.path}/IDENTITY.md')
          .writeAsString('# Agent identity');
      await Directory('${workspace.path}/memory').create(recursive: true);
      await File('${workspace.path}/memory/MEMORY.md')
          .writeAsString('# Long memory');
      await File('${workspace.path}/project-note.md')
          .writeAsString('note-content');
      final bridge = OpenclawBridge(
        appWorkspace: workspace,
        memoryStore: memory,
        webConfigStore: WebConfigStore(root),
      );
      final provider = _StaticProvider();
      final runtime = AiRuntime(
        provider: provider,
        memoryStore: memory,
        bridge: bridge,
      );

      final seed = List<ChatMessage>.generate(
        8,
        (int i) => ChatMessage(
          role: i.isEven ? ChatRole.user : ChatRole.assistant,
          content: 'seed-$i',
          sessionKey: 'default',
          createdAt: DateTime.now(),
        ),
      );
      await memory.setHistory('default', seed);

      await runtime.handleUserMessage(sessionKey: 'default', input: 'new-user');
      final summary = await memory.getSummary('default');

      expect(summary, contains('new-user'));
      expect(summary, contains('assistant-reply'));
      expect(summary, isNot(contains('seed-0')));

      final system =
          provider.lastMessages.firstWhere((m) => m.role == ChatRole.system);
      expect(system.content, contains('## AGENTS.md'));
      expect(system.content, contains('## IDENTITY.md'));
      expect(system.content, contains('## MEMORY.md'));
      expect(system.content, contains('[Workspace Attachments]'));
      expect(system.content, contains('## project-note.md'));
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });

  test('tool loop can update workspace memory markdown', () async {
    final root = await Directory.systemTemp.createTemp('mobileclaw-runtime-');
    try {
      final memory = JsonlMemoryStore(root);
      await memory.init();
      final workspace = Directory('${root.path}/workspace')
        ..createSync(recursive: true);
      final bridge = OpenclawBridge(
        appWorkspace: workspace,
        memoryStore: memory,
        webConfigStore: WebConfigStore(root),
      );
      final runtime = AiRuntime(
        provider: _ToolCallingProvider(),
        memoryStore: memory,
        bridge: bridge,
      );

      final reply = await runtime.handleUserMessage(
          sessionKey: 'default', input: 'remember tea');
      expect(reply.content, 'memory updated');

      final memoryFile = File('${workspace.path}/memory/MEMORY.md');
      expect(await memoryFile.exists(), isTrue);
      expect(await memoryFile.readAsString(), contains('user likes tea'));
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });
}
