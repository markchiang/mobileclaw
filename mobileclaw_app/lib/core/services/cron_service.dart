import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class CronJob {
  const CronJob({
    required this.id,
    required this.message,
    required this.createdAtMs,
    this.command = '',
    this.atEpochMs,
    this.everySeconds,
    this.cronExpr = '',
    this.enabled = true,
    this.lastRunAtMs,
    this.nextRunAtMs,
  });

  final String id;
  final String message;
  final String command;
  final int createdAtMs;
  final int? atEpochMs;
  final int? everySeconds;
  final String cronExpr;
  final bool enabled;
  final int? lastRunAtMs;
  final int? nextRunAtMs;

  CronJob copyWith({
    String? id,
    String? message,
    String? command,
    int? createdAtMs,
    int? atEpochMs,
    int? everySeconds,
    String? cronExpr,
    bool? enabled,
    int? lastRunAtMs,
    int? nextRunAtMs,
  }) {
    return CronJob(
      id: id ?? this.id,
      message: message ?? this.message,
      command: command ?? this.command,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      atEpochMs: atEpochMs ?? this.atEpochMs,
      everySeconds: everySeconds ?? this.everySeconds,
      cronExpr: cronExpr ?? this.cronExpr,
      enabled: enabled ?? this.enabled,
      lastRunAtMs: lastRunAtMs ?? this.lastRunAtMs,
      nextRunAtMs: nextRunAtMs ?? this.nextRunAtMs,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'message': message,
      'command': command,
      'created_at_ms': createdAtMs,
      'at_epoch_ms': atEpochMs,
      'every_seconds': everySeconds,
      'cron_expr': cronExpr,
      'enabled': enabled,
      'last_run_at_ms': lastRunAtMs,
      'next_run_at_ms': nextRunAtMs,
    };
  }

  factory CronJob.fromJson(Map<String, dynamic> json) {
    return CronJob(
      id: '${json['id'] ?? ''}',
      message: '${json['message'] ?? ''}',
      command: '${json['command'] ?? ''}',
      createdAtMs: (json['created_at_ms'] as num?)?.toInt() ?? 0,
      atEpochMs: (json['at_epoch_ms'] as num?)?.toInt(),
      everySeconds: (json['every_seconds'] as num?)?.toInt(),
      cronExpr: '${json['cron_expr'] ?? ''}',
      enabled: (json['enabled'] as bool?) ?? true,
      lastRunAtMs: (json['last_run_at_ms'] as num?)?.toInt(),
      nextRunAtMs: (json['next_run_at_ms'] as num?)?.toInt(),
    );
  }
}

typedef CronExecutor = Future<String> Function(CronJob job);

class CronService {
  CronService(this.appRoot);

  final Directory appRoot;
  bool _tickRunning = false;

  File get _jobsFile => File(p.join(appRoot.path, 'state', 'cron_jobs.json'));

  Future<List<CronJob>> listJobs() async {
    final file = _jobsFile;
    if (!await file.exists()) {
      return <CronJob>[];
    }
    try {
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      return raw
          .whereType<Map<String, dynamic>>()
          .map(CronJob.fromJson)
          .toList(growable: false);
    } catch (_) {
      return <CronJob>[];
    }
  }

