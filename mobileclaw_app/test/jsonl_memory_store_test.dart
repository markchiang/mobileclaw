import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileclaw_app/core/models/chat_models.dart';
import 'package:mobileclaw_app/core/services/jsonl_memory_store.dart';

void main() {
  group('JsonlMemoryStore', () {
    late Directory tmp;
    late JsonlMemoryStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('mobileclaw-mem-');
      store = JsonlMemoryStore(tmp);
      await store.init();
    });

    tearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    test('append and read history', () async {
      await store.addMessage('telegram:1', ChatRole.user, 'hello');
      await store.addMessage('telegram:1', ChatRole.assistant, 'world');

      final history = await store.getHistory('telegram:1');
      expect(history.length, 2);
      expect(history.first.content, 'hello');
      expect(history.last.content, 'world');
    });

    test('set summary and truncate', () async {
      await store.setHistory('default', <ChatMessage>[
        ChatMessage(role: ChatRole.user, content: 'a', sessionKey: 'default', createdAt: DateTime.now()),
        ChatMessage(role: ChatRole.assistant, content: 'b', sessionKey: 'default', createdAt: DateTime.now()),
        ChatMessage(role: ChatRole.user, content: 'c', sessionKey: 'default', createdAt: DateTime.now()),
      ]);
      await store.setSummary('default', 'summary-1');
      await store.truncateHistory('default', 1);

      final summary = await store.getSummary('default');
      final history = await store.getHistory('default');

      expect(summary, 'summary-1');
      expect(history.length, 1);
      expect(history.first.content, 'c');
    });

    test('list sessions keeps original session key from metadata', () async {
      await store.addMessage('telegram:123', ChatRole.user, 'hello');
      final sessions = await store.listSessions();

      expect(sessions, contains('telegram:123'));
    });
  });
}
