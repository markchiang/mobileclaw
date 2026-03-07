import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/chat_models.dart';
import '../utils/sanitize.dart';

class JsonlMemoryStore {
  JsonlMemoryStore(this.rootDir) : memoryDir = Directory(p.join(rootDir.path, 'memory'));

  final Directory rootDir;
  final Directory memoryDir;

  Future<void> init() async {
    await memoryDir.create(recursive: true);
  }

  File _jsonlFile(String sessionKey) {
    return File(p.join(memoryDir.path, '${sanitizeSessionKey(sessionKey)}.jsonl'));
  }

  File _metaFile(String sessionKey) {
    return File(p.join(memoryDir.path, '${sanitizeSessionKey(sessionKey)}.meta.json'));
  }

  Future<void> addMessage(String sessionKey, ChatRole role, String content) async {
    await addFullMessage(
      ChatMessage(
        role: role,
        content: content,
        sessionKey: sessionKey,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> addFullMessage(ChatMessage msg) async {
    await init();
    final sessionKey = msg.sessionKey;
    final jsonl = _jsonlFile(sessionKey);
    await jsonl.parent.create(recursive: true);
    await jsonl.writeAsString('${msg.toJsonLine()}\n', mode: FileMode.append, flush: true);

    final existing = await readMeta(sessionKey);
    final now = DateTime.now();
    final meta = existing.copyWith(
      key: sessionKey,
      count: existing.count + 1,
      createdAt: existing.createdAt.millisecondsSinceEpoch == 0 ? now : existing.createdAt,
      updatedAt: now,
    );
    await writeMeta(meta);
  }

  Future<List<ChatMessage>> getHistory(String sessionKey) async {
    await init();
    final file = _jsonlFile(sessionKey);
    if (!await file.exists()) {
      return <ChatMessage>[];
    }

    final meta = await readMeta(sessionKey);
    final lines = await file.readAsLines();

    final output = <ChatMessage>[];
    var lineNo = 0;
    for (final line in lines) {
      if (line.trim().isEmpty) {
        continue;
      }
      lineNo += 1;
      if (lineNo <= meta.skip) {
        continue;
      }
      try {
        output.add(ChatMessage.fromJsonLine(line));
      } catch (_) {
        // Skip malformed lines to preserve append-only behavior.
      }
    }
    return output;
  }

  Future<SessionMeta> readMeta(String sessionKey) async {
    await init();
    final file = _metaFile(sessionKey);
    if (!await file.exists()) {
      return SessionMeta(key: sessionKey);
    }
    final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return SessionMeta.fromJson(map);
  }

  Future<void> writeMeta(SessionMeta meta) async {
    await init();
    final file = _metaFile(meta.key);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(meta.toJson()),
      flush: true,
    );
  }

  Future<void> setSummary(String sessionKey, String summary) async {
    final meta = await readMeta(sessionKey);
    await writeMeta(meta.copyWith(
      key: sessionKey,
      summary: summary,
      updatedAt: DateTime.now(),
      createdAt: meta.createdAt.millisecondsSinceEpoch == 0 ? DateTime.now() : meta.createdAt,
    ));
  }

  Future<String> getSummary(String sessionKey) async {
    final meta = await readMeta(sessionKey);
    return meta.summary;
  }

  Future<void> truncateHistory(String sessionKey, int keepLast) async {
    final meta = await readMeta(sessionKey);
    final count = meta.count;
    final skip = keepLast <= 0 ? count : (count - keepLast).clamp(0, count);
    await writeMeta(meta.copyWith(skip: skip, updatedAt: DateTime.now()));
  }

  Future<void> setHistory(String sessionKey, List<ChatMessage> history) async {
    await init();
    final file = _jsonlFile(sessionKey);
    final sink = file.openWrite();
    for (final msg in history) {
      sink.writeln(msg.copyWith(sessionKey: sessionKey).toJsonLine());
    }
    await sink.flush();
    await sink.close();

    final now = DateTime.now();
    await writeMeta(
      SessionMeta(
        key: sessionKey,
        skip: 0,
        count: history.length,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<List<String>> listSessions() async {
    await init();
    final out = <String>[];
    await for (final ent in memoryDir.list()) {
      if (ent is File && ent.path.endsWith('.meta.json')) {
        try {
          final map = jsonDecode(await ent.readAsString()) as Map<String, dynamic>;
          final meta = SessionMeta.fromJson(map);
          if (meta.key.trim().isNotEmpty) {
            out.add(meta.key);
            continue;
          }
        } catch (_) {
          // Fall through to filename parsing for malformed metadata.
        }
        out.add(p.basename(ent.path).replaceFirst('.meta.json', ''));
      }
    }
    final unique = out.toSet().toList()..sort();
    return unique;
  }
}
