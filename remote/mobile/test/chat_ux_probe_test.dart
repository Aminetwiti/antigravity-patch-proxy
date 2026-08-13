import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/daemon_api.dart';
import 'package:mobile/features/chat_stream/chat_stream_screen.dart';
import 'package:mobile/widgets/tool_approval_card.dart';

void main() {
  testWidgets('probe: trace pipeline internals', (tester) async {
    final out = <Map<String, dynamic>>[];
    final ctrl = StreamController<dynamic>();
    final api = DaemonApi(incoming: ctrl.stream, send: (d) => out.add(d as Map<String, dynamic>));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B5CF6), brightness: Brightness.dark)),
        home: Scaffold(
          body: ChatStreamScreen(
            api: api,
            activeSessionId: 'c1',
            activeProjectName: 'Test',
            isConnected: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Drive via the input bar (real user path)
    await tester.enterText(find.byType(TextField), 'fais deux trucs');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pump();
    debugPrint('PROBE out: $out');

    // 1) raw event (as daemon would send)
    ctrl.add(jsonEncode({
      'type': 'stream_delta',
      'requestId': 'r1',
      'data': {
        'events': [
          {
            'kind': 'approval_required',
            'callId': 'call-1',
            'tool': 'run_command',
            'detail': '{"command_line":"echo call1"}',
            'cascadeId': 'c1',
          }
        ],
      },
    }));
    await tester.pump(const Duration(milliseconds: 120));
    debugPrint('PROBE raw: card=${find.byType(ToolApprovalCard).evaluate().length} cardsInTree=${find.byType(ToolApprovalCard).evaluate().length}');

    // 2) broadcast=true stream_delta (as _emitBatched for local stream would)
    ctrl.add({
      'type': 'stream_delta',
      'requestId': 'r1',
      'broadcast': true,
      'data': {
        'events': [
          {
            'kind': 'approval_required',
            'callId': 'call-2',
            'tool': 'edit_file',
            'detail': '{"command_line":"echo call2"}',
            'cascadeId': 'c1',
          }
        ],
      },
    });
    await tester.pump(const Duration(milliseconds: 120));
    debugPrint('PROBE broadcast: card=${find.byType(ToolApprovalCard).evaluate().length}');

    // What does the widget tree contain?
    debugPrint('PROBE text: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).where((d) => d != null).toList()}');
    debugPrint('PROBE icons: ${find.byType(Icon).evaluate().map((e) => (e.widget as Icon).icon?.codePoint.toRadixString(16)).toList()}');
  });
}
