class SubagentItem {
  final String id;
  final String role;
  final String status;
  final String? stateDetail;
  final String? typeName;
  final String? prompt;
  final String? parentId;
  final int? createdAt;

  const SubagentItem({
    required this.id,
    required this.role,
    required this.status,
    this.stateDetail,
    this.typeName,
    this.prompt,
    this.parentId,
    this.createdAt,
  });

  factory SubagentItem.fromJson(Map<String, dynamic> json) {
    return SubagentItem(
      id: json['conversationId'] as String? ?? json['id'] as String? ?? '',
      role: json['role'] as String? ?? 'Subagent',
      status: json['state'] as String? ?? json['status'] as String? ?? 'idle',
      stateDetail: json['stateDetail'] as String?,
      typeName: json['type'] as String? ?? json['typeName'] as String?,
      prompt: json['prompt'] as String?,
      parentId: json['parentId'] as String?,
      createdAt: json['createdAt'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'status': status,
      if (stateDetail != null) 'stateDetail': stateDetail,
      if (typeName != null) 'typeName': typeName,
      if (prompt != null) 'prompt': prompt,
      if (parentId != null) 'parentId': parentId,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }

  SubagentItem copyWith({
    String? id,
    String? role,
    String? status,
    String? stateDetail,
    String? typeName,
    String? prompt,
    String? parentId,
    int? createdAt,
  }) {
    return SubagentItem(
      id: id ?? this.id,
      role: role ?? this.role,
      status: status ?? this.status,
      stateDetail: stateDetail ?? this.stateDetail,
      typeName: typeName ?? this.typeName,
      prompt: prompt ?? this.prompt,
      parentId: parentId ?? this.parentId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

