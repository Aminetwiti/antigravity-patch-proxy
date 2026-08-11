/// Parses daemon `stream_delta` payloads into UI-ready message parts.
///
/// The daemon sends `{"type":"stream_delta","data":{"events":[{...}]}}`
/// where each event has a `kind` of `text` | `thinking` | `status_change` |
/// `approval_required` (see remote/daemon/pkg/connectrpc/event_parser.go).
class StreamDeltaParser {
  /// Extracts plain text deltas from a stream_delta message.
  static String textOf(Map<String, dynamic> message) {
    final data = message['data'];
    if (data is! Map<String, dynamic>) return '';
    final events = data['events'];
    if (events is! List) return '';
    final buffer = StringBuffer();
    for (final e in events) {
      if (e is Map<String, dynamic> && e['kind'] == 'text') {
        buffer.write(e['delta'] ?? '');
      }
    }
    return buffer.toString();
  }

  /// Extracts thinking deltas from a stream_delta message.
  static String thinkingOf(Map<String, dynamic> message) {
    final data = message['data'];
    if (data is! Map<String, dynamic>) return '';
    final events = data['events'];
    if (events is! List) return '';
    final buffer = StringBuffer();
    for (final e in events) {
      if (e is Map<String, dynamic> &&
          (e['kind'] == 'thinking' || e['kind'] == 'status_change')) {
        buffer.write(e['delta'] ?? '');
      }
    }
    return buffer.toString();
  }

  /// Extracts a tool-approval request if the delta carries one.
  static ToolApproval? approvalOf(Map<String, dynamic> message) {
    final data = message['data'];
    if (data is! Map<String, dynamic>) return null;
    final events = data['events'];
    if (events is! List) return null;
    for (final e in events) {
      if (e is Map<String, dynamic> && e['kind'] == 'approval_required') {
        final tool = e['tool'] ?? 'generic_tool';
        return ToolApproval(
          callId: e['callId'] ?? '',
          tool: tool,
          detail: e['detail'] ?? '',
          cascadeId: e['cascadeId'] ?? '',
          trajectoryId: e['trajectoryId'] ?? '',
          stepIndex: e['stepIndex'] is num ? (e['stepIndex'] as num).toInt() : -1,
          approvalType: tool == 'run_command' ? 'run_command' : 'approval',
        );
      }
    }
    return null;
  }
}

class ToolApproval {
  final String callId;
  final String tool;
  final String detail;
  final String cascadeId;
  final String trajectoryId;
  final int stepIndex;
  final String approvalType;

  const ToolApproval({
    required this.callId,
    required this.tool,
    required this.detail,
    required this.cascadeId,
    this.trajectoryId = '',
    this.stepIndex = -1,
    this.approvalType = 'approval',
  });

  /// The command line to echo back on approval (run_command oneof field 2).
  String get command => _extractCommand(detail);

  static String _extractCommand(String detail) {
    final m = RegExp(
          r'"(command_line|commandline)"\s*:\s*"((?:[^"\\]|\\.)*)"',
          caseSensitive: false,
        )
        .firstMatch(detail);
    if (m != null) return m.group(2)!.replaceAll(r'\n', '\n');
    // Fallback: first quoted line that looks like a shell command.
    for (final line in detail.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty && !t.startsWith('{') && !t.startsWith('}')) {
        return t;
      }
    }
    return '';
  }
}
