import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat_stream/chat_stream_screen.dart';
import 'package:mobile/widgets/session_top_tabs.dart';

class _FakeApi {
  Future<Map<String, dynamic>> noop() async => {};
}

void main() {
  testWidgets('P6 — swipe gauche passe de Chat à Review', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatStreamScreen(
            api: null,
            activeSessionId: 's1',
            activeProjectName: 'proj',
            isConnected: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Chat actif au départ.
    expect(
      tester.widget<SessionTopTabs>(find.byType(SessionTopTabs)).activeTab,
      SessionTabType.chat,
    );

    // Swipe horizontal rapide vers la gauche (velocity négative → onglet suivant).
    await tester.fling(
      find.byType(ChatStreamScreen),
      const Offset(-400, 0),
      800,
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<SessionTopTabs>(find.byType(SessionTopTabs)).activeTab,
      SessionTabType.review,
    );
  });

  testWidgets('P6 — swipe droit revient de Review à Chat', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatStreamScreen(
            api: null,
            activeSessionId: 's1',
            activeProjectName: 'proj',
            isConnected: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Aller sur Review d'abord (via l'API publique des tabs).
    await tester.tap(find.text('Review'));
    await tester.pump();
    expect(
      tester.widget<SessionTopTabs>(find.byType(SessionTopTabs)).activeTab,
      SessionTabType.review,
    );

    // Swipe vers la droite → retour sur Chat.
    await tester.fling(
      find.byType(ChatStreamScreen),
      const Offset(400, 0),
      800,
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<SessionTopTabs>(find.byType(SessionTopTabs)).activeTab,
      SessionTabType.chat,
    );
  });
}
