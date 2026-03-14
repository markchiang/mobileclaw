import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

enum LlmProviderId { openai, gemini, openrouter, ollama, custom }

String llmProviderIdValue(LlmProviderId id) {
  return switch (id) {
    LlmProviderId.openai => 'openai',
    LlmProviderId.gemini => 'gemini',
    LlmProviderId.openrouter => 'openrouter',
    LlmProviderId.ollama => 'ollama',
    LlmProviderId.custom => 'custom',
  };
}

LlmProviderId llmProviderIdFromValue(String raw) {
  for (final id in LlmProviderId.values) {
    if (llmProviderIdValue(id) == raw) {
      return id;
    }
  }
  return LlmProviderId.openai;
}

String llmProviderLabel(LlmProviderId id) {
  return switch (id) {
    LlmProviderId.openai => 'OpenAI',
    LlmProviderId.gemini => 'Gemini',
    LlmProviderId.openrouter => 'OpenRouter',
    LlmProviderId.ollama => 'Ollama (Local)',
    LlmProviderId.custom => 'Custom (OpenAI-compatible)',
  };
}

bool llmProviderRequiresApiKey(LlmProviderId id) {
  return id != LlmProviderId.ollama;
}

class LlmProviderProfile {
  const LlmProviderProfile({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
  });

  final String apiKey;
  final String baseUrl;
  final String model;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'api_key': apiKey,
      'base_url': baseUrl,
      'model': model,
    };
  }

  factory LlmProviderProfile.fromJson(Map<String, Object?> json) {
    return LlmProviderProfile(
      apiKey: (json['api_key'] ?? '').toString(),
      baseUrl: (json['base_url'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
    );
  }

  LlmProviderProfile copyWith({
    String? apiKey,
    String? baseUrl,
    String? model,
  }) {
    return LlmProviderProfile(
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
    );
  }

  static const LlmProviderProfile openAiDefault = LlmProviderProfile(
    apiKey: '',
    baseUrl: 'https://api.openai.com/v1/chat/completions',
    model: 'gpt-4o-mini',
  );

  static const LlmProviderProfile openRouterDefault = LlmProviderProfile(
    apiKey: '',
    baseUrl: 'https://openrouter.ai/api/v1/chat/completions',
    model: 'openrouter/free',
  );

  static const LlmProviderProfile geminiDefault = LlmProviderProfile(
    apiKey: '',
    baseUrl:
        'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
    model: 'gemini-2.0-flash',
  );

  static const LlmProviderProfile ollamaDefault = LlmProviderProfile(
    apiKey: '',
    baseUrl: 'http://127.0.0.1:11434/v1/chat/completions',
    model: 'minimax-m2.5:cloud',
  );

  static const LlmProviderProfile customDefault = LlmProviderProfile(
    apiKey: '',
    baseUrl: '',
    model: '',
  );
}

class LlmConfig {
  const LlmConfig({
    required this.selectedProvider,
    required this.profiles,
    required this.maxToolIterations,
  });

  final LlmProviderId selectedProvider;
  final Map<LlmProviderId, LlmProviderProfile> profiles;
  final int maxToolIterations;

  LlmProviderProfile profileOf(LlmProviderId id) {
    return profiles[id] ?? defaults.profiles[id]!;
  }

  LlmProviderProfile get selectedProfile => profileOf(selectedProvider);

  LlmConfig copyWith({
    LlmProviderId? selectedProvider,
    Map<LlmProviderId, LlmProviderProfile>? profiles,
    int? maxToolIterations,
  }) {
    return LlmConfig(
      selectedProvider: selectedProvider ?? this.selectedProvider,
      profiles: profiles ?? this.profiles,
      maxToolIterations: maxToolIterations ?? this.maxToolIterations,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'selected_provider': llmProviderIdValue(selectedProvider),
      'providers': <String, Object?>{
        for (final entry in profiles.entries)
          llmProviderIdValue(entry.key): entry.value.toJson(),
      },
      'max_tool_iterations': maxToolIterations,
    };
  }

  factory LlmConfig.fromJson(Map<String, Object?> json) {
    // Backward compatibility with old single-profile structure.
    if (json.containsKey('api_key') ||
        json.containsKey('base_url') ||
        json.containsKey('model')) {
      final oldProfile = LlmProviderProfile.fromJson(json);
      final nextProfiles = Map<LlmProviderId, LlmProviderProfile>.from(
        defaults.profiles,
      );
      nextProfiles[LlmProviderId.openai] = oldProfile;
      return LlmConfig(
        selectedProvider: LlmProviderId.openai,
        profiles: nextProfiles,
        maxToolIterations: defaults.maxToolIterations,
      );
    }

    final selected = llmProviderIdFromValue(
      (json['selected_provider'] ?? '').toString(),
    );

    final providersRaw =
        (json['providers'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    final nextProfiles = Map<LlmProviderId, LlmProviderProfile>.from(
      defaults.profiles,
    );

    for (final entry in providersRaw.entries) {
      final id = llmProviderIdFromValue(entry.key);
      final rawMap = entry.value;
      if (rawMap is Map<String, dynamic>) {
        nextProfiles[id] = LlmProviderProfile.fromJson(rawMap);
      }
    }

    final rawMax = (json['max_tool_iterations'] as num?)?.toInt() ??
        defaults.maxToolIterations;

    return LlmConfig(
      selectedProvider: selected,
      profiles: nextProfiles,
      maxToolIterations: rawMax.clamp(1, 50),
    );
  }

  static const LlmConfig defaults = LlmConfig(
    selectedProvider: LlmProviderId.openai,
    maxToolIterations: 20,
    profiles: <LlmProviderId, LlmProviderProfile>{
      LlmProviderId.openai: LlmProviderProfile.openAiDefault,
      LlmProviderId.gemini: LlmProviderProfile.geminiDefault,
      LlmProviderId.openrouter: LlmProviderProfile.openRouterDefault,
      LlmProviderId.ollama: LlmProviderProfile.ollamaDefault,
      LlmProviderId.custom: LlmProviderProfile.customDefault,
    },
  );
}

class LlmConfigStore {
  LlmConfigStore(this.appRoot);

  final Directory appRoot;

  File get _configFile => File(p.join(appRoot.path, 'config', 'llm.json'));

  Future<LlmConfig> load() async {
    final file = _configFile;
    if (!await file.exists()) {
      return LlmConfig.defaults;
    }
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return LlmConfig.fromJson(data);
    } catch (_) {
      return LlmConfig.defaults;
    }
  }

  Future<void> save(LlmConfig config) async {
    final file = _configFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
      flush: true,
    );
  }
}
