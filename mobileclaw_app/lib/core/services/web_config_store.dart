import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class WebConfig {
  const WebConfig({
    required this.enabled,
    required this.tavilyApiKey,
    required this.tavilyBaseUrl,
    required this.maxResults,
  });

  final bool enabled;
  final String tavilyApiKey;
  final String tavilyBaseUrl;
  final int maxResults;

  WebConfig copyWith({
    bool? enabled,
    String? tavilyApiKey,
    String? tavilyBaseUrl,
    int? maxResults,
  }) {
    return WebConfig(
      enabled: enabled ?? this.enabled,
      tavilyApiKey: tavilyApiKey ?? this.tavilyApiKey,
      tavilyBaseUrl: tavilyBaseUrl ?? this.tavilyBaseUrl,
      maxResults: maxResults ?? this.maxResults,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'tavily_api_key': tavilyApiKey,
      'tavily_base_url': tavilyBaseUrl,
      'max_results': maxResults,
    };
  }

  factory WebConfig.fromJson(Map<String, Object?> json) {
    return WebConfig(
      enabled: (json['enabled'] as bool?) ?? true,
      tavilyApiKey: (json['tavily_api_key'] ?? '').toString(),
      tavilyBaseUrl: (json['tavily_base_url'] ?? '').toString(),
      maxResults: (json['max_results'] as num?)?.toInt() ?? 5,
    );
  }

  static const WebConfig defaults = WebConfig(
    enabled: true,
    tavilyApiKey: '',
    tavilyBaseUrl: 'https://api.tavily.com/search',
    maxResults: 5,
  );
}

class WebConfigStore {
  WebConfigStore(this.appRoot);

  final Directory appRoot;

  File get _configFile => File(p.join(appRoot.path, 'config', 'web.json'));

  Future<WebConfig> load() async {
    final file = _configFile;
    if (!await file.exists()) {
      return WebConfig.defaults;
    }
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return WebConfig.fromJson(raw);
    } catch (_) {
      return WebConfig.defaults;
    }
  }

  Future<void> save(WebConfig config) async {
    final file = _configFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
      flush: true,
    );
  }
}
