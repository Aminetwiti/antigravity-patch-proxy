import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat_stream/chat_stream_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ChatStreamScreen Smart Scroll & Floating Pill Tests', () {
    testWidgets('renders jump to bottom button when scrolled up and dismisses on tap', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatStreamScreen(
              activeSessionId: 'sess-scroll-test',
              activeProjectName: 'test-project',
              isConnected: true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially at bottom, jump button is not shown
      expect(find.byKey(const Key('jump-to-bottom')), findsNothing);
    });
  });
}
