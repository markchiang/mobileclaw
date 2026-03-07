import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/chat_models.dart';
import '../providers/llm_provider.dart';
import 'jsonl_memory_store.dart';
import 'skill_loader.dart';

class ImportSummary {
  const ImportSummary({
    required this.copiedFiles,
    required this.importedSessions,
    required this.structuredWorkspace,
  });

  final int copiedFiles;
  final int importedSessions;
  final bool structuredWorkspace;
}

class ImportedFileData {
  const ImportedFileData({
    required this.name,
    required this.bytes,
  });

  final String name;
  final List<int> bytes;
}

class OpenclawBridge {
  OpenclawBridge({required this.appWorkspace, required this.memoryStore});

  final Directory appWorkspace;
  final JsonlMemoryStore memoryStore;

  List<LlmToolDefinition> workspaceTools() {
    return const <LlmToolDefinition>[
      LlmToolDefinition(
        name: 'list_workspace_docs',
        description:
            'List markdown files under workspace. Use this before reading files.',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'path': <String, Object?>{
              'type': 'string',
              'description': 'Optional relative path under workspace.',
            },
          },
          'additionalProperties': false,
        },
      ),
      LlmToolDefinition(
        name: 'read_workspace_doc',
        description:
            'Read a markdown file under workspace, especially memory/MEMORY.md and AGENTS.md/SOUL.md.',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'path': <String, Object?>{
              'type': 'string',
              'description': 'Relative path to a .md file in workspace.',
            },
          },
          'required': <String>['path'],
          'additionalProperties': false,
        },
      ),
      LlmToolDefinition(
        name: 'write_workspace_doc',
        description:
            'Overwrite a markdown file under workspace. Use to update memory/MEMORY.md.',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'path': <String, Object?>{
              'type': 'string',
              'description': 'Relative path to a .md file in workspace.',
            },
            'content': <String, Object?>{
              'type': 'string',
              'description': 'Full markdown content to write.',
            },
          },
          'required': <String>['path', 'content'],
          'additionalProperties': false,
        },
      ),
      LlmToolDefinition(
        name: 'append_workspace_doc',
        description:
            'Append text to a markdown file under workspace. Useful for memory logs.',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'path': <String, Object?>{
              'type': 'string',
              'description': 'Relative path to a .md file in workspace.',
            },
            'content': <String, Object?>{
              'type': 'string',
              'description': 'Text to append at the end.',
            },
          },
          'required': <String>['path', 'content'],
          'additionalProperties': false,
        },
      ),
    ];
  }

  Future<ImportSummary> importFromOpenclaw(Directory openclawHome) async {
    return importFromExternalDirectory(openclawHome);
  }

  Future<ImportSummary> importFromExternalDirectory(
      Directory selectedDir) async {
    final workspaceCandidate = Directory(p.join(selectedDir.path, 'workspace'));
    final srcWorkspace =
        await workspaceCandidate.exists() ? workspaceCandidate : selectedDir;
    await appWorkspace.create(recursive: true);

    var copied = 0;
    for (final fileName in const <String>[
      'AGENTS.md',
      'SOUL.md',
      'USER.md',
      'IDENTITY.md',
      'TOOLS.md',
      'HEARTBEAT.md'
    ]) {
      final src = File(p.join(srcWorkspace.path, fileName));
      if (await src.exists()) {
        await src.copy(p.join(appWorkspace.path, fileName));
        copied += 1;
      }
    }

    final srcSkills = Directory(p.join(srcWorkspace.path, 'skills'));
    if (await srcSkills.exists()) {
      copied += await _copyDir(
          srcSkills, Directory(p.join(appWorkspace.path, 'skills')));
    }

    final srcMemory = Directory(p.join(srcWorkspace.path, 'memory'));
    var importedSessions = 0;
    if (await srcMemory.exists()) {
      importedSessions = await _importMemoryMarkdown(srcMemory);
    }

    final structured = copied > 0 || importedSessions > 0;
    if (!structured) {
      copied += await _copySupportedFilesToWorkspace(selectedDir);
    }

    return ImportSummary(
      copiedFiles: copied,
      importedSessions: importedSessions,
      structuredWorkspace: structured,
    );
  }

  Future<ImportSummary> importPickedFiles(List<File> files) async {
    await appWorkspace.create(recursive: true);

    var copied = 0;
    for (final file in files) {
      if (!await file.exists() || !_isSupportedContentFile(file.path)) {
        continue;
      }
      final base = p.basename(file.path);
      final out = await _uniqueFile(appWorkspace, base);
      await file.copy(out.path);
      copied += 1;
    }

    return ImportSummary(
      copiedFiles: copied,
      importedSessions: 0,
      structuredWorkspace: false,
    );
  }

  Future<ImportSummary> importPickedFileData(
      List<ImportedFileData> files) async {
    await appWorkspace.create(recursive: true);

    var copied = 0;
    for (final file in files) {
      if (!_isSupportedContentFile(file.name)) {
        continue;
      }
      final out = await _uniqueFile(appWorkspace, p.basename(file.name));
      await out.writeAsBytes(file.bytes, flush: true);
      copied += 1;
    }

    return ImportSummary(
      copiedFiles: copied,
      importedSessions: 0,
      structuredWorkspace: false,
    );
  }

  Future<void> exportToOpenclaw(Directory openclawHome) async {
    final dstWorkspace = Directory(p.join(openclawHome.path, 'workspace'));
    await dstWorkspace.create(recursive: true);

    for (final fileName in const <String>[
      'AGENTS.md',
      'SOUL.md',
      'USER.md',
      'IDENTITY.md',
      'TOOLS.md',
      'HEARTBEAT.md'
    ]) {
      final src = File(p.join(appWorkspace.path, fileName));
      if (await src.exists()) {
        await src.copy(p.join(dstWorkspace.path, fileName));
      }
    }

    final srcSkills = Directory(p.join(appWorkspace.path, 'skills'));
    if (await srcSkills.exists()) {
      await _copyDir(srcSkills, Directory(p.join(dstWorkspace.path, 'skills')));
    }

    await _exportMemoryMarkdown(Directory(p.join(dstWorkspace.path, 'memory')));
  }

  Future<int> _importMemoryMarkdown(Directory srcMemory) async {
    await memoryStore.init();
    var sessions = 0;
    await for (final entity in srcMemory.list()) {
      if (entity is! File || !entity.path.endsWith('.md')) {
        continue;
      }
      final sessionKey = p.basenameWithoutExtension(entity.path);
      final raw = await entity.readAsString();
      final lines = raw.split('\n');

      final history = <ChatMessage>[];
      for (final line in lines) {
        if (line.startsWith('- user:')) {
          history.add(
            ChatMessage(
              role: ChatRole.user,
              content: line.replaceFirst('- user:', '').trim(),
              createdAt: DateTime.now(),
              sessionKey: sessionKey,
            ),
          );
        } else if (line.startsWith('- assistant:')) {
          history.add(
            ChatMessage(
              role: ChatRole.assistant,
              content: line.replaceFirst('- assistant:', '').trim(),
              createdAt: DateTime.now(),
              sessionKey: sessionKey,
            ),
          );
        }
      }
      if (history.isNotEmpty) {
        await memoryStore.setHistory(sessionKey, history);
        sessions += 1;
      }
    }
    return sessions;
  }

  Future<void> _exportMemoryMarkdown(Directory dstMemory) async {
    await dstMemory.create(recursive: true);
    final sessions = await memoryStore.listSessions();

    for (final session in sessions) {
      final history = await memoryStore.getHistory(session);
      if (history.isEmpty) {
        continue;
      }
      final buff = StringBuffer('# Memory: $session\n\n');
      for (final msg in history) {
        if (msg.role == ChatRole.user) {
          buff.writeln('- user: ${msg.content}');
        } else if (msg.role == ChatRole.assistant) {
          buff.writeln('- assistant: ${msg.content}');
        }
      }
      await File(p.join(dstMemory.path, '$session.md'))
          .writeAsString(buff.toString());
    }
  }

  Future<int> _copyDir(Directory source, Directory target) async {
    await target.create(recursive: true);
    var copied = 0;
    await for (final entity in source.list(recursive: true)) {
      final rel = p.relative(entity.path, from: source.path);
      final outPath = p.join(target.path, rel);
      if (entity is Directory) {
        await Directory(outPath).create(recursive: true);
      } else if (entity is File) {
        await File(outPath).parent.create(recursive: true);
        await entity.copy(outPath);
        copied += 1;
      }
    }
    return copied;
  }

  Future<String> buildRuntimeContext() async {
    final loader = SkillLoader(workspaceDir: appWorkspace);
    final profile = await loader.loadWorkspaceProfile();
    const runtimeRules = '''
## Runtime Rules
- Before answering, consult workspace markdown files when relevant.
- Use tools to read/write markdown files under workspace.
- Persist long-term memory updates in memory/MEMORY.md when the user provides stable preferences or facts.
''';
    final workspaceAttachments = await _buildWorkspaceAttachmentContext();
    if (workspaceAttachments.isEmpty) {
      return '$runtimeRules\n\n${profile.asPromptContext()}';
    }
    return '$runtimeRules\n\n${profile.asPromptContext()}\n\n[Workspace Attachments]\n$workspaceAttachments';
  }

  Future<int> _copySupportedFilesToWorkspace(Directory source) async {
    var copied = 0;
    await for (final entity in source.list(recursive: true)) {
      if (entity is! File || !_isSupportedContentFile(entity.path)) {
        continue;
      }
      final out = await _uniqueFile(appWorkspace, p.basename(entity.path));
      await entity.copy(out.path);
      copied += 1;
    }
    return copied;
  }

  bool _isSupportedContentFile(String path) {
    final ext = p.extension(path).toLowerCase();
    return const <String>{'.md', '.txt', '.json', '.yaml', '.yml'}
        .contains(ext);
  }

  Future<File> _uniqueFile(Directory dir, String baseName) async {
    var file = File(p.join(dir.path, baseName));
    if (!await file.exists()) {
      return file;
    }
    final stem = p.basenameWithoutExtension(baseName);
    final ext = p.extension(baseName);
    var i = 1;
    while (true) {
      file = File(p.join(dir.path, '$stem-$i$ext'));
      if (!await file.exists()) {
        return file;
      }
      i += 1;
    }
  }

  Future<String> _buildWorkspaceAttachmentContext() async {
    final excluded = <String>{
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
    final lines = <String>[];
    var count = 0;
    await for (final entity in appWorkspace.list(recursive: true)) {
      if (entity is! File || !_isSupportedContentFile(entity.path)) {
        continue;
      }
      final relPath = p.relative(entity.path, from: appWorkspace.path);
      final base = p.basename(relPath);
      if (excluded.contains(base)) {
        continue;
      }
      final raw = await entity.readAsString();
      final content = raw.trim();
      if (content.isEmpty) {
        continue;
      }
      final clipped =
          content.length > 2000 ? content.substring(0, 2000) : content;
      lines.add('## $relPath\n$clipped');
      count += 1;
      if (count >= 12) {
        break;
      }
    }
    return lines.join('\n\n');
  }

  Future<String> executeWorkspaceTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      switch (name) {
        case 'list_workspace_docs':
          final pathArg = '${args['path'] ?? '.'}';
          final base = await _resolveWorkspacePath(
            pathArg,
            mustExist: true,
            allowDirectory: true,
          );
          if (base is! Directory) {
            throw const FileSystemException('path is not a directory');
          }
          final out = <String>[];
          if (await base.exists()) {
            await for (final entity in base.list(recursive: true)) {
              if (entity is! File) {
                continue;
              }
              if (p.extension(entity.path).toLowerCase() != '.md') {
                continue;
              }
              out.add(p.relative(entity.path, from: appWorkspace.path));
            }
          }
          out.sort();
          return jsonEncode(<String, Object?>{
            'ok': true,
            'files': out,
          });
        case 'read_workspace_doc':
          final rel = '${args['path'] ?? ''}'.trim();
          final file =
              File((await _resolveWorkspacePath(rel, mustExist: true)).path);
          final text = await file.readAsString();
          return jsonEncode(<String, Object?>{
            'ok': true,
            'path': p.relative(file.path, from: appWorkspace.path),
            'content': text,
          });
        case 'write_workspace_doc':
          final rel = '${args['path'] ?? ''}'.trim();
          final content = '${args['content'] ?? ''}';
          final file =
              File((await _resolveWorkspacePath(rel, mustExist: false)).path);
          await file.parent.create(recursive: true);
          await file.writeAsString(content);
          return jsonEncode(<String, Object?>{
            'ok': true,
            'path': p.relative(file.path, from: appWorkspace.path),
            'bytes': content.length,
          });
        case 'append_workspace_doc':
          final rel = '${args['path'] ?? ''}'.trim();
          final content = '${args['content'] ?? ''}';
          final file =
              File((await _resolveWorkspacePath(rel, mustExist: false)).path);
          await file.parent.create(recursive: true);
          await file.writeAsString(content, mode: FileMode.append);
          return jsonEncode(<String, Object?>{
            'ok': true,
            'path': p.relative(file.path, from: appWorkspace.path),
            'bytes': content.length,
          });
        default:
          return jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Unknown tool: $name',
          });
      }
    } catch (e) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'error': '$e',
      });
    }
  }

  Future<FileSystemEntity> _resolveWorkspacePath(
    String inputPath, {
    required bool mustExist,
    bool allowDirectory = false,
  }) async {
    final raw = inputPath.trim();
    if (raw.isEmpty) {
      throw ArgumentError('path is required');
    }
    final normalized = p.normalize(raw);
    final targetPath = p.normalize(p.join(appWorkspace.path, normalized));
    final rel = p.relative(targetPath, from: appWorkspace.path);
    if (rel == '..' || rel.startsWith('../')) {
      throw const FileSystemException('path escapes workspace');
    }
    if (allowDirectory && !normalized.endsWith('.md')) {
      final dir = Directory(targetPath);
      if (mustExist && !await dir.exists()) {
        throw FileSystemException('directory does not exist', targetPath);
      }
      return dir;
    }
    if (!normalized.endsWith('.md')) {
      throw const FileSystemException('only .md files are allowed');
    }

    final file = File(targetPath);
    if (mustExist && !await file.exists()) {
      throw FileSystemException('file does not exist', targetPath);
    }
    return file;
  }
}
