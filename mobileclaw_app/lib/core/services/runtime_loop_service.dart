import 'dart:async';
import 'dart:io';

import '../models/chat_models.dart';
import 'cron_service.dart';
import 'heartbeat_service.dart';
import 'jsonl_memory_store.dart';

class RuntimeLoopService {
  RuntimeLoopService({
    required this.cronService,
    required this.heartbeatService,
    required this.memoryStore,
  });

  final CronService cronService;
  final HeartbeatService heartbeatService;
  final JsonlMemoryStore memoryStore;

  Timer? _cronTimer;
  Timer? _heartbeatTimer;

  Future<void> start() async {
    _cronTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_runCronTick());
    });
    _heartbeatTimer ??= Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_runHeartbeatTick());
    });
    await _runCronTick();
    await _runHeartbeatTick();
  }

  Future<void> dispose() async {
    _cronTimer?.cancel();
    _cronTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _runCronTick() async {
    final logs = await cronService.runDue((job) async {
      if (job.command.trim().isNotEmpty) {
        return _runCommandJob(job);
      }
      final msg = '[cron] ${job.message}';
      await memoryStore.addMessage('default', ChatRole.assistant, msg);
      heartbeatService.addEvent(msg);
      return 'sent message';
    });
    for (final line in logs) {
      heartbeatService.addEvent(line);
    }
  }

  Future<String> _runCommandJob(CronJob job) async {
    try {
      final result = await Process.run(
        'sh',
        <String>['-c', job.command],
      ).timeout(const Duration(minutes: 3));
      final stdoutText = '${result.stdout}'.trim();
      final stderrText = '${result.stderr}'.trim();
      final exitCode = result.exitCode;
      final preview = <String>[
        if (stdoutText.isNotEmpty) stdoutText,
        if (stderrText.isNotEmpty) 'stderr: $stderrText',
      ].join('\n');
      final msg =
          '[cron-cmd] ${job.message}\nexit=$exitCode\n${preview.length > 1000 ? preview.substring(0, 1000) : preview}';
      await memoryStore.addMessage('default', ChatRole.assistant, msg);
      heartbeatService.addEvent('command executed: ${job.id} exit=$exitCode');
      return 'command exit=$exitCode';
    } catch (e) {
      heartbeatService.addEvent('command failed: ${job.id} $e');
      return 'command failed: $e';
    }
  }

  Future<void> _runHeartbeatTick() async {
    final jobs = await cronService.listJobs();
    final active = jobs.where((j) => j.enabled).length;
    await heartbeatService.tick(activeCronJobs: active);
  }
}