  Future<void> _saveJobs(List<CronJob> jobs) async {
    final file = _jobsFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ')
          .convert(jobs.map((j) => j.toJson()).toList()),
      flush: true,
    );
  }

  Future<CronJob> addJob({
    required String message,
    required String command,
    int? atSeconds,
    int? everySeconds,
    String cronExpr = '',
  }) async {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final id = 'job_${nowMs}_${now.microsecond}';
    final atEpochMs = atSeconds != null
        ? now.add(Duration(seconds: atSeconds)).millisecondsSinceEpoch
        : null;
    final normalizedCron = cronExpr.trim();
    final nextRun = _computeNextRunMs(
      now: now,
      atEpochMs: atEpochMs,
      everySeconds: everySeconds,
      cronExpr: normalizedCron,
      lastRunAtMs: null,
    );
    final job = CronJob(
      id: id,
      message: message.trim(),
      command: command.trim(),
      createdAtMs: nowMs,
      atEpochMs: atEpochMs,
      everySeconds: everySeconds,
      cronExpr: normalizedCron,
      enabled: true,
      nextRunAtMs: nextRun,
    );
    final jobs = await listJobs();
    jobs.add(job);
    await _saveJobs(jobs);
    return job;
  }

  Future<bool> removeJob(String id) async {
    final jobs = await listJobs();
    final next = jobs.where((j) => j.id != id).toList(growable: false);
    if (next.length == jobs.length) {
      return false;
    }
    await _saveJobs(next);
    return true;
  }

  Future<bool> setEnabled(String id, bool enabled) async {
    final jobs = await listJobs();
    var changed = false;
    final now = DateTime.now();
    final next = jobs.map((j) {
      if (j.id != id) {
        return j;
      }
      changed = true;
      return j.copyWith(
        enabled: enabled,
        nextRunAtMs: enabled
            ? _computeNextRunMs(
                now: now,
                atEpochMs: j.atEpochMs,
                everySeconds: j.everySeconds,
                cronExpr: j.cronExpr,
                lastRunAtMs: j.lastRunAtMs,
              )
            : null,
      );
    }).toList(growable: false);
    if (changed) {
      await _saveJobs(next);
    }
    return changed;
  }

  Future<List<String>> runDue(CronExecutor executor) async {
    if (_tickRunning) {
      return <String>[];
    }
    _tickRunning = true;
    try {
      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;
      final jobs = await listJobs();
      final logs = <String>[];
      final out = <CronJob>[];
      for (final job in jobs) {
        if (!job.enabled ||
            job.nextRunAtMs == null ||
            job.nextRunAtMs! > nowMs) {
          out.add(job);
          continue;
        }
        final result = await executor(job);
        logs.add('[${DateTime.now().toIso8601String()}] ${job.id}: $result');

        final nextRun = _computeNextRunMs(
          now: now,
          atEpochMs: job.atEpochMs,
          everySeconds: job.everySeconds,
          cronExpr: job.cronExpr,
          lastRunAtMs: nowMs,
        );
        if (nextRun == null) {
          out.add(job.copyWith(
              enabled: false, lastRunAtMs: nowMs, nextRunAtMs: null));
        } else {
          out.add(job.copyWith(lastRunAtMs: nowMs, nextRunAtMs: nextRun));
        }
      }
      await _saveJobs(out);
      return logs;
    } finally {
      _tickRunning = false;
    }
  }

  int? _computeNextRunMs({
    required DateTime now,
    required int? atEpochMs,
    required int? everySeconds,
    required String cronExpr,
    required int? lastRunAtMs,
  }) {
    if (everySeconds != null && everySeconds > 0) {
      final base = lastRunAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(lastRunAtMs)
          : now;
      return base.add(Duration(seconds: everySeconds)).millisecondsSinceEpoch;
    }
    if (cronExpr.isNotEmpty) {
      return _nextCronTimeMs(cronExpr, from: now);
    }
    if (atEpochMs != null) {
      if (atEpochMs <= now.millisecondsSinceEpoch) {
        return null;
      }
      if (lastRunAtMs != null) {
        return null;
      }
      return atEpochMs;
    }
    return null;
  }

  int? _nextCronTimeMs(String expr, {required DateTime from}) {
    final parts = expr.trim().split(RegExp(r'\s+'));
    if (parts.length != 5) {
      return null;
    }
    final minuteSet = _parseCronField(parts[0], 0, 59);
    final hourSet = _parseCronField(parts[1], 0, 23);
    final domSet = _parseCronField(parts[2], 1, 31);
    final monthSet = _parseCronField(parts[3], 1, 12);
    final dowSet = _parseCronField(parts[4], 0, 6);
    if (minuteSet == null ||
        hourSet == null ||
        domSet == null ||
        monthSet == null ||
        dowSet == null) {
      return null;
    }

    var t = DateTime(from.year, from.month, from.day, from.hour, from.minute)
        .add(const Duration(minutes: 1));
    for (var i = 0; i < 366 * 24 * 60; i += 1) {
      if (minuteSet.contains(t.minute) &&
          hourSet.contains(t.hour) &&
          domSet.contains(t.day) &&
          monthSet.contains(t.month) &&
          dowSet.contains(t.weekday % 7)) {
        return t.millisecondsSinceEpoch;
      }
      t = t.add(const Duration(minutes: 1));
    }
    return null;
  }

  Set<int>? _parseCronField(String field, int min, int max) {
    final out = <int>{};
    final chunks = field.split(',');
    for (final chunk in chunks) {
      final c = chunk.trim();
      if (c.isEmpty) {
        return null;
      }
      if (c == '*') {
        for (var v = min; v <= max; v += 1) {
          out.add(v);
        }
        continue;
      }
      if (c.startsWith('*/')) {
        final step = int.tryParse(c.substring(2));
        if (step == null || step <= 0) {
          return null;
        }
        for (var v = min; v <= max; v += step) {
          out.add(v);
        }
        continue;
      }
      final v = int.tryParse(c);
      if (v == null || v < min || v > max) {
        return null;
      }
      out.add(v);
    }
    return out;
  }
}
