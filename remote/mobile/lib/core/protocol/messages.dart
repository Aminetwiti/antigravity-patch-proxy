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
      workspacePath: json['workspacePath'] ?? '',
      title: json['title'] ?? 'Cascade Session',
      status: json['status'] ?? 'CASCADE_STATUS_READY',
      time: json['time'] ?? 'Just now',
    );
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

  const ToolApprovalRequest({
    required this.callId,
    required this.toolName,
    required this.command,
    required this.description,
  });

  factory ToolApprovalRequest.fromJson(Map<String, dynamic> json) {
    return ToolApprovalRequest(
      callId: json['callId'] ?? '',
      toolName: json['toolName'] ?? 'run_command',
      command: json['command'] ?? '',
      description: json['description'] ?? 'An agent tool requires user confirmation',
    );
  }
}
