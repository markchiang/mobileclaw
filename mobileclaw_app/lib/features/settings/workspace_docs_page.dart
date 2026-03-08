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

class WorkspaceDocViewPage extends StatefulWidget {
  const WorkspaceDocViewPage({
    super.key,
    required this.workspaceDir,
    required this.file,
  });

  final Directory workspaceDir;
  final File file;

  @override
  State<WorkspaceDocViewPage> createState() => _WorkspaceDocViewPageState();
}

class _WorkspaceDocViewPageState extends State<WorkspaceDocViewPage> {
  late Future<String> _contentFuture;

  @override
  void initState() {
    super.initState();
    _contentFuture = widget.file.readAsString();
  }

  Future<void> _openEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkspaceDocEditPage(
          workspaceDir: widget.workspaceDir,
          file: widget.file,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _contentFuture = widget.file.readAsString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rel = p.relative(widget.file.path, from: widget.workspaceDir.path);
    return Scaffold(
      appBar: AppBar(
        title: Text(rel),
        actions: <Widget>[
          IconButton(
            tooltip: '編輯',
            onPressed: _openEditor,
            icon: const Icon(Icons.edit),
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _contentFuture,
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

class WorkspaceDocEditPage extends StatefulWidget {
  const WorkspaceDocEditPage({
    super.key,
    required this.workspaceDir,
    required this.file,
  });

  final Directory workspaceDir;
  final File file;

  @override
  State<WorkspaceDocEditPage> createState() => _WorkspaceDocEditPageState();
}

class _WorkspaceDocEditPageState extends State<WorkspaceDocEditPage> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final text = await widget.file.readAsString();
      if (!mounted) {
        return;
      }
      setState(() {
        _controller.text = text;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('讀取失敗: $e')),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      await widget.file.writeAsString(_controller.text, flush: true);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已儲存')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('儲存失敗: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rel = p.relative(widget.file.path, from: widget.workspaceDir.path);
    return Scaffold(
      appBar: AppBar(
        title: Text('編輯 $rel'),
        actions: <Widget>[
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('儲存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '編輯 Markdown 內容',
                ),
              ),
            ),
    );
  }
}
