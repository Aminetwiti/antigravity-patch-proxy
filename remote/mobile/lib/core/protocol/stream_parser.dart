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

  /// Extracts thinking deltas from a stream_delta message.
  static String thinkingOf(Map<String, dynamic> message) {
    final data = message['data'];
    if (data is! Map) return '';
    final events = data['events'];
    if (events is! List) return '';
    final buffer = StringBuffer();
    for (final e in events) {
      if (e is Map &&
          (e['kind'] == 'thinking' || e['kind'] == 'status_change')) {
        buffer.write(e['delta'] ?? '');
      }
    }
    return buffer.toString();
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
