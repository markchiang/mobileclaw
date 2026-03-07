import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileclaw_app/core/models/chat_models.dart';
import 'package:mobileclaw_app/core/providers/openai_compatible_provider.dart';
import 'package:mobileclaw_app/core/services/llm_config_store.dart';

void main() {
  test('throws helpful error when API key is missing for key-required provider',
      () async {
    final root = await Directory.systemTemp.createTemp('mobileclaw-llmcfg-');
    try {
      final store = LlmConfigStore(root);
      final provider = OpenAiCompatibleProvider(configStore: store);

      await expectLater(
        provider.chat(
          messages: <ChatMessage>[
            ChatMessage(
              role: ChatRole.user,
              content: 'hello',
              sessionKey: 'default',
              createdAt: DateTime.now(),
            ),
          ],
          model: provider.defaultModel,
        ),
        throwsA(isA<StateError>()),
      );
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });

  test('config store save and load round trip with selected provider',
      () async {
    final root = await Directory.systemTemp.createTemp('mobileclaw-llmcfg-');
    try {
      final store = LlmConfigStore(root);
      final input = LlmConfig.defaults.copyWith(
        selectedProvider: LlmProviderId.openrouter,
        profiles: <LlmProviderId, LlmProviderProfile>{
          ...LlmConfig.defaults.profiles,
          LlmProviderId.openrouter: const LlmProviderProfile(
            apiKey: 'or-key',
            baseUrl: 'https://openrouter.ai/api/v1/chat/completions',
            model: 'openai/gpt-4o-mini',
          ),
        },
      );

      await store.save(input);
      final out = await store.load();

      expect(out.selectedProvider, LlmProviderId.openrouter);
      expect(out.profileOf(LlmProviderId.openrouter).apiKey, 'or-key');
      expect(
        out.profileOf(LlmProviderId.openrouter).baseUrl,
        'https://openrouter.ai/api/v1/chat/completions',
      );
      expect(
          out.profileOf(LlmProviderId.openrouter).model, 'openai/gpt-4o-mini');
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });

  test('gemini provider profile is persisted and loaded', () async {
    final root = await Directory.systemTemp.createTemp('mobileclaw-llmcfg-');
    try {
      final store = LlmConfigStore(root);
      final input = LlmConfig.defaults.copyWith(
        selectedProvider: LlmProviderId.gemini,
        profiles: <LlmProviderId, LlmProviderProfile>{
          ...LlmConfig.defaults.profiles,
          LlmProviderId.gemini: const LlmProviderProfile(
            apiKey: 'g-key',
            baseUrl:
                'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
            model: 'gemini-2.0-flash',
          ),
        },
      );

      await store.save(input);
      final out = await store.load();

      expect(out.selectedProvider, LlmProviderId.gemini);
      expect(out.profileOf(LlmProviderId.gemini).apiKey, 'g-key');
      expect(
        out.profileOf(LlmProviderId.gemini).baseUrl,
        'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
      );
      expect(out.profileOf(LlmProviderId.gemini).model, 'gemini-2.0-flash');
      expect(llmProviderLabel(LlmProviderId.gemini), 'Gemini');
      expect(llmProviderRequiresApiKey(LlmProviderId.gemini), isTrue);
    } finally {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });
}
