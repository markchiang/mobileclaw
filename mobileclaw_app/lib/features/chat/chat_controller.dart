import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/models/chat_models.dart';
import '../../core/providers/openai_compatible_provider.dart';
import '../../core/services/ai_runtime.dart';
import '../../core/services/cron_service.dart';
import '../../core/services/jsonl_memory_store.dart';
import '../../core/services/llm_config_store.dart';
import '../../core/services/openclaw_bridge.dart';
import '../../core/services/skill_registry_service.dart';
import '../../core/services/web_config_store.dart';

class ChatController extends ChangeNotifier {
  ChatController({required this.appRoot, this.sessionKey = 'default'});

  final Directory appRoot;
  final String sessionKey;

  late final JsonlMemoryStore memoryStore;
  late final OpenclawBridge bridge;
  late final LlmConfigStore llmConfigStore;
  late final AiRuntime runtime;

  final List<ChatMessage> messages = <ChatMessage>[];
  bool isBusy = false;

  Future<void> init() async {
    final workspace = Directory('${appRoot.path}/workspace');
    await workspace.create(recursive: true);
    memoryStore = JsonlMemoryStore(appRoot);
    await memoryStore.init();

    bridge = OpenclawBridge(
      appWorkspace: workspace,
      memoryStore: memoryStore,
      webConfigStore: WebConfigStore(appRoot),
      cronService: CronService(appRoot),
      skillRegistryService: SkillRegistryService(workspaceDir: workspace),
    );
    llmConfigStore = LlmConfigStore(appRoot);
    final llmConfig = await llmConfigStore.load();
    runtime = AiRuntime(
      provider: OpenAiCompatibleProvider(configStore: llmConfigStore),
      memoryStore: memoryStore,
      bridge: bridge,
      maxToolIterations: llmConfig.maxToolIterations,
    );

    messages
      ..clear()
      ..addAll(await memoryStore.getHistory(sessionKey));
    notifyListeners();
  }

  Future<void> send(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || isBusy) {
      return;
    }

    isBusy = true;
    notifyListeners();

    try {
      await runtime.handleUserMessage(sessionKey: sessionKey, input: clean);
      messages
        ..clear()
        ..addAll(await memoryStore.getHistory(sessionKey));
    } catch (e) {
      final err = ChatMessage(
        role: ChatRole.assistant,
        content: 'LLM 呼叫失敗: $e',
        sessionKey: sessionKey,
        createdAt: DateTime.now(),
      );
      await memoryStore.addFullMessage(err);
      messages
        ..clear()
        ..addAll(await memoryStore.getHistory(sessionKey));
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }
}
