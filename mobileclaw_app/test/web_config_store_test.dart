import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileclaw_app/core/services/web_config_store.dart';

void main() {
  test('web config store save/load round trip', () async {
    final root = await Directory.systemTemp.createTemp('mobileclaw-webcfg-');
    try {
      final store = WebConfigStore(root);
      final input = WebConfig.defaults.copyWith(
        enabled: true,
        tavilyApiKey: 'tv-key',
        tavilyBaseUrl: 'https://api.tavily.com/search',
        maxResults: 7,
      );
      await store.save(input);
      final out = await store.load();
      expect(out.enabled, isTrue);
      expect(out.tavilyApiKey, 'tv-key');
      expect(out.tavilyBaseUrl, 'https://api.tavily.com/search');
      expect(out.maxResults, 7);
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });
}
