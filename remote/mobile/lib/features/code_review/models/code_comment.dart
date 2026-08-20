class CodeComment {
  final String id;
  final String filePath;
  final String snippet;
  final String commentText;
  final DateTime createdAt;

  CodeComment({
    required this.id,
    required this.filePath,
    required this.snippet,
    required this.commentText,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String formatPromptQuote() {
    return '> In `$filePath`:\n> ```\n> $snippet\n> ```\n$commentText\n';
  }
}
