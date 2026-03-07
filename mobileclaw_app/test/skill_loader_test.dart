import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileclaw_app/core/services/skill_loader.dart';

void main() {
  group('SkillLoader', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('mobileclaw-skills-');
      await File('${tmp.path}/AGENTS.md').writeAsString('# Agent rules');
      await File('${tmp.path}/IDENTITY.md').writeAsString('# Agent identity');
      await Directory('${tmp.path}/memory').create(recursive: true);
      await File('${tmp.path}/memory/MEMORY.md').writeAsString('# User memory');
      await Directory('${tmp.path}/skills/code-review').create(recursive: true);
      await File('${tmp.path}/skills/code-review/SKILL.md').writeAsString('''
---
name: code-review
description: Review code risks
---
# Code Review Skill
''');
    });

    tearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    test('loads profile and skills', () async {
      final loader = SkillLoader(workspaceDir: tmp);
      final profile = await loader.loadWorkspaceProfile();

      expect(profile.agentsMd, contains('Agent rules'));
      expect(profile.identityMd, contains('Agent identity'));
      expect(profile.memoryMd, contains('User memory'));
      expect(profile.skills.length, 1);
      expect(profile.skills.first.name, 'code-review');
      expect(profile.skills.first.description, 'Review code risks');
      expect(profile.skills.first.content, contains('Code Review Skill'));
    });
  });
}
