import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/skill_models.dart';

class SkillLoader {
  SkillLoader({required this.workspaceDir});

  final Directory workspaceDir;

  Future<AgentWorkspaceProfile> loadWorkspaceProfile() async {
    final agents =
        await _readFirstMatch(const <String>['AGENTS.md', 'AGENT.md']);
    final soul = await _readFirstMatch(const <String>['SOUL.md', 'SOAL.md']);
    final user = await _readFirstMatch(const <String>['USER.md']);
    final identity = await _readFirstMatch(const <String>['IDENTITY.md']);
    final memory = await _readFirstMatch(const <String>[
      'memory/MEMORY.md',
      'MEMORY.md',
    ]);
    final tools = await _readFirstMatch(const <String>['TOOLS.md']);
    final heartbeat = await _readFirstMatch(const <String>['HEARTBEAT.md']);
    final extraDocs = await _listExtraDocs();
    final skills = await listSkills();

    return AgentWorkspaceProfile(
      agentsMd: agents,
      soulMd: soul,
      userMd: user,
      identityMd: identity,
      memoryMd: memory,
      toolsMd: tools,
      heartbeatMd: heartbeat,
      extraDocs: extraDocs,
      skills: skills,
    );
  }

  Future<List<SkillDefinition>> _listExtraDocs() async {
    final known = <String>{
      'AGENTS.md',
      'AGENT.md',
      'SOUL.md',
      'SOAL.md',
      'USER.md',
      'IDENTITY.md',
      'MEMORY.md',
      'TOOLS.md',
      'HEARTBEAT.md',
    };

    final docs = <SkillDefinition>[];
    await for (final ent in workspaceDir.list()) {
      if (ent is! File) {
        continue;
      }
      final name = p.basename(ent.path);
      final ext = p.extension(name).toLowerCase();
      if (ext != '.md' || known.contains(name)) {
        continue;
      }
      final raw = await ent.readAsString();
      if (raw.trim().isEmpty) {
        continue;
      }
      docs.add(
        SkillDefinition(
          name: name,
          path: ent.path,
          content: raw.trim(),
          source: 'workspace',
        ),
      );
    }
    docs.sort((a, b) => a.name.compareTo(b.name));
    return docs;
  }

  Future<List<SkillDefinition>> listSkills() async {
    final skillsDir = Directory(p.join(workspaceDir.path, 'skills'));
    if (!await skillsDir.exists()) {
      return <SkillDefinition>[];
    }

    final result = <SkillDefinition>[];
    await for (final ent in skillsDir.list()) {
      if (ent is! Directory) {
        continue;
      }
      final skillFile = File(p.join(ent.path, 'SKILL.md'));
      if (!await skillFile.exists()) {
        continue;
      }
      final raw = await skillFile.readAsString();
      final meta = _extractFrontmatter(raw);
      result.add(
        SkillDefinition(
          name: meta['name']?.trim().isNotEmpty == true
              ? meta['name']!.trim()
              : p.basename(ent.path),
          description: meta['description'] ?? '',
          path: skillFile.path,
          content: _stripFrontmatter(raw).trim(),
          source: 'workspace',
        ),
      );
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  Map<String, String> _extractFrontmatter(String content) {
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (!normalized.startsWith('---\n')) {
      return <String, String>{};
    }
    final end = normalized.indexOf('\n---\n', 4);
    if (end < 0) {
      return <String, String>{};
    }

    final body = normalized.substring(4, end);
    final map = <String, String>{};
    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || !line.contains(':')) {
        continue;
      }
      final idx = line.indexOf(':');
      final key = line.substring(0, idx).trim();
      var value = line.substring(idx + 1).trim();
      final quotedBySingle =
          value.length >= 2 && value.startsWith("'") && value.endsWith("'");
      final quotedByDouble =
          value.length >= 2 && value.startsWith('"') && value.endsWith('"');
      if (quotedBySingle || quotedByDouble) {
        value = value.substring(1, value.length - 1);
      }
      map[key] = value;
    }
    return map;
  }

  String _stripFrontmatter(String content) {
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (!normalized.startsWith('---\n')) {
      return content;
    }
    final end = normalized.indexOf('\n---\n', 4);
    if (end < 0) {
      return content;
    }
    return normalized.substring(end + 5);
  }

  Future<String> _readIfExists(File file) async {
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  Future<String> _readFirstMatch(List<String> names) async {
    for (final name in names) {
      final content =
          await _readIfExists(File(p.join(workspaceDir.path, name)));
      if (content.trim().isNotEmpty) {
        return content;
      }
    }
    return '';
  }
}
