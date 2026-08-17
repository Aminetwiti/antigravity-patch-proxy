import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/daemon_api.dart';
import 'package:mobile/features/chat_stream/chat_stream_screen.dart';

({DaemonApi api, StreamController<dynamic> ctrl, List<Map<String, dynamic>> out})
    _mkApi() {
  final out = <Map<String, dynamic>>[];
  final ctrl = StreamController<dynamic>.broadcast();
  final api = DaemonApi(
    incoming: ctrl.stream,
    send: (d) {
      final map = d as Map<String, dynamic>;
      out.add(map);
      final reqId = map['requestId'] as String?;
      final type = map['type'] as String?;
      if (reqId != null &&
          (type == 'get_session_history' ||
              type == 'read_file' ||
              type == 'list_files' ||
              type == 'get_context' ||
              type == 'submit_approval')) {
        scheduleMicrotask(() {
          if (!ctrl.isClosed) {
            ctrl.add(jsonEncode({'requestId': reqId, 'data': {}}));
          }
        });
      }
    },
  );
  return (api: api, ctrl: ctrl, out: out);
}

void main() {
  group('Multi-Session Concurrency & Event Isolation Tests', () {
    testWidgets('Background session events do not contaminate active session UI',
        (WidgetTester tester) async {
      final fixture = _mkApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatStreamScreen(
              activeSessionId: 'session-B',
              activeProjectName: 'test-project',
              api: fixture.api,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Émission d'un flux complet pour la session A en arrière-plan
      fixture.ctrl.add(jsonEncode({
        'broadcast': true,
        'type': 'stream_start',
        'cascadeId': 'session-A',
        'requestId': 'req-A-1',
      }));
      await tester.pump();

      fixture.ctrl.add(jsonEncode({
        'broadcast': true,
        'type': 'stream_delta',
        'cascadeId': 'session-A',
        'requestId': 'req-A-1',
        'data': {
          'text': 'SECRET_TOKEN_FROM_SESSION_A',
        },
      }));
      await tester.pump();

      // Session B ne doit JAMAIS afficher le token de session A
      expect(find.textContaining('SECRET_TOKEN_FROM_SESSION_A'), findsNothing);

      // Émission d'un token pour la session B (active)
      fixture.ctrl.add(jsonEncode({
        'broadcast': true,
        'type': 'stream_start',
        'cascadeId': 'session-B',
        'requestId': 'req-B-1',
      }));
      await tester.pump();

      fixture.ctrl.add(jsonEncode({
        'broadcast': true,
        'type': 'stream_delta',
        'cascadeId': 'session-B',
        'requestId': 'req-B-1',
        'data': {
          'text': 'TOKEN_FOR_SESSION_B',
        },
      }));
      await tester.pump();

      // Session B affiche son token
      expect(find.textContaining('TOKEN_FOR_SESSION_B'), findsOneWidget);
      expect(find.textContaining('SECRET_TOKEN_FROM_SESSION_A'), findsNothing);

      fixture.ctrl.close();
    });

    testWidgets('Approvals from session A do not appear in session B',
        (WidgetTester tester) async {
      final fixture = _mkApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatStreamScreen(
              activeSessionId: 'session-B',
              activeProjectName: 'test-project',
              api: fixture.api,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Approbation envoyée pour session A
      fixture.ctrl.add(jsonEncode({
        'broadcast': true,
        'type': 'stream_delta',
        'cascadeId': 'session-A',
        'requestId': 'req-A-2',
        'data': {
          'approval': {
            'callId': 'call-A-approval',
            'tool': 'run_command',
            'command': 'rm -rf /tmp/test-A',
            'cascadeId': 'session-A',
            'approvalType': 'command',
          },
        },
      }));
      await tester.pump();

      // Dans session B, aucune carte d'approbation pour session A
      expect(find.textContaining('rm -rf /tmp/test-A'), findsNothing);

      // Approbation envoyée pour session B
      fixture.ctrl.add(jsonEncode({
        'broadcast': true,
        'type': 'stream_delta',
        'cascadeId': 'session-B',
        'requestId': 'req-B-2',
        'data': {
          'approval': {
            'callId': 'call-B-approval',
            'tool': 'run_command',
            'command': 'npm test session-B',
            'cascadeId': 'session-B',
            'approvalType': 'command',
          },
        },
      }));
      await tester.pump();

      // Dans session B, la commande de B est affichée
      expect(find.textContaining('npm test session-B'), findsOneWidget);

      fixture.ctrl.close();
    });

    testWidgets('Un-scoped events without cascadeId are ignored and do not pollute active session',
        (WidgetTester tester) async {
      final fixture = _mkApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatStreamScreen(
              activeSessionId: 'session-C',
              activeProjectName: 'test-project',
              api: fixture.api,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Événement orphelin sans cascadeId
      fixture.ctrl.add(jsonEncode({
        'broadcast': true,
        'type': 'stream_delta',
        'requestId': 'req-orphan-1',
        'data': {
          'text': 'ORPHAN_CONTAMINATION_TEXT',
        },
      }));
      await tester.pump();

      expect(find.textContaining('ORPHAN_CONTAMINATION_TEXT'), findsNothing);

      fixture.ctrl.close();
    });
  });
}
