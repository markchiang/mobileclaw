import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class BackgroundGuard with WidgetsBindingObserver {
  bool _started = false;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> disposeGuard() async {
    WidgetsBinding.instance.removeObserver(this);
    if (_started) {
      await FlutterForegroundTask.stopService();
      _started = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _ensureForeground();
    }
    if (state == AppLifecycleState.resumed) {
      _stopForeground();
    }
  }

  Future<void> _ensureForeground() async {
    if (_started) {
      return;
    }
    final running = await FlutterForegroundTask.isRunningService;
    if (!running) {
      await FlutterForegroundTask.startService(
        notificationTitle: 'MobileClaw AI 執行中',
        notificationText: '維持背景推理與記憶同步',
      );
    }
    _started = true;
  }

  Future<void> _stopForeground() async {
    if (!_started) {
      return;
    }
    await FlutterForegroundTask.stopService();
    _started = false;
  }
}
