import 'dart:io';

import 'package:path/path.dart' as p;

class HeartbeatService {
  HeartbeatService({required this.workspaceDir});

  final Directory workspaceDir;
  final List<String> _recentEvents = <String>[];

  void addEvent(String event) {
    final line = '- ${DateTime.now().toIso8601String()} $event';
    _recentEvents.add(line);
    if (_recentEvents.length > 20) {
      _recentEvents.removeRange(0, _recentEvents.length - 20);
    }
  }

  Future<void> tick({required int activeCronJobs}) async {
    await workspaceDir.create(recursive: true);
    final file = File(p.join(workspaceDir.path, 'HEARTBEAT.md'));
    final buff = StringBuffer()
      ..writeln('# HEARTBEAT')
      ..writeln()
      ..writeln('- Last update: ${DateTime.now().toIso8601String()}')
      ..writeln('- Active cron jobs: $activeCronJobs')
      ..writeln()
      ..writeln('## Recent Events');

    if (_recentEvents.isEmpty) {
      buff.writeln('- (none)');
    } else {
      for (final e in _recentEvents) {
        buff.writeln(e);
      }
    }
    await file.writeAsString(buff.toString(), flush: true);
  }
}
