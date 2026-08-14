class SubagentItem {
  final String id;
  final String role;
  final String status;
  final String? stateDetail;
  final String? typeName;

  const SubagentItem({
    required this.id,
    required this.role,
    required this.status,
    this.stateDetail,
    this.typeName,
  });

  factory SubagentItem.fromJson(Map<String, dynamic> json) {
    return SubagentItem(
      id: json['conversationId'] as String? ?? json['id'] as String? ?? '',
      role: json['role'] as String? ?? 'Subagent',
      status: json['state'] as String? ?? json['status'] as String? ?? 'idle',
      stateDetail: json['stateDetail'] as String?,
      typeName: json['type'] as String? ?? json['typeName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'status': status,
      if (stateDetail != null) 'stateDetail': stateDetail,
      if (typeName != null) 'typeName': typeName,
    };
  }

  SubagentItem copyWith({
    String? id,
    String? role,
    String? status,
    String? stateDetail,
    String? typeName,
  }) {
    return SubagentItem(
      id: id ?? this.id,
      role: role ?? this.role,
      status: status ?? this.status,
      stateDetail: stateDetail ?? this.stateDetail,
      typeName: typeName ?? this.typeName,
    );
  }
}
