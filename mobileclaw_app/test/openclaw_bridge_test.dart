import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileclaw_app/core/services/cron_service.dart';
import 'package:mobileclaw_app/core/services/jsonl_memory_store.dart';
import 'package:mobileclaw_app/core/services/openclaw_bridge.dart';
import 'package:mobileclaw_app/core/services/skill_registry_service.dart';
import 'package:mobileclaw_app/core/services/web_config_store.dart';

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
        webConfigStore: WebConfigStore(appRoot),
        cronService: CronService(appRoot),
        skillRegistryService: SkillRegistryService(
            workspaceDir: Directory('${appRoot.path}/workspace')),
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

    test('web_search returns error when disabled in settings', () async {
      final webStore = WebConfigStore(appRoot);
      await webStore.save(WebConfig.defaults.copyWith(enabled: false));
      final out = await bridge.executeWorkspaceTool(
        'web_search',
        <String, dynamic>{'query': 'OpenAI'},
      );
      expect(out, contains('"ok":false'));
      expect(out, contains('disabled'));
    });

    test('cron tool add/list/remove works', () async {
      final add = await bridge.executeWorkspaceTool('cron', <String, dynamic>{
        'action': 'add',
        'message': 'test cron',
        'at_seconds': 120,
      });
      expect(add, contains('"ok":true'));

      final list = await bridge.executeWorkspaceTool('cron', <String, dynamic>{
        'action': 'list',
      });
      expect(list, contains('"jobs"'));
      final match = RegExp(r'"id":"([^"]+)"').firstMatch(list);
      expect(match, isNotNull);
      final jobId = match!.group(1)!;

      final remove =
          await bridge.executeWorkspaceTool('cron', <String, dynamic>{
        'action': 'remove',
        'job_id': jobId,
      });
      expect(remove, contains('"ok":true'));
    });

    test('file and exec tools work inside workspace', () async {
      final write =
          await bridge.executeWorkspaceTool('write_file', <String, dynamic>{
        'path': 'notes/todo.txt',
        'content': 'alpha',
      });
      expect(write, contains('"ok":true'));

      final append =
          await bridge.executeWorkspaceTool('append_file', <String, dynamic>{
        'path': 'notes/todo.txt',
        'content': '\nbeta',
      });
      expect(append, contains('"ok":true'));

      final read =
          await bridge.executeWorkspaceTool('read_file', <String, dynamic>{
        'path': 'notes/todo.txt',
      });
      final readJson = jsonDecode(read) as Map<String, dynamic>;
      expect(readJson['ok'], isTrue);
      expect('${readJson['content']}', contains('alpha'));
      expect('${readJson['content']}', contains('beta'));

      final edit =
          await bridge.executeWorkspaceTool('edit_file', <String, dynamic>{
        'path': 'notes/todo.txt',
        'old_text': 'beta',
        'new_text': 'gamma',
      });
      expect(edit, contains('"ok":true'));
      final fileText =
          await File('${appRoot.path}/workspace/notes/todo.txt').readAsString();
      expect(fileText, contains('gamma'));

      final list =
          await bridge.executeWorkspaceTool('list_dir', <String, dynamic>{
        'path': 'notes',
      });
      expect(list, contains('todo.txt'));

      final exec = await bridge.executeWorkspaceTool('exec', <String, dynamic>{
        'command': 'cat notes/todo.txt',
      });
      final execJson = jsonDecode(exec) as Map<String, dynamic>;
      expect(execJson['ok'], isTrue);
      expect(execJson['exit_code'], 0);
      expect('${execJson['stdout']}', contains('gamma'));
    });

    test('tools reject path escaping workspace', () async {
      final read =
          await bridge.executeWorkspaceTool('read_file', <String, dynamic>{
        'path': '../outside.txt',
      });
      expect(read, contains('"ok":false'));
      expect(read, contains('escapes workspace'));
    });
  });
}
