import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/chat_models.dart';
import '../providers/llm_provider.dart';
import 'cron_service.dart';
import 'jsonl_memory_store.dart';
import 'skill_registry_service.dart';
import 'skill_loader.dart';
import 'web_config_store.dart';

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
  OpenclawBridge({
    required this.appWorkspace,
    required this.memoryStore,
    required this.webConfigStore,
    required this.cronService,
    required this.skillRegistryService,
  });

  final Directory appWorkspace;
  final JsonlMemoryStore memoryStore;
  final WebConfigStore webConfigStore;
  final CronService cronService;
  final SkillRegistryService skillRegistryService;

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
      LlmToolDefinition(
        name: 'list_dir',
        description:
            'List files/directories under workspace. Supports recursive listing.',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'path': <String, Object?>{
              'type': 'string',
              'description': 'Relative directory path. Default "."',
            },
            'recursive': <String, Object?>{
              'type': 'boolean',
              'description': 'List recursively when true.',
            },
            'max_entries': <String, Object?>{
              'type': 'integer',
              'description': 'Optional max number of entries (1-1000).',
            },
          },
          'additionalProperties': false,
        },
      ),
      LlmToolDefinition(
        name: 'read_file',
        description:
            'Read any text file under workspace and return UTF-8 content.',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'path': <String, Object?>{
              'type': 'string',
              'description': 'Relative file path in workspace.',
            },
          },
          'required': <String>['path'],
          'additionalProperties': false,
        },
      ),
      LlmToolDefinition(
        name: 'write_file',
        description: 'Write full text content to a workspace file.',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'path': <String, Object?>{
              'type': 'string',
              'description': 'Relative file path in workspace.',
            },
            'content': <String, Object?>{
              'type': 'string',
              'description': 'Full file content.',
            },
          },
          'required': <String>['path', 'content'],
          'additionalProperties': false,
        },
      ),
      LlmToolDefinition(
        name: 'append_file',
        description: 'Append text content to a workspace file.',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'path': <String, Object?>{
              'type': 'string',
              'description': 'Relative file path in workspace.',
            },
            'content': <String, Object?>{
              'type': 'string',
              'description': 'Text to append.',
            },
          },
          'required': <String>['path', 'content'],
          'additionalProperties': false,
        },
      ),
      LlmToolDefinition(
        name: 'edit_file',
        description: 'Replace text in a workspace file.',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'path': <String, Object?>{
              'type': 'string',
              'description': 'Relative file path in workspace.',
            },
            'old_text': <String, Object?>{
              'type': 'string',
              'description': 'Text to replace.',
            },
            'new_text': <String, Object?>{
              'type': 'string',
              'description': 'Replacement text.',
            },
            'replace_all': <String, Object?>{
              'type': 'boolean',
              'description': 'Replace all matches when true.',
            },
          },
          'required': <String>['path', 'old_text', 'new_text'],
          'additionalProperties': false,
        },
      ),
      LlmToolDefinition(
        name: 'exec',
        description:
            'Execute a shell command in workspace (sh -c). Returns stdout/stderr and exit code.',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'command': <String, Object?>{
              'type': 'string',
              'description': 'Shell command to run.',
            },
            'working_dir': <String, Object?>{
              'type': 'string',
              'description': 'Optional relative workspace directory.',
            },
            'timeout_seconds': <String, Object?>{
              'type': 'integer',
              'description': 'Optional timeout (1-300).',
            },
          },
          'required': <String>['command'],
          'additionalProperties': false,
        },
      ),
      LlmToolDefinition(
        name: 'web_search',
        description:
            'Search the web for recent/public information. Prefer this for current events and facts.',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'query': <String, Object?>{
              'type': 'string',
              'description': 'Search query.',
            },
            'max_results': <String, Object?>{
              'type': 'integer',
              'description': 'Optional number of results (1-10).',
            },
          },
          'required': <String>['query'],
          'additionalProperties': false,
        },
      ),
      LlmToolDefinition(
        name: 'web_fetch',
        description:
            'Fetch page content by URL. Use after web_search when you need details.',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'url': <String, Object?>{
              'type': 'string',
              'description': 'HTTP/HTTPS URL to fetch.',
            },
          },
          'required': <String>['url'],
          'additionalProperties': false,
        },
      ),
      LlmToolDefinition(
        name: 'cron',
        description:
            'Schedule and manage timed jobs. Supports one-time, interval, and cron expression schedules.',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'action': <String, Object?>{
              'type': 'string',
              'description': 'add | list | remove | enable | disable',
            },
            'message': <String, Object?>{
              'type': 'string',
              'description': 'Job message',
            },
            'command': <String, Object?>{
              'type': 'string',
              'description': 'Optional shell command to run at schedule',
            },
            'at_seconds': <String, Object?>{
              'type': 'integer',
              'description': 'One-time run after N seconds',
            },
            'every_seconds': <String, Object?>{
              'type': 'integer',
              'description': 'Interval run every N seconds',
            },
            'cron_expr': <String, Object?>{
              'type': 'string',
              'description': 'Cron format: minute hour day month weekday',
            },
            'job_id': <String, Object?>{
              'type': 'string',
              'description': 'Job id for remove/enable/disable',
            },
          },
          'required': <String>['action'],
          'additionalProperties': false,
        },
      ),
      LlmToolDefinition(
        name: 'find_skills',
        description:
            'Search installable skills from registry and local workspace.',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'query': <String, Object?>{
              'type': 'string',
              'description': 'Search query',
            },
            'limit': <String, Object?>{
              'type': 'integer',
              'description': 'Max results (1-20)',
            },
          },
          'required': <String>['query'],
          'additionalProperties': false,
        },
      ),
      LlmToolDefinition(
        name: 'install_skill',
        description:
            'Install a skill into workspace/skills. Supports clawhub by slug or github repo.',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'slug': <String, Object?>{
              'type': 'string',
              'description': 'Skill slug',
            },
            'registry': <String, Object?>{
              'type': 'string',
              'description': 'Registry name, default clawhub',
            },
            'version': <String, Object?>{
              'type': 'string',
              'description': 'Optional version for registry installs',
            },
            'git_repo': <String, Object?>{
              'type': 'string',
              'description': 'Optional github repo owner/name',
            },
            'skill_md_url': <String, Object?>{
              'type': 'string',
              'description': 'Optional direct SKILL.md URL',
            },
            'force': <String, Object?>{
              'type': 'boolean',
              'description': 'Force reinstall',
            },
          },
          'required': <String>['slug'],
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
- For general file operations and shell tasks, use list_dir/read_file/write_file/append_file/edit_file/exec.
- Persist long-term memory updates in memory/MEMORY.md when the user provides stable preferences or facts.
- Use web_search/web_fetch when the task needs up-to-date web information.
- Use cron to schedule actual timed execution tasks (one-time, interval, or cron expression).
- Use find_skills/install_skill to discover and install skills into workspace/skills.
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
        case 'list_dir':
          return await _listDir(args);
        case 'read_file':
          return await _readFile(args);
        case 'write_file':
          return await _writeFile(args);
        case 'append_file':
          return await _appendFile(args);
        case 'edit_file':
          return await _editFile(args);
        case 'exec':
          return await _exec(args);
        case 'web_search':
          return await _webSearch(args);
        case 'web_fetch':
          return await _webFetch(args);
        case 'cron':
          return await _cronTool(args);
        case 'find_skills':
          return await _findSkills(args);
        case 'install_skill':
          return await _installSkill(args);
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

  Future<String> _listDir(Map<String, dynamic> args) async {
    final raw = '${args['path'] ?? '.'}'.trim();
    final recursive = (args['recursive'] as bool?) ?? false;
    final requestedMax = (args['max_entries'] as num?)?.toInt() ?? 200;
    final maxEntries = requestedMax.clamp(1, 1000);

    final dir = await _resolveWorkspaceDirectory(raw, mustExist: true);
    final out = <Map<String, Object?>>[];
    await for (final entity
        in dir.list(recursive: recursive, followLinks: false)) {
      final rel = p.relative(entity.path, from: appWorkspace.path);
      if (entity is Directory) {
        out.add(<String, Object?>{'path': rel, 'type': 'dir'});
      } else if (entity is File) {
        final stat = await entity.stat();
        out.add(<String, Object?>{
          'path': rel,
          'type': 'file',
          'size': stat.size,
        });
      }
      if (out.length >= maxEntries) {
        break;
      }
    }
    out.sort((a, b) => '${a['path']}'.compareTo('${b['path']}'));
    return jsonEncode(<String, Object?>{
      'ok': true,
      'path': p.relative(dir.path, from: appWorkspace.path),
      'entries': out,
      'truncated': out.length >= maxEntries,
    });
  }

  Future<String> _readFile(Map<String, dynamic> args) async {
    final rel = '${args['path'] ?? ''}'.trim();
    if (rel.isEmpty) {
      return jsonEncode(
          <String, Object?>{'ok': false, 'error': 'path is required'});
    }
    final file = await _resolveWorkspaceFile(rel, mustExist: true);
    final text = await file.readAsString();
    return jsonEncode(<String, Object?>{
      'ok': true,
      'path': p.relative(file.path, from: appWorkspace.path),
      'content': _clipText(text, 120000),
    });
  }

  Future<String> _writeFile(Map<String, dynamic> args) async {
    final rel = '${args['path'] ?? ''}'.trim();
    final content = '${args['content'] ?? ''}';
    if (rel.isEmpty) {
      return jsonEncode(
          <String, Object?>{'ok': false, 'error': 'path is required'});
    }
    final file = await _resolveWorkspaceFile(rel, mustExist: false);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return jsonEncode(<String, Object?>{
      'ok': true,
      'path': p.relative(file.path, from: appWorkspace.path),
      'bytes': content.length,
    });
  }

  Future<String> _appendFile(Map<String, dynamic> args) async {
    final rel = '${args['path'] ?? ''}'.trim();
    final content = '${args['content'] ?? ''}';
    if (rel.isEmpty) {
      return jsonEncode(
          <String, Object?>{'ok': false, 'error': 'path is required'});
    }
    final file = await _resolveWorkspaceFile(rel, mustExist: false);
    await file.parent.create(recursive: true);
    await file.writeAsString(content, mode: FileMode.append);
    return jsonEncode(<String, Object?>{
      'ok': true,
      'path': p.relative(file.path, from: appWorkspace.path),
      'bytes': content.length,
    });
  }

  Future<String> _editFile(Map<String, dynamic> args) async {
    final rel = '${args['path'] ?? ''}'.trim();
    final oldText = '${args['old_text'] ?? ''}';
    final newText = '${args['new_text'] ?? ''}';
    final replaceAll = (args['replace_all'] as bool?) ?? false;
    if (rel.isEmpty) {
      return jsonEncode(
          <String, Object?>{'ok': false, 'error': 'path is required'});
    }
    if (oldText.isEmpty) {
      return jsonEncode(
          <String, Object?>{'ok': false, 'error': 'old_text is required'});
    }
    final file = await _resolveWorkspaceFile(rel, mustExist: true);
    final src = await file.readAsString();
    if (!src.contains(oldText)) {
      return jsonEncode(
          <String, Object?>{'ok': false, 'error': 'old_text not found'});
    }
    final replaced = replaceAll
        ? src.replaceAll(oldText, newText)
        : src.replaceFirst(oldText, newText);
    await file.writeAsString(replaced);
    return jsonEncode(<String, Object?>{
      'ok': true,
      'path': p.relative(file.path, from: appWorkspace.path),
      'replace_all': replaceAll,
    });
  }

  Future<String> _exec(Map<String, dynamic> args) async {
    final command = '${args['command'] ?? ''}'.trim();
    if (command.isEmpty) {
      return jsonEncode(
          <String, Object?>{'ok': false, 'error': 'command is required'});
    }
    final timeoutSeconds =
        ((args['timeout_seconds'] as num?)?.toInt() ?? 20).clamp(1, 300);
    final workDirArg = '${args['working_dir'] ?? '.'}'.trim();
    final workDir =
        await _resolveWorkspaceDirectory(workDirArg, mustExist: true);
    try {
      final result = await Process.run(
        'sh',
        <String>['-c', command],
        workingDirectory: workDir.path,
      ).timeout(Duration(seconds: timeoutSeconds));
      final stdoutText = '${result.stdout}';
      final stderrText = '${result.stderr}';
      return jsonEncode(<String, Object?>{
        'ok': true,
        'command': command,
        'working_dir': p.relative(workDir.path, from: appWorkspace.path),
        'exit_code': result.exitCode,
        'stdout': _clipText(stdoutText.trim(), 12000),
        'stderr': _clipText(stderrText.trim(), 12000),
      });
    } on FileSystemException catch (e) {
      return jsonEncode(<String, Object?>{'ok': false, 'error': '$e'});
    } on ProcessException catch (e) {
      return jsonEncode(<String, Object?>{'ok': false, 'error': '$e'});
    } on TimeoutException {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'error': 'command timeout after ${timeoutSeconds}s',
      });
    }
  }

  Future<String> _cronTool(Map<String, dynamic> args) async {
    final action = '${args['action'] ?? ''}'.trim();
    switch (action) {
      case 'add':
        final message = '${args['message'] ?? ''}'.trim();
        if (message.isEmpty) {
          return jsonEncode(
              <String, Object?>{'ok': false, 'error': 'message is required'});
        }
        final atSeconds = (args['at_seconds'] as num?)?.toInt();
        final everySeconds = (args['every_seconds'] as num?)?.toInt();
        final cronExpr = '${args['cron_expr'] ?? ''}';
        final command = '${args['command'] ?? ''}';
        final job = await cronService.addJob(
          message: message,
          command: command,
          atSeconds: atSeconds,
          everySeconds: everySeconds,
          cronExpr: cronExpr,
        );
        return jsonEncode(<String, Object?>{
          'ok': true,
          'job': job.toJson(),
        });
      case 'list':
        final jobs = await cronService.listJobs();
        return jsonEncode(<String, Object?>{
          'ok': true,
          'jobs': jobs.map((j) => j.toJson()).toList(),
        });
      case 'remove':
        final id = '${args['job_id'] ?? ''}'.trim();
        if (id.isEmpty) {
          return jsonEncode(
              <String, Object?>{'ok': false, 'error': 'job_id is required'});
        }
        final removed = await cronService.removeJob(id);
        return jsonEncode(<String, Object?>{'ok': removed});
      case 'enable':
      case 'disable':
        final id = '${args['job_id'] ?? ''}'.trim();
        if (id.isEmpty) {
          return jsonEncode(
              <String, Object?>{'ok': false, 'error': 'job_id is required'});
        }
        final changed = await cronService.setEnabled(id, action == 'enable');
        return jsonEncode(<String, Object?>{'ok': changed});
      default:
        return jsonEncode(<String, Object?>{
          'ok': false,
          'error': 'invalid action',
        });
    }
  }

  Future<String> _findSkills(Map<String, dynamic> args) async {
    final query = '${args['query'] ?? ''}';
    final limit = (args['limit'] as num?)?.toInt() ?? 5;
    final result =
        await skillRegistryService.findSkills(query: query, limit: limit);
    return jsonEncode(result);
  }

  Future<String> _installSkill(Map<String, dynamic> args) async {
    final slug = '${args['slug'] ?? ''}';
    final registry = '${args['registry'] ?? 'clawhub'}';
    final version = '${args['version'] ?? ''}';
    final gitRepo = '${args['git_repo'] ?? ''}';
    final skillMdUrl = '${args['skill_md_url'] ?? ''}';
    final force = (args['force'] as bool?) ?? false;
    final result = await skillRegistryService.installSkill(
      slug: slug,
      registry: registry,
      version: version,
      gitRepo: gitRepo,
      skillMdUrl: skillMdUrl,
      force: force,
    );
    return jsonEncode(result);
  }

  Future<String> _webSearch(Map<String, dynamic> args) async {
    final query = '${args['query'] ?? ''}'.trim();
    if (query.isEmpty) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'error': 'query is required',
      });
    }
    final cfg = await webConfigStore.load();
    if (!cfg.enabled) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'error': 'web search is disabled in settings',
      });
    }
    final requested = (args['max_results'] as num?)?.toInt() ?? cfg.maxResults;
    final maxResults = requested.clamp(1, 10);

    if (cfg.tavilyApiKey.trim().isNotEmpty) {
      return _searchViaTavily(
        query: query,
        maxResults: maxResults,
        apiKey: cfg.tavilyApiKey.trim(),
        baseUrl: cfg.tavilyBaseUrl.trim().isEmpty
            ? WebConfig.defaults.tavilyBaseUrl
            : cfg.tavilyBaseUrl.trim(),
      );
    }
    return _searchViaDuckDuckGo(query: query, maxResults: maxResults);
  }

  Future<String> _searchViaTavily({
    required String query,
    required int maxResults,
    required String apiKey,
    required String baseUrl,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse(baseUrl);
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.add(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'api_key': apiKey,
            'query': query,
            'max_results': maxResults,
          }),
        ),
      );
      final resp = await req.close();
      final body = await utf8.decodeStream(resp);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return jsonEncode(<String, Object?>{
          'ok': false,
          'error': 'tavily error ${resp.statusCode}',
          'body': body,
        });
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      final results = (data['results'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .take(maxResults)
          .map(
            (r) => <String, Object?>{
              'title': '${r['title'] ?? ''}',
              'url': '${r['url'] ?? ''}',
              'content': '${r['content'] ?? ''}',
            },
          )
          .toList();
      return jsonEncode(<String, Object?>{
        'ok': true,
        'provider': 'tavily',
        'query': query,
        'results': results,
      });
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _searchViaDuckDuckGo({
    required String query,
    required int maxResults,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final results = await _searchViaDuckDuckGoApi(
        client: client,
        query: query,
        maxResults: maxResults,
      );
      if (results.isEmpty) {
        return jsonEncode(<String, Object?>{
          'ok': false,
          'provider': 'duckduckgo',
          'query': query,
          'error': 'no results from DuckDuckGo Instant Answer API',
        });
      }
      return jsonEncode(<String, Object?>{
        'ok': true,
        'provider': 'duckduckgo',
        'query': query,
        'results': results,
      });
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Map<String, Object?>>> _searchViaDuckDuckGoApi({
    required HttpClient client,
    required String query,
    required int maxResults,
  }) async {
    final uri = Uri.https('api.duckduckgo.com', '/', <String, String>{
      'q': query,
      'format': 'json',
      'no_redirect': '1',
      'no_html': '1',
      'skip_disambig': '1',
    });
    final req = await client.getUrl(uri);
    final resp = await req.close();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return <Map<String, Object?>>[];
    }

    final body = await utf8.decodeStream(resp);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final results = <Map<String, Object?>>[];
    final seen = <String>{};

    void addResult({
      required String title,
      required String url,
      required String content,
    }) {
      if (results.length >= maxResults) {
        return;
      }
      final trimmedUrl = url.trim();
      final trimmedTitle = title.trim();
      final trimmedContent = content.trim();
      if (trimmedUrl.isEmpty && trimmedTitle.isEmpty && trimmedContent.isEmpty) {
        return;
      }
      final dedupeKey = trimmedUrl.isNotEmpty
          ? trimmedUrl
          : '${trimmedTitle.toLowerCase()}|${trimmedContent.toLowerCase()}';
      if (!seen.add(dedupeKey)) {
        return;
      }
      results.add(<String, Object?>{
        'title': trimmedTitle.isNotEmpty
            ? trimmedTitle
            : (trimmedUrl.isNotEmpty ? trimmedUrl : query),
        'url': trimmedUrl,
        'content': trimmedContent,
      });
    }

    addResult(
      title: '${data['Heading'] ?? query}',
      url: '${data['AbstractURL'] ?? ''}',
      content: '${data['AbstractText'] ?? ''}',
    );
    addResult(
      title: '${data['AnswerType'] ?? 'answer'}',
      url: '',
      content: '${data['Answer'] ?? ''}',
    );
    addResult(
      title: 'definition',
      url: '${data['DefinitionURL'] ?? ''}',
      content: '${data['Definition'] ?? ''}',
    );

    final directResults = (data['Results'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>();
    for (final item in directResults) {
      if (results.length >= maxResults) {
        break;
      }
      addResult(
        title: '${item['Text'] ?? item['Result'] ?? ''}',
        url: '${item['FirstURL'] ?? ''}',
        content: '${item['Text'] ?? ''}',
      );
    }

    final related = (data['RelatedTopics'] as List<dynamic>? ?? <dynamic>[]);
    for (final item in related) {
      if (results.length >= maxResults) {
        break;
      }
      if (item is Map<String, dynamic>) {
        if (item['Text'] != null || item['FirstURL'] != null) {
          addResult(
            title: '${item['Text'] ?? ''}',
            url: '${item['FirstURL'] ?? ''}',
            content: '${item['Text'] ?? ''}',
          );
          continue;
        }
        final nested = item['Topics'];
        if (nested is List<dynamic>) {
          for (final n in nested) {
            if (results.length >= maxResults) {
              break;
            }
            if (n is Map<String, dynamic> &&
                (n['Text'] != null || n['FirstURL'] != null)) {
              addResult(
                title: '${n['Text'] ?? ''}',
                url: '${n['FirstURL'] ?? ''}',
                content: '${n['Text'] ?? ''}',
              );
            }
          }
        }
      }
    }
    return results.take(maxResults).toList();
  }

  Future<String> _webFetch(Map<String, dynamic> args) async {
    final rawUrl = '${args['url'] ?? ''}'.trim();
    if (rawUrl.isEmpty) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'error': 'url is required',
      });
    }
    Uri uri;
    try {
      uri = Uri.parse(rawUrl);
    } catch (_) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'error': 'invalid url',
      });
    }
    if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'error': 'only http/https urls are allowed',
      });
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'MobileClaw/0.1');
      final resp = await req.close();
      final body = await utf8.decodeStream(resp);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return jsonEncode(<String, Object?>{
          'ok': false,
          'error': 'fetch error ${resp.statusCode}',
        });
      }
      final contentType = resp.headers.contentType?.mimeType ?? '';
      final text = _normalizeFetchedText(body, contentType);
      final clipped = text.length > 12000 ? text.substring(0, 12000) : text;
      return jsonEncode(<String, Object?>{
        'ok': true,
        'url': rawUrl,
        'content_type': contentType,
        'content': clipped,
      });
    } finally {
      client.close(force: true);
    }
  }

  String _normalizeFetchedText(String body, String contentType) {
    if (contentType.contains('html')) {
      var txt = body
          .replaceAll(RegExp(r'(?is)<script.*?>.*?</script>'), ' ')
          .replaceAll(RegExp(r'(?is)<style.*?>.*?</style>'), ' ')
          .replaceAll(RegExp(r'(?is)<[^>]+>'), ' ');
      txt = txt
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>');
      return txt.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return body.trim();
  }

  String _clipText(String input, int maxChars) {
    if (input.length <= maxChars) {
      return input;
    }
    return input.substring(0, maxChars);
  }

  String _resolveWorkspaceRawPath(String inputPath) {
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
    return targetPath;
  }

  Future<Directory> _resolveWorkspaceDirectory(
    String inputPath, {
    required bool mustExist,
  }) async {
    final targetPath = _resolveWorkspaceRawPath(inputPath);
    final dir = Directory(targetPath);
    if (mustExist && !await dir.exists()) {
      throw FileSystemException('directory does not exist', targetPath);
    }
    return dir;
  }

  Future<File> _resolveWorkspaceFile(
    String inputPath, {
    required bool mustExist,
  }) async {
    final targetPath = _resolveWorkspaceRawPath(inputPath);
    final file = File(targetPath);
    if (mustExist && !await file.exists()) {
      throw FileSystemException('file does not exist', targetPath);
    }
    return file;
  }

  Future<FileSystemEntity> _resolveWorkspacePath(
    String inputPath, {
    required bool mustExist,
    bool allowDirectory = false,
  }) async {
    final targetPath = _resolveWorkspaceRawPath(inputPath);
    final normalized = p.normalize(inputPath.trim());
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
