class McpServerInfo {
  final String name;
  final String status;
  final int toolCount;
  final List<String> tools;
  final String? description;

  const McpServerInfo({
    required this.name,
    required this.status,
    required this.toolCount,
    required this.tools,
    this.description,
  });

  factory McpServerInfo.fromJson(Map<String, dynamic> json) {
    final toolsList = (json['tools'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    return McpServerInfo(
      name: json['name'] as String? ?? 'unknown',
      status: json['status'] as String? ?? 'ready',
      toolCount: json['toolCount'] as int? ?? toolsList.length,
      tools: toolsList,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'status': status,
        'toolCount': toolCount,
        'tools': tools,
        if (description != null) 'description': description,
      };
}
