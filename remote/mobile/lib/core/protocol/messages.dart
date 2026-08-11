/// Protocol Data Models for Antigravity Remote Protocol
class CascadeSession {
  final String id;
  final String workspacePath;
  final String title;
  final String status;
  final String time;

  const CascadeSession({
    required this.id,
    required this.workspacePath,
    required this.title,
    required this.status,
    required this.time,
  });

  factory CascadeSession.fromJson(Map<String, dynamic> json) {
    return CascadeSession(
      id: json['cascadeId'] ?? json['id'] ?? '',
      workspacePath: json['workspacePath'] ?? json['workspace'] ?? '',
      title: json['title'] ?? 'Cascade Session',
      status: json['status'] ?? 'CASCADE_STATUS_READY',
      time: json['time'] ?? _relativeTime(json['updatedAt']),
    );
  }

  static String _relativeTime(Object? iso) {
    if (iso is! String) return 'Just now';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return 'Just now';
    final diff = DateTime.now().difference(parsed.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  Map<String, dynamic> toJson() => {
        'cascadeId': id,
        'workspacePath': workspacePath,
        'title': title,
        'status': status,
        'time': time,
      };
}

class ChatMessage {
  final String id;
  final String sender; // 'user' or 'assistant'
  final String text;
  final String? thought;
  final String timestamp;
  final bool isStreaming;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    this.thought,
    required this.timestamp,
    this.isStreaming = false,
  });

  ChatMessage copyWith({
    String? text,
    String? thought,
    bool? isStreaming,
  }) {
    return ChatMessage(
      id: id,
      sender: sender,
      text: text ?? this.text,
      thought: thought ?? this.thought,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}

enum ToolDecision { allow, deny }

class ToolApprovalRequest {
  final String callId;
  final String toolName;
  final String command;
  final String description;
  final String cascadeId;
  final String trajectoryId;
  final int stepIndex;
  final String approvalType;

  const ToolApprovalRequest({
    required this.callId,
    required this.toolName,
    required this.command,
    required this.description,
    this.cascadeId = '',
    this.trajectoryId = '',
    this.stepIndex = -1,
    this.approvalType = 'approval',
  });

  factory ToolApprovalRequest.fromJson(Map<String, dynamic> json) {
    return ToolApprovalRequest(
      callId: json['callId'] ?? '',
      toolName: json['toolName'] ?? 'run_command',
      command: json['command'] ?? '',
      description: json['description'] ??
          'An agent tool requires user confirmation',
      cascadeId: json['cascadeId'] ?? '',
      trajectoryId: json['trajectoryId'] ?? '',
      stepIndex: (json['stepIndex'] as num?)?.toInt() ?? -1,
      approvalType: json['approvalType'] ?? 'approval',
    );
  }
}
