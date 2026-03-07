import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;

class WorkspaceDocsPage extends StatefulWidget {
  const WorkspaceDocsPage({super.key, required this.workspaceDir});

  final Directory workspaceDir;

  @override
  State<WorkspaceDocsPage> createState() => _WorkspaceDocsPageState();
}

class _WorkspaceDocsPageState extends State<WorkspaceDocsPage> {
  late Future<List<File>> _filesFuture;

  @override
  void initState() {
    super.initState();
    _filesFuture = _loadFiles();
  }

  Future<List<File>> _loadFiles() async {
    final files = <File>[];
    if (!await widget.workspaceDir.exists()) {
      return files;
    }
    await for (final entity in widget.workspaceDir.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      if (p.extension(entity.path).toLowerCase() != '.md') {
        continue;
      }
      files.add(entity);
    }
    files.sort((a, b) => p
        .relative(a.path, from: widget.workspaceDir.path)
        .compareTo(p.relative(b.path, from: widget.workspaceDir.path)));
    return files;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workspace .md'),
        actions: <Widget>[
          IconButton(
            onPressed: () {
              setState(() {
                _filesFuture = _loadFiles();
              });
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<File>>(
        future: _filesFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('讀取失敗: ${snap.error}'));
          }
          final files = snap.data ?? <File>[];
          if (files.isEmpty) {
            return const Center(child: Text('workspace 內沒有 .md 檔案'));
          }
          return ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              final rel = p.relative(file.path, from: widget.workspaceDir.path);
              return ListTile(
                title: Text(rel),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => WorkspaceDocViewPage(
                        workspaceDir: widget.workspaceDir,
                        file: file,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class WorkspaceDocViewPage extends StatelessWidget {
  const WorkspaceDocViewPage({
    super.key,
    required this.workspaceDir,
    required this.file,
  });

  final Directory workspaceDir;
  final File file;

  @override
  Widget build(BuildContext context) {
    final rel = p.relative(file.path, from: workspaceDir.path);
    return Scaffold(
      appBar: AppBar(title: Text(rel)),
      body: FutureBuilder<String>(
        future: file.readAsString(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('讀取失敗: ${snap.error}'));
          }
          final content = snap.data ?? '';
          if (content.trim().isEmpty) {
            return const Center(child: Text('檔案內容為空'));
          }
          return Markdown(data: content);
        },
      ),
    );
  }
}
