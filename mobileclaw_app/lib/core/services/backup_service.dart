import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

class BackupService {
  BackupService({required this.workspaceDir, required this.memoryDir});

  final Directory workspaceDir;
  final Directory memoryDir;

  Future<List<int>> createBundleBytes() async {
    final archive = Archive();

    await _addDirToArchive(archive, workspaceDir, 'workspace');
    await _addDirToArchive(archive, memoryDir, 'memory');

    final bytes = ZipEncoder().encode(archive);
    if (bytes == null) {
      throw StateError('zip encoding failed');
    }
    return bytes;
  }

  Future<File> createBundle(File outputZip) async {
    final bytes = await createBundleBytes();
    await outputZip.parent.create(recursive: true);
    await outputZip.writeAsBytes(bytes, flush: true);
    return outputZip;
  }

  Future<void> restoreBundle(File bundleZip, Directory restoreRoot) async {
    final bytes = await bundleZip.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final rootPath = p.normalize(p.absolute(restoreRoot.path));

    for (final file in archive.files) {
      final path = p.normalize(p.absolute(p.join(rootPath, file.name)));
      final insideRoot = path == rootPath || p.isWithin(rootPath, path);
      if (!insideRoot) {
        continue;
      }
      if (file.isFile) {
        final out = File(path);
        await out.parent.create(recursive: true);
        await out.writeAsBytes(file.content as List<int>, flush: true);
      } else {
        await Directory(path).create(recursive: true);
      }
    }
  }

  Future<void> _addDirToArchive(
      Archive archive, Directory dir, String prefix) async {
    if (!await dir.exists()) {
      return;
    }

    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final rel = p.relative(entity.path, from: dir.path);
      final bytes = await entity.readAsBytes();
      archive.addFile(ArchiveFile(p.join(prefix, rel), bytes.length, bytes));
    }
  }
}
