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

class ChatSessionItem {
  const ChatSessionItem({
    required this.key,
    required this.title,
    required this.updatedAt,
  });

  final String key;
  final String title;
  final DateTime updatedAt;
}

class ChatController extends ChangeNotifier {
  ChatController({required this.appRoot, String initialSessionKey = 'default'})
      : _sessionKey = initialSessionKey;

  final Directory appRoot;
  String _sessionKey;

  late final JsonlMemoryStore memoryStore;
  late final OpenclawBridge bridge;
  late final LlmConfigStore llmConfigStore;
  late final AiRuntime runtime;

  final List<ChatMessage> messages = <ChatMessage>[];
  final List<ChatSessionItem> sessions = <ChatSessionItem>[];
  bool isBusy = false;

  String get currentSessionKey => _sessionKey;

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

    await _loadSession(_sessionKey);
    await _reloadSessions();
    if (sessions.isEmpty) {
      sessions.add(
        ChatSessionItem(
          key: _sessionKey,
          title: _sessionTitle(_sessionKey, ''),
          updatedAt: DateTime.now(),
        ),
      );
    }
    notifyListeners();
  }

  Future<void> createNewChat() async {
    if (isBusy) {
      return;
    }
    final now = DateTime.now();
    var key = 'chat-${now.millisecondsSinceEpoch}';
    final existing = (await memoryStore.listSessions()).toSet();
    var i = 1;
    while (existing.contains(key)) {
      key = 'chat-${now.millisecondsSinceEpoch}-$i';
      i += 1;
    }
    _sessionKey = key;
    messages.clear();
    await memoryStore.setHistory(_sessionKey, const <ChatMessage>[]);
    await memoryStore.setSummary(_sessionKey, '');
    await _reloadSessions();
    notifyListeners();
  }

  Future<void> switchSession(String sessionKey) async {
    if (isBusy || sessionKey.trim().isEmpty || sessionKey == _sessionKey) {
      return;
    }
    _sessionKey = sessionKey;
    await _loadSession(_sessionKey);
    await _reloadSessions();
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
      await runtime.handleUserMessage(sessionKey: _sessionKey, input: clean);
      await _loadSession(_sessionKey);
      await _reloadSessions();
    } catch (e) {
      final err = ChatMessage(
        role: ChatRole.assistant,
        content: 'LLM 呼叫失敗: $e',
        sessionKey: _sessionKey,
        createdAt: DateTime.now(),
      );
      await memoryStore.addFullMessage(err);
      await _loadSession(_sessionKey);
      await _reloadSessions();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> _loadSession(String sessionKey) async {
    messages
      ..clear()
      ..addAll(await memoryStore.getHistory(sessionKey));
  }

  Future<void> _reloadSessions() async {
    final keys = await memoryStore.listSessions();
    final items = <ChatSessionItem>[];
    for (final key in keys) {
      final meta = await memoryStore.readMeta(key);
      items.add(
        ChatSessionItem(
          key: key,
          title: _sessionTitle(key, meta.summary),
          updatedAt: meta.updatedAt,
        ),
      );
    }
    if (items.every((e) => e.key != _sessionKey)) {
      items.add(
        ChatSessionItem(
          key: _sessionKey,
          title: _sessionTitle(_sessionKey, ''),
          updatedAt: DateTime.now(),
        ),
      );
    }
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    sessions
      ..clear()
      ..addAll(items);
  }

  String _sessionTitle(String key, String summary) {
    final source = summary.trim().isEmpty ? key : summary.trim();
    final singleLine = source.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= 32) {
      return singleLine;
    }
    return '${singleLine.substring(0, 32)}...';
  }
}
