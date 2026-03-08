import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileclaw_app/core/services/heartbeat_service.dart';

void main() {
  test('heartbeat service writes HEARTBEAT.md', () async {
    final ws = await Directory.systemTemp.createTemp('mobileclaw-heartbeat-');
    try {
      final hb = HeartbeatService(workspaceDir: ws);
      hb.addEvent('test event');
      await hb.tick(activeCronJobs: 2);
      final file = File('${ws.path}/HEARTBEAT.md');
      expect(await file.exists(), isTrue);
      final text = await file.readAsString();
      expect(text, contains('Active cron jobs: 2'));
      expect(text, contains('test event'));
    } finally {
      if (await ws.exists()) {
        await ws.delete(recursive: true);
      }
    }
  });
}
