import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'messages.dart';

/// Parses daemon `stream_delta` payloads into UI-ready message parts.
///
/// The daemon sends `{"type":"stream_delta","data":{"events":[{...}]}}`
/// where each event has a `kind` of `text` | `thinking` | `status_change` |
/// `approval_required` (see remote/daemon/pkg/connectrpc/event_parser.go).
class StreamDeltaParser {
  /// Extracts plain text deltas from a stream_delta message.
  static String textOf(Map<String, dynamic> message) {
    final data = message['data'];
    if (data is! Map) return '';
    final events = data['events'];
    if (events is! List) return '';
    final buffer = StringBuffer();
    for (final e in events) {
      if (e is Map && e['kind'] == 'text') {
        buffer.write(e['delta'] ?? '');
      }
    }
    return buffer.toString();
  }

  /// Extracts thinking and live tool execution deltas from a stream_delta message.
  static String thinkingOf(Map<String, dynamic> message) {
    final data = message['data'];
    if (data is! Map) return '';
    final events = data['events'];
    if (events is! List) return '';
    final buffer = StringBuffer();
    for (final e in events) {
      if (e is Map) {
        final kind = e['kind'];
        if (kind == 'thinking' || kind == 'status_change') {
          buffer.write(e['delta'] ?? '');
        } else if (e['tool'] != null &&
            e['tool'].toString().isNotEmpty &&
            kind != 'text') {
          final tool = e['tool'].toString();
          final detail = (e['detail'] ?? '').toString();
          final action = _formatToolAction(tool, detail);
          if (action.isNotEmpty) {
            if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
              buffer.writeln();
            }
            buffer.writeln(action);
          }
        }
      }
    }
    return buffer.toString();
  }

  static String _formatToolAction(String tool, String detail) {
    final lowerTool = tool.toLowerCase();
    if (lowerTool == 'ask_question' || lowerTool == 'ask_user') return '';
    String arg = '';
    if (detail.isNotEmpty) {
      try {
        final start = detail.indexOf('{');
        final end = detail.lastIndexOf('}');
        if (start >= 0 && end > start) {
          final jsonMap = json.decode(detail.substring(start, end + 1));
          if (jsonMap is Map) {
            arg = (jsonMap['command'] ??
                    jsonMap['CommandLine'] ??
                    jsonMap['command_line'] ??
                    jsonMap['path'] ??
                    jsonMap['filePath'] ??
                    jsonMap['file_path'] ??
                    jsonMap['targetFile'] ??
                    jsonMap['TargetFile'] ??
                    jsonMap['AbsolutePath'] ??
                    jsonMap['DirectoryPath'] ??
                    jsonMap['query'] ??
                    jsonMap['Query'] ??
                    jsonMap['pattern'] ??
                    jsonMap['description'] ??
                    jsonMap['toolSummary'] ??
                    jsonMap['toolAction'] ??
                    '')
                .toString();
          }
        }
      } catch (_) {}
      if (arg.isEmpty && !detail.startsWith('{')) {
        arg = detail.trim();
      }
    }
    if (lowerTool != 'run_command' && lowerTool != 'command' && lowerTool != 'bash' && lowerTool != 'terminal' && lowerTool != 'runner') {
      if (arg.contains('/') || arg.contains('\\')) {
        arg = arg.replaceAll(RegExp(r'^file:///[a-zA-Z]:[/\\]?'), '');
        arg = arg.replaceAll(RegExp(r'^[a-zA-Z]:[/\\]'), '');
        if (arg.length > 50) {
          final segments = arg.split(RegExp(r'[/\\]'));
          final base = segments.lastWhere((s) => s.trim().isNotEmpty, orElse: () => arg);
          if (base.isNotEmpty) {
            arg = base;
          }
        }
      }
    }
    if (arg.length > 70) {
      arg = '${arg.substring(0, 67)}…';
    }

    switch (lowerTool) {
      case 'run_command':
      case 'command':
      case 'bash':
      case 'terminal':
      case 'runner':
        return arg.isNotEmpty ? 'Ran $arg' : 'Ran command';
      case 'read_file':
      case 'view_file':
        return arg.isNotEmpty ? 'Viewed $arg' : 'Viewed file';
      case 'write_to_file':
      case 'edit_file':
      case 'replace_file_content':
      case 'multi_replace_file_content':
        return arg.isNotEmpty ? 'Edited $arg' : 'Edited file';
      case 'search_files':
      case 'grep':
      case 'grep_search':
        return arg.isNotEmpty ? 'Explored $arg' : 'Explored codebase';
      case 'search':
      case 'find_by_name':
        return arg.isNotEmpty ? 'Search $arg' : 'Search codebase';
      case 'list_files':
      case 'list_dir':
        return arg.isNotEmpty ? 'Explored $arg' : 'Explored directory';
      case 'invoke_subagent':
      case 'define_subagent':
      case 'subagent':
        return arg.isNotEmpty ? 'Subagent $arg' : 'Spawned subagent';
      case 'send_message':
        return arg.isNotEmpty ? 'Sent to $arg' : 'Sent message';
      case 'generate_image':
        return arg.isNotEmpty ? 'Generated $arg' : 'Generated image';
      case 'schedule':
      case 'timer':
        if (detail.isNotEmpty) {
          try {
            final start = detail.indexOf('{');
            final end = detail.lastIndexOf('}');
            if (start >= 0 && end > start) {
              final jsonMap = json.decode(detail.substring(start, end + 1));
              if (jsonMap is Map) {
                final dur = jsonMap['DurationSeconds'] ?? jsonMap['durationSeconds'] ?? jsonMap['duration_seconds'];
                final prompt = (jsonMap['Prompt'] ?? jsonMap['prompt'] ?? '').toString();
                if (dur != null) {
                  final durSec = int.tryParse(dur.toString()) ?? 0;
                  if (durSec > 0) {
                    if (prompt.isNotEmpty) {
                      return 'Timed $durSec seconds\n> $prompt\nStatus: Fired';
                    }
                    return 'Timed $durSec seconds';
                  }
                }
                if (prompt.isNotEmpty) {
                  return 'Scheduled $prompt';
                }
              }
            }
          } catch (_) {}
        }
        return arg.isNotEmpty ? 'Scheduled $arg' : 'Scheduled task';
      case 'browse':
      case 'read_url_content':
      case 'read_url':
        return arg.isNotEmpty ? 'Browsed $arg' : 'Browsed web';
      case 'auto_proceed':
      case 'auto_proceeded':
        return arg.isNotEmpty ? 'Auto-proceeded with $arg' : 'Auto-proceeded with Implementation Plan';
      case 'task_finished':
      case 'task_completed':
        return arg.isNotEmpty ? 'Task $arg finished' : 'Task finished';
      case 'tool_output':
      case 'runner_output':
      case 'search_result':
        return arg.isNotEmpty ? '✓ $arg' : '✓ completed';
      default:
        final cleanTool = tool.replaceAll('_', ' ');
        if (cleanTool.toLowerCase().startsWith('task ') && (arg.toLowerCase().contains('finish') || arg.toLowerCase().contains('complete'))) {
          return cleanTool;
        }
        return arg.isNotEmpty ? 'Task $cleanTool ($arg)' : 'Task $cleanTool';
    }
  }

  /// Extracts a tool-approval request if the delta carries one.
  static ToolApproval? approvalOf(Map<String, dynamic> message) {
    final data = message['data'];
    if (data is! Map) return null;
    final events = data['events'];
    if (events is! List) return null;
    for (final e in events) {
      if (e is Map && e['kind'] == 'approval_required') {
        final tool = e['tool'] as String? ?? 'generic_tool';
        // Si c'est ask_question, ce n'est pas un tool standard d'approbation binaire
        if (tool == 'ask_question' || tool == 'ask_user') continue;
        return ToolApproval(
          callId: e['callId'] as String? ?? '',
          tool: tool,
          detail: e['detail'] as String? ?? '',
          cascadeId: e['cascadeId'] as String? ?? '',
          trajectoryId: e['trajectoryId'] as String? ?? '',
          stepIndex: e['stepIndex'] is num ? (e['stepIndex'] as num).toInt() : -1,
          approvalType: tool == 'run_command' ? 'run_command' : 'approval',
        );
      }
    }
    return null;
  }

  /// Extracts an interactive question request if the delta carries one.
  /// H1 (audit clean-code-guard) : ne fabrique JAMAIS de question synthétique
  /// — un `approval_required` sans payload JSON exploitable (ex. run_command
  /// avec un champ "options" dans ses args) retourne null au lieu d'une carte
  /// fantôme, et l'anomalie est loggée pour diagnostic.
  static AskQuestionChoiceRequest? questionOf(Map<String, dynamic> message) {
    final data = message['data'];
    if (data is! Map) return null;
    final events = data['events'];
    if (events is! List) return null;
    for (final e in events) {
      if (e is Map && e['kind'] == 'approval_required') {
        final eMap = Map<String, dynamic>.from(e);
        final tool = (eMap['tool'] ?? '').toString().toLowerCase();
        final detail = (eMap['detail'] ?? '').toString();
        if (tool == 'ask_question' || tool == 'ask_user') {
          final q = _parseQuestionDetail(eMap);
          if (q != null) return q;
          debugPrint('stream_parser: ask_question sans payload JSON exploitable '
              '(callId=${eMap['callId'] ?? '?'}) — ignoré');
          continue;
        }
        // Heuristique legacy : certains daemons marquent ask_question avec un
        // tool générique mais un detail contenant "questions"/"options".
        // H1 : on exige alors un champ question réel — un run_command dont les
        // args contiennent un tableau "options" ne doit pas créer de question.
        if (detail.contains('"questions"') || detail.contains('"options"')) {
          final q = _parseQuestionDetail(eMap);
          if (q != null) return q;
        }
      }
    }
    return null;
  }

  static AskQuestionChoiceRequest? _parseQuestionDetail(
      Map<String, dynamic> event) {
    final detail = (event['detail'] ?? '').toString();
    final callId = event['callId'] ?? '';
    final cascadeId = event['cascadeId'] ?? '';
    final trajectoryId = event['trajectoryId'] ?? '';
    final stepIndex =
        event['stepIndex'] is num ? (event['stepIndex'] as num).toInt() : -1;

    try {
      final startIndex = detail.indexOf('{');
      final endIndex = detail.lastIndexOf('}');
      if (startIndex >= 0 && endIndex > startIndex) {
        final jsonStr = detail.substring(startIndex, endIndex + 1);
        final decoded = json.decode(jsonStr);
        if (decoded is Map) {
          final decMap = Map<String, dynamic>.from(decoded);
          // H1 : un approval_required non-question (tool générique) ne doit
          // pas produire de question fantôme — exiger question/questions.
          if (decMap['question'] == null && decMap['questions'] == null) {
            debugPrint('stream_parser: detail JSON sans champ question '
                '(callId=$callId) — ignoré');
            return null;
          }
          return AskQuestionChoiceRequest.fromJson({
            ...decMap,
            'callId': callId,
            'cascadeId': cascadeId,
            'trajectoryId': trajectoryId,
            'stepIndex': stepIndex,
          });
        }
      }
    } catch (e) {
      debugPrint('stream_parser: détail JSON illisible (callId=$callId) : $e');
    }
    return null;
  }

  /// Parses a standalone approval payload (e.g. from reactive approval_pending push).
  static ToolApproval? parseApprovalMap(Map<String, dynamic> map, {String cascadeId = ''}) {
    final callId = map['callId'] as String? ?? map['approvalId'] as String? ?? '';
    if (callId.isEmpty) return null;
    final tool = map['toolName'] as String? ?? map['tool'] as String? ?? 'tool';
    final detail = map['detail'] as String? ?? map['command'] as String? ?? '';
    final targetCascade = (map['cascadeId'] as String?)?.isNotEmpty == true
        ? map['cascadeId'] as String
        : cascadeId;
    final trajectoryId = map['trajectoryId'] as String? ?? '';
    final stepIndex = map['stepIndex'] is num ? (map['stepIndex'] as num).toInt() : -1;
    final approvalType = map['approvalType'] as String? ?? (tool == 'run_command' ? 'run_command' : 'approval');

    return ToolApproval(
      callId: callId,
      tool: tool,
      detail: detail,
      cascadeId: targetCascade,
      trajectoryId: trajectoryId,
      stepIndex: stepIndex,
      approvalType: approvalType,
    );
  }

  /// Parses a standalone question payload (e.g. from reactive question_pending push).
  static AskQuestionChoiceRequest? parseQuestionMap(Map<String, dynamic> map, {String cascadeId = ''}) {
    final callId = map['callId'] as String? ?? map['requestId'] as String? ?? '';
    final targetCascade = (map['cascadeId'] as String?)?.isNotEmpty == true
        ? map['cascadeId'] as String
        : cascadeId;
    final trajectoryId = map['trajectoryId'] as String? ?? '';
    final stepIndex = map['stepIndex'] is num ? (map['stepIndex'] as num).toInt() : -1;

    try {
      if (map.containsKey('questions') || map.containsKey('question')) {
        return AskQuestionChoiceRequest.fromJson({
          ...map,
          'callId': callId,
          'cascadeId': targetCascade,
          'trajectoryId': trajectoryId,
          'stepIndex': stepIndex,
        });
      }
    } catch (_) {}
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
