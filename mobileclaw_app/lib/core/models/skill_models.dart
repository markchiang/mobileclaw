class SkillDefinition {
  SkillDefinition({
    required this.name,
    required this.path,
    required this.content,
    this.description = '',
    this.source = 'workspace',
  });

  final String name;
  final String path;
  final String content;
  final String description;
  final String source;
}

class AgentWorkspaceProfile {
  AgentWorkspaceProfile({
    this.agentsMd = '',
    this.soulMd = '',
    this.userMd = '',
    this.identityMd = '',
    this.memoryMd = '',
    this.toolsMd = '',
    this.heartbeatMd = '',
    this.extraDocs = const <SkillDefinition>[],
    this.skills = const <SkillDefinition>[],
  });

  final String agentsMd;
  final String soulMd;
  final String userMd;
  final String identityMd;
  final String memoryMd;
  final String toolsMd;
  final String heartbeatMd;
  final List<SkillDefinition> extraDocs;
  final List<SkillDefinition> skills;

  String asPromptContext() {
    final buff = StringBuffer();
    if (agentsMd.trim().isNotEmpty) {
      buff.writeln('## AGENTS.md');
      buff.writeln(agentsMd.trim());
      buff.writeln();
    }
    if (soulMd.trim().isNotEmpty) {
      buff.writeln('## SOUL.md');
      buff.writeln(soulMd.trim());
      buff.writeln();
    }
    if (userMd.trim().isNotEmpty) {
      buff.writeln('## USER.md');
      buff.writeln(userMd.trim());
      buff.writeln();
    }
    if (identityMd.trim().isNotEmpty) {
      buff.writeln('## IDENTITY.md');
      buff.writeln(identityMd.trim());
      buff.writeln();
    }
    if (memoryMd.trim().isNotEmpty) {
      buff.writeln('## MEMORY.md');
      buff.writeln(memoryMd.trim());
      buff.writeln();
    }
    if (toolsMd.trim().isNotEmpty) {
      buff.writeln('## TOOLS.md');
      buff.writeln(toolsMd.trim());
      buff.writeln();
    }
    if (heartbeatMd.trim().isNotEmpty) {
      buff.writeln('## HEARTBEAT.md');
      buff.writeln(heartbeatMd.trim());
      buff.writeln();
    }
    if (extraDocs.isNotEmpty) {
      buff.writeln('## EXTRA_DOCS');
      for (final doc in extraDocs) {
        buff.writeln('### ${doc.name}');
        buff.writeln(doc.content.trim());
        buff.writeln();
      }
    }
    if (skills.isNotEmpty) {
      buff.writeln('## SKILLS');
      for (final skill in skills) {
        buff.writeln('### ${skill.name}');
        if (skill.description.trim().isNotEmpty) {
          buff.writeln(skill.description.trim());
          buff.writeln();
        }
        buff.writeln(skill.content.trim());
        buff.writeln();
      }
    }
    return buff.toString().trim();
  }
}
