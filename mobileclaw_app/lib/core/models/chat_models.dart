import 'dart:convert';

enum ChatRole { system, user, assistant, tool }

ChatRole chatRoleFromString(String raw) {
  return ChatRole.values.firstWhere(
    (e) => e.name == raw,
    orElse: () => ChatRole.user,
  );
}

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    DateTime? createdAt,
    this.sessionKey = 'default',
    this.toolCallId,
    this.toolCalls = const <ToolCallRecord>[],
  }) : createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final ChatRole role;
  final String content;
  final DateTime createdAt;
  final String sessionKey;
  final String? toolCallId;
  final List<ToolCallRecord> toolCalls;

  ChatMessage copyWith({
    ChatRole? role,
    String? content,
    DateTime? createdAt,
    String? sessionKey,
    String? toolCallId,
    List<ToolCallRecord>? toolCalls,
  }) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      sessionKey: sessionKey ?? this.sessionKey,
      toolCallId: toolCallId ?? this.toolCallId,
      toolCalls: toolCalls ?? this.toolCalls,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'role': role.name,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'session_key': sessionKey,
      if (toolCallId != null) 'tool_call_id': toolCallId,
      if (toolCalls.isNotEmpty)
        'tool_calls': toolCalls.map((e) => e.toJson()).toList(),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: chatRoleFromString('${json['role'] ?? 'user'}'),
      content: '${json['content'] ?? ''}',
      createdAt:
          DateTime.tryParse('${json['created_at'] ?? ''}') ?? DateTime.now(),
      sessionKey: '${json['session_key'] ?? 'default'}',
      toolCallId: json['tool_call_id']?.toString(),
      toolCalls: ((json['tool_calls'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ToolCallRecord.fromJson)
          .toList(),
    );
  }

  String toJsonLine() => jsonEncode(toJson());

  factory ChatMessage.fromJsonLine(String line) {
    return ChatMessage.fromJson(jsonDecode(line) as Map<String, dynamic>);
  }
}

class ToolCallRecord {
  ToolCallRecord({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  final String id;
  final String name;
  final String argumentsJson;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'arguments_json': argumentsJson,
    };
  }

  factory ToolCallRecord.fromJson(Map<String, dynamic> json) {
    return ToolCallRecord(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      argumentsJson: '${json['arguments_json'] ?? ''}',
    );
  }
}

class SessionMeta {
  SessionMeta({
    required this.key,
    this.summary = '',
    this.skip = 0,
    this.count = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String key;
  final String summary;
  final int skip;
  final int count;
  final DateTime createdAt;
  final DateTime updatedAt;

  SessionMeta copyWith({
    String? key,
    String? summary,
    int? skip,
    int? count,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SessionMeta(
      key: key ?? this.key,
      summary: summary ?? this.summary,
      skip: skip ?? this.skip,
      count: count ?? this.count,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'key': key,
      'summary': summary,
      'skip': skip,
      'count': count,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory SessionMeta.fromJson(Map<String, dynamic> json) {
    return SessionMeta(
      key: '${json['key'] ?? ''}',
      summary: '${json['summary'] ?? ''}',
      skip: (json['skip'] as num?)?.toInt() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse('${json['created_at'] ?? ''}') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse('${json['updated_at'] ?? ''}') ?? DateTime.now(),
    );
  }
}
