import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

class SkillRegistryService {
  SkillRegistryService({required this.workspaceDir});

  final Directory workspaceDir;

  Future<Map<String, Object?>> findSkills({
    required String query,
    int limit = 5,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return <String, Object?>{'ok': false, 'error': 'query is required'};
    }
    final safeLimit = limit.clamp(1, 20);
    final local = await _findLocalSkills(q);
    final remote = await _findClawHubSkills(q, safeLimit);
    final merged = <Map<String, Object?>>[...local, ...remote];
    merged.sort((a, b) {
      final sa = (a['score'] as num?)?.toDouble() ?? 0;
      final sb = (b['score'] as num?)?.toDouble() ?? 0;
      return sb.compareTo(sa);
    });
    final dedup = <String, Map<String, Object?>>{};
    for (final row in merged) {
      final slug = '${row['slug'] ?? ''}';
      if (slug.isEmpty || dedup.containsKey(slug)) {
        continue;
      }
      dedup[slug] = row;
      if (dedup.length >= safeLimit) {
        break;
      }
    }
    return <String, Object?>{
      'ok': true,
      'query': q,
      'results': dedup.values.toList(growable: false),
    };
  }

  Future<Map<String, Object?>> installSkill({
    required String slug,
    String registry = 'clawhub',
    String version = '',
    String gitRepo = '',
    String skillMdUrl = '',
    bool force = false,
  }) async {
    final cleanSlug = _sanitizeSkillSlug(slug);
    if (cleanSlug.isEmpty) {
      return <String, Object?>{'ok': false, 'error': 'invalid slug'};
    }
    final targetDir = Directory(p.join(workspaceDir.path, 'skills', cleanSlug));
    if (await targetDir.exists()) {
      if (!force) {
        return <String, Object?>{
          'ok': false,
          'error': 'skill already exists, use force=true',
        };
      }
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    try {
      if (gitRepo.trim().isNotEmpty) {
        final skill = await _fetchSkillMdFromGitHub(gitRepo.trim());
        await File(p.join(targetDir.path, 'SKILL.md'))
            .writeAsString(skill, flush: true);
      } else if (skillMdUrl.trim().isNotEmpty) {
        final skill = await _fetchText(skillMdUrl.trim());
        await File(p.join(targetDir.path, 'SKILL.md'))
            .writeAsString(skill, flush: true);
      } else if (registry.trim() == 'clawhub') {
        await _installFromClawHub(
            slug: cleanSlug, version: version.trim(), targetDir: targetDir);
      } else {
        return <String, Object?>{
          'ok': false,
          'error': 'unsupported registry: $registry'
        };
      }
      return <String, Object?>{
        'ok': true,
        'slug': cleanSlug,
        'path': p.relative(targetDir.path, from: workspaceDir.path),
      };
    } catch (e) {
      return <String, Object?>{'ok': false, 'error': '$e'};
    }
  }

  Future<List<Map<String, Object?>>> _findLocalSkills(String query) async {
    final skillsDir = Directory(p.join(workspaceDir.path, 'skills'));
    if (!await skillsDir.exists()) {
      return <Map<String, Object?>>[];
    }
    final q = query.toLowerCase();
    final out = <Map<String, Object?>>[];
    await for (final ent in skillsDir.list()) {
      if (ent is! Directory) {
        continue;
      }
      final skillFile = File(p.join(ent.path, 'SKILL.md'));
      if (!await skillFile.exists()) {
        continue;
      }
      final content = await skillFile.readAsString();
      final slug = p.basename(ent.path);
      final hay = '$slug\n$content'.toLowerCase();
      final score = hay.contains(q) ? 0.8 : 0.0;
      if (score <= 0) {
        continue;
      }
      out.add(<String, Object?>{
        'score': score,
        'slug': slug,
        'summary': _clip(content.replaceAll('\n', ' '), 180),
        'registry': 'workspace',
      });
    }
    return out;
  }

  Future<List<Map<String, Object?>>> _findClawHubSkills(
      String query, int limit) async {
    final uri = Uri.parse('https://clawhub.ai/api/v1/search')
        .replace(queryParameters: <String, String>{
      'q': query,
      'limit': '$limit',
    });
    try {
      final raw = await _fetchText(uri.toString());
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final rows = (data['results'] as List<dynamic>? ?? <dynamic>[]);
      final out = <Map<String, Object?>>[];
      for (final row in rows) {
        if (row is! Map<String, dynamic>) {
          continue;
        }
        final slug = '${row['slug'] ?? ''}'.trim();
        final summary = '${row['summary'] ?? ''}'.trim();
        if (slug.isEmpty || summary.isEmpty) {
          continue;
        }
        out.add(<String, Object?>{
          'score': (row['score'] as num?)?.toDouble() ?? 0.5,
          'slug': slug,
          'summary': summary,
          'version': '${row['version'] ?? ''}',
          'registry': 'clawhub',
        });
      }
      return out;
    } catch (_) {
      return <Map<String, Object?>>[];
    }
  }

  Future<void> _installFromClawHub({
    required String slug,
    required String version,
    required Directory targetDir,
  }) async {
    final uri = Uri.parse('https://clawhub.ai/api/v1/download')
        .replace(queryParameters: <String, String>{
      'slug': slug,
      if (version.isNotEmpty) 'version': version,
    });
    final bytes = await _fetchBytes(uri.toString());
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive.files) {
      final name = p.normalize(file.name);
      if (name.contains('..')) {
        continue;
      }
      final outPath = p.join(targetDir.path, name);
      if (file.isFile) {
        final out = File(outPath);
        await out.parent.create(recursive: true);
        await out.writeAsBytes(file.content as List<int>, flush: true);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
    final skillFile = File(p.join(targetDir.path, 'SKILL.md'));
    if (!await skillFile.exists()) {
      throw const FileSystemException('installed package missing SKILL.md');
    }
  }

  Future<String> _fetchSkillMdFromGitHub(String repo) async {
    final normalized = repo
        .replaceAll(RegExp(r'^https?://github.com/'), '')
        .replaceAll(RegExp(r'/$'), '');
    final tries = <String>[
      'https://raw.githubusercontent.com/$normalized/main/SKILL.md',
      'https://raw.githubusercontent.com/$normalized/master/SKILL.md',
    ];
    Object? lastErr;
    for (final u in tries) {
      try {
        return await _fetchText(u);
      } catch (e) {
        lastErr = e;
      }
    }
    throw Exception('failed to fetch SKILL.md from $repo: $lastErr');
  }

  Future<String> _fetchText(String url) async {
    final bytes = await _fetchBytes(url);
    return utf8.decode(bytes);
  }

  Future<List<int>> _fetchBytes(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      final bytes = await resp.fold<List<int>>(<int>[], (acc, data) {
        acc.addAll(data);
        return acc;
      });
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw HttpException('HTTP ${resp.statusCode}', uri: Uri.parse(url));
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  String _sanitizeSkillSlug(String raw) {
    final s = raw.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]*$').hasMatch(s)) {
      return '';
    }
    return s;
  }

  String _clip(String s, int max) {
    return s.length <= max ? s : s.substring(0, max);
  }
}
