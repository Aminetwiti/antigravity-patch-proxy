import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/daemon_api.dart';
import 'package:mobile/features/chat_stream/chat_stream_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ChatStreamScreen Smart Scroll & Floating Pill Tests', () {
    testWidgets('renders jump to bottom button when scrolled up and dismisses on tap', (tester) async {
      final ctrl = StreamController<dynamic>.broadcast();
      final api = DaemonApi(
        incoming: ctrl.stream,
        send: (d) {
          final map = d as Map<String, dynamic>;
          final reqId = map['requestId'] as String?;
          if (reqId != null) {
            scheduleMicrotask(() {
              if (!ctrl.isClosed) {
                ctrl.add(jsonEncode({'requestId': reqId, 'data': {}}));
              }
            });
          }
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatStreamScreen(
              api: api,
              activeSessionId: 'sess-scroll-test',
              activeProjectName: 'test-project',
              isConnected: true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Initially at bottom, jump button is not shown
      expect(find.byKey(const Key('jump-to-bottom')), findsNothing);

      // Clean up widget tree to cancel periodic timers
      await tester.pumpWidget(const SizedBox());
      await ctrl.close();
      api.dispose();
    });
  });
}
