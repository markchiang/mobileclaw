import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileclaw_app/features/chat/chat_controller.dart';
import 'package:mobileclaw_app/core/models/chat_models.dart';
import 'package:mobileclaw_app/core/services/jsonl_memory_store.dart';

void main() {
  test('loads sessions, can switch session, and create new chat', () async {
    final root =
        await Directory.systemTemp.createTemp('mobileclaw-controller-');
    try {
      final memory = JsonlMemoryStore(root);
      await memory.init();
      await memory.setHistory('chat-a', <ChatMessage>[
        ChatMessage(
          role: ChatRole.user,
          content: 'hello-a',
          sessionKey: 'chat-a',
          createdAt: DateTime.now(),
        ),
      ]);
      await memory.setSummary(
        'chat-a',
        'Session A summary that is intentionally long for clipping behavior',
      );

      await memory.setHistory('chat-b', <ChatMessage>[
        ChatMessage(
          role: ChatRole.user,
          content: 'hello-b',
          sessionKey: 'chat-b',
          createdAt: DateTime.now(),
        ),
      ]);
      await memory.setSummary('chat-b', 'Session B summary');

      final controller =
          ChatController(appRoot: root, initialSessionKey: 'chat-a');
      await controller.init();

      expect(controller.currentSessionKey, 'chat-a');
      expect(controller.messages, isNotEmpty);
      expect(controller.messages.first.content, 'hello-a');
      expect(controller.sessions.map((e) => e.key),
          containsAll(<String>['chat-a', 'chat-b']));

      await controller.switchSession('chat-b');
      expect(controller.currentSessionKey, 'chat-b');
      expect(controller.messages, isNotEmpty);
      expect(controller.messages.first.content, 'hello-b');

      await controller.createNewChat();
      expect(controller.currentSessionKey, startsWith('chat-'));
      expect(controller.messages, isEmpty);
      expect(
        controller.sessions.any((e) => e.key == controller.currentSessionKey),
        isTrue,
      );
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });
}
