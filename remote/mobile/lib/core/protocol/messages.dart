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
    if (parsed == null || parsed.year < 2000) return 'Just now';
    final diff = DateTime.now().difference(parsed.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  bool get isAvailable {
    if (id.isEmpty) return false;
    final st = status.toUpperCase();
    if (st.contains('ARCHIV') ||
        st.contains('DELET') ||
        st.contains('TRASH') ||
        st.contains('KILLED') ||
        st == 'CASCADE_STATUS_ARCHIVED' ||
        st == 'CASCADE_STATUS_DELETED' ||
        st == 'CASCADE_STATUS_KILLED') {
      return false;
    }
    return true;
  }

  bool get isRunning {
    final st = status.toUpperCase();
    return st.contains('RUNNING');
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
  // true quand le stream s'est terminé sur une erreur : la bulle affiche un
  // état « erreur » dédié (fond danger) au lieu d'un texte markdown mélangé.
  final bool isError;
  // true quand le message est en attente d'envoi dans l'outbox hors-ligne.
  final bool isQueued;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    this.thought,
    required this.timestamp,
    this.isStreaming = false,
    this.isError = false,
    this.isQueued = false,
  });

  ChatMessage copyWith({
    String? text,
    String? thought,
    bool? isStreaming,
    bool? isError,
    bool? isQueued,
  }) {
    return ChatMessage(
      id: id,
      sender: sender,
      text: text ?? this.text,
      thought: thought ?? this.thought,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      isError: isError ?? this.isError,
      isQueued: isQueued ?? this.isQueued,
    );
  }
}

enum ToolDecision { allow, deny }

/// Portée d'une décision d'approbation : ponctuelle (par défaut) ou
/// « pour toute la session » (auto-approuvé côté daemon ensuite).
enum ApprovalScope { once, session }

class ToolApprovalRequest {
  final String callId;
  final String toolName;
  final String command;
  final String description;
  final String cascadeId;
  final String trajectoryId;
  final int stepIndex;
  final String approvalType;
  final String? filePath;

  /// "Ne plus redemander pour cette session" — le daemon auto-approuve les
  /// approbations du même type pour cette cascade.
  final ApprovalScope scope;

  const ToolApprovalRequest({
    required this.callId,
    required this.toolName,
    required this.command,
    required this.description,
    this.cascadeId = '',
    this.trajectoryId = '',
    this.stepIndex = -1,
    this.approvalType = 'approval',
    this.filePath,
    this.scope = ApprovalScope.once,
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
      filePath: json['filePath'],
      scope: json['scope'] == 'session'
          ? ApprovalScope.session
          : ApprovalScope.once,
    );
  }
}

class AskQuestionChoiceRequest {
  final String requestId;
  final String cascadeId;
  final String trajectoryId;
  final int stepIndex;
  final String question;
  final List<String> options;
  final bool isMultiSelect;
  final bool allowCustom;

  const AskQuestionChoiceRequest({
    required this.requestId,
    this.cascadeId = '',
    this.trajectoryId = '',
    this.stepIndex = -1,
    required this.question,
    required this.options,
    this.isMultiSelect = false,
    this.allowCustom = true,
  });

  factory AskQuestionChoiceRequest.fromJson(Map<String, dynamic> json) {
    List<String> parsedOptions = [];
    if (json['options'] is List) {
      parsedOptions = (json['options'] as List).map((e) => e.toString()).toList();
    } else if (json['questions'] is List && (json['questions'] as List).isNotEmpty) {
      final firstQ = (json['questions'] as List).first;
      if (firstQ is Map && firstQ['options'] is List) {
        parsedOptions = (firstQ['options'] as List).map((e) => e.toString()).toList();
      }
    }

    String parsedQuestion = json['question'] ?? '';
    if (parsedQuestion.isEmpty && json['questions'] is List && (json['questions'] as List).isNotEmpty) {
      final firstQ = (json['questions'] as List).first;
      if (firstQ is Map && firstQ['question'] != null) {
        parsedQuestion = firstQ['question'].toString();
      }
    }
    if (parsedQuestion.isEmpty) {
      parsedQuestion = 'The agent needs your feedback:';
    }

    return AskQuestionChoiceRequest(
      requestId: json['requestId'] ?? json['callId'] ?? '',
      cascadeId: json['cascadeId'] ?? '',
      trajectoryId: json['trajectoryId'] ?? '',
      stepIndex: (json['stepIndex'] as num?)?.toInt() ?? -1,
      question: parsedQuestion,
      options: parsedOptions,
      isMultiSelect: json['isMultiSelect'] == true || json['is_multi_select'] == true,
      allowCustom: json['allowCustom'] ?? true,
    );
  }
}

class ClientMessage {
  final String type;
  final String? requestId;
  final String? cascadeId;
  final Map<String, dynamic>? data;

  const ClientMessage({
    required this.type,
    this.requestId,
    this.cascadeId,
    this.data,
  });

  factory ClientMessage.fromJson(Map<String, dynamic> json) {
    return ClientMessage(
      type: json['type'] as String? ?? '',
      requestId: json['requestId'] as String?,
      cascadeId: json['cascadeId'] as String?,
      data: json['data'] is Map ? (json['data'] as Map).cast<String, dynamic>() : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    if (requestId != null) 'requestId': requestId,
    if (cascadeId != null) 'cascadeId': cascadeId,
    if (data != null) ...data!,
  };
}

