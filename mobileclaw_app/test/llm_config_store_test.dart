import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileclaw_app/core/services/llm_config_store.dart';

void main() {
  test('llm config store saves and loads max_tool_iterations', () async {
    final root = await Directory.systemTemp.createTemp('mobileclaw-llmcfg-');
    try {
      final store = LlmConfigStore(root);
      final input = LlmConfig.defaults.copyWith(
        selectedProvider: LlmProviderId.openrouter,
        maxToolIterations: 33,
      );
      await store.save(input);

      final out = await store.load();
      expect(out.selectedProvider, LlmProviderId.openrouter);
      expect(out.maxToolIterations, 33);
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });

  test('llm config uses default iterations for legacy payload', () async {
    final root = await Directory.systemTemp.createTemp('mobileclaw-llmcfg-');
    try {
      final file = File('${root.path}/config/llm.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '{"selected_provider":"openai","providers":{}}',
        flush: true,
      );

      final out = await LlmConfigStore(root).load();
      expect(out.maxToolIterations, LlmConfig.defaults.maxToolIterations);
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });
}
