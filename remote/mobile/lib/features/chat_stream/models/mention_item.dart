enum MentionType { file, rule, mcp, conversation, terminal }

class MentionItem {
  final MentionType type;
  final String label;
  final String detail;
  final String? iconName;

  const MentionItem({
    required this.type,
    required this.label,
    required this.detail,
    this.iconName,
  });

  String get tag => '@${type.name}:$label';
}
