import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mobileclaw_app/core/services/backup_service.dart';

void main() {
  test('backup and restore bundle', () async {
    final root = await Directory.systemTemp.createTemp('mobileclaw-backup-');
    final restore = await Directory.systemTemp.createTemp('mobileclaw-restore-');
    try {
      final workspace = Directory('${root.path}/workspace')..createSync(recursive: true);
      final memory = Directory('${root.path}/memory')..createSync(recursive: true);

      File('${workspace.path}/AGENTS.md').writeAsStringSync('# Agent');
      File('${memory.path}/default.md').writeAsStringSync('- user: hi');

      final svc = BackupService(workspaceDir: workspace, memoryDir: memory);
      final zip = await svc.createBundle(File('${root.path}/backup.zip'));

      expect(await zip.exists(), isTrue);
      await svc.restoreBundle(zip, restore);

      expect(await File('${restore.path}/workspace/AGENTS.md').exists(), isTrue);
      expect(await File('${restore.path}/memory/default.md').exists(), isTrue);
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
      if (await restore.exists()) {
        await restore.delete(recursive: true);
      }
    }
  });

  test('restore skips files outside restore root', () async {
    final root = await Directory.systemTemp.createTemp('mobileclaw-backup-');
    final restore = await Directory.systemTemp.createTemp('mobileclaw-restore-');
    final outside = Directory(p.join(restore.parent.path, '${p.basename(restore.path)}-evil'));
    try {
      final archive = Archive()
        ..addFile(
          ArchiveFile(
            p.join('..', p.basename(outside.path), 'owned.txt'),
            'pwn'.length,
            'pwn'.codeUnits,
          ),
        )
        ..addFile(
          ArchiveFile(
            p.join('workspace', 'ok.txt'),
            'ok'.length,
            'ok'.codeUnits,
          ),
        );
      final bytes = ZipEncoder().encode(archive)!;
      final zip = File('${root.path}/evil.zip')..writeAsBytesSync(bytes);

      final svc = BackupService(
        workspaceDir: Directory('${root.path}/workspace'),
        memoryDir: Directory('${root.path}/memory'),
      );
      await svc.restoreBundle(zip, restore);

      expect(await File('${restore.path}/workspace/ok.txt').exists(), isTrue);
      expect(await File('${outside.path}/owned.txt').exists(), isFalse);
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
      if (await restore.exists()) {
        await restore.delete(recursive: true);
      }
      if (await outside.exists()) {
        await outside.delete(recursive: true);
      }
    }
  });
}
