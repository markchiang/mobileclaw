import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileclaw_app/core/services/cron_service.dart';

void main() {
  test('cron service add/list/remove and run due', () async {
    final root = await Directory.systemTemp.createTemp('mobileclaw-cron-');
    try {
      final cron = CronService(root);
      final job = await cron.addJob(
        message: 'once',
        command: '',
        atSeconds: 1,
      );
      final jobs = await cron.listJobs();
      expect(jobs.any((j) => j.id == job.id), isTrue);

      await Future<void>.delayed(const Duration(seconds: 2));
      var called = 0;
      await cron.runDue((j) async {
        called += 1;
        return 'ok';
      });
      expect(called, 1);

      final removed = await cron.removeJob(job.id);
      expect(removed, isTrue);
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });
}
