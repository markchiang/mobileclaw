String sanitizeSessionKey(String key) {
  return key.replaceAll(':', '_');
}

bool isSafeSkillIdentifier(String id) {
  final trimmed = id.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if (trimmed.contains('..') || trimmed.contains('/') || trimmed.contains(r'\')) {
    return false;
  }
  return true;
}
