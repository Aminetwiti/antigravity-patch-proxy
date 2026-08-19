import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat_stream/widgets/execution_progress_view.dart';

void main() {
  group('ExecutionProgressView — Antigravity 2.0 Fidelity Tests', () {
    testWidgets('Renders collapsible Task finished, Worked for, Timers, Auto-proceed and Working..', (tester) async {
      String? openedArtifact;

      const rawThought = '''
Vérification globale de la suite Gateway Go en cours...
Task 332 finished
Worked for 19m
Exécution de la suite complète de tests Flutter en cours...
Auto-proceeded with Implementation Plan
Worked for 35s
Timed 30 seconds
> Check flutter test results
Status: Fired
Attente des résultats des tests...
Wait for task-424: Timer has expired
> Check flutter test results
Explored 1 task
Task 424 finished
''';

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExecutionProgressView(
                messageId: 'msg-test-1',
                thoughtText: rawThought,
                isStreaming: true,
                modelLabel: 'Gemini 3.7 Flash High',
                onOpenArtifact: (name) {
                  openedArtifact = name;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // 1. Vérification de l'en-tête de streaming et du modèle actif
      expect(find.textContaining("Agent en cours d'exécution"), findsOneWidget);
      expect(find.text('Gemini 3.7 Flash High'), findsOneWidget);

      // 2. Vérification des tâches terminées (Task 332 finished, Task 424 finished)
      expect(find.text('Task 332 finished'), findsOneWidget);
      expect(find.text('Task 424 finished'), findsOneWidget);

      // 3. Vérification des durées (Worked for 19m, Worked for 35s)
      expect(find.text('for 19m'), findsOneWidget);
      expect(find.text('for 35s'), findsOneWidget);

      // 4. Vérification de la pillule Auto-proceeded with Implementation Plan
      expect(find.text('Auto-proceeded with'), findsOneWidget);
      expect(find.text('Implementation Plan'), findsOneWidget);

      // Test du tap sur la pillule Auto-proceed
      await tester.tap(find.text('Implementation Plan'));
      expect(openedArtifact, equals('Implementation Plan'));

      // 5. Vérification du minuteur Timed 30 seconds et Wait for task-424
      expect(find.text('Timed 30 seconds'), findsOneWidget);
      expect(find.text('Wait for task-424: Timer has expired'), findsOneWidget);

      // 6. Vérification du texte narratif de l'agent
      expect(find.text('Vérification globale de la suite Gateway Go en cours...'), findsOneWidget);
      expect(find.text('Exécution de la suite complète de tests Flutter en cours...'), findsOneWidget);
      expect(find.text('Attente des résultats des tests...'), findsOneWidget);

      // 7. Vérification de l'indicateur d'exécution Working..
      expect(find.textContaining('Working'), findsWidgets);

      // 8. Test de dépliage d'un minuteur pour voir les détails (Check flutter test results & Status: Fired)
      await tester.tap(find.text('Timed 30 seconds'));
      await tester.pump();
      expect(find.text('Check flutter test results'), findsWidgets);
      expect(find.text('Status: Fired'), findsWidgets);
    });

    testWidgets('Hides Working.. and live header when isStreaming is false', (tester) async {
      const rawThought = '''
Task 332 finished
Worked for 19m
Task 424 finished
''';

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: ExecutionProgressView(
              messageId: 'msg-test-done',
              thoughtText: rawThought,
              isStreaming: false,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text("Agent en cours d'exécution"), findsNothing);
      expect(find.text('Task 332 finished'), findsOneWidget);
      expect(find.text('Task 424 finished'), findsOneWidget);
      expect(find.text('for 19m'), findsOneWidget);
    });
  });
}
