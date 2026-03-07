import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileclaw_app/core/services/jsonl_memory_store.dart';
import 'package:mobileclaw_app/core/services/openclaw_bridge.dart';

void main() {
  group('OpenclawBridge', () {
    late Directory appRoot;
    late Directory openclawHome;
    late OpenclawBridge bridge;

    setUp(() async {
      appRoot = await Directory.systemTemp.createTemp('mobileclaw-app-');
      openclawHome = await Directory.systemTemp.createTemp('openclaw-home-');
      await Directory('${openclawHome.path}/workspace/skills/demo')
          .create(recursive: true);
      await Directory('${openclawHome.path}/workspace/memory')
          .create(recursive: true);
      await File('${openclawHome.path}/workspace/AGENTS.md')
          .writeAsString('# OpenClaw Agents');
      await File('${openclawHome.path}/workspace/IDENTITY.md')
          .writeAsString('# OpenClaw Identity');
      await File('${openclawHome.path}/workspace/skills/demo/SKILL.md')
          .writeAsString('# Demo Skill');
      await File('${openclawHome.path}/workspace/memory/default.md')
          .writeAsString('''
- user: hello
- assistant: hi
''');

      final store = JsonlMemoryStore(appRoot);
      await store.init();
      bridge = OpenclawBridge(
        appWorkspace: Directory('${appRoot.path}/workspace'),
        memoryStore: store,
      );
    });

    tearDown(() async {
      if (await appRoot.exists()) {
        await appRoot.delete(recursive: true);
      }
      if (await openclawHome.exists()) {
        await openclawHome.delete(recursive: true);
      }
    });

    test('imports and exports workspace and memory', () async {
      await bridge.importFromOpenclaw(openclawHome);
      expect(
          await File('${appRoot.path}/workspace/AGENTS.md').exists(), isTrue);
      expect(
          await File('${appRoot.path}/workspace/IDENTITY.md').exists(), isTrue);

      final exportHome =
          await Directory.systemTemp.createTemp('openclaw-export-');
      try {
        await bridge.exportToOpenclaw(exportHome);
        expect(await File('${exportHome.path}/workspace/AGENTS.md').exists(),
            isTrue);
        expect(await File('${exportHome.path}/workspace/IDENTITY.md').exists(),
            isTrue);
        expect(
            await File('${exportHome.path}/workspace/memory/default.md')
                .exists(),
            isTrue);
      } finally {
        if (await exportHome.exists()) {
          await exportHome.delete(recursive: true);
        }
      }
    });
  });
}
