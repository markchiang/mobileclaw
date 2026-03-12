import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/chat_models.dart';
import 'app_paths.dart';
import 'cron_service.dart';
import 'heartbeat_service.dart';
import 'jsonl_memory_store.dart';

@pragma('vm:entry-point')
void startBackgroundRuntimeTask() {
  FlutterForegroundTask.setTaskHandler(MobileClawTaskHandler());
}

class MobileClawTaskHandler extends TaskHandler {
  Directory? _appRoot;
  CronService? _cronService;
  HeartbeatService? _heartbeatService;
  JsonlMemoryStore? _memoryStore;
  bool _tickRunning = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _appRoot = await getMobileClawAppRoot();
    final workspace = Directory('${_appRoot!.path}/workspace');
    _cronService = CronService(_appRoot!);
    _heartbeatService = HeartbeatService(workspaceDir: workspace);
    _memoryStore = JsonlMemoryStore(_appRoot!);
    await _memoryStore!.init();
    await _runTick();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_runTick());
  }

  Future<void> _runTick() async {
    if (_tickRunning || _cronService == null || _heartbeatService == null) {
      return;
    }
    _tickRunning = true;
    try {
      final logs = await _cronService!.runDue((job) async {
        if (job.command.trim().isNotEmpty) {
          return _runCommandJob(job);
        }
        final msg = '[cron-bg] ${job.message}';
        await _memoryStore!.addMessage('default', ChatRole.assistant, msg);
        _heartbeatService!.addEvent(msg);
        return 'sent message';
      });
      for (final line in logs) {
        _heartbeatService!.addEvent('[bg] $line');
      }
      final jobs = await _cronService!.listJobs();
      final active = jobs.where((j) => j.enabled).length;
      await _heartbeatService!.tick(activeCronJobs: active);
    } finally {
      _tickRunning = false;
    }
  }

  Future<String> _runCommandJob(CronJob job) async {
    try {
      final result = await Process.run('sh', <String>['-c', job.command])
          .timeout(const Duration(minutes: 3));
      final stdoutText = '${result.stdout}'.trim();
      final stderrText = '${result.stderr}'.trim();
      final exitCode = result.exitCode;
      final preview = <String>[
        if (stdoutText.isNotEmpty) stdoutText,
        if (stderrText.isNotEmpty) 'stderr: $stderrText',
      ].join('\n');
      final msg =
          '[cron-bg-cmd] ${job.message}\nexit=$exitCode\n${preview.length > 1000 ? preview.substring(0, 1000) : preview}';
      await _memoryStore!.addMessage('default', ChatRole.assistant, msg);
      _heartbeatService!.addEvent('background command: ${job.id} exit=$exitCode');
      return 'command exit=$exitCode';
    } catch (e) {
      _heartbeatService!.addEvent('background command failed: ${job.id} $e');
      return 'command failed: $e';
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}
