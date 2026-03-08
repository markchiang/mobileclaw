import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'core/services/jsonl_memory_store.dart';
import 'core/services/background_guard.dart';
import 'core/services/cron_service.dart';
import 'core/services/heartbeat_service.dart';
import 'core/services/openclaw_bridge.dart';
import 'core/services/runtime_loop_service.dart';
import 'core/services/skill_registry_service.dart';
import 'core/services/web_config_store.dart';
import 'features/chat/chat_controller.dart';
import 'features/chat/chat_page.dart';
import 'features/settings/settings_page.dart';

class MobileClawApp extends StatefulWidget {
  const MobileClawApp({super.key});

  @override
  State<MobileClawApp> createState() => _MobileClawAppState();
}

class _MobileClawAppState extends State<MobileClawApp> {
  ChatController? _controller;
  Directory? _appRoot;
  String? _bootError;
  final BackgroundGuard _backgroundGuard = BackgroundGuard();
  RuntimeLoopService? _runtimeLoop;

  @override
  void initState() {
    super.initState();
    unawaited(_backgroundGuard.init());
    _boot();
  }

  @override
  void dispose() {
    unawaited(_backgroundGuard.disposeGuard());
    final loop = _runtimeLoop;
    if (loop != null) {
      unawaited(loop.dispose());
    }
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final appRoot = Directory('${dir.path}/mobileclaw');
      await appRoot.create(recursive: true);
      final workspace = Directory('${appRoot.path}/workspace');
      await _seedBundledWorkspace(appRoot);
      final cronService = CronService(appRoot);
      final heartbeatService = HeartbeatService(workspaceDir: workspace);
      final runtimeLoop = RuntimeLoopService(
        cronService: cronService,
        heartbeatService: heartbeatService,
        memoryStore: JsonlMemoryStore(appRoot),
      );
      await runtimeLoop.start();

      final controller = ChatController(appRoot: appRoot);
      await controller.init();

      if (!mounted) {
        return;
      }
      setState(() {
        _bootError = null;
        _appRoot = appRoot;
        _controller = controller;
        _runtimeLoop = runtimeLoop;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _bootError = '$e';
      });
    }
  }

  Future<void> _seedBundledWorkspace(Directory appRoot) async {
    final workspace = Directory('${appRoot.path}/workspace');
    await workspace.create(recursive: true);

    var hasMarkdown = false;
    await for (final entity in workspace.list(recursive: true)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
        hasMarkdown = true;
        break;
      }
    }
    if (hasMarkdown) {
      return;
    }

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final keys = manifest.listAssets();
    const prefix = 'assets/default_workspace/';

    for (final key in keys) {
      if (!key.startsWith(prefix)) {
        continue;
      }
      final rel = key.substring(prefix.length);
      if (rel.isEmpty || rel.endsWith('/')) {
        continue;
      }
      final outFile = File('${workspace.path}/$rel');
      await outFile.parent.create(recursive: true);
      final data = await rootBundle.load(key);
      await outFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final appRoot = _appRoot;
    final bootError = _bootError;

    if (controller == null || appRoot == null) {
      if (bootError != null) {
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('啟動失敗'),
                    const SizedBox(height: 8),
                    Text(bootError, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _boot,
                      child: const Text('重試'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final bridge = OpenclawBridge(
      appWorkspace: Directory('${appRoot.path}/workspace'),
      memoryStore: JsonlMemoryStore(appRoot),
      webConfigStore: WebConfigStore(appRoot),
      cronService: CronService(appRoot),
      skillRegistryService: SkillRegistryService(
        workspaceDir: Directory('${appRoot.path}/workspace'),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MobileClaw',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1A8A5B),
        brightness: Brightness.light,
      ),
      home: _HomeScaffold(
        controller: controller,
        settingsBuilder: () => SettingsPage(
          appRoot: appRoot,
          bridge: bridge,
          memoryStore: JsonlMemoryStore(appRoot),
        ),
      ),
    );
  }
}

class _HomeScaffold extends StatefulWidget {
  const _HomeScaffold(
      {required this.controller, required this.settingsBuilder});

  final ChatController controller;
  final Widget Function() settingsBuilder;

  @override
  State<_HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<_HomeScaffold> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ChatPage(controller: widget.controller),
      widget.settingsBuilder(),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int idx) => setState(() => _index = idx),
        destinations: const <Widget>[
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
