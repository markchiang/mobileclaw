import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/services/backup_service.dart';
import '../../core/services/jsonl_memory_store.dart';
import '../../core/services/llm_config_store.dart';
import '../../core/services/openclaw_bridge.dart';
import '../../core/services/web_config_store.dart';
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
  late final WebConfigStore _webConfigStore;
  final TextEditingController _apiKey = TextEditingController();
  final TextEditingController _baseUrl = TextEditingController();
  final TextEditingController _model = TextEditingController();
  final TextEditingController _maxToolIterations = TextEditingController();
  final TextEditingController _tavilyApiKey = TextEditingController();
  final TextEditingController _tavilyBaseUrl = TextEditingController();
  final TextEditingController _webMaxResults = TextEditingController();

  LlmConfig _config = LlmConfig.defaults;
  WebConfig _webConfig = WebConfig.defaults;

  @override
  void initState() {
    super.initState();
    _configStore = LlmConfigStore(widget.appRoot);
    _webConfigStore = WebConfigStore(widget.appRoot);
    _loadLlmConfig();
    _loadWebConfig();
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _maxToolIterations.dispose();
    _tavilyApiKey.dispose();
    _tavilyBaseUrl.dispose();
    _webMaxResults.dispose();
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
      _maxToolIterations.text = cfg.maxToolIterations.toString();
    });
  }

  Future<void> _loadWebConfig() async {
    final cfg = await _webConfigStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _webConfig = cfg;
      _tavilyApiKey.text = cfg.tavilyApiKey;
      _tavilyBaseUrl.text = cfg.tavilyBaseUrl;
      _webMaxResults.text = cfg.maxResults.toString();
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
    final parsedIterations = int.tryParse(_maxToolIterations.text.trim());
    final withIterations = nextConfig.copyWith(
      maxToolIterations:
          (parsedIterations ?? nextConfig.maxToolIterations).clamp(1, 50),
    );
    await _configStore.save(withIterations);

    if (!mounted) {
      return;
    }

    setState(() {
      _config = withIterations;
      _maxToolIterations.text = withIterations.maxToolIterations.toString();
    });
    _snack(context, 'LLM 設定已儲存');
  }

  Future<void> _saveWebConfig() async {
    final parsedMax = int.tryParse(_webMaxResults.text.trim());
    final next = _webConfig.copyWith(
      tavilyApiKey: _tavilyApiKey.text.trim(),
      tavilyBaseUrl: _tavilyBaseUrl.text.trim(),
      maxResults: (parsedMax ?? _webConfig.maxResults).clamp(1, 10),
    );
    await _webConfigStore.save(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _webConfig = next;
      _webMaxResults.text = next.maxResults.toString();
    });
    _snack(context, 'Web 搜尋設定已儲存');
  }

  Future<void> _importFromFileSelector() async {
    try {
      final mode = await showModalBottomSheet<String>(
        context: context,
        builder: (BuildContext context) {
          return SafeArea(
            child: Wrap(
              children: <Widget>[
                const ListTile(
                  title: Text('選擇匯入方式'),
                  subtitle: Text('資料夾 (OpenClaw) 或 匯入 *.md / .zip'),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('匯入資料夾（OpenClaw）'),
                  onTap: () => Navigator.of(context).pop('dir'),
                ),
                ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: const Text('匯入 *.md / .zip'),
                  onTap: () => Navigator.of(context).pop('file'),
                ),
              ],
            ),
          );
        },
      );
      if (mode == null) {
        return;
      }

      if (mode == 'dir') {
        final dirPath = await FilePicker.platform.getDirectoryPath(
          dialogTitle: '選擇要匯入的資料夾',
        );
        if (dirPath == null || dirPath.trim().isEmpty) {
          return;
        }
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
        allowedExtensions: const <String>['md', 'zip'],
      );
      if (picked == null || picked.files.isEmpty) {
        return;
      }

      final backup = BackupService(
        workspaceDir: Directory(p.join(widget.appRoot.path, 'workspace')),
        memoryDir: Directory(p.join(widget.appRoot.path, 'memory')),
      );

      var restoredZipCount = 0;
      final contentFilesFromPath = <File>[];
      final contentFilesFromBytes = <ImportedFileData>[];

      for (final f in picked.files) {
        final nameLower = f.name.toLowerCase();
        final isZip = nameLower.endsWith('.zip');
        if (isZip) {
          File? zipFile;
          if (f.path != null && f.path!.trim().isNotEmpty) {
            zipFile = File(f.path!);
          } else if (f.bytes != null) {
            final tmpDir =
                Directory(p.join(widget.appRoot.path, 'imports', 'tmp_zip'));
            await tmpDir.create(recursive: true);
            zipFile = File(
              p.join(tmpDir.path,
                  '${DateTime.now().millisecondsSinceEpoch}_${f.name}'),
            );
            await zipFile.writeAsBytes(f.bytes!, flush: true);
          }
          if (zipFile != null && await zipFile.exists()) {
            await backup.restoreBundle(zipFile, widget.appRoot);
            restoredZipCount += 1;
          }
          continue;
        }
        final isMarkdown = nameLower.endsWith('.md');
        if (!isMarkdown) {
          continue;
        }

        if (f.path != null && f.path!.trim().isNotEmpty) {
          contentFilesFromPath.add(File(f.path!));
        } else if (f.bytes != null) {
          contentFilesFromBytes.add(
            ImportedFileData(
              name: f.name,
              bytes: f.bytes!,
            ),
          );
        }
      }

      final fromPath =
          await widget.bridge.importPickedFiles(contentFilesFromPath);
      final fromBytes =
          await widget.bridge.importPickedFileData(contentFilesFromBytes);
      final totalCopied = fromPath.copiedFiles + fromBytes.copiedFiles;
      if (!mounted) {
        return;
      }
      _snack(context, '匯入完成: $totalCopied 檔案, $restoredZipCount 個 ZIP');
    } catch (e) {
      if (!mounted) {
        return;
      }
      _snack(context, '匯入失敗: $e');
    }
  }

  Future<void> _exportBackupZip() async {
    try {
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final suggestedName = 'mobileclaw_backup_$ts.zip';
      final backup = BackupService(
        workspaceDir: Directory(p.join(widget.appRoot.path, 'workspace')),
        memoryDir: Directory(p.join(widget.appRoot.path, 'memory')),
      );
      final bytes = Uint8List.fromList(await backup.createBundleBytes());

      String? selectedPath;
      if (Platform.isAndroid || Platform.isIOS) {
        selectedPath = await FilePicker.platform.saveFile(
          dialogTitle: '選擇備份 ZIP 儲存位置',
          fileName: suggestedName,
          type: FileType.custom,
          allowedExtensions: const <String>['zip'],
          bytes: bytes,
        );
        if (selectedPath == null || selectedPath.trim().isEmpty) {
          _snack(context, '已取消匯出');
          return;
        }
      } else {
        selectedPath = await FilePicker.platform.saveFile(
          dialogTitle: '選擇備份 ZIP 儲存位置',
          fileName: suggestedName,
          type: FileType.custom,
          allowedExtensions: const <String>['zip'],
          bytes: bytes,
        );
        if (selectedPath == null || selectedPath.trim().isEmpty) {
          final dirPath = await FilePicker.platform.getDirectoryPath(
            dialogTitle: '選擇備份 ZIP 儲存資料夾',
          );
          if (dirPath == null || dirPath.trim().isEmpty) {
            _snack(context, '已取消匯出');
            return;
          }
          selectedPath = p.join(dirPath, suggestedName);
          await backup.createBundle(File(selectedPath));
          if (!mounted) {
            return;
          }
          _snack(context, '備份完成: ${selectedPath}');
          return;
        }
      }

      if (!mounted) {
        return;
      }
      _snack(context, '備份完成: ${selectedPath}');
    } catch (e) {
      if (!mounted) {
        return;
      }
      _snack(context, '匯出失敗: $e');
    }
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
            child: TextField(
              controller: _maxToolIterations,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Max Tool Iterations (1-50)',
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
          SwitchListTile(
            title: const Text('啟用 Web Search 工具'),
            subtitle: const Text('未設定 Tavily Key 時會使用 DuckDuckGo fallback'),
            value: _webConfig.enabled,
            onChanged: (v) => setState(() {
              _webConfig = _webConfig.copyWith(enabled: v);
            }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _tavilyApiKey,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Tavily API Key (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _tavilyBaseUrl,
              decoration: const InputDecoration(
                labelText: 'Tavily Base URL',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _webMaxResults,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Web Search Max Results (1-10)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: FilledButton(
              onPressed: () async {
                await _saveWebConfig();
              },
              child: const Text('儲存 Web 搜尋設定'),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('匯入 *.md'),
            onTap: _importFromFileSelector,
          ),
          ListTile(
            title: const Text('檢視 workspace *.md 檔案'),
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
            title: const Text('備份 *.md 成 zip'),
            onTap: _exportBackupZip,
          ),
        ],
      ),
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
