import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/services/backup_service.dart';
import '../../core/services/jsonl_memory_store.dart';
import '../../core/services/llm_config_store.dart';
import '../../core/services/openclaw_bridge.dart';
import 'workspace_docs_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.appRoot,
    required this.bridge,
    required this.memoryStore,
  });

  final Directory appRoot;
  final OpenclawBridge bridge;
  final JsonlMemoryStore memoryStore;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final LlmConfigStore _configStore;
  final TextEditingController _apiKey = TextEditingController();
  final TextEditingController _baseUrl = TextEditingController();
  final TextEditingController _model = TextEditingController();

  LlmConfig _config = LlmConfig.defaults;

  @override
  void initState() {
    super.initState();
    _configStore = LlmConfigStore(widget.appRoot);
    _loadLlmConfig();
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _baseUrl.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _loadLlmConfig() async {
    final cfg = await _configStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _config = cfg;
      _fillControllers(cfg.selectedProfile);
    });
  }

  void _fillControllers(LlmProviderProfile profile) {
    _apiKey.text = profile.apiKey;
    _baseUrl.text = profile.baseUrl;
    _model.text = profile.model;
  }

  void _onProviderChanged(LlmProviderId? next) {
    if (next == null) {
      return;
    }
    final updatedConfig = _config.copyWith(selectedProvider: next);
    setState(() {
      _config = updatedConfig;
      _fillControllers(updatedConfig.selectedProfile);
    });
  }

  Future<void> _saveLlmConfig() async {
    final selected = _config.selectedProvider;
    final nextProfiles = Map<LlmProviderId, LlmProviderProfile>.from(
      _config.profiles,
    );
    nextProfiles[selected] = _config.selectedProfile.copyWith(
      apiKey: _apiKey.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      model: _model.text.trim(),
    );

    final nextConfig = _config.copyWith(profiles: nextProfiles);
    await _configStore.save(nextConfig);

    if (!mounted) {
      return;
    }

    setState(() {
      _config = nextConfig;
    });
    _snack(context, 'LLM 設定已儲存');
  }

  Future<void> _importFromFileSelector() async {
    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '選擇要匯入的資料夾',
    );

    if (dirPath != null && dirPath.trim().isNotEmpty) {
      final result = await widget.bridge.importFromExternalDirectory(
        Directory(dirPath),
      );
      if (!mounted) {
        return;
      }
      _snack(
        context,
        '匯入完成: ${result.copiedFiles} 檔案, ${result.importedSessions} memory sessions',
      );
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const <String>['md', 'txt', 'json', 'yaml', 'yml'],
    );
    if (picked == null || picked.files.isEmpty) {
      return;
    }

    final files = picked.paths.whereType<String>().map(File.new).toList();
    final fromPath = await widget.bridge.importPickedFiles(files);
    final inMemory = picked.files
        .where((f) => (f.path == null || f.path!.isEmpty) && f.bytes != null)
        .map(
          (f) => ImportedFileData(
            name: f.name,
            bytes: f.bytes!,
          ),
        )
        .toList(growable: false);
    final fromBytes = await widget.bridge.importPickedFileData(inMemory);
    final totalCopied = fromPath.copiedFiles + fromBytes.copiedFiles;
    if (!mounted) {
      return;
    }
    _snack(context, '匯入完成: $totalCopied 檔案');
  }

  @override
  Widget build(BuildContext context) {
    final selectedProvider = _config.selectedProvider;
    final needApiKey = llmProviderRequiresApiKey(selectedProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('設定 / 轉移')),
      body: ListView(
        children: <Widget>[
          const ListTile(title: Text('LLM 設定')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DropdownButtonFormField<LlmProviderId>(
              value: selectedProvider,
              items: LlmProviderId.values
                  .map(
                    (id) => DropdownMenuItem<LlmProviderId>(
                      value: id,
                      child: Text(llmProviderLabel(id)),
                    ),
                  )
                  .toList(),
              onChanged: _onProviderChanged,
              decoration: const InputDecoration(
                labelText: 'Provider',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _apiKey,
              obscureText: true,
              decoration: InputDecoration(
                labelText: needApiKey ? 'API Key' : 'API Key (Optional)',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _baseUrl,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _model,
              decoration: const InputDecoration(
                labelText: 'Model',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: FilledButton(
              onPressed: _saveLlmConfig,
              child: const Text('儲存 LLM 設定'),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('匯入 OpenClaw / 文件 (選擇資料夾或檔案)'),
            onTap: _importFromFileSelector,
          ),
          ListTile(
            title: const Text('檢視 workspace .md 檔案'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WorkspaceDocsPage(
                    workspaceDir:
                        Directory(p.join(widget.appRoot.path, 'workspace')),
                  ),
                ),
              );
            },
          ),
          ListTile(
            title: const Text('匯出到 OpenClaw (預設 ~/.openclaw)'),
            onTap: () async {
              final home = Platform.environment['HOME'] ?? '';
              await widget.bridge
                  .exportToOpenclaw(Directory(p.join(home, '.openclaw')));
              _snack(context, '已匯出到 OpenClaw workspace');
            },
          ),
          ListTile(
            title: const Text('建立備份 ZIP'),
            onTap: () async {
              final backup = BackupService(
                workspaceDir:
                    Directory(p.join(widget.appRoot.path, 'workspace')),
                memoryDir: Directory(p.join(widget.appRoot.path, 'memory')),
              );
              final out = await backup.createBundle(
                File(
                  p.join(
                      widget.appRoot.path, 'backups', 'mobileclaw_backup.zip'),
                ),
              );
              _snack(context, '備份完成: ${out.path}');
            },
          ),
        ],
      ),
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
